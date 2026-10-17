const std = @import("std");
const ir = @import("ir.zig");
const abi = @import("abi_amd64.zig");
const module_validation = @import("module_validation.zig");
const stack_homes = @import("stack_homes.zig");
const Module = @import("module.zig").Module;
pub const Error = stack_homes.Error || abi.Error || module_validation.Error || error{FrameTooLarge};

pub const Options = struct {
    reuse_stack_homes: bool = false,
    callee_saved_homes: bool = false,
};

/// Experimental Linux ELF/System V base-scalar slice. Values have persistent
/// stack/preserved homes; no instruction selection/register allocation parity.
/// Caller owns the returned assembly. Invalid input never returns partial text.
pub fn emit(allocator: std.mem.Allocator, module: *const Module) Error![]u8 {
    return emitWithOptions(allocator, module, .{});
}

pub fn emitWithOptions(allocator: std.mem.Allocator, module: *const Module, options: Options) Error![]u8 {
    try module_validation.validate(allocator, module);
    for (module.data.items) |object| {
        if (!validSymbol(module.symbols.get(object.name).?)) return error.InvalidSymbol;
        for (object.items.items) |item| if (item == .symbol_address) {
            if (!validSymbol(module.symbols.get(item.symbol_address.symbol).?)) return error.InvalidSymbol;
        };
    }
    for (module.functions.items) |function| {
        if (!validSymbol(module.symbols.get(function.name).?)) return error.InvalidSymbol;
        if (!options.reuse_stack_homes and !options.callee_saved_homes) _ = try Frame.init(function);
        for (function.blocks.items) |block| {
            for (block.phis.items) |phi| for (phi.inputs) |input| try validateOperandSymbol(module, input.value);
            for (block.instructions.items) |instruction| {
                var operands = instruction.operands();
                while (operands.next()) |operand| try validateOperandSymbol(module, operand);
            }
            switch (block.terminator.?) {
                .branch => |branch| try validateOperandSymbol(module, branch.condition),
                .return_value => |value| if (value) |operand| try validateOperandSymbol(module, operand),
                .jump, .halt => {},
            }
        }
        for (function.blocks.items) |block| for (block.instructions.items) |instruction| switch (instruction) {
            .call => |call| switch (call.callee) {
                .symbol => |symbol| if (!validSymbol(module.symbols.get(symbol).?)) return error.InvalidSymbol,
                .address => {},
            },
            else => {},
        };
    }
    var emitter: Emitter = .{ .output = .init(allocator), .module = module, .allocator = allocator, .options = options };
    defer emitter.output.deinit();
    if (module.data.items.len != 0) {
        for (module.data.items) |object| try emitter.dataDefinition(object);
    }
    try emitter.print(".text\n", .{});
    for (module.functions.items, 0..) |function, index| try emitter.function(function, index);
    try emitter.print(".section .note.GNU-stack,\"\",@progbits\n", .{});
    return emitter.output.toOwnedSlice();
}

fn validateOperandSymbol(module: *const Module, operand: ir.Operand) Error!void {
    if (operand.referencedSymbol()) |symbol| if (!validSymbol(module.symbols.get(symbol).?)) return error.InvalidSymbol;
}

const Frame = struct {
    bytes: usize,
    scratch_base: usize,
    saved_base: usize,
    outgoing_bytes: usize = 0,
    variadic_save_end: ?usize = null,

    fn init(function: *const ir.Function) error{FrameTooLarge}!Frame {
        var max_phis: usize = 0;
        for (function.blocks.items) |block| max_phis = @max(max_phis, block.phis.items.len);
        return fromCounts(function.values.items.len, max_phis, function.parameters.items.len);
    }

    /// Outgoing arguments occupy the bottom of the aligned frame, below all
    /// homes, phi scratch and preserved originals. RSP stays aligned at calls.
    fn addOutgoing(self: *Frame, function: *const ir.Function) (error{FrameTooLarge} || abi.Error)!void {
        var slots: usize = 0;
        for (function.blocks.items) |block| for (block.instructions.items) |instruction| switch (instruction) {
            .call => |call| {
                var cursor: abi.ArgumentCursor = .{};
                for (call.arguments) |argument| _ = try cursor.next(argument.scalar_type);
                slots = @max(slots, cursor.stack_used);
            },
            else => {},
        };
        const outgoing = std.math.mul(usize, slots, 8) catch return error.FrameTooLarge;
        const outgoing_rounded = std.math.add(usize, outgoing, 15) catch return error.FrameTooLarge;
        const outgoing_aligned = outgoing_rounded & ~@as(usize, 15);
        const raw = std.math.add(usize, self.bytes, outgoing_aligned) catch return error.FrameTooLarge;
        const rounded = std.math.add(usize, raw, 15) catch return error.FrameTooLarge;
        const bytes = rounded & ~@as(usize, 15);
        if (bytes > 64 * 1024) return error.FrameTooLarge;
        self.bytes = bytes;
        self.outgoing_bytes = outgoing_aligned;
    }

    /// Below the old aligned homes/phi/saved-original region, above outgoing.
    fn addVariadic(self: *Frame, enabled: bool) error{FrameTooLarge}!void {
        if (!enabled) return;
        const bytes = std.math.add(usize, self.bytes, 176) catch return error.FrameTooLarge;
        if (bytes > 64 * 1024) return error.FrameTooLarge;
        self.bytes = bytes;
        self.variadic_save_end = bytes;
    }

    fn fromCounts(values: usize, phis: usize, parameters: usize) error{FrameTooLarge}!Frame {
        return withSavedCounts(values, phis, parameters, 0);
    }

    fn withSavedCounts(values: usize, phis: usize, parameters: usize, saved: usize) error{FrameTooLarge}!Frame {
        const count = std.math.add(usize, values, phis) catch return error.FrameTooLarge;
        const total = std.math.add(usize, count, saved) catch return error.FrameTooLarge;
        const raw = std.math.mul(usize, total, 8) catch return error.FrameTooLarge;
        const rounded = std.math.add(usize, raw, 15) catch return error.FrameTooLarge;
        const bytes = rounded & ~@as(usize, 15);
        // Explicit prototype limit; reservation probes do not remove the cap.
        if (bytes > 64 * 1024) return error.FrameTooLarge;
        if (parameters > 6 and parameters - 6 > (std.math.maxInt(i32) - 16) / 8) return error.FrameTooLarge;
        return .{ .bytes = bytes, .scratch_base = values * 8, .saved_base = count * 8 };
    }
};

const Preserved = enum {
    rbx,
    r12,
    r13,
    r14,
    r15,

    fn name(self: Preserved, ty: ir.ScalarType) []const u8 {
        const narrow = ty == .word or ty == .single;
        return switch (self) {
            .rbx => if (narrow) "%ebx" else "%rbx",
            .r12 => if (narrow) "%r12d" else "%r12",
            .r13 => if (narrow) "%r13d" else "%r13",
            .r14 => if (narrow) "%r14d" else "%r14",
            .r15 => if (narrow) "%r15d" else "%r15",
        };
    }
};
const preserved_registers = [_]Preserved{ .rbx, .r12, .r13, .r14, .r15 };
const Home = union(enum) { stack_offset: usize, preserved: Preserved };

const Scratch = enum { accumulator, temporary, count };

