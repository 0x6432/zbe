const std = @import("std");
const testing = std.testing;
const ir = @import("ir.zig");
const interpreter = @import("interpreter.zig");
const validation = @import("module_validation.zig");
const amd64 = @import("amd64.zig");
const entry: @import("module.zig").FunctionId = @fromBackingInt(@as(u32, 0));
fn parse(allocator: std.mem.Allocator, text: []const u8) !@import("module.zig").Module {
    var diagnostic: ?@import("source.zig").Diagnostic = null;
    return @import("frontend.zig").parse(allocator, .{ .name = "symbol-addresses", .text = text }, &diagnostic);
}
const fixture = @embedFile("fixtures/symbol-addresses.ssa");
const contexts = [_][]const u8{
    "function l $f() {\n@e\nret $target\n}",
    "function l $f() {\n@e\n%p =l copy $target\nret %p\n}",
    "function l $f() {\n@e\n%p =l loadl $target\nret %p\n}",
    "function $f() {\n@e\nstorel $target, $target\nret\n}",
    "function $f() {\n@e\nblit $target, $target, 0\nret\n}",
    "function $f() {\n@e\ncall $external(l $target)\nret\n}",
    "function l $f() {\n@e\n%p =l alloc4 $target\nret %p\n}",
    "function l $f() {\n@e\nret 0\n@dead\nret $target\n}",
    "function w $f() {\n@e\njnz $target, @yes, @no\n@yes\nret 1\n@no\nret 0\n}",
    "function l $f(w %c) {\n@e\njnz %c, @left, @right\n@left\njmp @join\n@right\njmp @join\n@join\n%p =l phi @left $target, @right $target\nret %p\n}",
};

fn replaceSymbols(function: *ir.Function, symbol: @import("symbols.zig").Id) void {
    // Test-only independent exhaustive positions, deliberately not the production
    // operand iterator. Contexts below use only these instruction forms.
    // Const casts intentionally corrupt allocator-owned slices for verifier tests.
    for (function.blocks.items) |*block| {
        for (block.phis.items) |*phi| for (@constCast(phi.inputs)) |*input| {
            if (input.value == .symbol) input.value.symbol = symbol;
        };
        for (block.instructions.items) |*instruction| switch (instruction.*) {
            .copy => |*copy| if (copy.operand == .symbol) {
                copy.operand.symbol = symbol;
            },
            .load => |*load| if (load.address == .symbol) {
                load.address.symbol = symbol;
            },
            .store => |*store| {
                if (store.value == .symbol) store.value.symbol = symbol;
                if (store.address == .symbol) store.address.symbol = symbol;
            },
            .blit => |*blit| {
                if (blit.source == .symbol) blit.source.symbol = symbol;
                if (blit.destination == .symbol) blit.destination.symbol = symbol;
            },
            .allocate => |*allocation| if (allocation.size == .symbol) {
                allocation.size.symbol = symbol;
            },
            .call => |*call| {
                if (call.callee == .address and call.callee.address == .symbol) call.callee.address.symbol = symbol;
                for (@constCast(call.arguments)) |*argument| if (argument.operand == .symbol) {
                    argument.operand.symbol = symbol;
                };
            },
            else => {},
        };
        switch (block.terminator.?) {
            .return_value => |value| if (value != null and value.? == .symbol) {
                block.terminator.?.return_value.?.symbol = symbol;
            },
            .branch => |branch| if (branch.condition == .symbol) {
                block.terminator.?.branch.condition.symbol = symbol;
            },
            else => {},
        }
    }
}

