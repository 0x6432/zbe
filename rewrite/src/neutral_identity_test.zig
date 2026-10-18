const std = @import("std");
const testing = std.testing;
const ir = @import("ir.zig");
const interpreter = @import("interpreter.zig");
const optimize = @import("optimize.zig");
const frontend = @import("frontend.zig");
fn parse(allocator: std.mem.Allocator, text: []const u8) !@import("module.zig").Module {
    var diagnostic: ?@import("source.zig").Diagnostic = null;
    return frontend.parse(allocator, .{ .name = "neutral-identity", .text = text }, &diagnostic);
}

fn resultBits(c: ir.Constant) u64 {
    return switch (c) {
        .word => |v| v,
        .long => |v| v,
        else => unreachable,
    };
}

test "neutral identities and near misses match independent width-masked oracle with exact steps and backlinks" {
    var lines = std.mem.tokenizeScalar(u8, @embedFile("fixtures/neutral_identity_oracle.tsv"), '\n');
    var count: usize = 0;
    while (lines.next()) |line| {
        if (line[0] == '#') continue;
        var fields = std.mem.tokenizeAny(u8, line, "\t");
        const ty = fields.next().?;
        const op = fields.next().?;
        const side = fields.next().?;
        const n = fields.next().?;
        const input = try std.fmt.parseInt(u64, fields.next().?, 10);
        const expected = try std.fmt.parseInt(u64, fields.next().?, 10);
        const changed = try std.fmt.parseInt(usize, fields.next().?, 10);
        const lhs = if (std.mem.eql(u8, side, "1")) n else "%x";
        const rhs = if (std.mem.eql(u8, side, "1")) "%x" else n;
        const text = try std.fmt.allocPrint(testing.allocator, "function {s} $f({s} %x) {{\n@b\n%r ={s} {s} {s}, {s}\nret %r\n}}", .{ ty, ty, ty, op, lhs, rhs });
        defer testing.allocator.free(text);
        var module = try parse(testing.allocator, text);
        defer module.deinit();
        const f = module.functions.items[0];
        const instruction = f.blocks.items[0].instructions.items[0];
        const result = instruction.result().?;
        const value = f.values.items[@backingInt(result)];
        const args = [_]ir.Constant{if (ty[0] == 'w') .{ .word = @intCast(input) } else .{ .long = input }};
        try testing.expectEqual(expected, resultBits((try interpreter.evaluate(testing.allocator, f, &args, .{ .max_steps = 2 })).?));
        try testing.expectError(error.StepLimitExceeded, interpreter.evaluate(testing.allocator, f, &args, .{ .max_steps = 1 }));
        try testing.expectEqual(changed, try optimize.foldIntegerConstants(testing.allocator, f));
        try testing.expectEqualDeep(value, f.values.items[@backingInt(result)]);
        try testing.expectEqual(result, f.blocks.items[0].instructions.items[0].result().?);
        try testing.expectEqual(@as(usize, 1), f.blocks.items.len);
        try testing.expectEqual(@as(usize, 1), f.blocks.items[0].instructions.items.len);
        if (changed != 0) try testing.expect(f.blocks.items[0].instructions.items[0] == .copy);
        try f.validateStructure();
        try testing.expectEqual(expected, resultBits((try interpreter.evaluate(testing.allocator, f, &args, .{ .max_steps = 2 })).?));
        try testing.expectError(error.StepLimitExceeded, interpreter.evaluate(testing.allocator, f, &args, .{ .max_steps = 1 }));
        try testing.expectEqual(@as(usize, 0), try optimize.foldIntegerConstants(testing.allocator, f));
        count += 1;
    }
    try testing.expectEqual(@as(usize, 476), count);
}

