const std = @import("std");
const testing = std.testing;
const ir = @import("ir.zig");
const frontend = @import("frontend.zig");
const source = @import("source.zig");
const validation = @import("module_validation.zig");
const interpreter = @import("interpreter.zig");
const amd64 = @import("amd64.zig");
const Module = @import("module.zig").Module;
const entry: @import("module.zig").FunctionId = @fromBackingInt(@as(u32, 0));
const options = [_]amd64.Options{ .{}, .{ .reuse_stack_homes = true }, .{ .callee_saved_homes = true } };
fn parse(allocator: std.mem.Allocator, text: []const u8) !Module {
    var diagnostic: ?source.Diagnostic = null;
    return frontend.parse(allocator, .{ .name = "void-calls", .text = text }, &diagnostic);
}

test "void calls are effects without SSA results homes or fabricated return bits" {
    var module = try parse(testing.allocator, @embedFile("fixtures/void-calls.ssa"));
    defer module.deinit();
    try validation.validate(testing.allocator, &module);
    const f = module.functions.items[0];
    try testing.expectEqual(@as(usize, 0), f.values.items.len);
    try testing.expectEqual(@as(usize, 2), f.blocks.items[0].instructions.items.len);
    for (f.blocks.items[0].instructions.items) |instruction| try testing.expectEqual(@as(?ir.ValueId, null), instruction.result());
    try testing.expectEqual(@as(usize, 0), try @import("optimize.zig").foldIntegerConstants(testing.allocator, f));
    try testing.expectEqual(@as(usize, 2), f.blocks.items[0].instructions.items.len);
    try testing.expectEqual(@as(?ir.Constant, null), try interpreter.evaluateModule(testing.allocator, &module, entry, &.{}, .{ .max_steps = 5, .max_call_depth = 2 }));
    try testing.expectError(error.StepLimitExceeded, interpreter.evaluateModule(testing.allocator, &module, entry, &.{}, .{ .max_steps = 4 }));
    try testing.expectError(error.CallDepthLimitExceeded, interpreter.evaluateModule(testing.allocator, &module, entry, &.{}, .{ .max_call_depth = 1 }));
    try testing.expectError(error.UnsupportedCall, interpreter.evaluate(testing.allocator, f, &.{}, .{}));
    var layout = try @import("stack_homes.zig").Layout.init(testing.allocator, f, .{});
    defer layout.deinit();
    try testing.expectEqual(@as(usize, 0), layout.slot_count);
    for (options) |option| {
        const assembly = try amd64.emitWithOptions(testing.allocator, &module, option);
        defer testing.allocator.free(assembly);
        const end = std.mem.indexOf(u8, assembly, ".size void_outer").?;
        const outer = assembly[0..end];
        try testing.expectEqual(@as(usize, 2), std.mem.count(u8, outer, "\tcall void_inner\n"));
        try testing.expect(std.mem.indexOf(u8, outer, "subq $") == null);
        try testing.expect(std.mem.indexOf(u8, outer, "movl %eax,") == null);
        try testing.expect(std.mem.indexOf(u8, outer, "movq %rax,") == null);
    }
}

test "void builder duplicates arguments and fails without publishing values or effects" {
    for (0..2) |failure_offset| {
        var failing = testing.FailingAllocator.init(testing.allocator, .{ .resize_fail_index = 0 });
        var f = ir.Function.init(failing.allocator(), @fromBackingInt(@as(u32, 0)), null);
        defer f.deinit();
        const b = try f.addBlock(null);
        var arguments = [_]ir.CallArgument{.{ .scalar_type = .word, .operand = .{ .constant = .{ .word = 7 } } }};
        failing.fail_index = failing.alloc_index + failure_offset;
        try testing.expectError(error.OutOfMemory, f.appendVoidCall(b, f.name, &arguments));
        try testing.expectEqual(@as(usize, 0), f.values.items.len);
        try testing.expectEqual(@as(usize, 0), f.blocks.items[0].instructions.items.len);
        failing.fail_index = std.math.maxInt(usize);
        arguments[0].scalar_type = .long;
        try testing.expectError(error.TypeMismatch, f.appendVoidCall(b, f.name, &arguments));
        arguments[0].scalar_type = .word;
        try f.appendVoidCall(b, f.name, &arguments);
        arguments[0].operand = .{ .constant = .{ .word = 99 } };
        try testing.expectEqual(@as(u32, 7), f.blocks.items[0].instructions.items[0].call.arguments[0].operand.constant.word);
        try f.terminate(b, .{ .return_value = null });
        try f.validateStructure();
        try testing.expectError(error.BlockTerminated, f.appendVoidCall(b, f.name, &.{}));
    }
}

