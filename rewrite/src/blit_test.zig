const std = @import("std");
const testing = std.testing;
const ir = @import("ir.zig");
const memory = @import("memory.zig");
const interpreter = @import("interpreter.zig");
const amd64 = @import("amd64.zig");
fn parse(allocator: std.mem.Allocator, text: []const u8) !@import("module.zig").Module {
    var diagnostic: ?@import("source.zig").Diagnostic = null;
    return @import("frontend.zig").parse(allocator, .{ .name = "blit", .text = text }, &diagnostic);
}

test "blit builders are typed effect-only failure atomic and reject closed blocks" {
    var failing = testing.FailingAllocator.init(testing.allocator, .{ .resize_fail_index = 0 });
    var f = ir.Function.init(failing.allocator(), @fromBackingInt(@as(u32, 0)), null);
    defer f.deinit();
    const b = try f.addBlock(null);
    const src: ir.Operand = .{ .constant = .{ .long = 0 } };
    const wrong: ir.Operand = .{ .constant = .{ .word = 0 } };
    try testing.expectError(error.TypeMismatch, f.appendBlit(b, src, wrong, 7));
    try testing.expectError(error.TypeMismatch, f.appendBlit(b, wrong, src, 7));
    failing.fail_index = failing.alloc_index;
    try testing.expectError(error.OutOfMemory, f.appendBlit(b, src, src, 7));
    try testing.expectEqual(@as(usize, 0), f.blocks.items[0].instructions.items.len);
    failing.fail_index = std.math.maxInt(usize);
    try f.appendBlit(b, src, src, 7);
    try testing.expectEqual(@as(?ir.ValueId, null), f.blocks.items[0].instructions.items[0].result());
    try testing.expectEqual(@as(usize, 0), f.values.items.len);
    try f.terminate(b, .{ .return_value = null });
    try testing.expectError(error.BlockTerminated, f.appendBlit(b, src, src, 0));
    try f.validateStructure();
    f.blocks.items[0].instructions.items[0].blit.source = wrong;
    try testing.expectError(error.TypeMismatch, f.validateStructure());
}

test "blit frontend requires exact nonnegative signed-word constants and long addresses" {
    for ([_][]const u8{ "0", "1", "268435456", "2147483647" }) |count| {
        const text = try std.fmt.allocPrint(testing.allocator, "function $f(l %p) {{\n@e\nblit %p, %p, {s}\nret\n}}", .{count});
        defer testing.allocator.free(text);
        var module = try parse(testing.allocator, text);
        defer module.deinit();
        const f = module.functions.items[0];
        try f.validateStructure();
        const assembly = try amd64.emit(testing.allocator, &module);
        defer testing.allocator.free(assembly);
        try testing.expect(assembly.len < 2048);
        try testing.expectEqual(@as(usize, if (count[0] == '0') 0 else 1), std.mem.count(u8, assembly, "rep movsb"));
    }
    for ([_][]const u8{
        "function $f(l %p,w %n) {\n@e\nblit %p, %p, %n\nret\n}",
        "function $f(l %p) {\n@e\nblit %p, %p, -1\nret\n}",
        "function $f(l %p) {\n@e\nblit %p, %p, -0\nret\n}",
        "function $f(l %p) {\n@e\nblit %p, %p, 2147483648\nret\n}",
        "function $f(l %p) {\n@e\nblit %p, %p, 18446744073709551616\nret\n}",
        "function $f(l %p) {\n@e\nblit %p, %p, d_1\nret\n}",
        "function $f(w %p) {\n@e\nblit %p, %p, 1\nret\n}",
        "function $f(l %p) {\n@e\nblit %p, %p\nret\n}",
    }) |text| try testing.expectError(error.InvalidInput, parse(testing.allocator, text));
}

test "blit spans are checked entirely before writes with exact alias and zero-count rules" {
    var image = try memory.Image.init(testing.allocator, 32, .{});
    defer image.deinit();
    for (0..32) |i| image.bytes[i] = @intCast(i);
    const before: [32]u8 = image.bytes[0..32].*;
    try image.copy(0, std.math.maxInt(u64), 0);
    try image.copy(image.base + 3, image.base + 3, 7);
    try testing.expectEqualSlices(u8, &before, image.bytes);
    for ([_]struct { src: u64, dst: u64, count: usize, expected: anyerror }{
        .{ .src = image.base, .dst = image.base + 1, .count = 7, .expected = error.PartialMemoryOverlap },
        .{ .src = image.base + 1, .dst = image.base, .count = 7, .expected = error.PartialMemoryOverlap },
        .{ .src = image.base, .dst = image.base + 31, .count = 2, .expected = error.MemoryOutOfBounds },
        .{ .src = image.base + 31, .dst = image.base, .count = 2, .expected = error.MemoryOutOfBounds },
        .{ .src = image.base + 31, .dst = image.base + 31, .count = 2, .expected = error.MemoryOutOfBounds },
        .{ .src = 0, .dst = 0, .count = 1, .expected = error.MemoryOutOfBounds },
        .{ .src = std.math.maxInt(u64), .dst = image.base, .count = 2, .expected = error.MemoryOutOfBounds },
    }) |case| {
        try testing.expectError(case.expected, image.copy(case.src, case.dst, case.count));
        try testing.expectEqualSlices(u8, &before, image.bytes);
    }
    try image.copy(image.base + 1, image.base + 16, 7);
    var expected = before;
    @memcpy(expected[16..23], before[1..8]);
    try testing.expectEqualSlices(u8, &expected, image.bytes);
    // Adjacent ranges are legal in either direction, without a gap.
    try image.copy(image.base, image.base + 8, 8);
    try testing.expectEqualSlices(u8, image.bytes[0..8], image.bytes[8..16]);
    try image.copy(image.base + 16, image.base, 8);
    try testing.expectEqualSlices(u8, image.bytes[16..24], image.bytes[0..8]);
}