test "known neutral facts and projected counts preserve exact original low word operand" {
    for ([_][]const u8{ "4294967328", "4294967360" }) |count| {
        const text = try std.fmt.allocPrint(testing.allocator, "function w $f(l %x) {{\n@b\n%n =l copy {s}\n%r =w shr %x, %n\nret %r\n}}", .{count});
        defer testing.allocator.free(text);
        var module = try parse(testing.allocator, text);
        defer module.deinit();
        const f = module.functions.items[0];
        const original = f.blocks.items[0].instructions.items[1].shift.value;
        try testing.expect(original == .low_word);
        try testing.expectEqual(@as(usize, 1), try optimize.foldIntegerConstants(testing.allocator, f));
        try testing.expectEqualDeep(original, f.blocks.items[0].instructions.items[1].copy.operand);
        try testing.expectEqual(@as(u32, 0x80000001), (try interpreter.evaluate(testing.allocator, f, &.{.{ .long = 0xdeadbeef80000001 }}, .{})).?.word);
    }
    var module = try parse(testing.allocator, "function l $f(l %x) {\n@b\n%n =w add 63, 1\n%r =l shl %x, %n\nret %r\n}");
    defer module.deinit();
    try testing.expectEqual(@as(usize, 2), try optimize.foldIntegerConstants(testing.allocator, module.functions.items[0]));
}

test "symbol payloads refusals step precedence and prior Image writes survive legitimate identities" {
    for ([_][]const u8{ "$missing", "$missing+7", "$missing+-2147483648" }) |symbol| {
        const text = try std.fmt.allocPrint(testing.allocator, "function l $f() {{\n@b\nstorel 99, 65536\n%r =l add {s}, 0\nret %r\n}}", .{symbol});
        defer testing.allocator.free(text);
        var module = try parse(testing.allocator, text);
        defer module.deinit();
        const f = module.functions.items[0];
        const operand = f.blocks.items[0].instructions.items[1].binary.lhs;
        var image = try @import("memory.zig").Image.init(testing.allocator, 8, .{});
        defer image.deinit();
        for ([_]bool{ false, true }) |fold| {
            if (fold) {
                try testing.expectEqual(@as(usize, 1), try optimize.foldIntegerConstants(testing.allocator, f));
                try testing.expectEqualDeep(operand, f.blocks.items[0].instructions.items[1].copy.operand);
            }
            try image.write(.long, .{ .long = 0 }, 65536);
            try testing.expectError(error.StepLimitExceeded, interpreter.evaluate(testing.allocator, f, &.{}, .{ .memory_image = &image, .max_steps = 1 }));
            try testing.expectEqual(@as(u64, 99), (try image.read(.long, .long, 65536)).long);
            try testing.expectError(error.UnsupportedSymbolAddress, interpreter.evaluate(testing.allocator, f, &.{}, .{ .memory_image = &image, .max_steps = 2 }));
            try testing.expectEqual(@as(u64, 99), (try image.read(.long, .long, 65536)).long);
        }
    }
}

test "operand dropping identities float and divide faults remain executable" {
    for ([_][]const u8{ "mul $missing, 0", "and $missing, 0", "sub $missing, $missing", "xor $missing, $missing", "div $missing, 1", "urem $missing, 1" }) |operation| {
        const text = try std.fmt.allocPrint(testing.allocator, "function l $f() {{\n@b\n%r =l {s}\nret %r\n}}", .{operation});
        defer testing.allocator.free(text);
        var module = try parse(testing.allocator, text);
        defer module.deinit();
        const f = module.functions.items[0];
        try testing.expectEqual(@as(usize, 0), try optimize.foldIntegerConstants(testing.allocator, f));
        try testing.expect(f.blocks.items[0].instructions.items[0] == .binary);
        try testing.expectError(error.UnsupportedSymbolAddress, interpreter.evaluate(testing.allocator, f, &.{}, .{}));
    }
    var module = try parse(testing.allocator, "function d $f(d %x) {\n@b\n%r =d add %x, d_0\nret %r\n}\nfunction l $g(l %x) {\n@b\n%r =l div %x, 0\nret %r\n}");
    defer module.deinit();
    for (module.functions.items) |f| try testing.expectEqual(@as(usize, 0), try optimize.foldIntegerConstants(testing.allocator, f));
    try testing.expectError(error.DivisionByZero, interpreter.evaluate(testing.allocator, module.functions.items[1], &.{.{ .long = 42 }}, .{}));
}

