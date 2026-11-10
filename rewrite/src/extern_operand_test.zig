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
        try testing.expectError(error.UnsupportedIndirectCall, interpreter.evaluateModule(testing.allocator, &module, @fromBackingInt(@as(u32, 0)), &.{}, .{}));
        const assembly = try amd64.emit(testing.allocator, &module);
        defer testing.allocator.free(assembly);
        try testing.expect(std.mem.indexOf(u8, assembly, "movq g@GOTPCREL(%rip), %rax") != null);
        try testing.expect(std.mem.indexOf(u8, assembly, "call *%r11") != null);
    }
    const unknown = try module.symbols.intern("unknown_external");
    call.callee = .{ .address = .{ .got_symbol = unknown } };
    try validation.validate(testing.allocator, &module);
    try testing.expectError(error.UnsupportedIndirectCall, interpreter.evaluateModule(testing.allocator, &module, @fromBackingInt(@as(u32, 0)), &.{}, .{}));
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

fn exerciseExternAllocation(allocator: std.mem.Allocator) !void {
    var diagnostic: ?@import("source.zig").Diagnostic = null;
    var module = try frontend.parse(allocator, .{ .name = "extern-oom", .text = "function l $f() {\n@e\n%p =l copy extern $external_data\n%r =l call extern $external_fn(l %p)\nret %r\n}" }, &diagnostic);
    defer module.deinit();
    try validation.validate(allocator, &module);
    const assembly = try amd64.emit(allocator, &module);
    defer allocator.free(assembly);
    try testing.expect(std.mem.indexOf(u8, assembly, "external_fn@GOTPCREL") != null);
}

test "extern parse validation and emission clean up at every allocation failure" {
    try @import("test_support.zig").checkAllocationFailures(exerciseExternAllocation);
}

// Frozen half-open byte spans and precedence, independent of token contents.
test "extern diagnostics have exact spans and stable precedence" {
    const Case = struct { name: []const u8, text: []const u8, code: @import("source.zig").Diagnostic.Code, start: usize, end: usize };
    const cases = [_]Case{
        .{ .name = "EOF", .text = "function l $f() {\n@e\nret extern", .code = .unexpected_token, .start = 31, .end = 31 },
        .{ .name = "temporary", .text = "function l $f() {\n@e\nret extern %x\n}", .code = .unexpected_token, .start = 32, .end = 34 },
        .{ .name = "integer", .text = "function l $f() {\n@e\nret extern 42\n}", .code = .unexpected_token, .start = 32, .end = 34 },
        .{ .name = "punctuation", .text = "function l $f() {\n@e\nret extern ,\n}", .code = .unexpected_token, .start = 32, .end = 33 },
        .{ .name = "identifier", .text = "function l $f() {\n@e\nret extern nonsense\n}", .code = .unexpected_token, .start = 32, .end = 40 },
        .{ .name = "LF", .text = "function l $f() {\n@e\nret extern\n$x\n}", .code = .unexpected_token, .start = 31, .end = 32 },
        .{ .name = "CRLF", .text = "function l $f() {\n@e\nret extern\r\n$x\n}", .code = .unexpected_token, .start = 31, .end = 33 },
        .{ .name = "comment newline", .text = "function l $f() {\n@e\nret extern # comment\n$x\n}", .code = .unexpected_token, .start = 32, .end = 42 },
        .{ .name = "stacked extern", .text = "function l $f() {\n@e\nret extern extern $x\n}", .code = .unsupported_construct, .start = 32, .end = 38 },
        .{ .name = "stacked thread", .text = "function l $f() {\n@e\nret extern thread $x\n}", .code = .unsupported_construct, .start = 32, .end = 38 },
        .{ .name = "stacked export", .text = "function l $f() {\n@e\nret extern export $x\n}", .code = .unsupported_construct, .start = 32, .end = 38 },
        .{ .name = "stacked common", .text = "function l $f() {\n@e\nret extern common $x\n}", .code = .unsupported_construct, .start = 32, .end = 38 },
        .{ .name = "stacked section", .text = "function l $f() {\n@e\nret extern section $x\n}", .code = .unsupported_construct, .start = 32, .end = 39 },
        .{ .name = "suffix $x+0", .text = "function l $f() {\n@e\nret extern $x+0\n}", .code = .unsupported_construct, .start = 34, .end = 35 },
        .{ .name = "suffix $x + 0", .text = "function l $f() {\n@e\nret extern $x + 0\n}", .code = .unsupported_construct, .start = 35, .end = 36 },
        .{ .name = "suffix $x +", .text = "function l $f() {\n@e\nret extern $x +\n}", .code = .unsupported_construct, .start = 35, .end = 36 },
        .{ .name = "suffix $x + 2147483648", .text = "function l $f() {\n@e\nret extern $x + 2147483648\n}", .code = .unsupported_construct, .start = 35, .end = 36 },
        .{ .name = "type w", .text = "function w $f() {\n@e\nret extern $x\n}", .code = .type_mismatch, .start = 25, .end = 31 },
        .{ .name = "type s", .text = "function s $f() {\n@e\nret extern $x\n}", .code = .type_mismatch, .start = 25, .end = 31 },
        .{ .name = "type d", .text = "function d $f() {\n@e\nret extern $x\n}", .code = .type_mismatch, .start = 25, .end = 31 },
        .{ .name = "type plus precedence", .text = "function w $f() {\n@e\nret extern $x+0\n}", .code = .unsupported_construct, .start = 34, .end = 35 },
        .{ .name = "data initializer", .text = "data $x = { l extern $other }", .code = .unsupported_construct, .start = 14, .end = 20 },
        .{ .name = "data declaration", .text = "data extern $x = { l 1 }", .code = .unsupported_construct, .start = 5, .end = 11 },
        .{ .name = "export data declaration", .text = "export data extern $x = { l 1 }", .code = .unsupported_construct, .start = 12, .end = 18 },
        .{ .name = "common data declaration", .text = "common data extern $x = { z 8 }", .code = .unsupported_construct, .start = 12, .end = 18 },
        .{ .name = "typed function declaration", .text = "function l extern $f() {\n@e\nret 1\n}", .code = .unsupported_construct, .start = 11, .end = 17 },
        .{ .name = "export function declaration", .text = "export function l extern $f() {\n@e\nret 1\n}", .code = .unsupported_construct, .start = 18, .end = 24 },
        .{ .name = "untyped function declaration", .text = "function extern $f() {\n@e\nret\n}", .code = .unsupported_construct, .start = 9, .end = 15 },
        .{ .name = "declaration modifier", .text = "extern function l $f() {\n@e\nret 0\n}", .code = .unsupported_construct, .start = 0, .end = 6 },
        .{ .name = "malformed quoted global before plus", .text = "function l $f() {\n@e\nret extern $\"bad\\q\"+0\n}", .code = .unsupported_construct, .start = 32, .end = 40 },
        .{ .name = "whole input lexer precedence", .text = "function l $f() {\n@e\nret extern $x+0\n?\n}", .code = .invalid_character, .start = 37, .end = 38 },
    };
    for (cases) |case| {
        var diagnostic: ?@import("source.zig").Diagnostic = null;
        if (frontend.parse(testing.allocator, .{ .name = case.name, .text = case.text }, &diagnostic)) |module| {
            var owned = module;
            owned.deinit();
            std.debug.print("unexpected parse success: {s}\n", .{case.name});
            return error.TestUnexpectedResult;
        } else |err| {
            try testing.expectEqual(error.InvalidInput, err);
        }
        const got = diagnostic orelse return error.TestUnexpectedResult;
        if (got.code != case.code or got.span.start != case.start or got.span.end != case.end) {
            std.debug.print("{s}: got {s} [{d},{d}), expected {s} [{d},{d})\n", .{ case.name, @tagName(got.code), got.span.start, got.span.end, @tagName(case.code), case.start, case.end });
            return error.TestUnexpectedResult;
        }
    }
}