test "symbol operands own module names keep long type and never invent SSA values" {
    var module = try parse(testing.allocator, "function l $f() {\n@e\n%p =l copy $target\n%r =l add %p, $target\nret %r\n}");
    defer module.deinit();
    const f = module.functions.items[0];
    const operand = f.blocks.items[0].instructions.items[0].copy.operand;
    try testing.expect(operand == .symbol);
    try testing.expectEqual(ir.ScalarType.long, try f.operandType(operand));
    try testing.expect(operand.referencedValue() == null);
    try testing.expectEqual(@as(usize, 2), f.values.items.len);
    var iterator = f.blocks.items[0].instructions.items[0].operands();
    f.blocks.items[0].instructions.items[0].copy.operand = .{ .constant = .{ .long = 0 } };
    try testing.expectEqualDeep(operand, iterator.next().?);
    try testing.expect(iterator.next() == null);
    var name: [32]u8 = undefined;
    for (0..80) |i| _ = try module.symbols.intern(try std.fmt.bufPrint(&name, "other_{d}", .{i}));
    try testing.expectEqualStrings("target", module.symbols.get(operand.symbol).?);
    try validation.validate(testing.allocator, &module);
    for ([_][]const u8{
        "function w $f() {\n@e\nret $target\n}",
        "function s $f() {\n@e\nret $target\n}",
        "function l $f() {\n@e\nret $\"\"\n}",
        "function l $f() {\n@e\nret $target+2147483648\n}",
    }) |text| {
        if (parse(testing.allocator, text)) |*unexpected| {
            var owned = unexpected.*;
            owned.deinit();
            return error.ExpectedInvalidInput;
        } else |err| try testing.expectEqual(error.InvalidInput, err);
    }
}

test "all scalar symbol positions reject invalid IDs and hostile assembler spellings" {
    for (contexts) |text| {
        var module = try parse(testing.allocator, text);
        defer module.deinit();
        try validation.validate(testing.allocator, &module);
        const f = module.functions.items[0];
        const hostile = try module.symbols.intern("bad\n.globl injected");
        replaceSymbols(f, hostile);
        try validation.validate(testing.allocator, &module); // Spelling is target-specific.
        try testing.expectError(error.InvalidSymbol, amd64.emit(testing.allocator, &module));
        replaceSymbols(f, @fromBackingInt(std.math.maxInt(u32)));
        try f.validateStructure(); // Symbol pool belongs to Module, not Function.
        try testing.expectError(error.InvalidSymbol, validation.validate(testing.allocator, &module));
        try testing.expectError(error.InvalidSymbol, amd64.emit(testing.allocator, &module));
    }
    var indirect = try parse(testing.allocator, "function l $f() {\n@e\n%r =l call 0()\nret %r\n}");
    defer indirect.deinit();
    indirect.functions.items[0].blocks.items[0].instructions.items[0].call.callee = .{ .address = .{ .symbol = @fromBackingInt(std.math.maxInt(u32)) } };
    try testing.expectError(error.InvalidSymbol, validation.validate(testing.allocator, &indirect));
}

test "symbol address facts remain unknown and materialize full-width RIP-relative addresses in every home mode" {
    var module = try parse(testing.allocator, fixture);
    defer module.deinit();
    for (module.functions.items) |f| _ = try @import("optimize.zig").foldIntegerConstants(testing.allocator, f);
    try testing.expect(module.functions.items[7].blocks.items[0].instructions.items[0].copy.operand == .symbol);
    for ([_]amd64.Options{ .{}, .{ .reuse_stack_homes = true }, .{ .callee_saved_homes = true }, .{ .reuse_stack_homes = true, .callee_saved_homes = true } }) |options| {
        const assembly = try amd64.emitWithOptions(testing.allocator, &module, options);
        defer testing.allocator.free(assembly);
        try testing.expect(std.mem.indexOf(u8, assembly, "leaq zbe_symbol_bytes(%rip), %rax") != null);
        try testing.expect(std.mem.indexOf(u8, assembly, "leaq symbol_target(%rip), %rax") != null);
        try testing.expect(std.mem.indexOf(u8, assembly, "call *%r11") != null);
        try testing.expect(std.mem.indexOf(u8, assembly, "movabsq $zbe_symbol") == null);
    }
}

test "symbol interpretation refusal preserves safe paths budget precedence and caller image writes" {
    var module = try parse(testing.allocator, "function l $f(w %take) {\n@e\njnz %take, @symbol, @safe\n@symbol\nret $target\n@safe\nret 42\n}");
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
}

fn exerciseRefusal(allocator: std.mem.Allocator) !void {
    var module = try parse(allocator, "function $root(l %image) {\n@e\n%own =l alloc4 8\nstorel 17, %image\ncall $child()\nret\n}\nfunction $child() {\n@e\n%own =l alloc16 8\n%bad =l copy $target\nret\n}");
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
}
test "all symbolic parser analysis folder emitter and refused frame allocations clean up" {
    try @import("test_support.zig").checkAllocationFailures(exercise);
}