test "void and scalar call signatures cannot be interchanged or orphan old result definitions" {
    const mismatches = [_][]const u8{
        "function $f() {\n@e\ncall $g()\nret\n}\nfunction w $g() {\n@e\nret 1\n}",
        "function w $f() {\n@e\n%r =w call $g()\nret %r\n}\nfunction $g() {\n@e\nret\n}",
    };
    for (mismatches) |text| {
        var module = try parse(testing.allocator, text);
        defer module.deinit();
        try testing.expectError(error.CallSignatureMismatch, validation.validate(testing.allocator, &module));
        for (options) |option| try testing.expectError(error.CallSignatureMismatch, amd64.emitWithOptions(testing.allocator, &module, option));
    }
    var orphan = try parse(testing.allocator, "function w $f() {\n@e\n%r =w call $g()\nret %r\n}");
    defer orphan.deinit();
    orphan.functions.items[0].blocks.items[0].instructions.items[0].call.result = null;
    try testing.expectError(error.InvalidDefinition, orphan.functions.items[0].validateStructure());
    try testing.expectError(error.InvalidInput, parse(testing.allocator, "function $f() {\n@e\ncall $g()\nhlt\ncall $g()\n}"));
}

test "arguments used only by void calls remain live and malformed void arguments fail SSA" {
    var module = try parse(testing.allocator, @embedFile("fixtures/void-calls.ssa"));
    defer module.deinit();
    const f = module.functions.items[2];
    var live = try @import("liveness.zig").Snapshot.init(testing.allocator, f, .{});
    defer live.deinit();
    try testing.expect(live.isLiveOut(@fromBackingInt(@as(u32, 0)), f.parameters.items[0]).?);
    try testing.expect(live.isLiveIn(@fromBackingInt(@as(u32, 1)), f.parameters.items[0]).?);
    var graph = try @import("interference.zig").Graph.init(testing.allocator, f, .{});
    defer graph.deinit();
    try testing.expectEqual(@as(usize, 1), graph.value_count);
    var forward = try parse(testing.allocator, "function $f() {\n@e\ncall $g(w %later)\n%later =w copy 1\nret\n}");
    defer forward.deinit();
    var issue: ?@import("ssa.zig").Issue = null;
    try testing.expectError(error.InvalidSSA, @import("ssa.zig").validate(testing.allocator, forward.functions.items[0], &issue));
}

fn exercise(allocator: std.mem.Allocator) !void {
    var module = try parse(allocator, @embedFile("fixtures/void-calls.ssa"));
    defer module.deinit();
    try testing.expectEqual(@as(?ir.Constant, null), try interpreter.evaluateModule(allocator, &module, entry, &.{}, .{}));
    for (module.functions.items) |f| {
        var graph = try @import("interference.zig").Graph.init(allocator, f, .{});
        defer graph.deinit();
        _ = try @import("optimize.zig").foldIntegerConstants(allocator, f);
    }
    for (options) |option| {
        const assembly = try amd64.emitWithOptions(allocator, &module, option);
        defer allocator.free(assembly);
    }
}
test "void call ownership and empty invocation frames clean every allocation failure" {
    try @import("test_support.zig").checkAllocationFailures(exercise);
}

test "void recursion shares exact budgets and outgoing-only frames still obey the cap" {
    var recursive = try parse(testing.allocator, "function $f(w %n) {\n@e\njnz %n, @step, @done\n@step\n%next =w sub %n, 1\ncall $f(w %next)\nret\n@done\nret\n}");
    defer recursive.deinit();
    try testing.expectEqual(@as(?ir.Constant, null), try interpreter.evaluateModule(testing.allocator, &recursive, entry, &.{.{ .word = 100 }}, .{ .max_call_depth = 101, .max_steps = 402 }));
    try testing.expectError(error.StepLimitExceeded, interpreter.evaluateModule(testing.allocator, &recursive, entry, &.{.{ .word = 100 }}, .{ .max_call_depth = 101, .max_steps = 401 }));
    var module = Module.init(testing.allocator);
    defer module.deinit();
    const function_id = try module.addFunction("void_large", null);
    const f = module.getFunction(function_id).?;
    const b = try f.addBlock(null);
    const target = try module.symbols.intern("external");
    const arguments = try testing.allocator.alloc(ir.CallArgument, 8300);
    defer testing.allocator.free(arguments);
    @memset(arguments, .{ .scalar_type = .word, .operand = .{ .constant = .{ .word = 1 } } });
    try f.appendVoidCall(b, target, arguments);
    try f.terminate(b, .{ .return_value = null });
    try testing.expectEqual(@as(usize, 0), f.values.items.len);
    for (options) |option| try testing.expectError(error.FrameTooLarge, amd64.emitWithOptions(testing.allocator, &module, option));
}