const Emitter = struct {
    output: std.Io.Writer.Allocating,
    module: *const Module,
    allocator: std.mem.Allocator,
    options: Options,
    homes: ?[]const stack_homes.SlotId = null,
    saved_count: usize = 0,
    current: *const ir.Function = undefined,
    ordinal: usize = 0,
    frame: Frame = undefined,

    fn print(self: *Emitter, comptime format: []const u8, args: anytype) Error!void {
        // The allocating writer's only backing failure is allocator exhaustion.
        self.output.writer.print(format, args) catch return error.OutOfMemory;
    }

    fn dataDefinition(self: *Emitter, object: *const @import("data.zig").Data) Error!void {
        const name = self.module.symbols.get(object.name).?;
        const zero = object.isAllZero();
        if (zero) try self.print(".bss\n", .{}) else try self.print(".data\n", .{});
        try self.print(".balign {d}\n", .{object.alignment.bytes()});
        if (object.linkage == .exported) try self.print(".globl {s}\n", .{name});
        try self.print(".type {s}, @object\n{s}:\n", .{ name, name });
        if (zero) {
            if (object.byte_len != 0) try self.print("\t.zero {d}\n", .{object.byte_len});
        } else {
            for (object.items.items) |item| switch (item) {
                .byte => |bits| try self.print("\t.byte {d}\n", .{bits}),
                .half => |bits| try self.print("\t.short {d}\n", .{bits}),
                .word, .single_bits => |bits| try self.print("\t.long {d}\n", .{bits}),
                .long, .double_bits => |bits| try self.print("\t.quad {d}\n", .{bits}),
                .bytes => |bytes| for (bytes, 0..) |byte, index| {
                    if (index % 16 == 0) try self.print("\t.byte ", .{}) else try self.print(",", .{});
                    try self.print("{d}", .{byte});
                    if (index % 16 == 15 or index + 1 == bytes.len) try self.print("\n", .{});
                },
                .symbol_address => |reference| {
                    try self.print("\t.quad {s}", .{self.module.symbols.get(reference.symbol).?});
                    if (reference.addend > 0) try self.print("+{d}", .{reference.addend});
                    // Printing the signed minimum directly never negates/overflows it.
                    if (reference.addend < 0) try self.print("{d}", .{reference.addend});
                    try self.print("\n", .{});
                },
                .zero => |count| if (count != 0) {
                    try self.print("\t.zero {d}\n", .{count});
                },
            };
        }
        try self.print(".size {s}, .-{s}\n", .{ name, name });
    }

    /// Frame construction established the aligned, bounded extent. Touch each
    /// new stack page before descending farther; flags are dead in the prologue.
    fn reserveFrame(self: *Emitter, frame: Frame) Error!void {
        std.debug.assert(frame.bytes % 16 == 0 and frame.bytes <= 64 * 1024);
        var remaining = frame.bytes;
        while (remaining != 0) {
            const step = @min(remaining, 4096);
            try self.print("\tsubq ${d}, %rsp\n\ttestb $0, (%rsp)\n", .{step});
            remaining -= step;
        }
    }

    fn function(self: *Emitter, f: *const ir.Function, index: usize) Error!void {
        self.current = f;
        self.ordinal = index;
        var layout: ?stack_homes.Layout = if (self.options.reuse_stack_homes or self.options.callee_saved_homes) try stack_homes.Layout.init(self.allocator, f, .{}) else null;
        defer if (layout) |*owned| owned.deinit();
        self.homes = if (layout) |owned| owned.slots else null;
        defer self.homes = null;
        self.saved_count = if (self.options.callee_saved_homes) @min(preserved_registers.len, layout.?.slot_count) else 0;
        if (layout) |owned| {
            var max_phis: usize = 0;
            for (f.blocks.items) |block| max_phis = @max(max_phis, block.phis.items.len);
            self.frame = try Frame.withSavedCounts(owned.slot_count - self.saved_count, max_phis, f.parameters.items.len, self.saved_count);
        } else self.frame = try Frame.init(f);
        try self.frame.addVariadic(f.variadic);
        try self.frame.addOutgoing(f);
        const name = self.module.symbols.get(f.name).?;
        try self.print("{s} {s}\n.type {s}, @function\n{s}:\n\tpushq %rbp\n\tmovq %rsp, %rbp\n", .{ if (f.linkage == .exported) @as([]const u8, ".globl") else ".local", name, name, name });
        try self.reserveFrame(self.frame);
        for (preserved_registers[0..self.saved_count], 0..) |preserved, i| {
            try self.print("\tmovq {s}, -{d}(%rbp)\n", .{ preserved.name(.long), self.frame.saved_base + (i + 1) * 8 });
        }
        if (self.frame.variadic_save_end) |offset| {
            const registers = [_]abi.General{ .rdi, .rsi, .rdx, .rcx, .r8, .r9 };
            for (registers, 0..) |reg, i| try self.print("\tmovq {s}, -{d}(%rbp)\n", .{ reg.name(.long), offset - i * 8 });
            // Raw moves cannot raise floating arithmetic exceptions. Saving all
            // eight registers avoids relying on AL after any scratch homing.
            for (0..8) |i| try self.print("\tmovdqu %xmm{d}, -{d}(%rbp)\n", .{ i, offset - 48 - i * 16 });
        }
        var arguments: abi.ArgumentCursor = .{};
        for (f.parameters.items) |parameter| {
            const ty = f.values.items[@backingInt(parameter)].scalar_type;
            switch (try arguments.next(ty)) {
                .general => |reg| {
                    const width: ir.IntegerType = switch (ty) {
                        .word => .word,
                        .long => .long,
                        else => unreachable, // ABI classifier guarantees an integer class.
                    };
                    try self.save(parameter, reg.name(width));
                },
                .vector => |reg| {
                    try self.print("\tmov{c} {s}, {s}\n", .{ sseMove(ty), reg.name(), register(ty, .accumulator) });
                    try self.save(parameter, register(ty, .accumulator));
                },
                .stack => |slot| {
                    try self.print("\tmov{c} {d}(%rbp), {s}\n", .{ suffix(ty), try slot.incomingOffset(), register(ty, .accumulator) });
                    try self.save(parameter, register(ty, .accumulator));
                },
            }
        }
        for (f.blocks.items, 0..) |block, number| {
            const id: ir.BlockId = @fromBackingInt(@as(u32, @intCast(number)));
            try self.print("\".Lzbe@{d}@b{d}\":\n", .{ index, number });
            for (block.instructions.items) |instruction| switch (instruction) {
                .va_start => |start| try self.vaStart(start.list, arguments),
                .va_argument => |argument| try self.vaArgument(argument.result, argument.list),
                .allocate => |allocation| try self.allocate(allocation.result, allocation.size, allocation.alignment),
                .convert => |conversion| try self.convert(conversion.result, conversion.op, conversion.operand),
                .blit => |blit| {
                    if (blit.byte_count == 0) continue;
                    try self.load(blit.source, .accumulator);
                    try self.print("\tmovq %rax, %rsi\n", .{});
                    try self.load(blit.destination, .accumulator);
                    try self.print("\tmovq %rax, %rdi\n\tmovl ${d}, %ecx\n\trep movsb\n", .{blit.byte_count});
                },
                .load => |read| {
                    try self.load(read.address, .accumulator);
                    try self.print("\tmovq %rax, %r10\n", .{});
                    const ty = f.values.items[@backingInt(read.result)].scalar_type;
                    const mnemonic: []const u8 = switch (read.kind) {
                        .signed_byte => if (ty == .long) "movsbq" else "movsbl",
                        .unsigned_byte => "movzbl",
                        .signed_half => if (ty == .long) "movswq" else "movswl",
                        .unsigned_half => "movzwl",
                        .signed_word => if (ty == .long) "movslq" else "movl",
                        .unsigned_word, .single => "movl",
                        .long, .double => "movq",
                    };
                    const destination: []const u8 = switch (read.kind) {
                        .unsigned_byte, .unsigned_half, .unsigned_word => "%eax",
                        else => register(ty, .accumulator),
                    };
                    try self.print("\t{s} (%r10), {s}\n", .{ mnemonic, destination });
                    try self.save(read.result, register(ty, .accumulator));
                },
                .store => |store| {
                    try self.load(store.address, .accumulator);
                    try self.print("\tmovq %rax, %r10\n", .{});
                    try self.load(store.value, .accumulator);
                    const width: u8 = switch (store.kind) {
                        .byte => 'b',
                        .half => 'w',
                        .word, .single => 'l',
                        .long, .double => 'q',
                    };
                    const source_register: []const u8 = switch (store.kind) {
                        .byte => "%al",
                        .half => "%ax",
                        else => register(store.kind.valueType(), .accumulator),
                    };
                    try self.print("\tmov{c} {s}, (%r10)\n", .{ width, source_register });
                },
                .call => |call| {
                    if (call.callee.addressOperand()) |address| {
                        try self.load(address, .accumulator);
                        try self.print("\tmovq %rax, %r11\n", .{});
                    }
                    var cursor: abi.ArgumentCursor = .{};
                    for (call.arguments) |argument| {
                        // Homes survive SysV calls and never alias argument registers.
                        // Loading uses only RAX, leaving already marshaled arguments intact.
                        try self.load(argument.operand, .accumulator);
                        const ty = argument.scalar_type;
                        switch (try cursor.next(ty)) {
                            .general => |reg| try self.print("\tmov{c} {s}, {s}\n", .{ suffix(ty), register(ty, .accumulator), reg.name(if (ty == .word) .word else .long) }),
                            .vector => |reg| try self.print("\tmov{c} {s}, {s}\n", .{ sseMove(ty), register(ty, .accumulator), reg.name() }),
                            .stack => |slot| try self.print("\tmov{c} {s}, {d}(%rsp)\n", .{ suffix(ty), register(ty, .accumulator), try slot.incomingOffset() - 16 }),
                        }
                    }
                    // AL counts occupied SSE argument registers, including named
                    // arguments. Set it last: ordinary RAX loads may poison AL.
                    if (call.variadic_start != null) try self.print("\tmovb ${d}, %al\n", .{cursor.vector_used});
                    switch (call.callee) {
                        .symbol => |symbol| try self.print("\tcall {s}\n", .{self.module.symbols.get(symbol).?}),
                        .address => try self.print("\tcall *%r11\n", .{}),
                    }
                    if (call.result) |result| {
                        const ty = f.values.items[@backingInt(result)].scalar_type;
                        if (!ty.isInteger()) try self.print("\tmov{c} %xmm0, {s}\n", .{ sseMove(ty), register(ty, .accumulator) });
                        try self.save(result, register(ty, .accumulator));
                    }
                },
                .copy => |copy| {
                    try self.load(copy.operand, .accumulator);
                    const ty = f.values.items[@backingInt(copy.result)].scalar_type;
                    try self.save(copy.result, register(ty, .accumulator));
                },
                .unary => |unary| {
                    try self.load(unary.operand, .accumulator);
                    const ty = f.values.items[@backingInt(unary.result)].scalar_type;
                    switch (unary.op) {
                        .negate => if (ty.isInteger()) {
                            try self.print("\tneg{c} {s}\n", .{ suffix(ty), register(ty, .accumulator) });
                        } else if (ty == .single) {
                            try self.print("\txorl $0x80000000, %eax\n", .{});
                        } else {
                            try self.print("\tmovabsq $0x8000000000000000, %r10\n\txorq %r10, %rax\n", .{});
                        },
                        .bitcast => {}, // Raw bits already occupy a same-width GP scratch register.
                        .widen_float => try self.print("\tmovd %eax, %xmm0\n\tcvtss2sd %xmm0, %xmm0\n\tmovq %xmm0, %rax\n", .{}),
                        .sign_extend_byte => try self.print("\tmovsb{c} %al, {s}\n", .{ suffix(ty), register(ty, .accumulator) }),
                        .zero_extend_byte => try self.print("\tmovzbl %al, %eax\n", .{}),
                        .sign_extend_half => try self.print("\tmovsw{c} %ax, {s}\n", .{ suffix(ty), register(ty, .accumulator) }),
                        .zero_extend_half => try self.print("\tmovzwl %ax, %eax\n", .{}),
                        .sign_extend_word => try self.print("\tmovslq %eax, %rax\n", .{}),
                        .zero_extend_word => {}, // Loading a word already clears the upper half of RAX.
                    }
                    try self.save(unary.result, register(ty, .accumulator));
                },
                .shift => |shift| {
                    try self.load(shift.value, .accumulator);
                    try self.load(shift.amount, .count);
                    const ty = f.values.items[@backingInt(shift.result)].scalar_type;
                    const mnemonic: []const u8 = switch (shift.op) {
                        .left => "shl",
                        .logical_right => "shr",
                        .arithmetic_right => "sar",
                    };
                    try self.print("\t{s}{c} %cl, {s}\n", .{ mnemonic, suffix(ty), register(ty, .accumulator) });
                    try self.save(shift.result, register(ty, .accumulator));
                },
                .compare_float => |comparison| {
                    try self.load(comparison.lhs, .accumulator);
                    try self.load(comparison.rhs, .temporary);
                    const ty = comparison.operand_type.scalar();
                    try self.print("\tmov{c} {s}, %xmm0\n\tmov{c} {s}, %xmm1\n\tucomi{s} %xmm1, %xmm0\n", .{ sseMove(ty), register(ty, .accumulator), sseMove(ty), register(ty, .temporary), if (ty == .single) @as([]const u8, "ss") else "sd" });
                    const condition: []const u8 = switch (comparison.predicate) {
                        .equal => "e",
                        .not_equal => "ne",
                        .less => "b",
                        .less_equal => "be",
                        .greater => "a",
                        .greater_equal => "ae",
                        .ordered => "np",
                        .unordered => "p",
                    };
                    try self.print("\tset{s} %al\n", .{condition});
                    switch (comparison.predicate) {
                        .equal, .less, .less_equal => try self.print("\tsetnp %r10b\n\tandb %r10b, %al\n", .{}),
                        .not_equal => try self.print("\tsetp %r10b\n\torb %r10b, %al\n", .{}),
                        else => {},
                    }
                    try self.print("\tmovzbl %al, %eax\n", .{});
                    const result_type = f.values.items[@backingInt(comparison.result)].scalar_type;
                    try self.save(comparison.result, register(result_type, .accumulator));
                },
                .compare_integer => |comparison| {
                    try self.load(comparison.lhs, .accumulator);
                    try self.load(comparison.rhs, .temporary);
                    const ty = comparison.operand_type.scalar();
                    const condition: []const u8 = switch (comparison.predicate) {
                        .equal => "e",
                        .not_equal => "ne",
                        .signed_less => "l",
                        .signed_less_equal => "le",
                        .signed_greater => "g",
                        .signed_greater_equal => "ge",
                        .unsigned_less => "b",
                        .unsigned_less_equal => "be",
                        .unsigned_greater => "a",
                        .unsigned_greater_equal => "ae",
                    };
                    try self.print("\tcmp{c} {s}, {s}\n\tset{s} %al\n\tmovzbl %al, %eax\n", .{ suffix(ty), register(ty, .temporary), register(ty, .accumulator), condition });
                    const result_type = f.values.items[@backingInt(comparison.result)].scalar_type;
                    try self.save(comparison.result, register(result_type, .accumulator));
                },
                .binary => |binary| {
                    try self.load(binary.lhs, .accumulator);
                    try self.load(binary.rhs, .temporary);
                    const ty = f.values.items[@backingInt(binary.result)].scalar_type;
                    if (!ty.isInteger()) {
                        const mnemonic: []const u8 = switch (binary.op) {
                            .add => "add",
                            .sub => "sub",
                            .mul => "mul",
                            .signed_divide => "div",
                            else => unreachable, // Structural validation rejects non-floating opcodes.
                        };
                        try self.print("\tmov{c} {s}, %xmm0\n\tmov{c} {s}, %xmm1\n\t{s}{s} %xmm1, %xmm0\n\tmov{c} %xmm0, {s}\n", .{ sseMove(ty), register(ty, .accumulator), sseMove(ty), register(ty, .temporary), mnemonic, if (ty == .single) @as([]const u8, "ss") else "sd", sseMove(ty), register(ty, .accumulator) });
                        try self.save(binary.result, register(ty, .accumulator));
                    } else switch (binary.op) {
                        .signed_divide, .unsigned_divide, .signed_remainder, .unsigned_remainder => {
                            const signed = binary.op == .signed_divide or binary.op == .signed_remainder;
                            const remainder = binary.op == .signed_remainder or binary.op == .unsigned_remainder;
                            if (signed) {
                                try self.print("\t{s}\n", .{if (ty == .word) @as([]const u8, "cltd") else "cqto"});
                            } else {
                                try self.print("\txorl %edx, %edx\n", .{});
                            }
                            try self.print("\t{s}div{c} {s}\n", .{ if (signed) @as([]const u8, "i") else "", suffix(ty), register(ty, .temporary) });
                            try self.save(binary.result, if (remainder) (if (ty == .word) @as([]const u8, "%edx") else "%rdx") else register(ty, .accumulator));
                        },
                        else => {
                            const mnemonic: []const u8 = switch (binary.op) {
                                .add => "add",
                                .sub => "sub",
                                .mul => "imul",
                                .bit_and => "and",
                                .bit_or => "or",
                                .bit_xor => "xor",
                                else => unreachable,
                            };
                            try self.print("\t{s}{c} {s}, {s}\n", .{ mnemonic, suffix(ty), register(ty, .temporary), register(ty, .accumulator) });
                            try self.save(binary.result, register(ty, .accumulator));
                        },
                    }
                },
            };
            switch (block.terminator.?) {
                .halt => try self.print("\tud2\n", .{}),
                .jump => |target| try self.edge(id, target),
                .branch => |branch| {
                    try self.load(branch.condition, .accumulator);
                    try self.print("\ttestl %eax, %eax\n\tjne \".Lzbe@{d}@t{d}\"\n", .{ index, number });
                    try self.edge(id, branch.not_taken);
                    try self.print("\".Lzbe@{d}@t{d}\":\n", .{ index, number });
                    try self.edge(id, branch.taken);
                },
                .return_value => |operand| {
                    if (operand) |value| {
                        try self.load(value, .accumulator);
                        const ty = f.return_type.?;
                        if (!ty.isInteger()) try self.print("\tmov{c} {s}, %xmm0\n", .{ sseMove(ty), register(ty, .accumulator) });
                    }
                    for (preserved_registers[0..self.saved_count], 0..) |preserved, i| {
                        try self.print("\tmovq -{d}(%rbp), {s}\n", .{ self.frame.saved_base + (i + 1) * 8, preserved.name(.long) });
                    }
                    try self.print("\tleave\n\tret\n", .{});
                },
            }
        }
        try self.print(".size {s}, .-{s}\n", .{ name, name });
    }

    fn edge(self: *Emitter, from: ir.BlockId, to: ir.BlockId) Error!void {
        const phis = self.current.blocks.items[@backingInt(to)].phis.items;
        // Preserve parallel phi assignment using distinct scratch stack homes.
        for (phis, 0..) |phi, index| {
            const operand = incoming: {
                for (phi.inputs) |input| if (input.predecessor == from) break :incoming input.value;
                return error.InvalidPhi;
            };
            const ty = self.current.values.items[@backingInt(phi.result)].scalar_type;
            try self.load(operand, .accumulator);
            try self.print("\tmov{c} {s}, -{d}(%rbp)\n", .{ suffix(ty), register(ty, .accumulator), self.frame.scratch_base + (index + 1) * 8 });
        }
        for (phis, 0..) |phi, index| {
            const ty = self.current.values.items[@backingInt(phi.result)].scalar_type;
            try self.print("\tmov{c} -{d}(%rbp), {s}\n", .{ suffix(ty), self.frame.scratch_base + (index + 1) * 8, register(ty, .accumulator) });
            try self.save(phi.result, register(ty, .accumulator));
        }
        try self.print("\tjmp \".Lzbe@{d}@b{d}\"\n", .{ self.ordinal, @backingInt(to) });
    }

    fn allocate(self: *Emitter, result: ir.ValueId, size: ir.Operand, alignment: ir.AllocationAlignment) Error!void {
        // Over-aligning to 16 satisfies all three IL alignments and keeps calls
        // aligned. Each execution moves RSP; constants in loops are not hoisted.
        std.debug.assert(16 % @as(usize, alignment.bytes()) == 0);
        try self.load(size, .accumulator);
        const value = @backingInt(result);
        try self.print("\taddq $15, %rax\n\tjnc \".Lzbe@{d}@allocround{d}\"\n\tud2\n\".Lzbe@{d}@allocround{d}\":\n\tandq $-16, %rax\n\".Lzbe@{d}@allocpage{d}\":\n\tcmpq $4096, %rax\n\tjb \".Lzbe@{d}@allocrest{d}\"\n\tsubq $4096, %rsp\n\ttestb $0, (%rsp)\n\tsubq $4096, %rax\n\tjmp \".Lzbe@{d}@allocpage{d}\"\n\".Lzbe@{d}@allocrest{d}\":\n\ttestq %rax, %rax\n\tje \".Lzbe@{d}@allocdone{d}\"\n\tsubq %rax, %rsp\n\ttestb $0, (%rsp)\n\".Lzbe@{d}@allocdone{d}\":\n\tleaq {d}(%rsp), %rax\n", .{ self.ordinal, value, self.ordinal, value, self.ordinal, value, self.ordinal, value, self.ordinal, value, self.ordinal, value, self.ordinal, value, self.ordinal, value, self.frame.outgoing_bytes });
        // Keep outgoing argument slots below every live dynamic allocation.
        try self.save(result, "%rax");
    }

    fn convert(self: *Emitter, result: ir.ValueId, op: ir.ConvertOp, operand: ir.Operand) Error!void {
        try self.load(operand, .accumulator);
        const ty = self.current.values.items[@backingInt(result)].scalar_type;
        const source_type = try op.operandType(ty);
        const float_type = if (source_type.isInteger()) ty else source_type;
        const precision: []const u8 = if (float_type == .single) "ss" else "sd";
        switch (op) {
            .signed_word_to_float, .signed_long_to_float, .unsigned_word_to_float => {
                // Unsigned words arrive zero-extended in RAX, so signed
                // 64-bit conversion covers the whole unsigned-word domain.
                const width = if (op == .unsigned_word_to_float) ir.ScalarType.long else source_type;
                try self.print("\tcvtsi2{s}{c} {s}, %xmm0\n", .{ precision, suffix(width), register(width, .accumulator) });
            },
            .unsigned_long_to_float => {
                // High-half integers cannot be converted as signed i64.
                // Sticky halving then exact doubling gives nearest-even
                // results without losing a rounding-relevant low bit.
                const value = @backingInt(result);
                try self.print("\ttestq %rax, %rax\n\tjns \".Lzbe@{d}@uif{d}\"\n\tmovq %rax, %r10\n\tandl $1, %r10d\n\tshrq $1, %rax\n\torq %r10, %rax\n\tcvtsi2{s}q %rax, %xmm0\n\tadd{s} %xmm0, %xmm0\n\tjmp \".Lzbe@{d}@uifdone{d}\"\n\".Lzbe@{d}@uif{d}\":\n\tcvtsi2{s}q %rax, %xmm0\n\".Lzbe@{d}@uifdone{d}\":\n", .{ self.ordinal, value, precision, precision, self.ordinal, value, self.ordinal, value, precision, self.ordinal, value });
            },
            .single_to_signed_integer, .double_to_signed_integer, .single_to_unsigned_integer, .double_to_unsigned_integer => {
                try self.print("\tmov{c} {s}, %xmm0\n", .{ sseMove(source_type), register(source_type, .accumulator) });
                const unsigned = op == .single_to_unsigned_integer or op == .double_to_unsigned_integer;
                if (unsigned and ty == .long) {
                    const value = @backingInt(result);
                    // The upper-half subtraction is exact (Sterbenz),
                    // and its result fits signed i64 for defined inputs.
                    const threshold: u64 = if (source_type == .single) 0x5f000000 else 0x43e0000000000000;
                    try self.print("\tmovabsq ${d}, %r10\n\tmov{c} {s}, %xmm1\n\tucomi{s} %xmm1, %xmm0\n\tjb \".Lzbe@{d}@fui{d}\"\n\tsub{s} %xmm1, %xmm0\n\tcvtt{s}2siq %xmm0, %rax\n\tbtcq $63, %rax\n\tjmp \".Lzbe@{d}@fuidone{d}\"\n\".Lzbe@{d}@fui{d}\":\n\tcvtt{s}2siq %xmm0, %rax\n\".Lzbe@{d}@fuidone{d}\":\n", .{ threshold, sseMove(source_type), if (source_type == .single) @as([]const u8, "%r10d") else "%r10", precision, self.ordinal, value, precision, precision, self.ordinal, value, self.ordinal, value, precision, self.ordinal, value });
                } else {
                    const width = if (unsigned) ir.ScalarType.long else ty;
                    try self.print("\tcvtt{s}2si{c} %xmm0, {s}\n", .{ precision, suffix(width), register(width, .accumulator) });
                }
            },
        }
        if (source_type.isInteger()) try self.print("\tmov{c} %xmm0, {s}\n", .{ sseMove(ty), register(ty, .accumulator) });
        try self.save(result, register(ty, .accumulator));
    }

    fn vaStart(self: *Emitter, list: ir.Operand, named: abi.ArgumentCursor) Error!void {
        try self.load(list, .accumulator);
        try self.print("\tmovq %rax, %r10\n\tmovl ${d}, 0(%r10)\n\tmovl ${d}, 4(%r10)\n", .{ named.general_used * 8, 48 + named.vector_used * 16 });
        try self.print("\tleaq {d}(%rbp), %rax\n\tmovq %rax, 8(%r10)\n", .{16 + named.stack_used * 8});
        try self.print("\tleaq -{d}(%rbp), %rax\n\tmovq %rax, 16(%r10)\n", .{self.frame.variadic_save_end.?});
    }

    /// Native descriptor validity and available arguments are caller contracts.
    fn vaArgument(self: *Emitter, result: ir.ValueId, list: ir.Operand) Error!void {
        const ty = self.current.values.items[@backingInt(result)].scalar_type;
        const field: u8 = if (ty.isInteger()) 0 else 4;
        const limit: u16 = if (ty.isInteger()) 48 else 176;
        const stride: u8 = if (ty.isInteger()) 8 else 16;
        const id = @backingInt(result);
        try self.load(list, .accumulator);
        try self.print("\tmovq %rax, %r10\n\tmovl {d}(%r10), %eax\n\tcmpl ${d}, %eax\n\tjae \".Lzbe@{d}@va{d}@stack\"\n", .{ field, limit, self.ordinal, id });
        try self.print("\taddq 16(%r10), %rax\n\taddl ${d}, {d}(%r10)\n\tjmp \".Lzbe@{d}@va{d}@load\"\n", .{ stride, field, self.ordinal, id });
        try self.print("\".Lzbe@{d}@va{d}@stack\":\n\tmovq 8(%r10), %rax\n\taddq $8, 8(%r10)\n\".Lzbe@{d}@va{d}@load\":\n", .{ self.ordinal, id, self.ordinal, id });
        try self.print("\tmov{c} (%rax), {s}\n", .{ suffix(ty), register(ty, .accumulator) });
        try self.save(result, register(ty, .accumulator));
    }

    fn load(self: *Emitter, operand: ir.Operand, scratch: Scratch) Error!void {
        const ty = try self.current.operandType(operand);
        const target = register(ty, scratch);
        switch (operand) {
            .value, .low_word => |value| switch (self.location(value)) {
                .stack_offset => |offset| try self.print("\tmov{c} -{d}(%rbp), {s}\n", .{ suffix(ty), offset, target }),
                .preserved => |preserved| try self.print("\tmov{c} {s}, {s}\n", .{ suffix(ty), preserved.name(ty), target }),
            },
            .symbol => |symbol| try self.print("\tleaq {s}(%rip), {s}\n", .{ self.module.symbols.get(symbol).?, target }),
            .symbol_offset => |address| {
                const name = self.module.symbols.get(address.symbol).?;
                // Print negative addends directly: negating minInt(i32) overflows.
                if (address.addend < 0)
                    try self.print("\tleaq {s}{d}(%rip), {s}\n", .{ name, address.addend, target })
                else
                    try self.print("\tleaq {s}+{d}(%rip), {s}\n", .{ name, address.addend, target });
            },
            .constant => |constant| switch (constant) {
                .word => |bits| try self.print("\tmovl $0x{x}, {s}\n", .{ bits, target }),
                .long => |bits| try self.print("\tmovabsq $0x{x}, {s}\n", .{ bits, target }),
                .single_bits => |bits| try self.print("\tmovl $0x{x}, {s}\n", .{ bits, target }),
                .double_bits => |bits| try self.print("\tmovabsq $0x{x}, {s}\n", .{ bits, target }),
            },
        }
    }

    fn save(self: *Emitter, value: ir.ValueId, reg: []const u8) Error!void {
        const ty = self.current.values.items[@backingInt(value)].scalar_type;
        switch (self.location(value)) {
            .stack_offset => |offset| try self.print("\tmov{c} {s}, -{d}(%rbp)\n", .{ suffix(ty), reg, offset }),
            .preserved => |preserved| try self.print("\tmov{c} {s}, {s}\n", .{ suffix(ty), reg, preserved.name(ty) }),
        }
    }

    fn location(self: *const Emitter, value: ir.ValueId) Home {
        const ordinal: usize = @backingInt(value);
        const slot = if (self.homes) |homes| @as(usize, @backingInt(homes[ordinal])) else ordinal;
        if (slot < self.saved_count) return .{ .preserved = preserved_registers[slot] };
        return .{ .stack_offset = (slot - self.saved_count + 1) * 8 };
    }
};
fn suffix(ty: ir.ScalarType) u8 {
    return switch (ty) {
        .word, .single => 'l',
        .long, .double => 'q',
    };
}
fn sseMove(ty: ir.ScalarType) u8 {
    return switch (ty) {
        .single => 'd',
        .double => 'q',
        else => unreachable,
    };
}
fn register(ty: ir.ScalarType, scratch: Scratch) []const u8 {
    const narrow = ty == .word or ty == .single;
    return switch (scratch) {
        .accumulator => if (narrow) "%eax" else "%rax",
        .temporary => if (narrow) "%r10d" else "%r10",
        .count => if (narrow) "%ecx" else "%rcx",
    };
}
fn validSymbol(name: []const u8) bool {
    if (name.len == 0 or std.mem.eql(u8, name, ".")) return false;
    if (!(std.ascii.isAlphabetic(name[0]) or name[0] == '_' or name[0] == '.')) return false;
    for (name[1..]) |c| if (!(std.ascii.isAlphanumeric(c) or c == '_' or c == '.' or c == '$')) return false;
    return true;
}

