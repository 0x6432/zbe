//! Conservative source-order constant propagation. No CFG or floating arithmetic
//! rewrites; integer faults remain executable instructions, not fake constants.
const std = @import("std");
const ir = @import("ir.zig");
const ssa = @import("ssa.zig");
const semantics = @import("semantics.zig");

/// Validate first and allocate all scratch before mutation. No fallible work
/// remains after rewriting starts. IDs, definition backlinks and CFG stay fixed.
/// Facts are invocation-owned and conservative: phi/parameter facts are unknown.
pub fn foldIntegerConstants(allocator: std.mem.Allocator, function: *ir.Function) ssa.Error!usize {
    var issue: ?ssa.Issue = null;
    try ssa.validate(allocator, function, &issue);
    const facts = try allocator.alloc(?ir.Constant, function.values.items.len);
    defer allocator.free(facts);
    @memset(facts, null);
    var changes: usize = 0;
    for (function.blocks.items) |*block| {
        for (block.instructions.items) |*instruction| {
            const result = instruction.result() orelse continue;
            const ty = function.values.items[@backingInt(result)].scalar_type;
            if (folded(instruction.*, facts, ty)) |constant| {
                facts[@backingInt(result)] = constant;
                if (instruction.* == .copy and instruction.copy.operand == .constant) continue;
                instruction.* = .{ .copy = .{ .result = result, .operand = .{ .constant = constant } } };
                changes += 1;
            }
        }
    }
    return changes;
}

fn known(facts: []const ?ir.Constant, operand: ir.Operand) ?ir.Constant {
    return switch (operand) {
        .constant => |c| c,
        .symbol => null,
        .value => |v| facts[@backingInt(v)],
        .low_word => |v| if (facts[@backingInt(v)]) |constant| .{ .word = @truncate(constant.long) } else null,
    };
}
fn folded(instruction: ir.Instruction, facts: []const ?ir.Constant, ty: ir.ScalarType) ?ir.Constant {
    return switch (instruction) {
        .copy => |copy| known(facts, copy.operand),
        .unary => |unary| if (unary.op == .widen_float) null else semantics.unaryValue(unary.op, known(facts, unary.operand) orelse return null, ty),
        .binary => |binary| if (!ty.isInteger()) null else semantics.binaryValue(binary.op, known(facts, binary.lhs) orelse return null, known(facts, binary.rhs) orelse return null) catch null,
        .shift => |shift| semantics.shiftedValue(shift.op, known(facts, shift.value) orelse return null, (known(facts, shift.amount) orelse return null).word),
        .compare_integer => |comparison| semantics.comparisonValue(comparison.predicate, known(facts, comparison.lhs) orelse return null, known(facts, comparison.rhs) orelse return null, ty),
        .allocate => null, // Allocation remains a reached stack effect, even unused.
        .load, .store, .blit => null, // Preserve memory reads, faults and ordered effects.
        .call => null, // Calls remain effectful even when their result is unused.
        .convert => null, // Numeric conversions retain rounding/error behavior.
        .compare_float => null, // Preserve floating-environment/NaN flag behavior.
    };
}

const testing = std.testing;
const frontend = @import("frontend.zig");
const source = @import("source.zig");
const interpreter = @import("interpreter.zig");
fn parse(allocator: std.mem.Allocator, text: []const u8) !@import("module.zig").Module {
    var diagnostic: ?source.Diagnostic = null;
    return frontend.parse(allocator, .{ .name = "fold-test", .text = text }, &diagnostic);
}
const chain = "function l $f() {\n@entry\n%a =l add 1048576, 0\n%b =l mul %a, %a\n%s =l sar %b, 64\n%c =w ceql %s, 1099511627776\n%m =w add 4294967295, 2\n%w =l extsw %m\n%r =l add %w, %s\njnz %b, @yes, @no\n@yes\nret 0\n@no\nret %r\n}";

