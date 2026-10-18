//! Additional conformance for existing exts; no narrowing or new capability.
const std = @import("std");
const testing = std.testing;
const ir = @import("ir.zig");
const frontend = @import("frontend.zig");
const interpreter = @import("interpreter.zig");
const amd64 = @import("amd64.zig");
const ssa = @import("ssa.zig");
const optimize = @import("optimize.zig");
const liveness = @import("liveness.zig");
const interference = @import("interference.zig");
const stack_homes = @import("stack_homes.zig");
const program = @embedFile("fixtures/float_precision_program.ssa");
const simple = "function d $f(s %v) {\n@entry\n%r =d exts %v\nret %r\n}";

fn parse(allocator: std.mem.Allocator, text: []const u8) !@import("module.zig").Module {
    var diagnostic: ?@import("source.zig").Diagnostic = null;
    return frontend.parse(allocator, .{ .name = "float_precision", .text = text }, &diagnostic);
}

fn nan(bits: u64) bool {
    return bits & 0x7ff0000000000000 == 0x7ff0000000000000 and bits & 0xfffffffffffff != 0;
}

test "float_precision exact field-mapping oracle spans every binary32 exponent" {
    var module = try parse(testing.allocator, simple);
    defer module.deinit();
    const f = module.functions.items[0];
    var lines = std.mem.tokenizeScalar(u8, @embedFile("fixtures/float_precision_oracle.tsv"), '\n');
    var count: usize = 0;
    var exponents: [256]bool = @splat(false);
    while (lines.next()) |line| {
        if (line[0] == '#') continue;
        var fields = std.mem.tokenizeAny(u8, line, " \t");
        const input = try std.fmt.parseInt(u32, fields.next().?, 16);
        const expected = try std.fmt.parseInt(u64, fields.next().?, 16);
        try testing.expect(fields.next() == null);
        const result = (try interpreter.evaluate(testing.allocator, f, &.{.{ .single_bits = input }}, .{ .max_steps = 2 })).?;
        try testing.expectEqual(expected, result.double_bits);
        exponents[(input >> 23) & 255] = true;
        count += 1;
    }
    try testing.expectEqual(@as(usize, 3693), count);
    for (exponents) |covered| try testing.expect(covered);
}

test "float_precision NaNs remain NaNs without asserting payload or signaling flags" {
    var module = try parse(testing.allocator, simple);
    defer module.deinit();
    for ([_]u32{ 0x7fc00001, 0xffc12345, 0x7fffffff, 0xffffffff, 0x7f800001, 0xff800001 }) |bits| {
        const result = (try interpreter.evaluate(testing.allocator, module.functions.items[0], &.{.{ .single_bits = bits }}, .{})).?;
        try testing.expect(nan(result.double_bits));
    }
}

test "float_precision builder failure is atomic and rejects all non-single sources" {
    var failing = testing.FailingAllocator.init(testing.allocator, .{ .resize_fail_index = 0 });
    var f = ir.Function.init(failing.allocator(), @fromBackingInt(@as(u32, 0)), .double);
    defer f.deinit();
    const b = try f.addBlock(null);
    const result = try f.declareValue(.double);
    for ([_]ir.Constant{ .{ .word = 0 }, .{ .long = 0 }, .{ .double_bits = 0 } }) |value| {
        try testing.expectError(error.TypeMismatch, f.defineUnary(b, result, .widen_float, .{ .constant = value }));
        try testing.expect(f.values.items[@backingInt(result)].definition == .pending);
    }
    failing.fail_index = failing.alloc_index;
    try testing.expectError(error.OutOfMemory, f.defineUnary(b, result, .widen_float, .{ .constant = .{ .single_bits = 1 } }));
    try testing.expect(f.values.items[@backingInt(result)].definition == .pending);
    try testing.expectEqual(@as(usize, 0), f.blocks.items[0].instructions.items.len);
    failing.fail_index = std.math.maxInt(usize);
    try f.defineUnary(b, result, .widen_float, .{ .constant = .{ .single_bits = 1 } });
    try f.terminate(b, .{ .return_value = .{ .value = result } });
    try f.validateStructure();
    try testing.expectError(error.BlockTerminated, f.defineUnary(b, result, .widen_float, .{ .constant = .{ .single_bits = 0 } }));
    f.blocks.items[0].instructions.items[0].unary.operand = .{ .constant = .{ .double_bits = 0 } };
    try testing.expectError(error.TypeMismatch, f.validateStructure());
    for ([_]ir.ScalarType{ .word, .long, .single }) |ty| try testing.expectError(error.TypeMismatch, ir.UnaryOp.widen_float.operandType(ty));
    try testing.expectEqual(ir.ScalarType.single, try ir.UnaryOp.widen_float.operandType(.double));
    for ([_][]const u8{
        "function s $f(s %v) {\n@e\n%r =s exts %v\nret %r\n}",
        "function d $f(d %v) {\n@e\n%r =d exts %v\nret %r\n}",
        "function d $f(l %v) {\n@e\n%r =d exts %v\nret %r\n}",
        "function d $f(w %v) {\n@e\n%r =d exts %v\nret %r\n}",
        "function s $f(d %v) {\n@e\n%r =s truncd %v\nret %r\n}",
    }) |text| try testing.expectError(error.InvalidInput, parse(testing.allocator, text));
}