const testing = std.testing;
const frontend = @import("frontend.zig");
const source = @import("source.zig");
fn parse(text: []const u8) !Module {
    var diagnostic: ?source.Diagnostic = null;
    return frontend.parse(testing.allocator, .{ .name = "amd64-test", .text = text }, &diagnostic);
}

test "integer emitter validates low-word branches and phi scratch ownership" {
    var module = try parse(@embedFile("fixtures/constant-jump.ssa") ++ "\n" ++ @embedFile("fixtures/phi-loop.ssa"));
    defer module.deinit();
    const text = try emit(testing.allocator, &module);
    defer testing.allocator.free(text);
    try testing.expect(std.mem.indexOf(u8, text, "testl %eax, %eax") != null);
    try testing.expect(std.mem.indexOf(u8, text, "movabsq $0x10000000000") != null);
    try testing.expect(std.mem.indexOf(u8, text, ".globl swap") != null);
    try testing.expect(std.mem.indexOf(u8, text, ".note.GNU-stack") != null);
}

test "emitter supports base scalars and rejects invalid symbols and oversized frames" {
    var module = try parse("export function d $f() {\n@b\nret d_1\n}");
    defer module.deinit();
    const text = try emit(testing.allocator, &module);
    defer testing.allocator.free(text);
    try testing.expect(std.mem.indexOf(u8, text, "movq %rax, %xmm0") != null);
    try testing.expect(!validSymbol(".Lzbe@0@b0"));
    try testing.expect(!validSymbol("x\n.globl injected"));
    try testing.expect(!validSymbol("."));
    try testing.expect(validSymbol("user.name$1"));
    try testing.expectError(error.FrameTooLarge, Frame.fromCounts(std.math.maxInt(usize), 1, 0));
    try testing.expectError(error.FrameTooLarge, Frame.fromCounts(8193, 0, 0));
}

