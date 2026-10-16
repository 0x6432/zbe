const std = @import("std");
const testing = std.testing;
const ir = @import("ir.zig");
const frontend = @import("frontend.zig");
const source = @import("source.zig");
const validation = @import("module_validation.zig");
const interpreter = @import("interpreter.zig");
const amd64 = @import("amd64.zig");
const entry: @import("module.zig").FunctionId = @fromBackingInt(@as(u32, 0));
const options = [_]amd64.Options{ .{}, .{ .reuse_stack_homes = true }, .{ .callee_saved_homes = true } };
fn parse(allocator: std.mem.Allocator, text: []const u8) !@import("module.zig").Module {
    var diagnostic: ?source.Diagnostic = null;
    return frontend.parse(allocator, .{ .name = "indirect", .text = text }, &diagnostic);
}

test "indirect calls retain long targets as operands and never invoke addresses in the evaluator" {
    var module = try parse(testing.allocator, @embedFile("fixtures/indirect-calls.ssa"));
    defer module.deinit();
    try validation.validate(testing.allocator, &module);
    const f = module.functions.items[0];
    try testing.expectEqual(f.parameters.items[0], f.blocks.items[1].instructions.items[0].call.callee.address.value);
    try testing.expectError(error.UnsupportedIndirectCall, interpreter.evaluateModule(testing.allocator, &module, entry, &.{ .{ .long = 0 }, .{ .long = 42 } }, .{}));
    try testing.expectError(error.UnsupportedCall, interpreter.evaluate(testing.allocator, f, &.{ .{ .long = 0 }, .{ .long = 42 } }, .{}));
    const path: @import("module.zig").FunctionId = @fromBackingInt(@as(u32, 2));
    try testing.expectEqual(@as(u32, 7), (try interpreter.evaluateModule(testing.allocator, &module, path, &.{ .{ .word = 0 }, .{ .long = 0 } }, .{})).?.word);
    try testing.expectError(error.UnsupportedIndirectCall, interpreter.evaluateModule(testing.allocator, &module, path, &.{ .{ .word = 1 }, .{ .long = 0 } }, .{}));
    try testing.expectError(error.StepLimitExceeded, interpreter.evaluateModule(testing.allocator, &module, path, &.{ .{ .word = 1 }, .{ .long = 0 } }, .{ .max_steps = 1 }));
    var literal = try parse(testing.allocator, "function $f() {\n@e\ncall 0()\nret\n}");
    defer literal.deinit();
    try validation.validate(testing.allocator, &literal);
    try testing.expectEqual(@as(u64, 0), literal.functions.items[0].blocks.items[0].instructions.items[0].call.callee.address.constant.long);
    try testing.expectError(error.UnsupportedIndirectCall, interpreter.evaluateModule(testing.allocator, &literal, entry, &.{}, .{}));
}

test "indirect target type ordering and dominance are validated independently of arguments" {
    const invalid_ssa = [_][]const u8{
        "function w $f() {\n@e\n%r =w call %p()\n%p =l copy 0\nret %r\n}",
        "function w $f(w %c) {\n@e\njnz %c, @left, @right\n@left\n%p =l copy 0\njmp @right\n@right\n%r =w call %p()\nret %r\n}",
    };
    for (invalid_ssa) |text| {
        var module = try parse(testing.allocator, text);
        defer module.deinit();
        var issue: ?@import("ssa.zig").Issue = null;
        try testing.expectError(error.InvalidSSA, @import("ssa.zig").validate(testing.allocator, module.functions.items[0], &issue));
        try testing.expect(issue.?.site == .instruction);
    }
    for ([_][]const u8{ "function w $f(w %p) {\n@e\n%r =w call %p()\nret %r\n}", "function $f(d %p) {\n@e\ncall %p()\nret\n}" }) |text| try testing.expectError(error.InvalidInput, parse(testing.allocator, text));
}

