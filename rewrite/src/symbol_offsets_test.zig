const std = @import("std");
const testing = std.testing;
const ir = @import("ir.zig");
const interpreter = @import("interpreter.zig");
const validation = @import("module_validation.zig");
const amd64 = @import("amd64.zig");
const entry: @import("module.zig").FunctionId = @fromBackingInt(@as(u32, 0));
fn parse(allocator: std.mem.Allocator, text: []const u8) !@import("module.zig").Module {
    var diagnostic: ?@import("source.zig").Diagnostic = null;
    return @import("frontend.zig").parse(allocator, .{ .name = "symbol-offsets", .text = text }, &diagnostic);
}
const fixture = @embedFile("fixtures/symbol-offsets.ssa");
const contexts = [_][]const u8{
    "function l $f() {\n@e\n%x =l shl $target+3, 1\nret %x\n}",
    "function l $f() {\n@e\n%x =l add $target+3, $target+-2\nret %x\n}",
    "function l $f() {\n@e\n%x =l neg $target+3\nret %x\n}",
    "function d $f() {\n@e\n%x =d sltof $target+3\nret %x\n}",
    "function w $f() {\n@e\n%x =w ceql $target+3, $target+-2\nret %x\n}",
    "function l $f() {\n@e\nret $target+3\n}",
    "function l $f() {\n@e\n%p =l copy $target+3\nret %p\n}",
    "function l $f() {\n@e\n%p =l loadl $target+3\nret %p\n}",
    "function $f() {\n@e\nstorel $target+3, $target+3\nret\n}",
    "function $f() {\n@e\nblit $target+3, $target+3, 0\nret\n}",
    "function $f() {\n@e\ncall $external(l $target+3)\nret\n}",
    "function l $f() {\n@e\n%p =l alloc4 $target+3\nret %p\n}",
    "function l $f() {\n@e\nret 0\n@dead\nret $target+3\n}",
    "function w $f() {\n@e\njnz $target+3, @yes, @no\n@yes\nret 1\n@no\nret 0\n}",
    "function l $f(w %c) {\n@e\njnz %c, @left, @right\n@left\njmp @join\n@right\njmp @join\n@join\n%p =l phi @left $target+3, @right $target+3\nret %p\n}",
};

fn replaceOffsets(function: *ir.Function, symbol: @import("symbols.zig").Id) void {
    // Test-only independent exhaustive positions, deliberately not the production
    // operand iterator. Contexts below use only these instruction forms.
    // Const casts intentionally corrupt allocator-owned slices for verifier tests.
    for (function.blocks.items) |*block| {
        for (block.phis.items) |*phi| for (@constCast(phi.inputs)) |*input| {
            if (input.value == .symbol_offset) input.value.symbol_offset.symbol = symbol;
        };
        for (block.instructions.items) |*instruction| switch (instruction.*) {
            .shift => |*shift| if (shift.value == .symbol_offset) {
                shift.value.symbol_offset.symbol = symbol;
            },
            .binary => |*binary| {
                if (binary.lhs == .symbol_offset) binary.lhs.symbol_offset.symbol = symbol;
                if (binary.rhs == .symbol_offset) binary.rhs.symbol_offset.symbol = symbol;
            },
            .unary => |*unary| if (unary.operand == .symbol_offset) {
                unary.operand.symbol_offset.symbol = symbol;
            },
            .convert => |*convert| if (convert.operand == .symbol_offset) {
                convert.operand.symbol_offset.symbol = symbol;
            },
            .compare_integer => |*compare| {
                if (compare.lhs == .symbol_offset) compare.lhs.symbol_offset.symbol = symbol;
                if (compare.rhs == .symbol_offset) compare.rhs.symbol_offset.symbol = symbol;
            },
            .copy => |*copy| if (copy.operand == .symbol_offset) {
                copy.operand.symbol_offset.symbol = symbol;
            },
            .load => |*load| if (load.address == .symbol_offset) {
                load.address.symbol_offset.symbol = symbol;
            },
            .store => |*store| {
                if (store.value == .symbol_offset) store.value.symbol_offset.symbol = symbol;
                if (store.address == .symbol_offset) store.address.symbol_offset.symbol = symbol;
            },
            .blit => |*blit| {
                if (blit.source == .symbol_offset) blit.source.symbol_offset.symbol = symbol;
                if (blit.destination == .symbol_offset) blit.destination.symbol_offset.symbol = symbol;
            },
            .allocate => |*allocation| if (allocation.size == .symbol_offset) {
                allocation.size.symbol_offset.symbol = symbol;
            },
            .call => |*call| {
                if (call.callee == .address and call.callee.address == .symbol_offset) call.callee.address.symbol_offset.symbol = symbol;
                for (@constCast(call.arguments)) |*argument| if (argument.operand == .symbol_offset) {
                    argument.operand.symbol_offset.symbol = symbol;
                };
            },
            else => {},
        };
        switch (block.terminator.?) {
            .return_value => |value| if (value != null and value.? == .symbol_offset) {
                block.terminator.?.return_value.?.symbol_offset.symbol = symbol;
            },
            .branch => |branch| if (branch.condition == .symbol_offset) {
                block.terminator.?.branch.condition.symbol_offset.symbol = symbol;
            },
            else => {},
        }
    }
}

