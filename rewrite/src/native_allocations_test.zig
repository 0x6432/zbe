const std = @import("std");
const testing = std.testing;
const ir = @import("ir.zig");
const interpreter = @import("interpreter.zig");
const amd64 = @import("amd64.zig");
fn parse(allocator: std.mem.Allocator, text: []const u8) !@import("module.zig").Module {
    var diagnostic: ?@import("source.zig").Diagnostic = null;
    return @import("frontend.zig").parse(allocator, .{ .name = "allocations", .text = text }, &diagnostic);
}

test "allocation builder retains pending definitions on class and allocation failures" {
    var failing = testing.FailingAllocator.init(testing.allocator, .{ .resize_fail_index = 0 });
    var f = ir.Function.init(failing.allocator(), @fromBackingInt(@as(u32, 0)), .long);
    defer f.deinit();
    const b = try f.addBlock(null);
    const result = try f.declareValue(.long);
    try testing.expectError(error.TypeMismatch, f.defineAllocate(b, result, .{ .constant = .{ .word = 4 } }, .four));
    failing.fail_index = failing.alloc_index;
    try testing.expectError(error.OutOfMemory, f.defineAllocate(b, result, .{ .constant = .{ .long = 4 } }, .four));
    try testing.expect(f.values.items[0].definition == .pending);
    try testing.expectEqual(@as(usize, 0), f.blocks.items[0].instructions.items.len);
    failing.fail_index = std.math.maxInt(usize);
    try f.defineAllocate(b, result, .{ .constant = .{ .long = 4 } }, .four);
    try f.terminate(b, .{ .return_value = .{ .value = result } });
    try f.validateStructure();
    try testing.expectError(error.BlockTerminated, f.defineAllocate(b, result, .{ .constant = .{ .long = 4 } }, .four));
    f.blocks.items[0].instructions.items[0].allocate.size = .{ .constant = .{ .word = 4 } };
    try testing.expectError(error.TypeMismatch, f.validateStructure());
}

test "all typed allocation alignments parse and reached allocation is explicitly refused by evaluators" {
    for ([_]struct { spelling: []const u8, alignment: ir.AllocationAlignment, bytes: u5 }{
        .{ .spelling = "alloc4", .alignment = .four, .bytes = 4 },
        .{ .spelling = "alloc8", .alignment = .eight, .bytes = 8 },
        .{ .spelling = "alloc16", .alignment = .sixteen, .bytes = 16 },
    }) |case| {
        const text = try std.fmt.allocPrint(testing.allocator, "function l $f(l %size) {{\n@e\n%ptr =l {s} %size\nret %ptr\n}}", .{case.spelling});
        defer testing.allocator.free(text);
        var module = try parse(testing.allocator, text);
        defer module.deinit();
        const f = module.functions.items[0];
        try testing.expectEqual(case.alignment, f.blocks.items[0].instructions.items[0].allocate.alignment);
        try testing.expectEqual(case.bytes, case.alignment.bytes());
        for ([_]u64{ 0, 1, 4096, std.math.maxInt(u64) }) |size| {
            try testing.expectError(error.UnsupportedAllocation, interpreter.evaluate(testing.allocator, f, &.{.{ .long = size }}, .{}));
            try testing.expectError(error.StepLimitExceeded, interpreter.evaluate(testing.allocator, f, &.{.{ .long = size }}, .{ .max_steps = 0 }));
        }
        var image = try @import("memory.zig").Image.init(testing.allocator, 32, .{});
        defer image.deinit();
        try testing.expectError(error.UnsupportedAllocation, interpreter.evaluateModule(testing.allocator, &module, @fromBackingInt(@as(u32, 0)), &.{.{ .long = 8 }}, .{ .memory_image = &image }));
    }
}

test "allocation types arity and size SSA dependencies are validated" {
    for ([_][]const u8{
        "function w $f() {\n@e\n%r =w alloc4 4\nret %r\n}",
        "function s $f() {\n@e\n%r =s alloc8 4\nret %r\n}",
        "function l $f(w %n) {\n@e\n%r =l alloc16 %n\nret %r\n}",
        "function l $f() {\n@e\n%r =l alloc4 s_4\nret %r\n}",
        "function l $f() {\n@e\n%r =l alloc4 4, 4\nret %r\n}",
        "function l $f() {\n@e\n%r =l alloc4\nret %r\n}",
    }) |text| try testing.expectError(error.InvalidInput, parse(testing.allocator, text));
    var module = try parse(testing.allocator, "function l $f() {\n@e\n%r =l alloc8 %n\n%n =l copy 8\nret %r\n}");
    defer module.deinit();
    var issue: ?@import("ssa.zig").Issue = null;
    try testing.expectError(error.InvalidSSA, @import("ssa.zig").validate(testing.allocator, module.functions.items[0], &issue));
    try testing.expectEqual(@import("ssa.zig").Code.use_before_definition, issue.?.code);
}