test "folding preserves IDs CFG low-word branches and all SSA backlinks" {
    var module = try parse(testing.allocator, chain);
    defer module.deinit();
    const f = module.functions.items[0];
    const before = (try interpreter.evaluate(testing.allocator, f, &.{}, .{})).?.long;
    const values = f.values.items.len;
    try testing.expectEqual(@as(usize, 7), try foldIntegerConstants(testing.allocator, f));
    try testing.expectEqual(values, f.values.items.len);
    try testing.expectEqual(@as(usize, 3), f.blocks.items.len);
    try testing.expect(f.blocks.items[0].terminator.? == .branch);
    for (f.blocks.items[0].instructions.items) |instruction| try testing.expect(instruction == .copy);
    try f.validateStructure();
    const after = (try interpreter.evaluate(testing.allocator, f, &.{}, .{})).?.long;
    try testing.expectEqual(@as(u64, (1 << 40) + 1), before);
    try testing.expectEqual(before, after);
    try testing.expectEqual(@as(usize, 0), try foldIntegerConstants(testing.allocator, f));
}

test "floating arithmetic widening and comparisons are not folded" {
    var module = try parse(testing.allocator, "function d $f() {\n@b\n%a =d add d_1, d_2\n%b =d neg d_-0\n%s =s copy s_1\n%w =d exts %s\n%c =w ceqd d_nan, d_1\nret %a\n}");
    defer module.deinit();
    const f = module.functions.items[0];
    try testing.expectEqual(@as(usize, 1), try foldIntegerConstants(testing.allocator, f));
    const instructions = f.blocks.items[0].instructions.items;
    try testing.expect(instructions[0] == .binary);
    try testing.expectEqual(@as(u64, 0), instructions[1].copy.operand.constant.double_bits);
    try testing.expect(instructions[3] == .unary);
    try testing.expect(instructions[4] == .compare_float);
}

test "constant arithmetic exceptions remain executable binary instructions" {
    for ([_][]const u8{ "w", "l" }) |ty| {
        for ([_][]const u8{ "div", "udiv", "rem", "urem" }) |opcode| {
            const text = try std.fmt.allocPrint(testing.allocator, "function {s} $f() {{\n@b\n%r ={s} {s} 1, 0\nret %r\n}}", .{ ty, ty, opcode });
            defer testing.allocator.free(text);
            var module = try parse(testing.allocator, text);
            defer module.deinit();
            const f = module.functions.items[0];
            try testing.expectEqual(@as(usize, 0), try foldIntegerConstants(testing.allocator, f));
            try testing.expect(f.blocks.items[0].instructions.items[0] == .binary);
            try testing.expectError(error.DivisionByZero, interpreter.evaluate(testing.allocator, f, &.{}, .{}));
            if (std.mem.eql(u8, opcode, "div") or std.mem.eql(u8, opcode, "rem")) {
                const minimum = if (std.mem.eql(u8, ty, "w")) "2147483648" else "9223372036854775808";
                const overflow = try std.fmt.allocPrint(testing.allocator, "function {s} $f() {{\n@b\n%r ={s} {s} {s}, -1\nret %r\n}}", .{ ty, ty, opcode, minimum });
                defer testing.allocator.free(overflow);
                var invalid = try parse(testing.allocator, overflow);
                defer invalid.deinit();
                const g = invalid.functions.items[0];
                try testing.expectEqual(@as(usize, 0), try foldIntegerConstants(testing.allocator, g));
                try testing.expect(g.blocks.items[0].instructions.items[0] == .binary);
                try testing.expectError(error.IntegerOverflow, interpreter.evaluate(testing.allocator, g, &.{}, .{}));
            }
        }
    }
}