const oom_source = "function l $f(l %x) {\n@e\n%n =l add 0, 0\n%a =l mul %x, 1\n%b =l and %a, -1\n%r =l add %b, %n\nret %r\n}";
fn exercise(allocator: std.mem.Allocator) !void {
    var module = try parse(allocator, oom_source);
    defer module.deinit();
    _ = try optimize.foldIntegerConstants(allocator, module.functions.items[0]);
}
test "every optimizer allocation failure is atomic and permits same-function retry" {
    try @import("test_support.zig").checkAllocationFailures(exercise);
    var counter_module = try parse(testing.allocator, oom_source);
    defer counter_module.deinit();
    var count = testing.FailingAllocator.init(testing.allocator, .{ .resize_fail_index = 0 });
    try testing.expectEqual(@as(usize, 4), try optimize.foldIntegerConstants(count.allocator(), counter_module.functions.items[0]));
    try testing.expectEqual(count.allocated_bytes, count.freed_bytes);
    for (0..count.alloc_index) |fail_at| {
        var module = try parse(testing.allocator, oom_source);
        defer module.deinit();
        const f = module.functions.items[0];
        const before = try testing.allocator.dupe(ir.Instruction, f.blocks.items[0].instructions.items);
        defer testing.allocator.free(before);
        var failing = testing.FailingAllocator.init(testing.allocator, .{ .fail_index = fail_at, .resize_fail_index = 0 });
        try testing.expectError(error.OutOfMemory, optimize.foldIntegerConstants(failing.allocator(), f));
        try testing.expectEqualDeep(before, f.blocks.items[0].instructions.items);
        try testing.expectEqual(failing.allocated_bytes, failing.freed_bytes);
        failing.fail_index = std.math.maxInt(usize);
        try testing.expectEqual(@as(usize, 4), try optimize.foldIntegerConstants(failing.allocator(), f));
        try testing.expectEqual(failing.allocated_bytes, failing.freed_bytes);
        try testing.expectEqual(@as(u64, 0xabcdef00deadbeef), (try interpreter.evaluate(testing.allocator, f, &.{.{ .long = 0xabcdef00deadbeef }}, .{})).?.long);
    }
}

test "source-order neutral facts retain projected operands and ordered effects unchanged" {
    for ([_][]const u8{ "add %x, %n", "add %n, %x", "sub %x, %n", "or %x, %n", "xor %n, %x" }) |operation| {
        const text = try std.fmt.allocPrint(testing.allocator, "function w $f(l %x) {{\n@e\n%n =w sub 77, 77\n%r =w {s}\nret %r\n}}", .{operation});
        defer testing.allocator.free(text);
        var module = try parse(testing.allocator, text);
        defer module.deinit();
        const f = module.functions.items[0];
        const original = f.blocks.items[0].instructions.items[1].binary;
        const projected = if (original.lhs == .low_word) original.lhs else original.rhs;
        try testing.expectEqual(@as(usize, 2), try optimize.foldIntegerConstants(testing.allocator, f));
        try testing.expectEqualDeep(projected, f.blocks.items[0].instructions.items[1].copy.operand);
    }
    var module = try parse(testing.allocator, "function l $f(l %x, ...) {\n@e\n%p =l alloc8 24\nstorel %x, %p\n%v =l loadl %p\n%a =l add %v, 0\nvastart %p\n%unused =l vaarg %p\ncall $effect(l %a)\nret %a\n}");
    defer module.deinit();
    const f = module.functions.items[0];
    const before = try testing.allocator.dupe(ir.Instruction, f.blocks.items[0].instructions.items);
    defer testing.allocator.free(before);
    try testing.expectEqual(@as(usize, 1), try optimize.foldIntegerConstants(testing.allocator, f));
    for (before, f.blocks.items[0].instructions.items, 0..) |old, new, index| {
        if (index == 3) continue;
        try testing.expectEqualDeep(old, new);
    }
}

test "checked symbol addend overflow stays observable after identity rewrite" {
    var module = try parse(testing.allocator, "data $g = {}\nfunction l $f() {\n@e\n%r =l add $g+-2147483648, 0\nret %r\n}");
    defer module.deinit();
    const f = module.functions.items[0];
    const options: interpreter.Options = .{ .global_memory = .{ .base = 64 } };
    const id: @import("module.zig").FunctionId = @fromBackingInt(@as(u32, 0));
    try testing.expectError(error.GlobalAddressOverflow, interpreter.evaluateModule(testing.allocator, &module, id, &.{}, options));
    try testing.expectEqual(@as(usize, 1), try optimize.foldIntegerConstants(testing.allocator, f));
    try testing.expectError(error.GlobalAddressOverflow, interpreter.evaluateModule(testing.allocator, &module, id, &.{}, options));
}
