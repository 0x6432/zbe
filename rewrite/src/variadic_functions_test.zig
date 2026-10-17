const std = @import("std");
const testing = std.testing;
const ir = @import("ir.zig");
const Module = @import("module.zig").Module;
const interpreter = @import("interpreter.zig");
const fixture = @embedFile("fixtures/variadic-functions.ssa");
const options = [_]@import("amd64.zig").Options{ .{}, .{ .reuse_stack_homes = true }, .{ .callee_saved_homes = true }, .{ .reuse_stack_homes = true, .callee_saved_homes = true } };
fn parse(allocator: std.mem.Allocator, text: []const u8) !Module {
    var diagnostic: ?@import("source.zig").Diagnostic = null;
    return @import("frontend.zig").parse(allocator, .{ .name = "variadic-functions", .text = text }, &diagnostic);
}

test "variadic definitions retain named identity and direct signatures require an exact named prefix" {
    for ([_][]const u8{ "function $f(...) {\n@e\nret\n}", "function w $f(w %p, ...) {\n@e\nret %p\n}" }) |text| {
        var module = try parse(testing.allocator, text);
        defer module.deinit();
        try testing.expect(module.functions.items[0].variadic);
        try @import("module_validation.zig").validate(testing.allocator, &module);
    }
    for ([_][]const u8{
        "function $f(..., w %p) {\n@e\nret\n}",
        "function $f(..., ...) {\n@e\nret\n}",
        "function $f(w %p, ...,) {\n@e\nret\n}",
        "function $f(w %p ...) {\n@e\nret\n}",
    }) |text| try testing.expectError(error.InvalidInput, parse(testing.allocator, text));
    for ([_][]const u8{ "w 7", "..., w 7", "w 7, w 8, ...", "l 7, ...", "sb 7, ..." }) |list| {
        const text = try std.fmt.allocPrint(testing.allocator, "function w $caller() {{\n@e\n%x =w call $f({s})\nret %x\n}}\nfunction w $f(w %p, ...) {{\n@e\nret %p\n}}", .{list});
        defer testing.allocator.free(text);
        var module = try parse(testing.allocator, text);
        defer module.deinit();
        try testing.expectError(error.CallSignatureMismatch, @import("module_validation.zig").validate(testing.allocator, &module));
    }
    for ([_][]const u8{ "w 7, ...", "w 7, ..., l 8, d d_1" }) |list| {
        const text = try std.fmt.allocPrint(testing.allocator, "function w $caller() {{\n@e\n%x =sb call $f({s})\nret %x\n}}\nfunction sb $f(w %p, ...) {{\n@e\nret %p\n}}", .{list});
        defer testing.allocator.free(text);
        var module = try parse(testing.allocator, text);
        defer module.deinit();
        try @import("module_validation.zig").validate(testing.allocator, &module);
    }
}

test "vastart construction checks variadic ownership and long list before failure atomic publication" {
    var failing = testing.FailingAllocator.init(testing.allocator, .{ .resize_fail_index = 0 });
    var f = ir.Function.init(failing.allocator(), @fromBackingInt(@as(u32, 0)), null);
    defer f.deinit();
    const block = try f.addBlock(null);
    const before = failing.alloc_index;
    try testing.expectError(error.InvalidVaStart, f.appendVaStart(block, .{ .constant = .{ .long = 0 } }));
    f.variadic = true;
    try testing.expectError(error.TypeMismatch, f.appendVaStart(block, .{ .constant = .{ .word = 0 } }));
    try testing.expectEqual(before, failing.alloc_index);
    failing.fail_index = failing.alloc_index;
    try testing.expectError(error.OutOfMemory, f.appendVaStart(block, .{ .constant = .{ .long = 0 } }));
    try testing.expectEqual(@as(usize, 0), f.blocks.items[0].instructions.items.len);
    failing.fail_index = std.math.maxInt(usize);
    try f.appendVaStart(block, .{ .constant = .{ .long = 0 } });
    try testing.expect(f.blocks.items[0].instructions.items[0].result() == null);
    try f.terminate(block, .{ .return_value = null });
    try f.validateStructure();
    f.variadic = false;
    try testing.expectError(error.InvalidVaStart, f.validateStructure());
    f.variadic = true;
    f.blocks.items[0].instructions.items[0].va_start.list = .{ .constant = .{ .word = 0 } };
    try testing.expectError(error.TypeMismatch, f.validateStructure());
    try testing.expectError(error.BlockTerminated, f.appendVaStart(block, .{ .constant = .{ .long = 0 } }));
}

