const std = @import("std");
const testing = std.testing;
const ir = @import("ir.zig");
const interpreter = @import("interpreter.zig");
const amd64 = @import("amd64.zig");
fn parse(allocator: std.mem.Allocator, text: []const u8) !@import("module.zig").Module {
    var diagnostic: ?@import("source.zig").Diagnostic = null;
    return @import("frontend.zig").parse(allocator, .{ .name = "low-word", .text = text }, &diagnostic);
}
fn id(index: u32) ir.ValueId {
    return @fromBackingInt(index);
}

test "low-word projections have a validated long source and a word type without a definition" {
    var f = ir.Function.init(testing.allocator, @fromBackingInt(@as(u32, 0)), .word);
    defer f.deinit();
    const long = try f.addParameter(.long);
    const word = try f.addParameter(.word);
    const single = try f.addParameter(.single);
    try testing.expectEqual(ir.ScalarType.word, try f.operandType(.{ .low_word = long }));
    try testing.expectEqual(long, (ir.Operand{ .low_word = long }).referencedValue().?);
    try testing.expectEqual(word, (ir.Operand{ .value = word }).referencedValue().?);
    try testing.expectEqual(@as(?ir.ValueId, null), (ir.Operand{ .constant = .{ .word = 1 } }).referencedValue());
    try testing.expectError(error.TypeMismatch, f.operandType(.{ .low_word = word }));
    try testing.expectError(error.TypeMismatch, f.operandType(.{ .low_word = single }));
    try testing.expectError(error.InvalidValue, f.operandType(.{ .low_word = id(999) }));
    const block = try f.addBlock(null);
    const result = try f.declareValue(.word);
    try testing.expectError(error.TypeMismatch, f.defineCopy(block, result, .{ .value = long }));
    try testing.expect(f.values.items[@backingInt(result)].definition == .pending);
    try f.defineCopy(block, result, .{ .low_word = long });
    try f.terminate(block, .{ .return_value = .{ .value = result } });
    try f.validateStructure();
    f.blocks.items[0].instructions.items[0].copy.operand = .{ .low_word = word };
    try testing.expectError(error.TypeMismatch, f.validateStructure());
}

test "1024 Python low-word arithmetic cases preserve the original long parameter types" {
    var module = try parse(testing.allocator, @embedFile("fixtures/low-word-operations.ssa"));
    defer module.deinit();
    for ([_]bool{ false, true }) |fold| {
        if (fold) for (module.functions.items) |f| {
            _ = try @import("optimize.zig").foldIntegerConstants(testing.allocator, f);
        };
        var lines = std.mem.tokenizeScalar(u8, @embedFile("fixtures/low-word-oracle.tsv"), '\n');
        var count: usize = 0;
        while (lines.next()) |line| {
            if (line[0] == '#') continue;
            var fields = std.mem.tokenizeAny(u8, line, " \t");
            const index = try std.fmt.parseInt(usize, fields.next().?, 10);
            const x = try std.fmt.parseInt(u64, fields.next().?, 10);
            const y = try std.fmt.parseInt(u64, fields.next().?, 10);
            const expected = try std.fmt.parseInt(u32, fields.next().?, 10);
            const f = module.functions.items[index];
            try testing.expectEqual(ir.ScalarType.long, f.values.items[@backingInt(f.parameters.items[0])].scalar_type);
            try testing.expectEqual(expected, (try interpreter.evaluate(testing.allocator, f, &.{ .{ .long = x }, .{ .long = y } }, .{})).?.word);
            count += 1;
        }
        try testing.expectEqual(@as(usize, 1024), count);
    }
}

test "low-word projections cover phi call return store numeric cast and live original contexts" {
    var module = try parse(testing.allocator, @embedFile("fixtures/low-word-contexts.ssa"));
    defer module.deinit();
    var image = try @import("memory.zig").Image.init(testing.allocator, 8, .{});
    defer image.deinit();
    const x: u64 = 0xdeadbeef800000ff;
    const y: u64 = 0xfedcba987fffffff;
    for ([_]bool{ false, true }) |fold| {
        if (fold) for (module.functions.items) |f| {
            _ = try @import("optimize.zig").foldIntegerConstants(testing.allocator, f);
        };
        try testing.expectEqual(@as(u32, 0x800000ff), (try interpreter.evaluate(testing.allocator, module.functions.items[0], &.{.{ .long = x }}, .{})).?.word);
        for ([_]u32{ 0, 1 }) |choose| {
            try testing.expectEqual(@as(u32, @truncate(if (choose == 0) y else x)), (try interpreter.evaluate(testing.allocator, module.functions.items[1], &.{ .{ .long = x }, .{ .long = y }, .{ .word = choose } }, .{})).?.word);
        }
        try testing.expectEqual(x & 0xffffffff00000000, (try interpreter.evaluate(testing.allocator, module.functions.items[2], &.{.{ .long = x }}, .{})).?.long);
        try testing.expectEqual(x ^ @as(u64, 0x00000213), (try interpreter.evaluateModule(testing.allocator, &module, @fromBackingInt(@as(u32, 4)), &.{ .{ .long = x }, .{ .long = 1 }, .{ .long = 2 }, .{ .long = 3 }, .{ .long = 4 }, .{ .long = 5 }, .{ .long = 6 } }, .{})).?.long);
        try testing.expectEqual(@as(u32, 0x800000ff), (try interpreter.evaluate(testing.allocator, module.functions.items[6], &.{ .{ .long = image.base }, .{ .long = x } }, .{ .memory_image = &image })).?.word);
        try testing.expectEqual(@as(u64, @bitCast(@as(f64, -2147483393.0))), (try interpreter.evaluate(testing.allocator, module.functions.items[7], &.{.{ .long = x }}, .{})).?.double_bits);
        try testing.expectEqual(@as(u64, @bitCast(@as(f64, 2147483903.0))), (try interpreter.evaluate(testing.allocator, module.functions.items[8], &.{.{ .long = x }}, .{})).?.double_bits);
        try testing.expectEqual(@as(u64, 1) << 33, (try interpreter.evaluate(testing.allocator, module.functions.items[9], &.{.{ .long = 0xfedcba9800000021 }}, .{})).?.long);
        try testing.expectEqual(@as(u64, 1), (try interpreter.evaluate(testing.allocator, module.functions.items[10], &.{ .{ .long = x }, .{ .long = y } }, .{})).?.long);
        for ([_]u32{ 0, 1, 2, 10 }) |n| try testing.expectEqual(@as(u32, 0x800000ff) +% n, (try interpreter.evaluate(testing.allocator, module.functions.items[11], &.{ .{ .long = x }, .{ .word = n } }, .{})).?.word);
        try testing.expectEqual(@as(u32, 0x800000ff), (try interpreter.evaluate(testing.allocator, module.functions.items[12], &.{.{ .long = x }}, .{})).?.single_bits);
        try testing.expectEqual(std.math.maxInt(u64), (try interpreter.evaluate(testing.allocator, module.functions.items[13], &.{.{ .long = x }}, .{})).?.long);
        try testing.expectEqual(@as(u64, 0xdeadbeef00000001), (try interpreter.evaluate(testing.allocator, module.functions.items[14], &.{}, .{})).?.long);
    }
}

