const std = @import("std");
const ir = @import("ir.zig");
const ssa = @import("ssa.zig");

pub const Options = struct { max_steps: usize = 100_000 };
pub const Error = ssa.Error || error{ ArgumentCountMismatch, ArgumentTypeMismatch, StepLimitExceeded, UninitializedValue };

/// Bounded reference evaluator for the current scalar subset, not target code
/// generation. Each instruction and terminator consumes one step. Validates SSA
/// on every call; execution storage is owned by this invocation, not the IR.
pub fn evaluate(allocator: std.mem.Allocator, function: *const ir.Function, arguments: []const ir.Constant, options: Options) Error!?ir.Constant {
    var issue: ?ssa.Issue = null;
    try ssa.validate(allocator, function, &issue);
    if (arguments.len != function.parameters.items.len) return error.ArgumentCountMismatch;
    for (function.parameters.items, arguments) |parameter, argument| {
        if (function.values.items[@backingInt(parameter)].scalar_type != argument.scalarType()) return error.ArgumentTypeMismatch;
    }
    const values = try allocator.alloc(?ir.Constant, function.values.items.len);
    defer allocator.free(values);
    @memset(values, null);
    for (function.parameters.items, arguments) |parameter, argument| values[@backingInt(parameter)] = argument;
    var remaining = options.max_steps;
    var current: ir.BlockId = @fromBackingInt(@as(u32, 0));
    while (true) {
        const block = &function.blocks.items[@backingInt(current)];
        for (block.instructions.items) |instruction| {
            try step(&remaining);
            const result = switch (instruction) {
                .copy => |copy| try resolve(values, copy.operand),
                .binary => |binary| binaryValue(binary.op, try resolve(values, binary.lhs), try resolve(values, binary.rhs)),
            };
            values[@backingInt(instruction.result())] = result;
        }
        try step(&remaining);
        switch (block.terminator.?) {
            .jump => |target| current = target,
            .branch => |branch| {
                const condition = try resolve(values, branch.condition);
                current = if (try condition.branchTaken()) branch.taken else branch.not_taken;
            },
            .return_value => |operand| return if (operand) |value| try resolve(values, value) else null,
        }
    }
}

fn step(remaining: *usize) error{StepLimitExceeded}!void {
    if (remaining.* == 0) return error.StepLimitExceeded;
    remaining.* -= 1;
}

fn resolve(values: []const ?ir.Constant, operand: ir.Operand) error{UninitializedValue}!ir.Constant {
    return switch (operand) {
        .constant => |constant| constant,
        .value => |value| values[@backingInt(value)] orelse error.UninitializedValue,
    };
}

fn binaryValue(op: ir.BinaryOp, lhs: ir.Constant, rhs: ir.Constant) ir.Constant {
    // Structural/SSA validation and argument checks establish matching tags.
    return switch (lhs) {
        .word => |a| .{ .word = integerValue(u32, op, a, rhs.word) },
        .long => |a| .{ .long = integerValue(u64, op, a, rhs.long) },
        .single_bits => |a| .{ .single_bits = @bitCast(floatValue(f32, op, @bitCast(a), @bitCast(rhs.single_bits))) },
        .double_bits => |a| .{ .double_bits = @bitCast(floatValue(f64, op, @bitCast(a), @bitCast(rhs.double_bits))) },
    };
}

fn integerValue(comptime T: type, op: ir.BinaryOp, lhs: T, rhs: T) T {
    return switch (op) {
        .add => lhs +% rhs,
        .sub => lhs -% rhs,
        .mul => lhs *% rhs,
        .bit_and => lhs & rhs,
        .bit_or => lhs | rhs,
        .bit_xor => lhs ^ rhs,
    };
}

fn floatValue(comptime F: type, op: ir.BinaryOp, lhs: F, rhs: F) F {
    @setFloatMode(.strict);
    return switch (op) {
        .add => lhs + rhs,
        .sub => lhs - rhs,
        .mul => lhs * rhs,
        .bit_and, .bit_or, .bit_xor => unreachable, // Rejected by validation.
    };
}

const testing = std.testing;
const frontend = @import("frontend.zig");
const source = @import("source.zig");