test "variadic root named safe paths and reached operation call refusals preserve exact budget precedence" {
    var module = try parse(testing.allocator, fixture);
    defer module.deinit();
    const named: @import("module.zig").FunctionId = @fromBackingInt(@as(u32, 2));
    const safe: @import("module.zig").FunctionId = @fromBackingInt(@as(u32, 3));
    const call: @import("module.zig").FunctionId = @fromBackingInt(@as(u32, 4));
    try testing.expectEqual(@as(u32, 7), (try interpreter.evaluateModule(testing.allocator, &module, named, &.{.{ .word = 7 }}, .{})).?.word);
    try testing.expectError(error.ArgumentCountMismatch, interpreter.evaluateModule(testing.allocator, &module, named, &.{ .{ .word = 7 }, .{ .long = 9 } }, .{}));
    try testing.expectEqual(@as(u32, 42), (try interpreter.evaluateModule(testing.allocator, &module, safe, &.{.{ .word = 0 }}, .{})).?.word);
    try testing.expectError(error.StepLimitExceeded, interpreter.evaluateModule(testing.allocator, &module, safe, &.{.{ .word = 1 }}, .{ .max_steps = 1 }));
    try testing.expectError(error.UnsupportedVariadicOperation, interpreter.evaluateModule(testing.allocator, &module, safe, &.{.{ .word = 1 }}, .{ .max_steps = 2 }));
    try testing.expectError(error.StepLimitExceeded, interpreter.evaluateModule(testing.allocator, &module, call, &.{}, .{ .max_steps = 0 }));
    try testing.expectError(error.UnsupportedVariadicCall, interpreter.evaluateModule(testing.allocator, &module, call, &.{}, .{ .max_steps = 1, .max_call_depth = 1 }));
    try testing.expectError(error.UnsupportedCall, interpreter.evaluate(testing.allocator, module.functions.items[4], &.{}, .{}));
}