test "unused allocations remain effects while unreachable allocation need not execute" {
    var module = try parse(testing.allocator, "function l $f(w %take) {\n@entry\njnz %take, @alloc, @safe\n@alloc\n%unused =l alloc4 0\nret 7\n@safe\nret 42\n}");
    defer module.deinit();
    const f = module.functions.items[0];
    _ = try @import("optimize.zig").foldIntegerConstants(testing.allocator, f);
    try testing.expect(f.blocks.items[1].instructions.items[0] == .allocate);
    try testing.expectEqual(@as(u64, 42), (try interpreter.evaluate(testing.allocator, f, &.{.{ .word = 0 }}, .{})).?.long);
    try testing.expectError(error.UnsupportedAllocation, interpreter.evaluate(testing.allocator, f, &.{.{ .word = 1 }}, .{}));
    for ([_]amd64.Options{ .{}, .{ .reuse_stack_homes = true }, .{ .callee_saved_homes = true } }) |options| {
        const assembly = try amd64.emitWithOptions(testing.allocator, &module, options);
        defer testing.allocator.free(assembly);
        try testing.expect(std.mem.indexOf(u8, assembly, "allocpage") != null);
        try testing.expect(std.mem.indexOf(u8, assembly, "testb $0, (%rsp)") != null);
    }
}

const pipeline = "function l $f(l %size) {\n@e\n%first =l alloc4 %size\n%second =l alloc8 1\n%third =l alloc16 16\n%r =l call $sink(l %first,l %second,l %third,l 1,l 2,l 3,l 4,l 5)\nret %r\n}";
fn exercise(allocator: std.mem.Allocator) !void {
    var module = try parse(allocator, pipeline);
    defer module.deinit();
    const f = module.functions.items[0];
    var graph = try @import("interference.zig").Graph.init(allocator, f, .{});
    defer graph.deinit();
    _ = try @import("optimize.zig").foldIntegerConstants(allocator, f);
    if (interpreter.evaluateModule(allocator, &module, @fromBackingInt(@as(u32, 0)), &.{.{ .long = 16 }}, .{})) |_| return error.ExpectedAllocationRefusal else |err| {
        if (err != error.UnsupportedAllocation) return err;
    }
    for ([_]amd64.Options{ .{}, .{ .reuse_stack_homes = true }, .{ .callee_saved_homes = true } }) |options| {
        const assembly = try amd64.emitWithOptions(allocator, &module, options);
        defer allocator.free(assembly);
        try testing.expect(std.mem.indexOf(u8, assembly, "leaq 16(%rsp), %rax") != null);
        try testing.expectEqual(@as(usize, 3), std.mem.count(u8, assembly, "addq $15, %rax"));
    }
}
test "allocation parse analysis refusal and all native home modes clean every allocation failure" {
    try @import("test_support.zig").checkAllocationFailures(exercise);
}

test "child allocation refusal preserves earlier image writes without fabricating addresses" {
    var module = try parse(testing.allocator, "function l $f(l %p) {\n@e\nstoreb 99, %p\n%r =l call $child()\nret %r\n}\nfunction l $child() {\n@e\n%r =l alloc16 16\nret %r\n}");
    defer module.deinit();
    var image = try @import("memory.zig").Image.init(testing.allocator, 8, .{});
    defer image.deinit();
    try testing.expectError(error.UnsupportedAllocation, interpreter.evaluateModule(testing.allocator, &module, @fromBackingInt(@as(u32, 0)), &.{.{ .long = image.base }}, .{ .memory_image = &image }));
    try testing.expectEqual(@as(u8, 99), image.bytes[0]);
    try testing.expectEqualSlices(u8, &.{ 0, 0, 0, 0, 0, 0, 0 }, image.bytes[1..]);
}
