const std = @import("std");
const ir = @import("ir.zig");
const ssa = @import("ssa.zig");
const Module = @import("module.zig").Module;
pub const Error = ssa.Error || error{ InvalidSymbol, DuplicateSymbol, FrameTooLarge };

/// Experimental Linux ELF/System V base-scalar slice. Every SSA value has a stack
/// home; this is not instruction selection/register allocation parity with QBE.
/// Caller owns the returned assembly. Invalid input never returns partial text.
pub fn emit(allocator: std.mem.Allocator, module: *const Module) Error![]u8 {
    for (module.functions.items, 0..) |function, index| {
        const name = module.symbols.get(function.name) orelse return error.InvalidSymbol;
        if (!validSymbol(name)) return error.InvalidSymbol;
        for (module.functions.items[0..index]) |previous| if (previous.name == function.name) return error.DuplicateSymbol;
        _ = try Frame.init(function);
        var issue: ?ssa.Issue = null;
        try ssa.validate(allocator, function, &issue);
    }
    var emitter: Emitter = .{ .output = .init(allocator), .module = module };
    defer emitter.output.deinit();
    try emitter.print(".text\n", .{});
    for (module.functions.items, 0..) |function, index| try emitter.function(function, index);
    try emitter.print(".section .note.GNU-stack,\"\",@progbits\n", .{});
    return emitter.output.toOwnedSlice();
}

const Frame = struct {
    bytes: usize,
    scratch_base: usize,

    fn init(function: *const ir.Function) error{FrameTooLarge}!Frame {
        var max_phis: usize = 0;
        for (function.blocks.items) |block| max_phis = @max(max_phis, block.phis.items.len);
        return fromCounts(function.values.items.len, max_phis, function.parameters.items.len);
    }

    fn fromCounts(values: usize, phis: usize, parameters: usize) error{FrameTooLarge}!Frame {
        const count = std.math.add(usize, values, phis) catch return error.FrameTooLarge;
        const raw = std.math.mul(usize, count, 8) catch return error.FrameTooLarge;
        const rounded = std.math.add(usize, raw, 15) catch return error.FrameTooLarge;
        const bytes = rounded & ~@as(usize, 15);
        // Explicit prototype limit; large-frame probing is not implemented.
        if (bytes > 64 * 1024) return error.FrameTooLarge;
        if (parameters > 6 and parameters - 6 > (std.math.maxInt(i32) - 16) / 8) return error.FrameTooLarge;
        return .{ .bytes = bytes, .scratch_base = values * 8 };
    }
};

const Scratch = enum { accumulator, temporary, count };
const ArgumentRegisters = struct { word: []const u8, long: []const u8 };
const argument_registers = [_]ArgumentRegisters{
    .{ .word = "%edi", .long = "%rdi" }, .{ .word = "%esi", .long = "%rsi" },
    .{ .word = "%edx", .long = "%rdx" }, .{ .word = "%ecx", .long = "%rcx" },
    .{ .word = "%r8d", .long = "%r8" },  .{ .word = "%r9d", .long = "%r9" },
};

const Emitter = struct {
    output: std.Io.Writer.Allocating,
    module: *const Module,
    current: *const ir.Function = undefined,
    ordinal: usize = 0,
    frame: Frame = undefined,

    fn print(self: *Emitter, comptime format: []const u8, args: anytype) Error!void {
        // The allocating writer's only backing failure is allocator exhaustion.
        self.output.writer.print(format, args) catch return error.OutOfMemory;
    }

    fn function(self: *Emitter, f: *const ir.Function, index: usize) Error!void {
        self.current = f;
        self.ordinal = index;
        self.frame = try Frame.init(f);
        const name = self.module.symbols.get(f.name).?;
        try self.print("{s} {s}\n.type {s}, @function\n{s}:\n\tpushq %rbp\n\tmovq %rsp, %rbp\n", .{ if (f.linkage == .exported) @as([]const u8, ".globl") else ".local", name, name, name });
        if (self.frame.bytes != 0) try self.print("\tsubq ${d}, %rsp\n", .{self.frame.bytes});
        var gp: usize = 0;
        var fp: usize = 0;
        var stack: usize = 0;
        for (f.parameters.items) |parameter| {
            const ty = f.values.items[@backingInt(parameter)].scalar_type;
            if (ty.isInteger() and gp < argument_registers.len) {
                const registers = argument_registers[gp];
                try self.save(parameter, if (ty == .word) registers.word else registers.long);
                gp += 1;
            } else if (!ty.isInteger() and fp < 8) {
                try self.print("\tmov{c} %xmm{d}, {s}\n", .{ sseMove(ty), fp, register(ty, .accumulator) });
                try self.save(parameter, register(ty, .accumulator));
                fp += 1;
            } else {
                try self.print("\tmov{c} {d}(%rbp), {s}\n", .{ suffix(ty), 16 + stack * 8, register(ty, .accumulator) });
                try self.save(parameter, register(ty, .accumulator));
                stack += 1;
            }
        }
        for (f.blocks.items, 0..) |block, number| {
            const id: ir.BlockId = @fromBackingInt(@as(u32, @intCast(number)));
            try self.print("\".Lzbe@{d}@b{d}\":\n", .{ index, number });
            for (block.instructions.items) |instruction| switch (instruction) {
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

    fn load(self: *Emitter, operand: ir.Operand, scratch: Scratch) Error!void {
        const ty = try self.current.operandType(operand);
        const target = register(ty, scratch);
        switch (operand) {
            .value => |value| try self.print("\tmov{c} -{d}(%rbp), {s}\n", .{ suffix(ty), home(value), target }),
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
        try self.print("\tmov{c} {s}, -{d}(%rbp)\n", .{ suffix(ty), reg, home(value) });
    }
};

fn home(value: ir.ValueId) usize {
    return (@as(usize, @backingInt(value)) + 1) * 8;
}
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