test "extern call refusal precedes arguments, environment and dispatch depth" {
    var module = try parse("function l $f() {\n@e\n%r =l call extern $external_fn(env extern $poison_env, l extern $poison_arg)\nret %r\n}");
    defer module.deinit();
    const f = module.functions.items[0];
    const call = &f.blocks.items[0].instructions.items[0].call;
    const target = call.callee.extern_symbol;
    const entry: @import("module.zig").FunctionId = @fromBackingInt(@as(u32, 0));
    for ([_]ir.CallTarget{ .{ .extern_symbol = target }, .{ .address = .{ .got_symbol = target } } }) |form| {
        call.callee = form;
        try validation.validate(testing.allocator, &module);
        try testing.expectError(error.UnsupportedCall, interpreter.evaluate(testing.allocator, f, &.{}, .{}));
        try testing.expectError(error.InvalidFunction, interpreter.evaluateModule(testing.allocator, &module, @fromBackingInt(std.math.maxInt(u32)), &.{}, .{}));
        try testing.expectError(error.CallDepthLimitExceeded, interpreter.evaluateModule(testing.allocator, &module, entry, &.{}, .{ .max_call_depth = 0 }));
        try testing.expectError(error.StepLimitExceeded, interpreter.evaluateModule(testing.allocator, &module, entry, &.{}, .{ .max_steps = 0 }));
        try testing.expectError(error.UnsupportedIndirectCall, interpreter.evaluateModule(testing.allocator, &module, entry, &.{}, .{ .max_call_depth = 1, .max_steps = 1 }));
        try testing.expectError(error.UnsupportedIndirectCall, interpreter.evaluateModule(testing.allocator, &module, entry, &.{}, .{ .global_memory = .{} }));
    }
}