test "scalar symbol offsets preserve checked signed i32 payload and copied non-SSA identity" {
    for ([_]i32{ 0, 1, -1, std.math.minInt(i32), std.math.maxInt(i32) }) |addend| {
        const text = try std.fmt.allocPrint(testing.allocator, "function l $f() {{\n@e\n%p =l copy $target+{d}\nret %p\n}}", .{addend});
        defer testing.allocator.free(text);
        var module = try parse(testing.allocator, text);
        defer module.deinit();
        const f = module.functions.items[0];
        const operand = f.blocks.items[0].instructions.items[0].copy.operand;
        try testing.expectEqual(addend, operand.symbol_offset.addend);
        try testing.expectEqualStrings("target", module.symbols.get(operand.symbol_offset.symbol).?);
        try testing.expectEqual(ir.ScalarType.long, try f.operandType(operand));
        try testing.expect(operand.referencedValue() == null);
        try testing.expectEqual(operand.symbol_offset.symbol, operand.referencedSymbol().?);
        var uses = f.blocks.items[0].instructions.items[0].operands();
        f.blocks.items[0].instructions.items[0].copy.operand = .{ .constant = .{ .long = 0 } };
        try testing.expectEqualDeep(operand, uses.next().?);
        try testing.expect(uses.next() == null);
        try testing.expect(uses.next() == null);
    }
    var bare = try parse(testing.allocator, "function l $f() {\n@e\nret $target\n}");
    defer bare.deinit();
    const operand = bare.functions.items[0].blocks.items[0].terminator.?.return_value.?;
    try testing.expect(operand == .symbol);
    try testing.expectEqual(operand.symbol, operand.referencedSymbol().?);
    try testing.expect((ir.Operand{ .constant = .{ .long = 1 } }).referencedSymbol() == null);
}

test "scalar displacement syntax rejects overflow wrong classes malformed addends and direct target expressions" {
    for ([_][]const u8{
        "function l $f() {\n@e\nret $target+2147483648\n}",
        "function l $f() {\n@e\nret $target+-2147483649\n}",
        "function l $f() {\n@e\nret $target+18446744073709551616\n}",
        "function l $f() {\n@e\nret $target+\n1\n}",
        "function l $f() {\n@e\nret $target\n+1\n}",
        "function l $f() {\n@e\nret $target-8\n}",
        "function l $f() {\n@e\nret $target++8\n}",
        "function l $f() {\n@e\nret $target+$other\n}",
        "function l $f() {\n@e\nret $target+d_1\n}",
        "function l $f() {\n@e\nret $target+1+2\n}",
        "function l $f() {\n@e\nret $\"quoted\"+1\n}",
        "function w $f() {\n@e\nret $target+0\n}",
        "function s $f() {\n@e\nret $target+0\n}",
        "function d $f() {\n@e\nret $target+0\n}",
        "function $f() {\n@e\ncall $target+0()\nret\n}",
        "function $f() {\n@e\ncall $target(w $other+0)\nret\n}",
    }) |text| {
        if (parse(testing.allocator, text)) |owned| {
            var unexpected = owned;
            unexpected.deinit();
            return error.ExpectedInvalidOffset;
        } else |err| try testing.expectEqual(error.InvalidInput, err);
    }
    const text = "function l $f() {\n@e\nret $target+-2147483649\n}";
    const input: @import("source.zig").Source = .{ .name = "offset-overflow", .text = text };
    var diagnostic: ?@import("source.zig").Diagnostic = null;
    try testing.expectError(error.InvalidInput, @import("frontend.zig").parse(testing.allocator, input, &diagnostic));
    try testing.expectEqual(@import("source.zig").Diagnostic.Code.invalid_integer, diagnostic.?.code);
    try testing.expectEqualStrings("-2147483649", input.slice(diagnostic.?.span).?);
    // The wider checked data-initializer language has not been narrowed.
    var data = try parse(testing.allocator, "data $x = { l $target+9223372036854775807 $target+-9223372036854775808 }");
    defer data.deinit();
    try testing.expectEqual(std.math.maxInt(i64), data.data.items[0].items.items[0].symbol_address.addend);
    try testing.expectEqual(std.math.minInt(i64), data.data.items[0].items.items[1].symbol_address.addend);
}

