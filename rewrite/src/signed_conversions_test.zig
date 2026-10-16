const std = @import("std");
const testing = std.testing;
const ir = @import("ir.zig");
const semantics = @import("semantics.zig");
const interpreter = @import("interpreter.zig");
const amd64 = @import("amd64.zig");
fn parse(allocator: std.mem.Allocator, text: []const u8) !@import("module.zig").Module {
    var diagnostic: ?@import("source.zig").Diagnostic = null;
    return @import("frontend.zig").parse(allocator, .{ .name = "signed-convert", .text = text }, &diagnostic);
}
fn constant(ty: u8, bits: u64) ir.Constant {
    return switch (ty) {
        'w' => .{ .word = @truncate(bits) },
        'l' => .{ .long = bits },
        's' => .{ .single_bits = @truncate(bits) },
        'd' => .{ .double_bits = bits },
        else => unreachable,
    };
}
fn bitsOf(value: ir.Constant) u64 {
    return switch (value) {
        .word => |v| v,
        .long => |v| v,
        .single_bits => |v| v,
        .double_bits => |v| v,
    };
}

test "512 exact Python signed numeric conversions match evaluator raw results" {
    var lines = std.mem.tokenizeScalar(u8, @embedFile("fixtures/signed-conversion-oracle.tsv"), '\n');
    var count: usize = 0;
    while (lines.next()) |line| {
        if (line[0] == '#') continue;
        var fields = std.mem.tokenizeAny(u8, line, " \t");
        const result_ty = fields.next().?;
        const opcode = fields.next().?;
        const source_ty = fields.next().?;
        const input = try std.fmt.parseInt(u64, fields.next().?, 10);
        const expected = try std.fmt.parseInt(u64, fields.next().?, 10);
        const text = try std.fmt.allocPrint(testing.allocator, "function {s} $f({s} %v) {{\n@e\n%r ={s} {s} %v\nret %r\n}}", .{ result_ty, source_ty, result_ty, opcode });
        defer testing.allocator.free(text);
        var module = try parse(testing.allocator, text);
        defer module.deinit();
        const f = module.functions.items[0];
        const result = (try interpreter.evaluate(testing.allocator, f, &.{constant(source_ty[0], input)}, .{})).?;
        try testing.expectEqual(constant(result_ty[0], expected).scalarType(), result.scalarType());
        try testing.expectEqual(expected, bitsOf(result));
        _ = try @import("optimize.zig").foldIntegerConstants(testing.allocator, f);
        try testing.expect(f.blocks.items[0].instructions.items[0] == .convert);
        count += 1;
    }
    try testing.expectEqual(@as(usize, 512), count);
}

test "signed conversion domain checks precede host integer casts and truncate toward zero" {
    for ([_]ir.ScalarType{ .word, .long }) |ty| {
        for ([_]u64{ 0x7ff0000000000000, 0xfff0000000000000, 0x7ff8123456789abc, 0x7ff0123456789abc, 0x43e0000000000000, 0xc3e0000000000001 }) |bits| {
            try testing.expectError(error.ConversionOutOfRange, semantics.convertedValue(.double_to_signed_integer, .{ .double_bits = bits }, ty));
        }
        for ([_]u32{ 0x7f800000, 0xff800000, 0x7fc12345, 0x7f812345, 0x5f000000, 0xdf000001 }) |bits| {
            try testing.expectError(error.ConversionOutOfRange, semantics.convertedValue(.single_to_signed_integer, .{ .single_bits = bits }, ty));
        }
    }
    try testing.expectError(error.ConversionOutOfRange, semantics.convertedValue(.double_to_signed_integer, .{ .double_bits = @bitCast(@as(f64, 2147483648.0)) }, .word));
    try testing.expectEqual(@as(u32, 0x80000000), (try semantics.convertedValue(.double_to_signed_integer, .{ .double_bits = @bitCast(@as(f64, -2147483648.5)) }, .word)).word);
    try testing.expectEqual(@as(u64, 0x8000000000000000), (try semantics.convertedValue(.double_to_signed_integer, .{ .double_bits = 0xc3e0000000000000 }, .long)).long);
    try testing.expectEqual(@as(u32, 0xffffffff), (try semantics.convertedValue(.double_to_signed_integer, .{ .double_bits = @bitCast(@as(f64, -1.75)) }, .word)).word);
    try testing.expectEqual(@as(u64, 0), (try semantics.convertedValue(.single_to_signed_integer, .{ .single_bits = 0x80000000 }, .long)).long);
}