test "vastart prologue saves complete incoming banks before homing and initialization remains ordered under folding" {
    var module = try parse(testing.allocator, "function w $f(w %p, d %d, l %address, ...) {\n@e\nvastart %address\nret %p\n}");
    defer module.deinit();
    _ = try @import("optimize.zig").foldIntegerConstants(testing.allocator, module.functions.items[0]);
    try testing.expect(module.functions.items[0].blocks.items[0].instructions.items[0] == .va_start);
    for (options) |option| {
        const assembly = try @import("amd64.zig").emitWithOptions(testing.allocator, &module, option);
        defer testing.allocator.free(assembly);
        try testing.expectEqual(@as(usize, 8), std.mem.count(u8, assembly, "movdqu %xmm"));
        const last_save = std.mem.indexOf(u8, assembly, "movdqu %xmm7").?;
        try testing.expect(last_save < std.mem.indexOf(u8, assembly, "movq %xmm0, %rax").?);
        try testing.expect(std.mem.indexOf(u8, assembly, "movl $16, 0(%r10)\n\tmovl $64, 4(%r10)") != null);
        try testing.expect(std.mem.indexOf(u8, assembly, "leaq 16(%rbp), %rax") != null);
    }
    // For a one-word return-through function the ONLY native changes are the
    // 176-byte region and incoming bank saves; stripping those is byte-identical.
    var normal = try parse(testing.allocator, "function w $identity(w %p) {\n@e\nret %p\n}");
    defer normal.deinit();
    var variadic = try parse(testing.allocator, "function w $identity(w %p, ...) {\n@e\nret %p\n}");
    defer variadic.deinit();
    for (options) |option| {
        const before = try @import("amd64.zig").emitWithOptions(testing.allocator, &normal, option);
        defer testing.allocator.free(before);
        const after = try @import("amd64.zig").emitWithOptions(testing.allocator, &variadic, option);
        defer testing.allocator.free(after);
        var stripped: std.Io.Writer.Allocating = .init(testing.allocator);
        defer stripped.deinit();
        var lines = std.mem.splitScalar(u8, after, '\n');
        var first = true;
        while (lines.next()) |line| {
            if (std.mem.startsWith(u8, line, "\tmovdqu %xmm") or std.mem.startsWith(u8, line, "\tmovq %rdi,") or std.mem.startsWith(u8, line, "\tmovq %rsi,") or std.mem.startsWith(u8, line, "\tmovq %rdx,") or std.mem.startsWith(u8, line, "\tmovq %rcx,") or std.mem.startsWith(u8, line, "\tmovq %r8,") or std.mem.startsWith(u8, line, "\tmovq %r9,")) continue;
            if (!first) try stripped.writer.writeByte('\n');
            first = false;
            try stripped.writer.writeAll(if (std.mem.eql(u8, line, "\tsubq $192, %rsp")) "\tsubq $16, %rsp" else line);
        }
        try testing.expectEqualStrings(before, stripped.written());
    }
}

test "vastart refusal never resolves a symbolic descriptor or changes earlier caller Image writes" {
    var module = try parse(testing.allocator, "function w $f(l %p, ...) {\n@e\nstorew 123, %p\nvastart $descriptor\nret 0\n}");
    defer module.deinit();
    var image = try @import("memory.zig").Image.init(testing.allocator, 24, .{});
    defer image.deinit();
    for (0..4) |bits| {
        try testing.expectError(error.UnsupportedVariadicOperation, interpreter.evaluateModule(testing.allocator, &module, @fromBackingInt(@as(u32, 0)), &.{.{ .long = image.base }}, .{ .memory_image = &image, .stack_memory = if (bits & 1 != 0) .{} else null, .global_memory = if (bits & 2 != 0) .{} else null }));
        try testing.expectEqual(@as(u8, 123), image.bytes[0]);
        for (image.bytes[1..]) |byte| try testing.expectEqual(@as(u8, 0), byte);
    }
}

fn exercise(allocator: std.mem.Allocator) !void {
    var module = try parse(allocator, fixture);
    defer module.deinit();
    if (interpreter.evaluateModule(allocator, &module, @fromBackingInt(@as(u32, 3)), &.{.{ .word = 1 }}, .{})) |_| return error.ExpectedRefusal else |err| {
        if (err != error.UnsupportedVariadicOperation) return err;
    }
    if (interpreter.evaluateModule(allocator, &module, @fromBackingInt(@as(u32, 4)), &.{}, .{})) |_| return error.ExpectedRefusal else |err| {
        if (err != error.UnsupportedVariadicCall) return err;
    }
    for (module.functions.items) |function| {
        var live = try @import("liveness.zig").Snapshot.init(allocator, function, .{});
        defer live.deinit();
        var graph = try @import("interference.zig").Graph.init(allocator, function, .{});
        defer graph.deinit();
        _ = try @import("optimize.zig").foldIntegerConstants(allocator, function);
    }
    for (options) |option| {
        const assembly = try @import("amd64.zig").emitWithOptions(allocator, &module, option);
        defer allocator.free(assembly);
    }
}
test "all variadic header vastart analysis interpreter refusal and emitter allocation failures clean up" {
    try @import("test_support.zig").checkAllocationFailures(exercise);
}