fn exercise(allocator: std.mem.Allocator) !void {
    var diagnostic: ?source.Diagnostic = null;
    var module = try frontend.parse(allocator, .{ .name = "fixture", .text = @embedFile("fixtures/phi-loop.ssa") }, &diagnostic);
    defer module.deinit();
    const text = try emit(allocator, &module);
    defer allocator.free(text);
    try testing.expect(text.len > 0);
}

test "every emitter allocation failure frees assembly and validation scratch" {
    try @import("test_support.zig").checkAllocationFailures(exercise);
}

test "emitter validates owned symbol names and duplicate identities" {
    var module = try parse("function w $local() {\n@b\nret 1\n}\nexport function w $public() {\n@b\nret 2\n}");
    defer module.deinit();
    const assembly = try emit(testing.allocator, &module);
    defer testing.allocator.free(assembly);
    try testing.expect(std.mem.indexOf(u8, assembly, ".local local") != null);
    module.functions.items[1].name = module.functions.items[0].name;
    try testing.expectError(error.DuplicateSymbol, emit(testing.allocator, &module));
    module.functions.items[0].name = try module.symbols.intern("invalid\n.globl injected");
    try testing.expectError(error.InvalidSymbol, emit(testing.allocator, &module));
}

fn exerciseScalarExtra(allocator: std.mem.Allocator) !void {
    var diagnostic: ?source.Diagnostic = null;
    var module = try frontend.parse(allocator, .{ .name = "scalar-extra", .text = @embedFile("fixtures/compare-loop.ssa") ++ "\nfunction l $shift(l %x, w %n) {\n@b\n%v =l sar %x, %n\n%r =l csltl %v, 0\nret %r\n}" }, &diagnostic);
    defer module.deinit();
    const text = try emit(allocator, &module);
    defer allocator.free(text);
    try testing.expect(std.mem.indexOf(u8, text, "sarq %cl") != null);
    try testing.expect(std.mem.indexOf(u8, text, "setl %al") != null);
}