test "float_precision SSA violations are rejected by every dependent consumer" {
    for ([_][]const u8{
        "function d $f() {\n@e\n%r =d exts %s\n%s =s copy s_1\nret %r\n}",
        "function d $f(w %choose) {\n@e\njnz %choose, @left, @right\n@left\n%s =s copy s_1\njmp @join\n@right\njmp @join\n@join\n%r =d exts %s\nret %r\n}",
    }) |text| {
        var module = try parse(testing.allocator, text);
        defer module.deinit();
        const f = module.functions.items[0];
        var issue: ?ssa.Issue = null;
        try testing.expectError(error.InvalidSSA, ssa.validate(testing.allocator, f, &issue));
        try testing.expect(issue != null);
        try testing.expectError(error.InvalidSSA, liveness.Snapshot.init(testing.allocator, f, .{}));
        try testing.expectError(error.InvalidSSA, interference.Graph.init(testing.allocator, f, .{}));
        try testing.expectError(error.InvalidSSA, stack_homes.Layout.init(testing.allocator, f, .{}));
        try testing.expectError(error.InvalidSSA, optimize.foldIntegerConstants(testing.allocator, f));
        const args: []const ir.Constant = if (f.parameters.items.len == 0) &.{} else &.{.{ .word = 0 }};
        try testing.expectError(error.InvalidSSA, interpreter.evaluate(testing.allocator, f, args, .{}));
        try testing.expectError(error.InvalidSSA, amd64.emit(testing.allocator, &module));
        try testing.expect(f.blocks.items[f.blocks.items.len - 1].instructions.items[0] == .unary);
    }
}

test "float_precision source and analysis snapshots have independent owned lifetimes" {
    const text = try testing.allocator.dupe(u8, "function d $f(s %v) {\n@entry\n%r =d exts %v\njmp @done\n@done\nret %r\n}");
    var module = parse(testing.allocator, text) catch |err| {
        testing.allocator.free(text);
        return err;
    };
    @memset(text, 0xa5);
    testing.allocator.free(text);
    const f = module.functions.items[0];
    const result = f.blocks.items[0].instructions.items[0].unary.result;
    var live = liveness.Snapshot.init(testing.allocator, f, .{}) catch |err| {
        module.deinit();
        return err;
    };
    defer live.deinit();
    var graph = interference.Graph.init(testing.allocator, f, .{}) catch |err| {
        module.deinit();
        return err;
    };
    defer graph.deinit();
    var homes = stack_homes.Layout.init(testing.allocator, f, .{}) catch |err| {
        module.deinit();
        return err;
    };
    defer homes.deinit();
    module.deinit();
    try testing.expect(live.isLiveOut(@fromBackingInt(@as(u32, 0)), result).?);
    try testing.expect(!graph.interferes(result, result).?);
    try testing.expect(homes.slot(result) != null);
}

