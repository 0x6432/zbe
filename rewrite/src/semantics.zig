//! Pure scalar bit-pattern operations shared by evaluation and integer folding.
//! Callers must establish the IR operation's type contract before invoking them.
const std = @import("std");
const ir = @import("ir.zig");
pub const ArithmeticError = error{ DivisionByZero, IntegerOverflow };

pub fn unaryValue(op: ir.UnaryOp, operand: ir.Constant, result_type: ir.ScalarType) ir.Constant {
    if (op == .negate) return switch (operand) {
        .word => |bits| .{ .word = 0 -% bits },
        .long => |bits| .{ .long = 0 -% bits },
        .single_bits => |bits| .{ .single_bits = bits ^ 0x80000000 },
        .double_bits => |bits| .{ .double_bits = bits ^ 0x8000000000000000 },
    };
    if (op == .bitcast) return switch (result_type) {
        .word => .{ .word = operand.single_bits },
        .long => .{ .long = operand.double_bits },
        .single => .{ .single_bits = operand.word },
        .double => .{ .double_bits = operand.long },
    };
    if (op == .widen_float) {
        @setFloatMode(.strict);
        const value: f32 = @bitCast(operand.single_bits);
        return .{ .double_bits = @bitCast(@as(f64, value)) };
    }
    const bits = operand.word;
    const extended: u64 = switch (op) {
        .negate, .bitcast, .widen_float => unreachable,
        .sign_extend_byte => signedExtension(u8, i8, bits),
        .zero_extend_byte => bits & 0xff,
        .sign_extend_half => signedExtension(u16, i16, bits),
        .zero_extend_half => bits & 0xffff,
        .sign_extend_word => signedExtension(u32, i32, bits),
        .zero_extend_word => bits,
    };
    return if (result_type == .word) .{ .word = @truncate(extended) } else .{ .long = extended };
}
fn signedExtension(comptime U: type, comptime S: type, bits: u32) u64 {
    const narrow: U = @truncate(bits);
    const signed: S = @bitCast(narrow);
    return @bitCast(@as(i64, signed));
}

pub fn shiftedValue(op: ir.ShiftOp, value: ir.Constant, amount: u32) ir.Constant {
    return switch (value) {
        .word => |bits| .{ .word = shifted(u32, i32, u5, op, bits, amount) },
        .long => |bits| .{ .long = shifted(u64, i64, u6, op, bits, amount) },
        else => unreachable,
    };
}
fn shifted(comptime U: type, comptime S: type, comptime Count: type, op: ir.ShiftOp, value: U, amount: u32) U {
    const count: Count = @truncate(amount);
    return switch (op) {
        .left => value << count,
        .logical_right => value >> count,
        .arithmetic_right => @bitCast(@as(S, @bitCast(value)) >> count),
    };
}
pub fn floatComparisonValue(predicate: ir.FloatPredicate, lhs: ir.Constant, rhs: ir.Constant, result_type: ir.ScalarType) ir.Constant {
    const result = switch (lhs) {
        .single_bits => |a| compareFloat(f32, predicate, @bitCast(a), @bitCast(rhs.single_bits)),
        .double_bits => |a| compareFloat(f64, predicate, @bitCast(a), @bitCast(rhs.double_bits)),
        else => unreachable,
    };
    return if (result_type == .word) .{ .word = @intFromBool(result) } else .{ .long = @intFromBool(result) };
}
fn compareFloat(comptime F: type, predicate: ir.FloatPredicate, lhs: F, rhs: F) bool {
    @setFloatMode(.strict);
    const unordered = std.math.isNan(lhs) or std.math.isNan(rhs);
    return switch (predicate) {
        .equal => lhs == rhs,
        .not_equal => lhs != rhs,
        .less => lhs < rhs,
        .less_equal => lhs <= rhs,
        .greater => lhs > rhs,
        .greater_equal => lhs >= rhs,
        .ordered => !unordered,
        .unordered => unordered,
    };
}

pub fn comparisonValue(predicate: ir.IntegerPredicate, lhs: ir.Constant, rhs: ir.Constant, result_type: ir.ScalarType) ir.Constant {
    const result = switch (lhs) {
        .word => |a| compare(u32, i32, predicate, a, rhs.word),
        .long => |a| compare(u64, i64, predicate, a, rhs.long),
        else => unreachable,
    };
    return if (result_type == .word) .{ .word = @intFromBool(result) } else .{ .long = @intFromBool(result) };
}
fn compare(comptime U: type, comptime S: type, predicate: ir.IntegerPredicate, lhs: U, rhs: U) bool {
    const a: S = @bitCast(lhs);
    const b: S = @bitCast(rhs);
    return switch (predicate) {
        .equal => lhs == rhs,
        .not_equal => lhs != rhs,
        .signed_less => a < b,
        .signed_less_equal => a <= b,
        .signed_greater => a > b,
        .signed_greater_equal => a >= b,
        .unsigned_less => lhs < rhs,
        .unsigned_less_equal => lhs <= rhs,
        .unsigned_greater => lhs > rhs,
        .unsigned_greater_equal => lhs >= rhs,
    };
}