test "shift and comparison emission clean up every allocation failure" {
    try @import("test_support.zig").checkAllocationFailures(exerciseScalarExtra);
}

fn exerciseUnary(allocator: std.mem.Allocator) !void {
    var diagnostic: ?source.Diagnostic = null;
    var module = try frontend.parse(allocator, .{ .name = "unary", .text = "function l $f(w %x) {\n@b\n%a =l extsb %x\n%r =l neg %a\nret %r\n}" }, &diagnostic);
    defer module.deinit();
    const text = try emit(allocator, &module);
    defer allocator.free(text);
    try testing.expect(std.mem.indexOf(u8, text, "movsbq %al, %rax") != null);
    try testing.expect(std.mem.indexOf(u8, text, "negq %rax") != null);
}

test "unary emission cleans up every allocation failure" {
    try @import("test_support.zig").checkAllocationFailures(exerciseUnary);
}

fn exerciseDivision(allocator: std.mem.Allocator) !void {
    var diagnostic: ?source.Diagnostic = null;
    var module = try frontend.parse(allocator, .{ .name = "division", .text = "function l $f(l %a, l %b) {\n@entry\n%x =l div %a, %b\n%y =l rem %a, %b\n%r =l add %x, %y\nret %r\n}" }, &diagnostic);
    defer module.deinit();
    const text = try emit(allocator, &module);
    defer allocator.free(text);
    try testing.expect(std.mem.indexOf(u8, text, "cqto\n\tidivq %r10") != null);
}