test "float_precision execution budgets, folding refusal and analysis resource limits" {
    var module = try parse(testing.allocator, "function w $f() {\n@entry\n%unused =d exts s_1\nret 7\n}");
    defer module.deinit();
    const f = module.functions.items[0];
    _ = try optimize.foldIntegerConstants(testing.allocator, f);
    try testing.expect(f.blocks.items[0].instructions.items[0] == .unary);
    for ([_]usize{ 0, 1 }) |budget| try testing.expectError(error.StepLimitExceeded, interpreter.evaluate(testing.allocator, f, &.{}, .{ .max_steps = budget }));
    try testing.expectEqual(@as(u32, 7), (try interpreter.evaluate(testing.allocator, f, &.{}, .{ .max_steps = 2 })).?.word);
    try testing.expectError(error.LivenessTooLarge, liveness.Snapshot.init(testing.allocator, f, .{ .max_matrix_bytes = 0 }));
    try testing.expectError(error.InterferenceTooLarge, interference.Graph.init(testing.allocator, f, .{ .max_graph_bytes = 0 }));
    try testing.expectError(error.LivenessTooLarge, stack_homes.Layout.init(testing.allocator, f, .{ .max_liveness_matrix_bytes = 0 }));
    const assembly = try amd64.emit(testing.allocator, &module);
    defer testing.allocator.free(assembly);
    try testing.expect(std.mem.indexOf(u8, assembly, "cvtss2sd") != null);
}

test "float_precision parallel double phi swaps preserve exact widened bits" {
    var module = try parse(testing.allocator, program);
    defer module.deinit();
    for ([_]bool{ false, true }) |fold| {
        if (fold) for (module.functions.items) |f| {
            _ = try optimize.foldIntegerConstants(testing.allocator, f);
        };
        for ([_]u32{ 0, 1, 2, 3, 10, 31 }) |n| {
            const result = (try interpreter.evaluateModule(testing.allocator, &module, @fromBackingInt(@as(u32, 2)), &.{ .{ .word = n }, .{ .word = 1 }, .{ .word = 0x80000000 } }, .{})).?;
            try testing.expectEqual(if (n % 2 == 0) @as(u64, 0x36a0000000000000) else 0x8000000000000000, result.long);
        }
        const result = (try interpreter.evaluateModule(testing.allocator, &module, @fromBackingInt(@as(u32, 1)), &.{.{ .word = 0x7f7fffff }}, .{})).?;
        try testing.expectEqual(@as(u64, 0x47efffffe0000000), result.long);
        try testing.expectError(error.CallDepthLimitExceeded, interpreter.evaluateModule(testing.allocator, &module, @fromBackingInt(@as(u32, 1)), &.{.{ .word = 1 }}, .{ .max_call_depth = 1 }));
    }
}

fn exercise(allocator: std.mem.Allocator) !void {
    var module = try parse(allocator, "function d $f(s %v) {\n@e\n%r =d exts %v\nret %r\n}\nfunction d $g(s %v) {\n@e\n%r =d call $f(s %v)\nret %r\n}");
    defer module.deinit();
    const f = module.functions.items[0];
    var live = try liveness.Snapshot.init(allocator, f, .{});
    defer live.deinit();
    var graph = try interference.Graph.init(allocator, f, .{});
    defer graph.deinit();
    var homes = try stack_homes.Layout.init(allocator, f, .{});
    defer homes.deinit();
    _ = try optimize.foldIntegerConstants(allocator, f);
    const result = (try interpreter.evaluateModule(allocator, &module, @fromBackingInt(@as(u32, 1)), &.{.{ .single_bits = 1 }}, .{})).?;
    try testing.expectEqual(@as(u64, 0x36a0000000000000), result.double_bits);
    for ([_]amd64.Options{ .{}, .{ .reuse_stack_homes = true }, .{ .callee_saved_homes = true } }) |options| {
        const assembly = try amd64.emitWithOptions(allocator, &module, options);
        defer allocator.free(assembly);
        try testing.expect(std.mem.indexOf(u8, assembly, "cvtss2sd") != null);
    }
}

test "float_precision every parse analysis call evaluation and emission allocation failure cleans up" {
    try @import("test_support.zig").checkAllocationFailures(exercise);
}