test "source order is conservative and facts never leak between functions" {
    var module = try parse(testing.allocator, "function w $f() {\n@entry\njmp @def\n@use\n%r =w add %x, 1\nret %r\n@def\n%x =w add 2, 3\njmp @use\n}\nfunction w $g(w %p) {\n@b\n%r =w add %p, 1\nret %r\n}");
    defer module.deinit();
    const f = module.functions.items[0];
    try testing.expectEqual(@as(usize, 1), try foldIntegerConstants(testing.allocator, f));
    try testing.expect(f.blocks.items[1].instructions.items[0] == .binary);
    try testing.expectEqual(@as(u32, 6), (try interpreter.evaluate(testing.allocator, f, &.{}, .{})).?.word);
    const g = module.functions.items[1];
    try testing.expectEqual(@as(usize, 0), try foldIntegerConstants(testing.allocator, g));
    try testing.expectEqual(@as(u32, 10), (try interpreter.evaluate(testing.allocator, g, &.{.{ .word = 9 }}, .{})).?.word);
}

fn exercise(allocator: std.mem.Allocator) !void {
    var module = try parse(allocator, chain);
    defer module.deinit();
    const f = module.functions.items[0];
    const changed = foldIntegerConstants(allocator, f) catch |err| {
        try testing.expect(f.blocks.items[0].instructions.items[0] == .binary);
        try testing.expect(f.blocks.items[0].instructions.items[6] == .binary);
        return err;
    };
    try testing.expectEqual(@as(usize, 7), changed);
    try f.validateStructure();
}

test "all folding allocation failures clean up and leave the function unmodified" {
    try @import("test_support.zig").checkAllocationFailures(exercise);
}

test "invalid SSA is rejected before any rewrite" {
    var module = try parse(testing.allocator, "function w $f() {\n@entry\n%x =w add 1, 2\n%y =w add %z, %x\n%z =w copy 3\nret %y\n}");
    defer module.deinit();
    const f = module.functions.items[0];
    try testing.expectError(error.InvalidSSA, foldIntegerConstants(testing.allocator, f));
    try testing.expect(f.blocks.items[0].instructions.items[0] == .binary);
}

test "folded arithmetic shift comparison and division constants match independent oracles" {
    const fixtures = .{ @embedFile("fixtures/integer-oracle.tsv"), @embedFile("fixtures/scalar-extra-oracle.tsv"), @embedFile("fixtures/division-oracle.tsv") };
    var case_count: usize = 0;
    inline for (fixtures) |fixture| {
        var lines = std.mem.tokenizeScalar(u8, fixture, '\n');
        while (lines.next()) |line| {
            if (line[0] == '#') continue;
            var fields = std.mem.tokenizeAny(u8, line, " \t");
            const ty = fields.next().?;
            const op = fields.next().?;
            const lhs = fields.next().?;
            const rhs = fields.next().?;
            const expected = try std.fmt.parseInt(u64, fields.next().?, 10);
            const mnemonic = if (std.mem.eql(u8, op, "bit_and")) "and" else if (std.mem.eql(u8, op, "bit_or")) "or" else if (std.mem.eql(u8, op, "bit_xor")) "xor" else op;
            const text = try std.fmt.allocPrint(testing.allocator, "function {s} $f() {{\n@b\n%r ={s} {s} {s}, {s}\nret %r\n}}", .{ ty, ty, mnemonic, lhs, rhs });
            defer testing.allocator.free(text);
            var module = try parse(testing.allocator, text);
            defer module.deinit();
            const f = module.functions.items[0];
            try testing.expectEqual(@as(usize, 1), try foldIntegerConstants(testing.allocator, f));
            const constant = f.blocks.items[0].instructions.items[0].copy.operand.constant;
            try testing.expectEqual(expected, if (std.mem.eql(u8, ty, "w")) @as(u64, constant.word) else constant.long);
            const evaluated = (try interpreter.evaluate(testing.allocator, f, &.{}, .{})).?;
            try testing.expectEqual(expected, if (std.mem.eql(u8, ty, "w")) @as(u64, evaluated.word) else evaluated.long);
            case_count += 1;
        }
    }
    try testing.expectEqual(@as(usize, 2444), case_count);
}