test "division emission cleans up every allocation failure" {
    try @import("test_support.zig").checkAllocationFailures(exerciseDivision);
}

fn exerciseFloating(allocator: std.mem.Allocator) !void {
    var diagnostic: ?source.Diagnostic = null;
    var module = try frontend.parse(allocator, .{ .name = "floating", .text = "function d $f(w %p, d %a, d %b) {\n@entry\njnz %p, @left, @right\n@left\n%x =d mul %a, %b\njmp @join\n@right\n%y =d neg %a\njmp @join\n@join\n%z =d phi @left %x, @right %y\nret %z\n}" }, &diagnostic);
    defer module.deinit();
    const text = try emit(allocator, &module);
    defer allocator.free(text);
    try testing.expect(std.mem.indexOf(u8, text, "mulsd %xmm1, %xmm0") != null);
    try testing.expect(std.mem.indexOf(u8, text, "movq %xmm1, %rax") != null);
}

test "floating emission and validation scratch clean up every allocation failure" {
    try @import("test_support.zig").checkAllocationFailures(exerciseFloating);
}

test "floating literal and direct IR payloads are loaded as exact integer bits" {
    var module = try parse("function s $s() {\n@entry\n%x =s copy s_-0\nret %x\n}\nfunction d $d() {\n@entry\n%x =d copy d_0\nret %x\n}");
    defer module.deinit();
    module.functions.items[1].blocks.items[0].instructions.items[0].copy.operand = .{ .constant = .{ .double_bits = 0x7ff0000000001234 } };
    const text = try emit(testing.allocator, &module);
    defer testing.allocator.free(text);
    try testing.expect(std.mem.indexOf(u8, text, "movl $0x80000000, %eax") != null);
    try testing.expect(std.mem.indexOf(u8, text, "movabsq $0x7ff0000000001234, %rax") != null);
}

fn exerciseConversions(allocator: std.mem.Allocator) !void {
    var diagnostic: ?source.Diagnostic = null;
    var module = try frontend.parse(allocator, .{ .name = "conversion", .text = "function l $f(w %v) {\n@entry\n%s =s cast %v\n%d =d exts %s\n%r =l cast %d\nret %r\n}" }, &diagnostic);
    defer module.deinit();
    const result = (try @import("interpreter.zig").evaluate(allocator, module.functions.items[0], &.{.{ .word = 0x3f800000 }}, .{})).?;
    try testing.expectEqual(@as(u64, 0x3ff0000000000000), result.long);
    const text = try emit(allocator, &module);
    defer allocator.free(text);
    try testing.expect(std.mem.indexOf(u8, text, "cvtss2sd %xmm0, %xmm0") != null);
}