test "signed conversion builders validate classes and retain pending definitions after failure" {
    var failing = testing.FailingAllocator.init(testing.allocator, .{ .resize_fail_index = 0 });
    var f = ir.Function.init(failing.allocator(), @fromBackingInt(@as(u32, 0)), null);
    defer f.deinit();
    const b = try f.addBlock(null);
    const result = try f.declareValue(.double);
    try testing.expectError(error.TypeMismatch, f.defineConvert(b, result, .single_to_signed_integer, .{ .constant = .{ .single_bits = 0 } }));
    try testing.expectError(error.TypeMismatch, f.defineConvert(b, result, .signed_word_to_float, .{ .constant = .{ .long = 0 } }));
    failing.fail_index = failing.alloc_index;
    try testing.expectError(error.OutOfMemory, f.defineConvert(b, result, .signed_word_to_float, .{ .constant = .{ .word = 42 } }));
    try testing.expect(f.values.items[0].definition == .pending);
    try testing.expectEqual(@as(usize, 0), f.blocks.items[0].instructions.items.len);
    failing.fail_index = std.math.maxInt(usize);
    try f.defineConvert(b, result, .signed_word_to_float, .{ .constant = .{ .word = 42 } });
    try f.terminate(b, .{ .return_value = null });
    try f.validateStructure();
    try testing.expectError(error.BlockTerminated, f.defineConvert(b, result, .signed_word_to_float, .{ .constant = .{ .word = 42 } }));
    f.blocks.items[0].instructions.items[0].convert.operand = .{ .constant = .{ .double_bits = 0 } };
    try testing.expectError(error.TypeMismatch, f.validateStructure());
    for ([_][]const u8{
        "function w $f() {\n@e\n%r =w swtof 1\nret %r\n}",
        "function s $f() {\n@e\n%r =s stosi s_1\nret %r\n}",
        "function d $f(s %x) {\n@e\n%r =d swtof %x\nret %r\n}",
        "function l $f() {\n@e\n%r =l dtosi s_1\nret %r\n}",
    }) |text| try testing.expectError(error.InvalidInput, parse(testing.allocator, text));
}

test "numeric conversions obey SSA and remain executed even with unused results" {
    var malformed = try parse(testing.allocator, "function d $f() {\n@e\n%r =d sltof %x\n%x =l copy 1\nret %r\n}");
    defer malformed.deinit();
    var issue: ?@import("ssa.zig").Issue = null;
    try testing.expectError(error.InvalidSSA, @import("ssa.zig").validate(testing.allocator, malformed.functions.items[0], &issue));
    var module = try parse(testing.allocator, "function w $f() {\n@e\n%unused =w dtosi d_nan\nret 7\n}");
    defer module.deinit();
    const f = module.functions.items[0];
    _ = try @import("optimize.zig").foldIntegerConstants(testing.allocator, f);
    try testing.expect(f.blocks.items[0].instructions.items[0] == .convert);
    try testing.expectError(error.ConversionOutOfRange, interpreter.evaluate(testing.allocator, f, &.{}, .{}));
    try testing.expectError(error.StepLimitExceeded, interpreter.evaluate(testing.allocator, f, &.{}, .{ .max_steps = 0 }));
    for ([_]amd64.Options{ .{}, .{ .reuse_stack_homes = true }, .{ .callee_saved_homes = true } }) |options| {
        const assembly = try amd64.emitWithOptions(testing.allocator, &module, options);
        defer testing.allocator.free(assembly);
        try testing.expect(std.mem.indexOf(u8, assembly, "cvttsd2sil %xmm0, %eax") != null);
    }
}

fn exercise(allocator: std.mem.Allocator) !void {
    var module = try parse(allocator, @embedFile("fixtures/signed-conversions.ssa"));
    defer module.deinit();
    for (module.functions.items, 0..) |f, i| {
        var graph = try @import("interference.zig").Graph.init(allocator, f, .{});
        defer graph.deinit();
        _ = try @import("optimize.zig").foldIntegerConstants(allocator, f);
        const ty = f.values.items[@backingInt(f.parameters.items[0])].scalar_type;
        const input: ir.Constant = switch (ty) {
            .word => .{ .word = 42 },
            .long => .{ .long = 42 },
            .single => .{ .single_bits = 0x42280000 },
            .double => .{ .double_bits = 0x4045000000000000 },
        };
        const result = (try interpreter.evaluateModule(allocator, &module, @fromBackingInt(@as(u32, @intCast(i))), &.{input}, .{})).?;
        try testing.expectEqual(f.return_type.?, result.scalarType());
    }
    for ([_]amd64.Options{ .{}, .{ .reuse_stack_homes = true }, .{ .callee_saved_homes = true } }) |options| {
        const assembly = try amd64.emitWithOptions(allocator, &module, options);
        defer allocator.free(assembly);
        try testing.expect(std.mem.indexOf(u8, assembly, "cvtsi2ss") != null);
        try testing.expect(std.mem.indexOf(u8, assembly, "cvttsd2si") != null);
    }
}
test "signed conversion parse analysis evaluation and emission free every allocation failure" {
    try @import("test_support.zig").checkAllocationFailures(exercise);
}

test "signed numeric conversions run through loop phis with and without integer folding" {
    var module = try parse(testing.allocator, @embedFile("fixtures/signed-conversion-loop.ssa"));
    defer module.deinit();
    const f = module.functions.items[0];
    for ([_]bool{ false, true }) |fold| {
        if (fold) _ = try @import("optimize.zig").foldIntegerConstants(testing.allocator, f);
        for ([_]u32{ 0, 1, 2, 10, 100 }) |n| {
            const expected = if (n == 0) 0 else n * (n - 1) / 2;
            try testing.expectEqual(expected, (try interpreter.evaluate(testing.allocator, f, &.{.{ .word = n }}, .{})).?.word);
        }
    }
}
