//! Initial GOT operand, parser and native assembly coverage. Full runtime,
//! loader, mutation and compatibility validation is still outstanding.
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

test "GOT operand owns its symbol identity and interpreter refuses execution" {
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
    const assembly = try amd64.emit(testing.allocator, &module);
    defer testing.allocator.free(assembly);
    try testing.expect(std.mem.indexOf(u8, assembly, "movq target@GOTPCREL(%rip), %rax") != null);
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

test "dedicated and wrapped GOT targets share identity and signature checks" {
    var module = try parse("function l $f() {\n@e\n%r =l call $g()\nret %r\n}\nfunction l $g() {\n@e\nret 1\n}");
    defer module.deinit();
    const f = module.functions.items[0];
    const call = &f.blocks.items[0].instructions.items[0].call;
    const symbol = call.callee.symbol;
    for ([_]ir.CallTarget{ .{ .extern_symbol = symbol }, .{ .address = .{ .got_symbol = symbol } } }) |target| {
        call.callee = target;
        try testing.expectEqual(symbol, target.symbolicIdentity().?);
        try testing.expectEqualDeep(ir.Operand{ .got_symbol = symbol }, target.addressOperand().?);
        try validation.validate(testing.allocator, &module);
        try testing.expectError(error.UnsupportedExternalCall, interpreter.evaluateModule(testing.allocator, &module, @fromBackingInt(@as(u32, 0)), &.{}, .{}));
        const assembly = try amd64.emit(testing.allocator, &module);
        defer testing.allocator.free(assembly);
        try testing.expect(std.mem.indexOf(u8, assembly, "movq g@GOTPCREL(%rip), %rax") != null);
        try testing.expect(std.mem.indexOf(u8, assembly, "call *%r11") != null);
    }
    const unknown = try module.symbols.intern("unknown_external");
    call.callee = .{ .address = .{ .got_symbol = unknown } };
    try validation.validate(testing.allocator, &module);
    try testing.expectError(error.UnsupportedExternalCall, interpreter.evaluateModule(testing.allocator, &module, @fromBackingInt(@as(u32, 0)), &.{}, .{}));
    try testing.expect((ir.CallTarget{ .address = .{ .symbol = symbol } }).symbolicIdentity() == null);
}

test "contextual extern values and calls preserve owned symbolic identity" {
    var module = try parse("function l $f() {\n@e\n%p =l copy extern $target\n%r =l call extern $callee(l %p)\nret %r\n}");
    defer module.deinit();
    const f = module.functions.items[0];
    const operand = f.blocks.items[0].instructions.items[0].copy.operand;
    const call = f.blocks.items[0].instructions.items[1].call;
    try testing.expect(operand == .got_symbol);
    try testing.expectEqualStrings("target", module.symbols.get(operand.got_symbol).?);
    try testing.expect(call.callee == .extern_symbol);
    try testing.expectEqualStrings("callee", module.symbols.get(call.callee.extern_symbol).?);
    try validation.validate(testing.allocator, &module);
    const assembly = try amd64.emit(testing.allocator, &module);
    defer testing.allocator.free(assembly);
    try testing.expect(std.mem.indexOf(u8, assembly, "movq target@GOTPCREL(%rip), %rax") != null);
    try testing.expect(std.mem.indexOf(u8, assembly, "movq callee@GOTPCREL(%rip), %rax") != null);
}

fn expectDiagnostic(text: []const u8, code: @import("source.zig").Diagnostic.Code, bad: []const u8) !void {
    var diagnostic: ?@import("source.zig").Diagnostic = null;
    try testing.expectError(error.InvalidInput, frontend.parse(testing.allocator, .{ .name = "extern-diagnostic", .text = text }, &diagnostic));
    try testing.expectEqual(code, diagnostic.?.code);
    try testing.expectEqualStrings(bad, text[diagnostic.?.span.start..diagnostic.?.span.end]);
}

test "extern grammar rejects addends, newlines, stacked modifiers and non-long values" {
    try expectDiagnostic("function l $f() {\n@e\nret extern $x+0\n}", .unsupported_construct, "+");
    try expectDiagnostic("function l $f() {\n@e\nret extern\n$x\n}", .unexpected_token, "\n");
    try expectDiagnostic("function l $f() {\n@e\nret extern extern $x\n}", .unsupported_construct, "extern");
    try expectDiagnostic("function l $f() {\n@e\nret extern thread $x\n}", .unsupported_construct, "thread");
    try expectDiagnostic("function w $f() {\n@e\nret extern $x\n}", .type_mismatch, "extern");
    try expectDiagnostic("data $x = { l extern $other }", .unsupported_construct, "extern");
}

test "GOT target forms reject called data and mismatched known signatures" {
    var module = try parse("data $notfn = { l 3 }\nfunction l $f() {\n@e\n%r =l call $g()\nret %r\n}\nfunction l $g(l %arg) {\n@e\nret %arg\n}");
    defer module.deinit();
    const call = &module.functions.items[0].blocks.items[0].instructions.items[0].call;
    const g = call.callee.symbol;
    const data = module.data.items[0].name;
    for ([_]ir.CallTarget{ .{ .extern_symbol = g }, .{ .address = .{ .got_symbol = g } } }) |target| {
        call.callee = target;
        try testing.expectError(error.CallSignatureMismatch, validation.validate(testing.allocator, &module));
    }
    for ([_]ir.CallTarget{ .{ .extern_symbol = data }, .{ .address = .{ .got_symbol = data } } }) |target| {
        call.callee = target;
        try testing.expectError(error.CalledDataSymbol, validation.validate(testing.allocator, &module));
    }
}

test "GOT target is parked after scalar arguments and before variadic AL" {
    var module = try parse("function l $f() {\n@e\n%r =l call extern $external_fn(l extern $external_data, ..., d d_1.5)\nret %r\n}");
    defer module.deinit();
    const assembly = try amd64.emit(testing.allocator, &module);
    defer testing.allocator.free(assembly);
    const arg = std.mem.indexOf(u8, assembly, "movq external_data@GOTPCREL").?;
    const target = std.mem.indexOf(u8, assembly, "movq external_fn@GOTPCREL").?;
    const al = std.mem.indexOf(u8, assembly, "movb $1, %al").?;
    const call = std.mem.indexOf(u8, assembly, "call *%r11").?;
    try testing.expect(arg < target and target < al and al < call);
}