pub fn binaryValue(op: ir.BinaryOp, lhs: ir.Constant, rhs: ir.Constant) ArithmeticError!ir.Constant {
    // Structural/SSA validation and argument checks establish matching tags.
    return switch (lhs) {
        .word => |a| .{ .word = try integerValue(u32, op, a, rhs.word) },
        .long => |a| .{ .long = try integerValue(u64, op, a, rhs.long) },
        .single_bits => |a| .{ .single_bits = @bitCast(floatValue(f32, op, @bitCast(a), @bitCast(rhs.single_bits))) },
        .double_bits => |a| .{ .double_bits = @bitCast(floatValue(f64, op, @bitCast(a), @bitCast(rhs.double_bits))) },
    };
}

fn integerValue(comptime T: type, op: ir.BinaryOp, lhs: T, rhs: T) ArithmeticError!T {
    switch (op) {
        .signed_divide, .unsigned_divide, .signed_remainder, .unsigned_remainder => {
            if (rhs == 0) return error.DivisionByZero;
            if (op == .signed_divide or op == .signed_remainder) {
                const S = @Int(.signed, @bitSizeOf(T));
                const a: S = @bitCast(lhs);
                const b: S = @bitCast(rhs);
                // AMD64 idiv traps on this pair for quotient and remainder alike.
                if (a == std.math.minInt(S) and b == -1) return error.IntegerOverflow;
                return @bitCast(if (op == .signed_divide) @divTrunc(a, b) else @rem(a, b));
            }
            return if (op == .unsigned_divide) lhs / rhs else lhs % rhs;
        },
        else => {},
    }
    return switch (op) {
        .add => lhs +% rhs,
        .sub => lhs -% rhs,
        .mul => lhs *% rhs,
        .bit_and => lhs & rhs,
        .bit_or => lhs | rhs,
        .bit_xor => lhs ^ rhs,
        .signed_divide, .unsigned_divide, .signed_remainder, .unsigned_remainder => unreachable,
    };
}

fn floatValue(comptime F: type, op: ir.BinaryOp, lhs: F, rhs: F) F {
    @setFloatMode(.strict);
    return switch (op) {
        .add => lhs + rhs,
        .sub => lhs - rhs,
        .mul => lhs * rhs,
        .signed_divide => lhs / rhs,
        .bit_and, .bit_or, .bit_xor, .unsigned_divide, .signed_remainder, .unsigned_remainder => unreachable, // Rejected by validation.
    };
}

/// Out-of-domain numeric conversion is an evaluator error, not a portable QBE
/// value or a promise to match native masked/unmasked floating exceptions.
pub const ConversionError = error{ConversionOutOfRange};
pub fn convertedValue(op: ir.ConvertOp, operand: ir.Constant, result_type: ir.ScalarType) ConversionError!ir.Constant {
    @setFloatMode(.strict);
    return switch (op) {
        .signed_word_to_float => integerToFloat(@as(i32, @bitCast(operand.word)), result_type),
        .signed_long_to_float => integerToFloat(@as(i64, @bitCast(operand.long)), result_type),
        .single_to_signed_integer => floatToInteger(@as(f32, @bitCast(operand.single_bits)), result_type),
        .double_to_signed_integer => floatToInteger(@as(f64, @bitCast(operand.double_bits)), result_type),
    };
}
fn integerToFloat(value: anytype, result_type: ir.ScalarType) ir.Constant {
    @setFloatMode(.strict);
    return switch (result_type) {
        .single => .{ .single_bits = @bitCast(@as(f32, @floatFromInt(value))) },
        .double => .{ .double_bits = @bitCast(@as(f64, @floatFromInt(value))) },
        else => unreachable, // Type validation precedes semantic evaluation.
    };
}
fn floatToInteger(value: anytype, result_type: ir.ScalarType) ConversionError!ir.Constant {
    @setFloatMode(.strict);
    const wide: f64 = value; // Widening f32 to f64 preserves finite values exactly.
    if (!std.math.isFinite(wide)) return error.ConversionOutOfRange;
    const truncated = @trunc(wide);
    const limit: f64 = if (result_type == .word) 0x1p31 else 0x1p63;
    // Check the truncated value, allowing e.g. -2147483648.5 -> signed MIN.
    if (truncated < -limit or truncated >= limit) return error.ConversionOutOfRange;
    const signed: i64 = @intFromFloat(truncated);
    return if (result_type == .word)
        .{ .word = @bitCast(@as(i32, @intCast(signed))) }
    else
        .{ .long = @bitCast(signed) };
}