test "cast and widening parsing evaluation and emission clean up allocation failures" {
    try @import("test_support.zig").checkAllocationFailures(exerciseConversions);
}

fn exerciseFloatComparisons(allocator: std.mem.Allocator) !void {
    var diagnostic: ?source.Diagnostic = null;
    var module = try frontend.parse(allocator, .{ .name = "float-comparison", .text = "function l $f(s %a, s %b) {\n@entry\n%r =l cuos %a, %b\nret %r\n}" }, &diagnostic);
    defer module.deinit();
    const result = (try @import("interpreter.zig").evaluate(allocator, module.functions.items[0], &.{ .{ .single_bits = 0x7fc01234 }, .{ .single_bits = 0 } }, .{})).?;
    try testing.expectEqual(@as(u64, 1), result.long);
    const text = try emit(allocator, &module);
    defer allocator.free(text);
    try testing.expect(std.mem.indexOf(u8, text, "ucomiss %xmm1, %xmm0") != null);
    try testing.expect(std.mem.indexOf(u8, text, "setp %al") != null);
}

test "floating comparison parsing evaluation and emission clean up every allocation failure" {
    try @import("test_support.zig").checkAllocationFailures(exerciseFloatComparisons);
}

test "optional stack reuse shrinks frames without changing default emission" {
    var module = try parse("function l $f(w %a) {\n@b\n%s =s cast %a\n%d =d exts %s\n%x =l cast %d\n%r =l add %x, 1\nret %r\n}");
    defer module.deinit();
    const original = try emit(testing.allocator, &module);
    defer testing.allocator.free(original);
    const explicit_default = try emitWithOptions(testing.allocator, &module, .{});
    defer testing.allocator.free(explicit_default);
    try testing.expectEqualSlices(u8, original, explicit_default);
    const reused = try emitWithOptions(testing.allocator, &module, .{ .reuse_stack_homes = true });
    defer testing.allocator.free(reused);
    try testing.expect(std.mem.indexOf(u8, original, "subq $48, %rsp") != null);
    try testing.expect(std.mem.indexOf(u8, reused, "subq $16, %rsp") != null);
    try testing.expect(std.mem.indexOf(u8, reused, "-16(%rbp)") == null);
}

test "reused phi scratch starts after all colored homes and remains parallel" {
    var module = try parse(@embedFile("fixtures/phi-loop.ssa"));
    defer module.deinit();
    var layout = try stack_homes.Layout.init(testing.allocator, module.functions.items[0], .{});
    defer layout.deinit();
    const assembly = try emitWithOptions(testing.allocator, &module, .{ .reuse_stack_homes = true });
    defer testing.allocator.free(assembly);
    for (0..3) |index| {
        const store = try std.fmt.allocPrint(testing.allocator, "movl %eax, -{d}(%rbp)", .{(layout.slot_count + index + 1) * 8});
        defer testing.allocator.free(store);
        try testing.expect(std.mem.indexOf(u8, assembly, store) != null);
    }
}

fn exerciseReusedHomes(allocator: std.mem.Allocator) !void {
    var diagnostic: ?source.Diagnostic = null;
    var module = try frontend.parse(allocator, .{ .name = "reused-homes", .text = @embedFile("fixtures/phi-loop.ssa") ++ "\nfunction l $bits(w %a) {\n@b\n%s =s cast %a\n%d =d exts %s\n%x =l cast %d\nret %x\n}" }, &diagnostic);
    defer module.deinit();
    const assembly = try emitWithOptions(allocator, &module, .{ .reuse_stack_homes = true });
    defer allocator.free(assembly);
    try testing.expect(std.mem.indexOf(u8, assembly, "cvtss2sd") != null);
}
test "reused-home emission cleans up every allocation failure across functions" {
    try @import("test_support.zig").checkAllocationFailures(exerciseReusedHomes);
}

test "reused frame limit applies to homes rather than original value count" {
    var module = Module.init(testing.allocator);
    defer module.deinit();
    const function_id = try module.addFunction("long_chain", .word);
    const f = module.getFunction(function_id).?;
    const block = try f.addBlock(null);
    var previous = try f.appendCopy(block, .word, .{ .constant = .{ .word = 1 } });
    for (0..8192) |_| previous = try f.appendBinary(block, .word, .add, .{ .value = previous }, .{ .constant = .{ .word = 1 } });
    try f.terminate(block, .{ .return_value = .{ .value = previous } });
    try testing.expectError(error.FrameTooLarge, emit(testing.allocator, &module));
    const assembly = try emitWithOptions(testing.allocator, &module, .{ .reuse_stack_homes = true });
    defer testing.allocator.free(assembly);
    try testing.expect(std.mem.indexOf(u8, assembly, "subq $16, %rsp") != null);
}

test "preserved register homes use width-aware moves and save only used registers" {
    var module = try parse("function l $f(w %a) {\n@b\n%s =s cast %a\n%d =d exts %s\n%x =l cast %d\nret %x\n}");
    defer module.deinit();
    const assembly = try emitWithOptions(testing.allocator, &module, .{ .callee_saved_homes = true });
    defer testing.allocator.free(assembly);
    try testing.expect(std.mem.indexOf(u8, assembly, "movq %rbx, -8(%rbp)") != null);
    try testing.expect(std.mem.indexOf(u8, assembly, "movq -8(%rbp), %rbx") != null);
    try testing.expect(std.mem.indexOf(u8, assembly, "movl %edi, %ebx") != null);
    try testing.expect(std.mem.indexOf(u8, assembly, "movq %rbx, %rax") != null);
    try testing.expect(std.mem.indexOf(u8, assembly, "%r12") == null);
    const combined = try emitWithOptions(testing.allocator, &module, .{ .callee_saved_homes = true, .reuse_stack_homes = true });
    defer testing.allocator.free(combined);
    try testing.expectEqualSlices(u8, assembly, combined);
}

test "preserved homes keep ordinary stack phi scratch and saved areas disjoint" {
    var module = try parse(@embedFile("fixtures/preserved-homes.ssa"));
    defer module.deinit();
    var layout = try stack_homes.Layout.init(testing.allocator, module.functions.items[0], .{});
    defer layout.deinit();
    try testing.expect(layout.slot_count > preserved_registers.len);
    const assembly = try emitWithOptions(testing.allocator, &module, .{ .callee_saved_homes = true });
    defer testing.allocator.free(assembly);
    const stack_count = layout.slot_count - preserved_registers.len;
    const saved_base = (stack_count + 7) * 8;
    for (preserved_registers, 0..) |preserved, i| {
        const store = try std.fmt.allocPrint(testing.allocator, "movq {s}, -{d}(%rbp)", .{ preserved.name(.long), saved_base + (i + 1) * 8 });
        defer testing.allocator.free(store);
        const restore = try std.fmt.allocPrint(testing.allocator, "movq -{d}(%rbp), {s}", .{ saved_base + (i + 1) * 8, preserved.name(.long) });
        defer testing.allocator.free(restore);
        try testing.expect(std.mem.indexOf(u8, assembly, store) != null);
        try testing.expect(std.mem.indexOf(u8, assembly, restore) != null);
    }
    const expected = (try @import("interpreter.zig").evaluate(testing.allocator, module.functions.items[0], &.{}, .{})).?;
    try testing.expectEqual(@as(u64, 21), expected.long);
}

