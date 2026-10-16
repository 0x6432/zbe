const std = @import("std");
const testing = std.testing;
const ir = @import("ir.zig");
const interpreter = @import("interpreter.zig");
const validation = @import("module_validation.zig");
const frontend = @import("frontend.zig");
const source = @import("source.zig");
const Module = @import("module.zig").Module;
const FunctionId = @import("module.zig").FunctionId;
fn id(index: u32) FunctionId {
    return @fromBackingInt(index);
}
fn parse(allocator: std.mem.Allocator, text: []const u8) !Module {
    var diagnostic: ?source.Diagnostic = null;
    return frontend.parse(allocator, .{ .name = "module-eval", .text = text }, &diagnostic);
}
const budget_case = "function w $f() {\n@e\n%a =w call $g(w 20)\n%b =w call $g(w 22)\n%r =w add %a, %b\nret %r\n}\nfunction w $g(w %x) {\n@e\nret %x\n}";

test "module evaluation shares one step budget and counts the root frame in depth" {
    var module = try parse(testing.allocator, budget_case);
    defer module.deinit();
    for (0..6) |steps| try testing.expectError(error.StepLimitExceeded, interpreter.evaluateModule(testing.allocator, &module, id(0), &.{}, .{ .max_steps = steps, .max_call_depth = 2 }));
    try testing.expectEqual(@as(u32, 42), (try interpreter.evaluateModule(testing.allocator, &module, id(0), &.{}, .{ .max_steps = 6, .max_call_depth = 2 })).?.word);
    try testing.expectError(error.CallDepthLimitExceeded, interpreter.evaluateModule(testing.allocator, &module, id(0), &.{}, .{ .max_call_depth = 1 }));
    try testing.expectError(error.CallDepthLimitExceeded, interpreter.evaluateModule(testing.allocator, &module, id(1), &.{.{ .word = 3 }}, .{ .max_call_depth = 0 }));
    try testing.expectError(error.StepLimitExceeded, interpreter.evaluateModule(testing.allocator, &module, id(0), &.{}, .{ .max_steps = 0, .max_call_depth = 1 }));
    try testing.expectError(error.InvalidFunction, interpreter.evaluateModule(testing.allocator, &module, id(std.math.maxInt(u32)), &.{}, .{}));
    try testing.expectError(error.ArgumentCountMismatch, interpreter.evaluateModule(testing.allocator, &module, id(1), &.{}, .{}));
    try testing.expectError(error.ArgumentTypeMismatch, interpreter.evaluateModule(testing.allocator, &module, id(1), &.{.{ .long = 3 }}, .{}));
    try testing.expectError(error.UnsupportedCall, interpreter.evaluate(testing.allocator, module.functions.items[0], &.{}, .{}));
}

const recursive = "function l $sum(l %n) {\n@entry\njnz %n, @step, @base\n@base\nret 0\n@step\n%next =l sub %n, 1\n%child =l call $sum(l %next)\n%r =l add %n, %child\nret %r\n}";
test "explicit invocation stack preserves suspended values across deep recursion and growth" {
    var module = try parse(testing.allocator, recursive);
    defer module.deinit();
    try testing.expectError(error.CallDepthLimitExceeded, interpreter.evaluateModule(testing.allocator, &module, id(0), &.{.{ .long = 64 }}, .{}));
    try testing.expectEqual(@as(u64, 2016), (try interpreter.evaluateModule(testing.allocator, &module, id(0), &.{.{ .long = 63 }}, .{})).?.long);
    // Exceeds the default depth and grows the handle array repeatedly. Runtime
    // control remains iterative; the host stack does not recurse with this IL.
    try testing.expectEqual(@as(u64, 500500), (try interpreter.evaluateModule(testing.allocator, &module, id(0), &.{.{ .long = 1000 }}, .{ .max_call_depth = 1001 })).?.long);
    try testing.expectError(error.CallDepthLimitExceeded, interpreter.evaluateModule(testing.allocator, &module, id(0), &.{.{ .long = 1000 }}, .{ .max_call_depth = 1000 }));
    try testing.expectError(error.StepLimitExceeded, interpreter.evaluateModule(testing.allocator, &module, id(0), &.{.{ .long = 1000 }}, .{ .max_steps = 50, .max_call_depth = 1001 }));
}