fn parse(text: []const u8) !@import("module.zig").Module {
    var diagnostic: ?source.Diagnostic = null;
    return frontend.parse(testing.allocator, .{ .name = "interpreter-test", .text = text }, &diagnostic);
}

test "constant-jump regression evaluates all four functions with low-word semantics" {
    var module = try parse(@embedFile("fixtures/constant-jump.ssa"));
    defer module.deinit();
    for (module.functions.items, [_]u32{ 0, 0, 0, 1 }) |function, expected| {
        const result = try evaluate(testing.allocator, function, &.{}, .{});
        try testing.expectEqual(expected, result.?.word);
    }
}

test "integer operations wrap at their declared width" {
    const cases = .{
        .{ "w", "add 4294967295, 1", @as(u64, 0) },
        .{ "w", "sub 0, 1", @as(u64, 0xffffffff) },
        .{ "w", "mul 65536, 65536", @as(u64, 0) },
        .{ "l", "add 18446744073709551615, 1", @as(u64, 0) },
        .{ "l", "sub 0, 1", @as(u64, 0xffffffffffffffff) },
        .{ "l", "mul 1099511627776, 1099511627776", @as(u64, 0) },
        .{ "w", "and 4042322160, 252645135", @as(u64, 0) },
        .{ "w", "or 4042322160, 252645135", @as(u64, 0xffffffff) },
        .{ "l", "xor 12297829382473034410, 6148914691236517205", @as(u64, 0xffffffffffffffff) },
    };
    inline for (cases) |case| {
        var module = try parse("function " ++ case[0] ++ " $f() {\n@b\n%x =" ++ case[0] ++ " " ++ case[1] ++ "\nret %x\n}");
        defer module.deinit();
        const result = (try evaluate(testing.allocator, module.functions.items[0], &.{}, .{})).?;
        const bits: u64 = if (comptime std.mem.eql(u8, case[0], "w")) result.word else result.long;
        try testing.expectEqual(case[2], bits);
    }
}

test "long parameter branches use the low word and invocation state is isolated" {
    var module = try parse("function w $f(l %condition) {\n@entry\njnz %condition, @yes, @no\n@yes\nret 1\n@no\nret 0\n}");
    defer module.deinit();
    const f = module.functions.items[0];
    for ([_]u64{ 1 << 40, (1 << 40) | 1, 0xffffffff00000000, 0x80000000 }, [_]u32{ 0, 1, 0, 1 }) |bits, expected| {
        const result = try evaluate(testing.allocator, f, &.{.{ .long = bits }}, .{});
        try testing.expectEqual(expected, result.?.word);
    }
    try testing.expectError(error.ArgumentCountMismatch, evaluate(testing.allocator, f, &.{}, .{}));
    try testing.expectError(error.ArgumentTypeMismatch, evaluate(testing.allocator, f, &.{.{ .word = 1 }}, .{}));
}

test "floating arithmetic has explicit width and copy retains signed zero" {
    var module = try parse("function d $f(d %a) {\n@entry\n%x =d mul %a, d_2\n%y =d sub %x, d_1\n%z =d add %y, d_0.5\nret %z\n}\nfunction s $zero() {\n@entry\n%x =s copy s_-0\nret %x\n}");
    defer module.deinit();
    const result = try evaluate(testing.allocator, module.functions.items[0], &.{.{ .double_bits = @bitCast(@as(f64, 1.25)) }}, .{});
    try testing.expectEqual(@as(u64, @bitCast(@as(f64, 2))), result.?.double_bits);
    const zero = try evaluate(testing.allocator, module.functions.items[1], &.{}, .{});
    try testing.expectEqual(@as(u32, 0x80000000), zero.?.single_bits);
}