test "projected uses retain SSA ordering and phi-edge dominance checks" {
    for ([_][]const u8{
        "function w $f() {\n@e\n%r =w add %x, 1\n%x =l copy 1\nret %r\n}",
        "function w $f(w %c) {\n@e\njnz %c, @left, @right\n@left\n%x =l copy 1\njmp @join\n@right\njmp @join\n@join\n%r =w phi @left %x, @right %x\nret %r\n}",
    }) |text| {
        var module = try parse(testing.allocator, text);
        defer module.deinit();
        var issue: ?@import("ssa.zig").Issue = null;
        try testing.expectError(error.InvalidSSA, @import("ssa.zig").validate(testing.allocator, module.functions.items[0], &issue));
        try testing.expect(issue != null);
    }
    for ([_][]const u8{
        "function l $f(w %x) {\n@e\n%r =l add %x, 1\nret %r\n}",
        "function l $f(w %x) {\n@e\nret %x\n}",
        "function l $f(w %x) {\n@e\n%r =l sltof %x\nret %r\n}",
    }) |text| try testing.expectError(error.InvalidInput, parse(testing.allocator, text));
}

const pipeline = "function l $f(l %x,w %choose) {\n@entry\njnz %choose, @left, @right\n@left\njmp @join\n@right\njmp @join\n@join\n%p =w phi @left %x, @right 7\n%r =w call $sink(w %x,w %p)\n%wide =l extuw %r\n%result =l xor %x, %wide\nret %result\n}\nfunction w $sink(w %x,w %y) {\n@entry\n%r =w add %x, %y\nret %r\n}";
fn exercise(allocator: std.mem.Allocator) !void {
    var module = try parse(allocator, pipeline);
    defer module.deinit();
    for (module.functions.items) |f| {
        var graph = try @import("interference.zig").Graph.init(allocator, f, .{});
        defer graph.deinit();
        _ = try @import("optimize.zig").foldIntegerConstants(allocator, f);
    }
    const result = (try interpreter.evaluateModule(allocator, &module, @fromBackingInt(@as(u32, 0)), &.{ .{ .long = 0xdeadbeef80000001 }, .{ .word = 1 } }, .{})).?.long;
    try testing.expectEqual(@as(u64, 0xdeadbeef80000003), result);
    for ([_]amd64.Options{ .{}, .{ .reuse_stack_homes = true }, .{ .callee_saved_homes = true } }) |options| {
        const assembly = try amd64.emitWithOptions(allocator, &module, options);
        defer allocator.free(assembly);
        try testing.expect(std.mem.indexOf(u8, assembly, "call sink") != null);
    }
}
test "projected parsing analysis folding calls and all homes clean every allocation failure" {
    try @import("test_support.zig").checkAllocationFailures(exercise);
}

test "projecting does not erase integer arithmetic faults or floating raw payloads" {
    var module = try parse(testing.allocator, "function w $f() {\n@e\n%x =l copy 9223372039002259456\n%y =l copy 4294967295\n%r =w div %x, %y\nret %r\n}");
    defer module.deinit();
    _ = try @import("optimize.zig").foldIntegerConstants(testing.allocator, module.functions.items[0]);
    try testing.expectError(error.IntegerOverflow, interpreter.evaluate(testing.allocator, module.functions.items[0], &.{}, .{}));
    var raw = try parse(testing.allocator, "function s $f(l %x) {\n@e\n%r =s cast %x\nret %r\n}");
    defer raw.deinit();
    try testing.expectEqual(@as(u32, 0x7fc12345), (try interpreter.evaluate(testing.allocator, raw.functions.items[0], &.{.{ .long = 0xdeadbeef7fc12345 }}, .{})).?.single_bits);
}