test "blit SSA uses stay live across edges and folding never deletes effects" {
    for ([_][]const u8{
        "function $f(l %p) {\n@e\nblit %src, %p, 0\n%src =l copy 0\nret\n}",
        "function $f(l %p) {\n@e\nblit %p, %dst, 0\n%dst =l copy 0\nret\n}",
        "function $f(w %c,l %p) {\n@e\njnz %c, @a, @b\n@a\n%x =l copy 0\njmp @b\n@b\nblit %x, %p, 1\nret\n}",
    }) |text| {
        var module = try parse(testing.allocator, text);
        defer module.deinit();
        var issue: ?@import("ssa.zig").Issue = null;
        try testing.expectError(error.InvalidSSA, @import("ssa.zig").validate(testing.allocator, module.functions.items[0], &issue));
    }
    var module = try parse(testing.allocator, @embedFile("fixtures/blit.ssa"));
    defer module.deinit();
    const f = module.functions.items[0];
    var live = try @import("liveness.zig").Snapshot.init(testing.allocator, f, .{});
    defer live.deinit();
    for (f.parameters.items) |p| try testing.expect(live.isLiveOut(@fromBackingInt(@as(u32, 0)), p).?);
    _ = try @import("optimize.zig").foldIntegerConstants(testing.allocator, f);
    try testing.expect(f.blocks.items[1].instructions.items[0] == .blit);
}

test "blit evaluator shares images observes one step and preserves default refusal" {
    var module = try parse(testing.allocator, "function $f(l %a,l %b) {\n@e\ncall $copy(l %a,l %b)\nret\n}\nfunction $copy(l %a,l %b) {\n@e\nblit %a, %b, 7\nret\n}");
    defer module.deinit();
    var image = try memory.Image.init(testing.allocator, 32, .{});
    defer image.deinit();
    @memcpy(image.bytes[1..8], "abcdefg");
    const args = [_]ir.Constant{ .{ .long = image.base + 1 }, .{ .long = image.base + 17 } };
    const entry: @import("module.zig").FunctionId = @fromBackingInt(@as(u32, 0));
    try testing.expectError(error.UnsupportedMemory, interpreter.evaluateModule(testing.allocator, &module, entry, &args, .{}));
    try testing.expectEqual(@as(?ir.Constant, null), try interpreter.evaluateModule(testing.allocator, &module, entry, &args, .{ .memory_image = &image, .max_steps = 4 }));
    try testing.expectEqualSlices(u8, "abcdefg", image.bytes[17..24]);
    @memset(image.bytes[17..24], 0);
    try testing.expectError(error.StepLimitExceeded, interpreter.evaluateModule(testing.allocator, &module, entry, &args, .{ .memory_image = &image, .max_steps = 1 }));
    try testing.expectEqualSlices(u8, &.{ 0, 0, 0, 0, 0, 0, 0 }, image.bytes[17..24]);
    try testing.expectError(error.PartialMemoryOverlap, interpreter.evaluateModule(testing.allocator, &module, entry, &.{ .{ .long = image.base + 1 }, .{ .long = image.base + 2 } }, .{ .memory_image = &image }));
    var zero = try parse(testing.allocator, "function $f() {\n@e\nblit 0, -1, 0\nret\n}");
    defer zero.deinit();
    try testing.expectEqual(@as(?ir.Constant, null), try interpreter.evaluate(testing.allocator, zero.functions.items[0], &.{}, .{ .memory_image = &image, .max_steps = 2 }));
    try testing.expectError(error.UnsupportedMemory, interpreter.evaluate(testing.allocator, zero.functions.items[0], &.{}, .{}));
}

fn exercise(allocator: std.mem.Allocator) !void {
    var module = try parse(allocator, @embedFile("fixtures/blit.ssa"));
    defer module.deinit();
    var image = try memory.Image.init(allocator, 32, .{});
    defer image.deinit();
    @memcpy(image.bytes[1..8], "abcdefg");
    for (module.functions.items) |f| {
        var graph = try @import("interference.zig").Graph.init(allocator, f, .{});
        defer graph.deinit();
        _ = try @import("optimize.zig").foldIntegerConstants(allocator, f);
    }
    const result = try interpreter.evaluateModule(allocator, &module, @fromBackingInt(@as(u32, 0)), &.{ .{ .long = image.base + 1 }, .{ .long = image.base + 17 }, .{ .word = 3 } }, .{ .memory_image = &image });
    try testing.expectEqual(@as(?ir.Constant, null), result);
    try testing.expectEqualSlices(u8, "abcdefg", image.bytes[17..24]);
    for ([_]amd64.Options{ .{}, .{ .reuse_stack_homes = true }, .{ .callee_saved_homes = true } }) |options| {
        const assembly = try amd64.emitWithOptions(allocator, &module, options);
        defer allocator.free(assembly);
        try testing.expectEqual(@as(usize, 1), std.mem.count(u8, assembly, "rep movsb"));
    }
}
test "blit parse analysis evaluation and emission release all failed allocations" {
    try @import("test_support.zig").checkAllocationFailures(exercise);
}
