//! Initial GOT operand foundation: explicitly fail closed until the complete
//! parser, planning, call-target and emitter endpoint is integrated.
const std = @import("std");
const testing = std.testing;
const ir = @import("ir.zig");
const frontend = @import("frontend.zig");
const validation = @import("module_validation.zig");
const interpreter = @import("interpreter.zig");
const amd64 = @import("amd64.zig");

fn parse(text: []const u8) !@import("module.zig").Module {
    var diagnostic: ?@import("source.zig").Diagnostic = null;
    return frontend.parse(testing.allocator, .{ .name = "got-foundation", .text = text }, &diagnostic);
}

test "GOT operand owns its symbol identity and remains unsupported by execution" {
    var module = try parse("function l $f() {\n@e\n%p =l copy $target\nret %p\n}");
    defer module.deinit();
    const f = module.functions.items[0];
    const copy = &f.blocks.items[0].instructions.items[0].copy;
    const sym = copy.operand.symbol;
    copy.operand = .{ .got_symbol = sym };
    try testing.expectEqual(sym, copy.operand.referencedSymbol().?);
    try testing.expect(copy.operand.referencedValue() == null);
    try testing.expectEqual(ir.ScalarType.long, try f.operandType(copy.operand));
    try validation.validate(testing.allocator, &module);
    _ = try @import("optimize.zig").foldIntegerConstants(testing.allocator, f);
    try testing.expect(copy.operand == .got_symbol);
    try testing.expectError(error.UnsupportedSymbolAddress, interpreter.evaluate(testing.allocator, f, &.{}, .{}));
    try testing.expectError(error.UnsupportedExternSymbol, amd64.emit(testing.allocator, &module));
    copy.operand = .{ .got_symbol = @fromBackingInt(std.math.maxInt(u32)) };
    try testing.expectError(error.InvalidSymbol, validation.validate(testing.allocator, &module));
    try testing.expectError(error.InvalidSymbol, amd64.emit(testing.allocator, &module));
}

test "GOT eligibility scans scalar module including unreachable blocks before early return" {
    var module = try parse("function l $f() {\n@e\nret 1\n@dead\nret $target\n}");
    defer module.deinit();
    const f = module.functions.items[0];
    const target = try module.symbols.intern(".portable_but_nonnative");
    f.blocks.items[1].terminator.?.return_value = .{ .got_symbol = target };
    try validation.validate(testing.allocator, &module);
    const plan = @import("abi_amd64_plan.zig");
    try testing.expectError(error.UnsupportedExternSymbol, plan.ModulePlans.init(testing.allocator, &module, .{}));
    try testing.expectError(error.UnsupportedExternSymbol, plan.FunctionPlan.init(testing.allocator, &module, @fromBackingInt(@as(u32, 0)), .{}));
    try testing.expectError(error.UnsupportedExternSymbol, amd64.emit(testing.allocator, &module));
    const bad = try module.symbols.intern("hostile\nname");
    f.blocks.items[1].terminator.?.return_value = .{ .got_symbol = bad };
    try testing.expectError(error.InvalidSymbol, plan.ModulePlans.init(testing.allocator, &module, .{}));
}