test "exact instruction budgets bound both finite and infinite execution" {
    var module = try parse("function w $finite() {\n@b\n%x =w copy 1\nret %x\n}\nfunction $loop() {\n@b\njmp @b\n}\nfunction $void() {\n@b\nret\n}");
    defer module.deinit();
    try testing.expectError(error.StepLimitExceeded, evaluate(testing.allocator, module.functions.items[0], &.{}, .{ .max_steps = 0 }));
    try testing.expectError(error.StepLimitExceeded, evaluate(testing.allocator, module.functions.items[0], &.{}, .{ .max_steps = 1 }));
    try testing.expectEqual(@as(u32, 1), (try evaluate(testing.allocator, module.functions.items[0], &.{}, .{ .max_steps = 2 })).?.word);
    try testing.expectError(error.StepLimitExceeded, evaluate(testing.allocator, module.functions.items[1], &.{}, .{ .max_steps = 17 }));
    try testing.expect((try evaluate(testing.allocator, module.functions.items[2], &.{}, .{ .max_steps = 1 })) == null);
}

test "execution rejects non-dominating uses before interpreting them" {
    var module = try parse("function w $f() {\n@entry\njnz 0, @left, @join\n@left\n%x =w copy 1\njmp @join\n@join\nret %x\n}");
    defer module.deinit();
    try testing.expectError(error.InvalidSSA, evaluate(testing.allocator, module.functions.items[0], &.{}, .{}));
}

test "copying a manually built NaN preserves payload bits" {
    var f = ir.Function.init(testing.allocator, @fromBackingInt(@as(u32, 0)), .double);
    defer f.deinit();
    const block = try f.addBlock(null);
    const value = try f.appendCopy(block, .double, .{ .constant = .{ .double_bits = 0xfff8000000001234 } });
    try f.terminate(block, .{ .return_value = .{ .value = value } });
    const result = try evaluate(testing.allocator, &f, &.{}, .{});
    try testing.expectEqual(@as(u64, 0xfff8000000001234), result.?.double_bits);
}

fn exercise(allocator: std.mem.Allocator) !void {
    var diagnostic: ?source.Diagnostic = null;
    var module = try frontend.parse(allocator, .{ .name = "fixture", .text = @embedFile("fixtures/constant-jump.ssa") }, &diagnostic);
    defer module.deinit();
    for (module.functions.items, [_]u32{ 0, 0, 0, 1 }) |f, expected| {
        const result = try evaluate(allocator, f, &.{}, .{});
        try testing.expectEqual(expected, result.?.word);
    }
}

test "every evaluator allocation failure frees analysis and execution frames" {
    try @import("test_support.zig").checkAllocationFailures(exercise);
}

test "384 Python arbitrary-precision oracle cases agree through parser and evaluator" {
    var lines = std.mem.tokenizeScalar(u8, @embedFile("fixtures/integer-oracle.tsv"), '\n');
    var case_count: usize = 0;
    while (lines.next()) |line| {
        if (line[0] == '#') continue;
        var fields = std.mem.tokenizeAny(u8, line, " \t");
        const ty = fields.next() orelse return error.MalformedOracle;
        const op = std.meta.stringToEnum(ir.BinaryOp, fields.next() orelse return error.MalformedOracle) orelse return error.MalformedOracle;
        const lhs = try std.fmt.parseInt(u64, fields.next() orelse return error.MalformedOracle, 10);
        const rhs = try std.fmt.parseInt(u64, fields.next() orelse return error.MalformedOracle, 10);
        const expected = try std.fmt.parseInt(u64, fields.next() orelse return error.MalformedOracle, 10);
        try testing.expect(fields.next() == null);
        const mnemonic = switch (op) {
            .bit_and => "and",
            .bit_or => "or",
            .bit_xor => "xor",
            else => @tagName(op),
        };
        const text = try std.fmt.allocPrint(testing.allocator, "function {s} $f() {{\n@entry\n%x ={s} {s} {d}, {d}\nret %x\n}}", .{ ty, ty, mnemonic, lhs, rhs });
        defer testing.allocator.free(text);
        var module = try parse(text);
        defer module.deinit();
        const result = (try evaluate(testing.allocator, module.functions.items[0], &.{}, .{ .max_steps = 2 })).?;
        const actual: u64 = if (std.mem.eql(u8, ty, "w")) result.word else result.long;
        try testing.expectEqual(expected, actual);
        case_count += 1;
    }
    try testing.expectEqual(@as(usize, 384), case_count);
}
