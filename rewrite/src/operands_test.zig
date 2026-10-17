const std = @import("std");
const testing = std.testing;
const ir = @import("ir.zig");
const a: ir.Operand = .{ .value = @fromBackingInt(@as(u32, 1)) };
const b: ir.Operand = .{ .constant = .{ .long = 0xfedcba9876543210 } };
const result: ir.ValueId = @fromBackingInt(@as(u32, 99));

fn check(instruction: ir.Instruction, expected: []const ir.Operand) !void {
    var iterator = instruction.operands();
    for (expected) |operand| try testing.expectEqualDeep(operand, iterator.next().?);
    for (0..4) |_| try testing.expectEqual(@as(?ir.Operand, null), iterator.next());
}

test "instruction use iterator covers each fixed variant in source order without definitions" {
    const cases = [_]struct { instruction: ir.Instruction, expected: []const ir.Operand }{
        .{ .instruction = .{ .copy = .{ .result = result, .operand = a } }, .expected = &.{a} },
        .{ .instruction = .{ .convert = .{ .result = result, .op = .signed_word_to_float, .operand = a } }, .expected = &.{a} },
        .{ .instruction = .{ .unary = .{ .result = result, .op = .negate, .operand = a } }, .expected = &.{a} },
        .{ .instruction = .{ .binary = .{ .result = result, .op = .add, .lhs = a, .rhs = b } }, .expected = &.{ a, b } },
        .{ .instruction = .{ .shift = .{ .result = result, .op = .left, .value = a, .amount = b } }, .expected = &.{ a, b } },
        .{ .instruction = .{ .compare_float = .{ .result = result, .predicate = .unordered, .operand_type = .double, .lhs = a, .rhs = b } }, .expected = &.{ a, b } },
        .{ .instruction = .{ .compare_integer = .{ .result = result, .predicate = .signed_less, .operand_type = .long, .lhs = a, .rhs = b } }, .expected = &.{ a, b } },
        .{ .instruction = .{ .va_start = .{ .list = b } }, .expected = &.{b} },
        .{ .instruction = .{ .va_argument = .{ .result = result, .list = b } }, .expected = &.{b} },
        .{ .instruction = .{ .allocate = .{ .result = result, .size = b, .alignment = .sixteen } }, .expected = &.{b} },
        .{ .instruction = .{ .load = .{ .result = result, .kind = .long, .address = b } }, .expected = &.{b} },
        .{ .instruction = .{ .store = .{ .kind = .long, .value = a, .address = b } }, .expected = &.{ a, b } },
        .{ .instruction = .{ .blit = .{ .source = a, .destination = b, .byte_count = 0 } }, .expected = &.{ a, b } },
    };
    for (cases) |case| try check(case.instruction, case.expected);
    // Accessor exhaustiveness is enforced by the tagged-union switch. This
    // explicit coverage assertion also requires a test case for any new tag.
    try testing.expectEqual(std.meta.fieldNames(ir.Instruction).len - 1, cases.len);
}

test "call use iterator handles direct indirect target-only scalar void and all argument classes" {
    const arguments = [_]ir.CallArgument{
        .{ .scalar_type = .word, .operand = .{ .constant = .{ .word = 42 } } },
        .{ .scalar_type = .long, .operand = b },
        .{ .scalar_type = .single, .operand = .{ .constant = .{ .single_bits = 0x7fc12345 } } },
        .{ .scalar_type = .double, .operand = .{ .constant = .{ .double_bits = 0x8000000000000000 } } },
    };
    for ([_]?ir.ValueId{ null, result }) |destination| for ([_]ir.CallTarget{ .{ .symbol = @fromBackingInt(@as(u32, 0)) }, .{ .address = a } }) |target| for (0..arguments.len + 1) |count| {
        const instruction: ir.Instruction = .{ .call = .{ .result = destination, .callee = target, .arguments = arguments[0..count] } };
        var expected: [arguments.len + 1]ir.Operand = undefined;
        var len: usize = 0;
        if (target == .address) {
            expected[0] = a;
            len = 1;
        }
        for (arguments[0..count]) |argument| {
            expected[len] = argument.operand;
            len += 1;
        }
        try check(instruction, expected[0..len]);
    };
}

test "fixed use iterators own operand copies and can outlive a temporary instruction value" {
    var instruction: ir.Instruction = .{ .copy = .{ .result = result, .operand = a } };
    var iterator = instruction.operands();
    instruction.copy.operand = b;
    try testing.expectEqualDeep(a, iterator.next().?);
    try testing.expectEqual(@as(?ir.Operand, null), iterator.next());
    var temporary = (ir.Instruction{ .binary = .{ .result = result, .op = .add, .lhs = a, .rhs = b } }).operands();
    try testing.expectEqualDeep(a, temporary.next().?);
    try testing.expectEqualDeep(b, temporary.next().?);
    try testing.expectEqual(@as(?ir.Operand, null), temporary.next());
}

test "projected use iterators copy the projection and retain its source identity" {
    const projected: ir.Operand = .{ .low_word = @fromBackingInt(@as(u32, 17)) };
    var instruction: ir.Instruction = .{ .copy = .{ .result = result, .operand = projected } };
    var iterator = instruction.operands();
    instruction.copy.operand = b;
    const operand = iterator.next().?;
    try testing.expectEqualDeep(projected, operand);
    try testing.expectEqual(projected.low_word, operand.referencedValue().?);
    try testing.expectEqual(@as(?ir.Operand, null), iterator.next());
    try check(.{ .binary = .{ .result = result, .op = .add, .lhs = projected, .rhs = a } }, &.{ projected, a });
}