test "indirect builders fail atomically and own arguments for scalar and void calls" {
    for ([_]bool{ false, true }) |has_result| for (0..2) |failure_offset| {
        var failing = testing.FailingAllocator.init(testing.allocator, .{ .resize_fail_index = 0 });
        var f = ir.Function.init(failing.allocator(), @fromBackingInt(@as(u32, 0)), null);
        defer f.deinit();
        const pointer = try f.addParameter(.long);
        const b = try f.addBlock(null);
        const result: ?ir.ValueId = if (has_result) try f.declareValue(.word) else null;
        var arguments = [_]ir.CallArgument{.{ .scalar_type = .word, .operand = .{ .constant = .{ .word = 7 } } }};
        const wrong: ir.Operand = .{ .constant = .{ .word = 0 } };
        if (result) |value| {
            try testing.expectError(error.TypeMismatch, f.defineIndirectCall(b, value, wrong, &arguments));
        } else try testing.expectError(error.TypeMismatch, f.appendVoidIndirectCall(b, wrong, &arguments));
        failing.fail_index = failing.alloc_index + failure_offset;
        const address: ir.Operand = .{ .value = pointer };
        if (result) |value| {
            try testing.expectError(error.OutOfMemory, f.defineIndirectCall(b, value, address, &arguments));
            try testing.expect(f.values.items[@backingInt(value)].definition == .pending);
        } else try testing.expectError(error.OutOfMemory, f.appendVoidIndirectCall(b, address, &arguments));
        try testing.expectEqual(@as(usize, 0), f.blocks.items[0].instructions.items.len);
        failing.fail_index = std.math.maxInt(usize);
        if (result) |value| {
            try f.defineIndirectCall(b, value, address, &arguments);
        } else try f.appendVoidIndirectCall(b, address, &arguments);
        arguments[0].operand = .{ .constant = .{ .word = 99 } };
        try testing.expectEqual(@as(u32, 7), f.blocks.items[0].instructions.items[0].call.arguments[0].operand.constant.word);
        try f.terminate(b, .{ .return_value = null });
        try f.validateStructure();
        f.blocks.items[0].instructions.items[0].call.callee = .{ .address = wrong };
        try testing.expectError(error.TypeMismatch, f.validateStructure());
    };
}

test "target-only uses remain live and target scratch is loaded before argument marshalling" {
    var module = try parse(testing.allocator, @embedFile("fixtures/indirect-calls.ssa"));
    defer module.deinit();
    const f = module.functions.items[1];
    var live = try @import("liveness.zig").Snapshot.init(testing.allocator, f, .{});
    defer live.deinit();
    try testing.expect(live.isLiveOut(@fromBackingInt(@as(u32, 0)), f.parameters.items[0]).?);
    for (options) |option| {
        const assembly = try amd64.emitWithOptions(testing.allocator, &module, option);
        defer testing.allocator.free(assembly);
        const saved = std.mem.indexOf(u8, assembly, "movq %rax, %r11").?;
        const argument = std.mem.indexOfPos(u8, assembly, saved, "movq %rax, %rdi").?;
        const invoked = std.mem.indexOfPos(u8, assembly, argument, "call *%r11").?;
        try testing.expect(saved < argument and argument < invoked);
    }
}

fn exercise(allocator: std.mem.Allocator) !void {
    var module = try parse(allocator, @embedFile("fixtures/indirect-calls.ssa"));
    defer module.deinit();
    for (module.functions.items) |f| {
        var graph = try @import("interference.zig").Graph.init(allocator, f, .{});
        defer graph.deinit();
        _ = try @import("optimize.zig").foldIntegerConstants(allocator, f);
    }
    for (options) |option| {
        const assembly = try amd64.emitWithOptions(allocator, &module, option);
        defer allocator.free(assembly);
    }
    if (interpreter.evaluateModule(allocator, &module, entry, &.{ .{ .long = 0 }, .{ .long = 42 } }, .{})) |_| return error.ExpectedIndirectRejection else |err| {
        if (err != error.UnsupportedIndirectCall) return err;
    }
}
test "indirect target and argument pipelines release every failed allocation" {
    try @import("test_support.zig").checkAllocationFailures(exercise);
}