test "mutual forward calls select only the module's typed target" {
    var module = try parse(testing.allocator, "function w $even(w %n) {\n@e\njnz %n, @step, @base\n@base\nret 1\n@step\n%next =w sub %n, 1\n%r =w call $odd(w %next)\nret %r\n}\nfunction w $odd(w %n) {\n@e\njnz %n, @step, @base\n@base\nret 0\n@step\n%next =w sub %n, 1\n%r =w call $even(w %next)\nret %r\n}");
    defer module.deinit();
    for (0..32) |n| {
        const argument = [_]ir.Constant{.{ .word = @intCast(n) }};
        try testing.expectEqual(@as(u32, if (n % 2 == 0) 1 else 0), (try interpreter.evaluateModule(testing.allocator, &module, id(0), &argument, .{})).?.word);
        try testing.expectEqual(@as(u32, if (n % 2 == 1) 1 else 0), (try interpreter.evaluateModule(testing.allocator, &module, id(1), &argument, .{})).?.word);
    }
}

test "calls preserve all scalar raw bits and each invocation owns its parallel phi scratch" {
    const types = [_][]const u8{ "w", "l", "s", "d" };
    const values = [_]ir.Constant{ .{ .word = 0x80000001 }, .{ .long = 0x1234567887654321 }, .{ .single_bits = 0xffc12345 }, .{ .double_bits = 0x7ff8123456789abc } };
    for (types, values) |ty, value| {
        const text = try std.fmt.allocPrint(testing.allocator, "function {s} $outer({s} %x) {{\n@e\n%r ={s} call $inner({s} %x)\nret %r\n}}\nfunction {s} $inner({s} %x) {{\n@e\njmp @loop\n@loop\n%n =w phi @e 2, @body %next\n%a ={s} phi @e %x, @body %b\n%b ={s} phi @e %x, @body %a\njnz %n, @body, @done\n@body\n%next =w sub %n, 1\njmp @loop\n@done\nret %a\n}}", .{ ty, ty, ty, ty, ty, ty, ty, ty });
        defer testing.allocator.free(text);
        var module = try parse(testing.allocator, text);
        defer module.deinit();
        try testing.expectEqualDeep(value, (try interpreter.evaluateModule(testing.allocator, &module, id(0), &.{value}, .{})).?);
    }
    // Distinct phi values prove simultaneous swaps, including a suspended
    // caller's own phi loop across a nested invocation using the same IR IDs.
    var module = try parse(testing.allocator, "function w $outer() {\n@e\njmp @loop\n@loop\n%n =w phi @e 3, @body %next\n%acc =w phi @e 0, @body %sum\njnz %n, @body, @done\n@body\n%r =w call $swap(w %n)\n%sum =w add %acc, %r\n%next =w sub %n, 1\njmp @loop\n@done\nret %acc\n}\nfunction w $swap(w %count) {\n@e\njmp @loop\n@loop\n%n =w phi @e %count, @body %next\n%a =w phi @e 10, @body %b\n%b =w phi @e 20, @body %a\njnz %n, @body, @done\n@body\n%next =w sub %n, 1\njmp @loop\n@done\nret %a\n}");
    defer module.deinit();
    try testing.expectEqual(@as(u32, 50), (try interpreter.evaluateModule(testing.allocator, &module, id(0), &.{}, .{})).?.word);
}