test "offset module and target validation cover scalar positions including unreachable phi and indirect target" {
    for (contexts) |text| {
        var module = try parse(testing.allocator, text);
        defer module.deinit();
        try validation.validate(testing.allocator, &module);
        const f = module.functions.items[0];
        replaceOffsets(f, try module.symbols.intern("bad\n.quad injected"));
        try validation.validate(testing.allocator, &module);
        try testing.expectError(error.InvalidSymbol, amd64.emit(testing.allocator, &module));
        replaceOffsets(f, @fromBackingInt(std.math.maxInt(u32)));
        try f.validateStructure();
        try testing.expectError(error.InvalidSymbol, validation.validate(testing.allocator, &module));
        try testing.expectError(error.InvalidSymbol, amd64.emit(testing.allocator, &module));
    }
    var indirect = try parse(testing.allocator, "function l $f() {\n@e\n%r =l call 0()\nret %r\n}");
    defer indirect.deinit();
    const callee = &indirect.functions.items[0].blocks.items[0].instructions.items[0].call.callee;
    callee.* = .{ .address = .{ .symbol_offset = .{ .symbol = try indirect.symbols.intern("external"), .addend = 0 } } };
    const assembly = try amd64.emit(testing.allocator, &indirect);
    defer testing.allocator.free(assembly);
    try testing.expect(std.mem.indexOf(u8, assembly, "leaq external+0(%rip), %rax\n\tmovq %rax, %r11") != null);
    try testing.expect(std.mem.indexOf(u8, assembly, "call *%r11") != null);
    callee.* = .{ .address = .{ .symbol_offset = .{ .symbol = try indirect.symbols.intern("bad\n.text"), .addend = -7 } } };
    try testing.expectError(error.InvalidSymbol, amd64.emit(testing.allocator, &indirect));
    callee.address.symbol_offset.symbol = @fromBackingInt(std.math.maxInt(u32));
    try testing.expectError(error.InvalidSymbol, validation.validate(testing.allocator, &indirect));
}

test "offset folding stays unknown and emits signed full-width RIP-relative expressions in every home mode" {
    var boundary = try parse(testing.allocator, "function l $f() {\n@e\n%x =l copy $target+-2147483648\n%y =l add %x, $target+2147483647\nret %y\n}");
    defer boundary.deinit();
    _ = try @import("optimize.zig").foldIntegerConstants(testing.allocator, boundary.functions.items[0]);
    try testing.expect(boundary.functions.items[0].blocks.items[0].instructions.items[0].copy.operand == .symbol_offset);
    for ([_]amd64.Options{ .{}, .{ .reuse_stack_homes = true }, .{ .callee_saved_homes = true }, .{ .reuse_stack_homes = true, .callee_saved_homes = true } }) |options| {
        const assembly = try amd64.emitWithOptions(testing.allocator, &boundary, options);
        defer testing.allocator.free(assembly);
        try testing.expect(std.mem.indexOf(u8, assembly, "leaq target-2147483648(%rip), %rax") != null);
        try testing.expect(std.mem.indexOf(u8, assembly, "leaq target+2147483647(%rip)") != null);
        try testing.expect(std.mem.indexOf(u8, assembly, "movabsq $target") == null);
    }
}