test "all return paths restore preserved registers and empty functions allocate none" {
    var module = try parse("function w $branch(w %p) {\n@entry\njnz %p, @a, @b\n@a\nret 1\n@b\nret %p\n}\nfunction $empty() {\n@entry\nret\n}");
    defer module.deinit();
    const assembly = try emitWithOptions(testing.allocator, &module, .{ .callee_saved_homes = true });
    defer testing.allocator.free(assembly);
    try testing.expectEqual(@as(usize, 2), std.mem.count(u8, assembly, "movq -8(%rbp), %rbx\n\tleave\n\tret"));
    const empty = assembly[std.mem.indexOf(u8, assembly, "empty:\n").?..];
    try testing.expect(std.mem.indexOf(u8, empty, "%rbx") == null);
    try testing.expect(std.mem.indexOf(u8, empty, "subq $") == null);
    try testing.expectError(error.FrameTooLarge, Frame.withSavedCounts(8192, 0, 0, 1));
    try testing.expectError(error.FrameTooLarge, Frame.withSavedCounts(0, 0, 0, std.math.maxInt(usize)));
}

fn exercisePreservedHomes(allocator: std.mem.Allocator) !void {
    var diagnostic: ?source.Diagnostic = null;
    var module = try frontend.parse(allocator, .{ .name = "preserved-homes", .text = @embedFile("fixtures/preserved-homes.ssa") ++ "\nfunction s $bits(w %a) {\n@b\n%s =s cast %a\nret %s\n}" }, &diagnostic);
    defer module.deinit();
    const assembly = try emitWithOptions(allocator, &module, .{ .callee_saved_homes = true });
    defer allocator.free(assembly);
    try testing.expect(std.mem.indexOf(u8, assembly, "%r15") != null);
}
test "preserved-register emission frees every failed allocation across functions" {
    try @import("test_support.zig").checkAllocationFailures(exercisePreservedHomes);
}

test "floating and void returns restore homes without clobbering result registers" {
    var module = try parse("function d $floating(d %a) {\n@b\nret %a\n}\nfunction $nothing() {\n@b\n%dead =w copy 1\nret\n}");
    defer module.deinit();
    const assembly = try emitWithOptions(testing.allocator, &module, .{ .callee_saved_homes = true });
    defer testing.allocator.free(assembly);
    try testing.expect(std.mem.indexOf(u8, assembly, "movq %rax, %xmm0\n\tmovq -8(%rbp), %rbx\n\tleave\n\tret") != null);
    const nothing = assembly[std.mem.indexOf(u8, assembly, "nothing:\n").?..];
    try testing.expect(std.mem.indexOf(u8, nothing, "movl %eax, %ebx\n\tmovq -8(%rbp), %rbx\n\tleave\n\tret") != null);
}

test "fixed frame reservation descends and touches every bounded page including the remainder" {
    var module = Module.init(testing.allocator);
    defer module.deinit();
    for ([_]usize{ 0, 16, 4080, 4096, 4112, 8192, 65536 }) |bytes| {
        var emitter: Emitter = .{ .output = .init(testing.allocator), .module = &module, .allocator = testing.allocator, .options = .{} };
        defer emitter.output.deinit();
        try emitter.reserveFrame(try Frame.fromCounts(bytes / 8, 0, 0));
        const assembly = try emitter.output.toOwnedSlice();
        defer testing.allocator.free(assembly);
        var lines = std.mem.tokenizeScalar(u8, assembly, '\n');
        var total: usize = 0;
        var touches: usize = 0;
        while (lines.next()) |line| {
            try testing.expect(std.mem.startsWith(u8, line, "\tsubq $"));
            const comma = std.mem.indexOfScalar(u8, line, ',').?;
            const step = try std.fmt.parseInt(usize, line[7..comma], 10);
            try testing.expect(step > 0 and step <= 4096 and step % 16 == 0);
            total += step;
            try testing.expectEqualStrings("\ttestb $0, (%rsp)", lines.next().?);
            touches += 1;
        }
        try testing.expectEqual(bytes, total);
        try testing.expectEqual((bytes + 4095) / 4096, touches);
    }
}

fn exerciseFrameProbes(allocator: std.mem.Allocator) !void {
    var module = Module.init(allocator);
    defer module.deinit();
    var emitter: Emitter = .{ .output = .init(allocator), .module = &module, .allocator = allocator, .options = .{} };
    defer emitter.output.deinit();
    try emitter.reserveFrame(try Frame.fromCounts(8192, 0, 0));
    const assembly = try emitter.output.toOwnedSlice();
    defer allocator.free(assembly);
    try testing.expectEqual(@as(usize, 16), std.mem.count(u8, assembly, "testb $0, (%rsp)"));
}
test "maximum fixed frame probe output cleans every failed allocation" {
    try @import("test_support.zig").checkAllocationFailures(exerciseFrameProbes);
}

test "dynamic allocation bases use aligned outgoing reservations even for one overflow slot" {
    var module = try parse("function l $f(l %n) {\n@e\n%p =l alloc16 %n\n%r =l call $sink(l %p,l 1,l 2,l 3,l 4,l 5,l 6)\nret %r\n}");
    defer module.deinit();
    var frame = try Frame.init(module.functions.items[0]);
    try frame.addOutgoing(module.functions.items[0]);
    try testing.expectEqual(@as(usize, 16), frame.outgoing_bytes);
    try testing.expectEqual(@as(usize, 0), frame.bytes % 16);
    const assembly = try emit(testing.allocator, &module);
    defer testing.allocator.free(assembly);
    try testing.expect(std.mem.indexOf(u8, assembly, "leaq 16(%rsp), %rax") != null);
}

test "variadic save area is aligned disjoint and included in fixed frame cap before outgoing" {
    var frame = try Frame.withSavedCounts(3, 2, 1, 5);
    const old = frame;
    try frame.addVariadic(false);
    try testing.expectEqualDeep(old, frame);
    try frame.addVariadic(true);
    try testing.expectEqual(old.bytes + 176, frame.bytes);
    try testing.expectEqual(frame.bytes, frame.variadic_save_end.?);
    try testing.expectEqual(@as(usize, 0), frame.variadic_save_end.? % 16);
    try testing.expectEqual(old.saved_base, frame.saved_base);
    try testing.expectEqual(old.scratch_base, frame.scratch_base);
    var exact = try Frame.fromCounts(8170, 0, 0);
    try exact.addVariadic(true);
    try testing.expectEqual(@as(usize, 65536), exact.bytes);
    var excess = try Frame.fromCounts(8171, 0, 0);
    try testing.expectError(error.FrameTooLarge, excess.addVariadic(true));
    var overflow = exact;
    overflow.bytes = std.math.maxInt(usize);
    try testing.expectError(error.FrameTooLarge, overflow.addVariadic(true));
    var caller = ir.Function.init(testing.allocator, @fromBackingInt(@as(u32, 0)), null);
    defer caller.deinit();
    const block = try caller.addBlock(null);
    const argument: ir.CallArgument = .{ .scalar_type = .word, .operand = .{ .constant = .{ .word = 1 } } };
    var arguments: [7]ir.CallArgument = undefined;
    for (&arguments) |*entry| entry.* = argument;
    try caller.appendVoidCall(block, caller.name, &arguments);
    try caller.terminate(block, .{ .return_value = null });
    var outgoing_exact = try Frame.fromCounts(8168, 0, 0);
    try outgoing_exact.addVariadic(true);
    try outgoing_exact.addOutgoing(&caller);
    try testing.expectEqual(@as(usize, 65536), outgoing_exact.bytes);
    try testing.expectEqual(@as(usize, 16), outgoing_exact.outgoing_bytes);
    try testing.expectEqual(@as(?usize, 65520), outgoing_exact.variadic_save_end);
    var outgoing_excess = exact;
    try testing.expectError(error.FrameTooLarge, outgoing_excess.addOutgoing(&caller));
}