test "external calls remain unexecuted and callee faults halt and void returns stay typed" {
    var module = try parse(testing.allocator, "function w $f(w %p) {\n@e\njnz %p, @call, @done\n@call\n%r =w call $unknown()\nret %r\n@done\nret 7\n}");
    defer module.deinit();
    try testing.expectEqual(@as(u32, 7), (try interpreter.evaluateModule(testing.allocator, &module, id(0), &.{.{ .word = 0 }}, .{})).?.word);
    try testing.expectError(error.UnsupportedExternalCall, interpreter.evaluateModule(testing.allocator, &module, id(0), &.{.{ .word = 1 }}, .{}));
    try testing.expectError(error.StepLimitExceeded, interpreter.evaluateModule(testing.allocator, &module, id(0), &.{.{ .word = 1 }}, .{ .max_steps = 1 }));
    for ([_][]const u8{ "hlt", "%r =w div 1, 0\nret %r", "%r =w div 2147483648, 4294967295\nret %r" }, [_]anyerror{ error.Halted, error.DivisionByZero, error.IntegerOverflow }) |body, expected| {
        const text = try std.fmt.allocPrint(testing.allocator, "function w $f() {{\n@e\n%r =w call $g()\nret %r\n}}\nfunction w $g() {{\n@e\n{s}\n}}", .{body});
        defer testing.allocator.free(text);
        var failing = try parse(testing.allocator, text);
        defer failing.deinit();
        try testing.expectError(expected, interpreter.evaluateModule(testing.allocator, &failing, id(0), &.{}, .{}));
        try testing.expectError(error.StepLimitExceeded, interpreter.evaluateModule(testing.allocator, &failing, id(0), &.{}, .{ .max_steps = 1 }));
    }
    var void_module = try parse(testing.allocator, "function $f() {\n@e\nret\n}");
    defer void_module.deinit();
    try testing.expectEqual(@as(?ir.Constant, null), try interpreter.evaluateModule(testing.allocator, &void_module, id(0), &.{}, .{}));
}

test "module validation is target independent but validates every body and known signature" {
    var module = try parse(testing.allocator, budget_case);
    defer module.deinit();
    try validation.validate(testing.allocator, &module);
    const original = module.functions.items[0].name;
    module.functions.items[0].name = try module.symbols.intern("semantic name;not assembler");
    try validation.validate(testing.allocator, &module);
    try testing.expectEqual(@as(u32, 42), (try interpreter.evaluateModule(testing.allocator, &module, id(0), &.{}, .{})).?.word);
    try testing.expectError(error.InvalidSymbol, @import("amd64.zig").emit(testing.allocator, &module));
    module.functions.items[0].name = module.functions.items[1].name;
    try testing.expectError(error.DuplicateSymbol, validation.validate(testing.allocator, &module));
    module.functions.items[0].name = original;
    module.functions.items[1].return_type = .long;
    // The body is now invalid even before call-signature checking.
    try testing.expectError(error.InvalidReturn, validation.validate(testing.allocator, &module));
    module.functions.items[1].return_type = .word;
    const call = &module.functions.items[0].blocks.items[0].instructions.items[0].call;
    call.callee = .{ .symbol = @fromBackingInt(std.math.maxInt(u32)) };
    try testing.expectError(error.InvalidSymbol, validation.validate(testing.allocator, &module));
    call.callee = .{ .symbol = module.functions.items[0].name };
    try testing.expectError(error.CallSignatureMismatch, interpreter.evaluateModule(testing.allocator, &module, id(0), &.{}, .{}));
}

fn exercise(allocator: std.mem.Allocator) !void {
    var module = try parse(allocator, recursive);
    defer module.deinit();
    try testing.expectEqual(@as(u64, 210), (try interpreter.evaluateModule(allocator, &module, id(0), &.{.{ .long = 20 }}, .{})).?.long);
    if (interpreter.evaluateModule(allocator, &module, id(0), &.{.{ .long = 20 }}, .{ .max_call_depth = 10 })) |_| return error.ExpectedDepthLimit else |err| {
        if (err != error.CallDepthLimitExceeded) return err;
    }
    if (interpreter.evaluateModule(allocator, &module, id(0), &.{.{ .long = 20 }}, .{ .max_steps = 20 })) |_| return error.ExpectedStepLimit else |err| {
        if (err != error.StepLimitExceeded) return err;
    }
    var phi_module = try parse(allocator, "function w $f() {\n@e\n%r =w call $g()\nret %r\n}\nfunction w $g() {\n@e\njmp @j\n@j\n%v =w phi @e 42\nret %v\n}");
    defer phi_module.deinit();
    try testing.expectEqual(@as(u32, 42), (try interpreter.evaluateModule(allocator, &phi_module, id(0), &.{}, .{})).?.word);
}
test "owned frame growth arguments phi storage and early failures free every allocation" {
    try @import("test_support.zig").checkAllocationFailures(exercise);
}