test "reached offsets refuse interpreter resolution preserving budgets safe branches and earlier writes" {
    var module = try parse(testing.allocator, "function l $f(w %take) {\n@e\njnz %take, @symbol, @safe\n@symbol\nret $target+-8\n@safe\nret 42\n}");
    defer module.deinit();
    const f = module.functions.items[0];
    for ([_]interpreter.Options{ .{}, .{ .stack_memory = .{} } }) |options| {
        try testing.expectEqual(@as(u64, 42), (try interpreter.evaluate(testing.allocator, f, &.{.{ .word = 0 }}, options)).?.long);
        try testing.expectError(error.UnsupportedSymbolAddress, interpreter.evaluate(testing.allocator, f, &.{.{ .word = 1 }}, options));
        try testing.expectError(error.UnsupportedSymbolAddress, interpreter.evaluateModule(testing.allocator, &module, entry, &.{.{ .word = 1 }}, options));
    }
    try testing.expectError(error.StepLimitExceeded, interpreter.evaluate(testing.allocator, f, &.{.{ .word = 1 }}, .{ .max_steps = 1 }));
    var phi = try parse(testing.allocator, contexts[contexts.len - 1]);
    defer phi.deinit();
    try testing.expectError(error.UnsupportedSymbolAddress, interpreter.evaluate(testing.allocator, phi.functions.items[0], &.{.{ .word = 0 }}, .{}));
    try testing.expectError(error.StepLimitExceeded, interpreter.evaluate(testing.allocator, phi.functions.items[0], &.{.{ .word = 0 }}, .{ .max_steps = 2 }));
    try exerciseRefusal(testing.allocator);
    var call = try parse(testing.allocator, "function $f() {\n@e\ncall $external(l $target+3)\nret\n}");
    defer call.deinit();
    try testing.expectError(error.UnsupportedCall, interpreter.evaluate(testing.allocator, call.functions.items[0], &.{}, .{}));
    try testing.expectError(error.UnsupportedExternalCall, interpreter.evaluateModule(testing.allocator, &call, entry, &.{}, .{}));
}

fn exerciseRefusal(allocator: std.mem.Allocator) !void {
    var module = try parse(allocator, "function $root(l %image) {\n@e\n%own =l alloc4 8\nstorel 17, %image\ncall $child()\nret\n}\nfunction $child() {\n@e\n%own =l alloc16 8\n%bad =l copy $target+-17\nret\n}");
    defer module.deinit();
    var image = try @import("memory.zig").Image.init(allocator, 8, .{});
    defer image.deinit();
    if (interpreter.evaluateModule(allocator, &module, entry, &.{.{ .long = image.base }}, .{ .memory_image = &image, .stack_memory = .{} })) |_| return error.ExpectedRefusal else |err| {
        if (err != error.UnsupportedSymbolAddress) return err;
    }
    try testing.expectEqual(@as(u64, 17), (try image.read(.long, .long, image.base)).long);
}
fn exercise(allocator: std.mem.Allocator) !void {
    var module = try parse(allocator, fixture);
    defer module.deinit();
    try validation.validate(allocator, &module);
    for (module.functions.items) |f| {
        _ = try @import("optimize.zig").foldIntegerConstants(allocator, f);
        var live = try @import("liveness.zig").Snapshot.init(allocator, f, .{});
        defer live.deinit();
        var conflicts = try @import("interference.zig").Graph.init(allocator, f, .{});
        defer conflicts.deinit();
    }
    for ([_]amd64.Options{ .{}, .{ .reuse_stack_homes = true, .callee_saved_homes = true } }) |options| {
        const assembly = try amd64.emitWithOptions(allocator, &module, options);
        defer allocator.free(assembly);
    }
    try exerciseRefusal(allocator);
    if (parse(allocator, "function l $f() {\n@e\n%x =l copy $target+8\nret $other+2147483648\n}")) |owned| {
        var unexpected = owned;
        unexpected.deinit();
        return error.ExpectedInvalidOffset;
    } else |err| if (err != error.InvalidInput) return err;
}
test "symbol offset parsing analysis emission and refused evaluation free every failed allocation" {
    try @import("test_support.zig").checkAllocationFailures(exercise);
}