// D08 applies at the type-declaration name boundary, without reserving :extern.
test "extern type declaration boundary preserves namespace and diagnostics" {
    var module = try parse("type :extern = { l }\nfunction l $f(:extern %p) {\n@e\nret 1\n}");
    defer module.deinit();
    try testing.expect(module.findRecord("extern") != null);
    try validation.validate(testing.allocator, &module);

    const Case = struct { text: []const u8, code: @import("source.zig").Diagnostic.Code, start: usize, end: usize };
    const cases = [_]Case{
        .{ .text = "type nope = { l }", .code = .unexpected_token, .start = 5, .end = 9 },
        .{ .text = "type $x = { l }", .code = .unexpected_token, .start = 5, .end = 7 },
        .{ .text = "type extern $x = { l }", .code = .unsupported_construct, .start = 5, .end = 11 },
        .{ .text = "type\nextern $x = { l }", .code = .unsupported_construct, .start = 5, .end = 11 },
        .{ .text = "type\r\nextern $x = { l }", .code = .unsupported_construct, .start = 6, .end = 12 },
        .{ .text = "type #comment\nextern $x = { l }", .code = .unsupported_construct, .start = 14, .end = 20 },
        .{ .text = "type", .code = .unexpected_token, .start = 4, .end = 4 },
        .{ .text = "type externally = { l }", .code = .unexpected_token, .start = 5, .end = 15 },
        .{ .text = "type extern $x = { l }\n?", .code = .invalid_character, .start = 23, .end = 24 },
    };
    for (cases) |case| {
        var diagnostic: ?@import("source.zig").Diagnostic = null;
        if (frontend.parse(testing.allocator, .{ .name = "type-boundary", .text = case.text }, &diagnostic)) |parsed| {
            var owned = parsed;
            owned.deinit();
            return error.TestUnexpectedResult;
        } else |err| {
            try testing.expectEqual(error.InvalidInput, err);
        }
        const got = diagnostic orelse return error.TestUnexpectedResult;
        try testing.expectEqual(case.code, got.code);
        try testing.expectEqual(case.start, got.span.start);
        try testing.expectEqual(case.end, got.span.end);
    }
}

// D08 is contextual: a single sequence of ordinary declaration flags may be
// followed by extern, while malformed old-only inputs retain their diagnostics.
test "extern after declaration linkage flags has exact span and old precedence" {
    const Case = struct { text: []const u8, code: @import("source.zig").Diagnostic.Code, start: usize, end: usize };
    const cases = [_]Case{
        .{ .text = "common extern data $x = { z 8 }", .code = .unsupported_construct, .start = 7, .end = 13 },
        .{ .text = "export common extern data $x = { z 8 }", .code = .unsupported_construct, .start = 14, .end = 20 },
        .{ .text = "common export extern data $x = { z 8 }", .code = .unsupported_construct, .start = 14, .end = 20 },
        .{ .text = "common\r\n# comment\nextern data $x = { z 8 }", .code = .unsupported_construct, .start = 18, .end = 24 },
        .{ .text = "export extern function $f() { @e ret }", .code = .unsupported_construct, .start = 7, .end = 13 },
        // Existing refusal points win for repeated flags and unrelated tokens.
        .{ .text = "common common extern data $x = { z 8 }", .code = .unsupported_construct, .start = 0, .end = 6 },
        .{ .text = "export export extern data $x = { z 8 }", .code = .unsupported_construct, .start = 7, .end = 13 },
        .{ .text = "export common nope", .code = .unsupported_construct, .start = 7, .end = 13 },
        .{ .text = "common nope", .code = .unsupported_construct, .start = 0, .end = 6 },
        .{ .text = "thread extern data $x = { z 8 }", .code = .unsupported_construct, .start = 0, .end = 6 },
        // Whole-input lexing still precedes the new contextual diagnostic.
        .{ .text = "common extern data $x = { z 8 }\n?", .code = .invalid_character, .start = 32, .end = 33 },
    };
    for (cases) |case| {
        var diagnostic: ?@import("source.zig").Diagnostic = null;
        if (frontend.parse(testing.allocator, .{ .name = "linkage-boundary", .text = case.text }, &diagnostic)) |parsed| {
            var owned = parsed;
            owned.deinit();
            return error.TestUnexpectedResult;
        } else |err| {
            try testing.expectEqual(error.InvalidInput, err);
        }
        const got = diagnostic orelse return error.TestUnexpectedResult;
        if (got.code != case.code or got.span.start != case.start or got.span.end != case.end) {
            std.debug.print("{s}: got {s} [{d},{d}), expected {s} [{d},{d})\n", .{ case.text, @tagName(got.code), got.span.start, got.span.end, @tagName(case.code), case.start, case.end });
            return error.TestUnexpectedResult;
        }
    }
    var module = try parse("type :extern = { l }\ncommon data $extern = { z 8 }\nexport function l $f() {\n@e\nret $extern\n}");
    defer module.deinit();
    try testing.expect(module.findRecord("extern") != null);
    try validation.validate(testing.allocator, &module);
}
