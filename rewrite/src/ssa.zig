const std = @import("std");
const ir = @import("ir.zig");
const cfg = @import("cfg.zig");

pub const Issue = struct {
    code: enum { use_before_definition, non_dominating_definition, unreachable_cross_block_use },
    value: ir.ValueId,
    block: ir.BlockId,
    instruction_index: ?usize, // Null identifies a terminator use.
};
pub const Error = cfg.Error || error{InvalidSSA};

/// Validate dominance and local ordering for the current scalar IR vocabulary.
/// No phi exists yet. Unreachable blocks permit parameters and ordered local
/// uses, but reject cross-block uses rather than inventing unreachable dominance.
/// Analysis owns its scratch storage and does not mutate the function.
pub fn validate(allocator: std.mem.Allocator, function: *const ir.Function, issue: *?Issue) Error!void {
    issue.* = null;
    var graph = try cfg.Graph.init(allocator, function);
    defer graph.deinit();
    var dominators = try cfg.Dominators.init(allocator, &graph);
    defer dominators.deinit();
    for (function.blocks.items, 0..) |block, number| {
        const id: ir.BlockId = @fromBackingInt(@as(u32, @intCast(number)));
        for (block.instructions.items, 0..) |instruction, index| switch (instruction) {
            .binary => |binary| {
                try checkUse(function, &graph, &dominators, binary.lhs, id, index, issue);
                try checkUse(function, &graph, &dominators, binary.rhs, id, index, issue);
            },
            .copy => |copy| try checkUse(function, &graph, &dominators, copy.operand, id, index, issue),
        };
        switch (block.terminator.?) {
            .jump => {},
            .branch => |branch| try checkUse(function, &graph, &dominators, branch.condition, id, null, issue),
            .return_value => |operand| if (operand) |value| try checkUse(function, &graph, &dominators, value, id, null, issue),
        }
    }
}

fn checkUse(function: *const ir.Function, graph: *const cfg.Graph, dominators: *const cfg.Dominators, operand: ir.Operand, block: ir.BlockId, index: ?usize, issue: *?Issue) error{InvalidSSA}!void {
    const value = switch (operand) {
        .constant => return,
        .value => |value| value,
    };
    switch (function.values.items[@backingInt(value)].definition) {
        .parameter => return,
        .instruction => |definition| {
            const use_index = index orelse function.blocks.items[@backingInt(block)].instructions.items.len;
            const code: @FieldType(Issue, "code") = if (definition.block == block) local: {
                if (definition.index < use_index) return;
                break :local .use_before_definition;
            } else if (!graph.reachable[@backingInt(block)]) .unreachable_cross_block_use else dominance: {
                if (dominators.dominates(definition.block, block)) return;
                break :dominance .non_dominating_definition;
            };
            issue.* = .{ .code = code, .value = value, .block = block, .instruction_index = index };
            return error.InvalidSSA;
        },
    }
}

const testing = std.testing;
const frontend = @import("frontend.zig");
const source = @import("source.zig");

fn parse(text: []const u8) !@import("module.zig").Module {
    var diagnostic: ?source.Diagnostic = null;
    return frontend.parse(testing.allocator, .{ .name = "ssa-test", .text = text }, &diagnostic);
}

test "parameters and dominating definitions are valid across diamond and loop" {
    var module = try parse("function w $f(w %p) {\n@entry\n%x =w add %p, 1\njnz %p, @left, @right\n@left\njmp @join\n@right\njmp @join\n@join\njnz %x, @join, @exit\n@exit\nret %x\n}");
    defer module.deinit();
    var issue: ?Issue = null;
    try validate(testing.allocator, module.functions.items[0], &issue);
    try testing.expect(issue == null);
}

test "textually earlier definition on one branch does not dominate the join" {
    var module = try parse("function w $f(w %p) {\n@entry\njnz %p, @left, @right\n@left\n%x =w copy 42\njmp @join\n@right\njmp @join\n@join\nret %x\n}");
    defer module.deinit();
    var issue: ?Issue = null;
    try testing.expectError(error.InvalidSSA, validate(testing.allocator, module.functions.items[0], &issue));
    try testing.expectEqual(.non_dominating_definition, issue.?.code);
    try testing.expectEqual(@as(u32, 3), @backingInt(issue.?.block));
    try testing.expect(issue.?.instruction_index == null);
}

test "self-reference and forward local uses fail despite valid backlinks" {
    var module = try parse("function w $f() {\n@b\n%x =w copy 1\n%y =w add %x, 2\nret %y\n}");
    defer module.deinit();
    const f = module.functions.items[0];
    const instructions = f.blocks.items[0].instructions.items;
    var issue: ?Issue = null;
    instructions[0].copy.operand = .{ .value = instructions[0].result() };
    try f.validateStructure();
    try testing.expectError(error.InvalidSSA, validate(testing.allocator, f, &issue));
    try testing.expectEqual(.use_before_definition, issue.?.code);
    instructions[0].copy.operand = .{ .value = instructions[1].result() };
    try testing.expectError(error.InvalidSSA, validate(testing.allocator, f, &issue));
    try testing.expectEqual(.use_before_definition, issue.?.code);
}

test "unreachable blocks accept parameters and local uses but not cross-block values" {
    var module = try parse("function w $f(w %p) {\n@entry\n%x =w copy %p\nret %x\n@dead\n%y =w copy %p\nret %y\n}");
    defer module.deinit();
    const f = module.functions.items[0];
    var issue: ?Issue = null;
    try validate(testing.allocator, f, &issue);
    f.blocks.items[1].instructions.items[0].copy.operand = .{ .value = f.blocks.items[0].instructions.items[0].result() };
    try testing.expectError(error.InvalidSSA, validate(testing.allocator, f, &issue));
    try testing.expectEqual(.unreachable_cross_block_use, issue.?.code);
}

test "structural errors are checked before SSA traversal" {
    var module = try parse("function w $f() {\n@b\nret 1\n}");
    defer module.deinit();
    const f = module.functions.items[0];
    f.blocks.items[0].terminator = .{ .return_value = .{ .value = @fromBackingInt(@as(u32, 99)) } };
    var issue: ?Issue = null;
    try testing.expectError(error.InvalidValue, validate(testing.allocator, f, &issue));
    try testing.expect(issue == null);
}

fn exercise(allocator: std.mem.Allocator) !void {
    var diagnostic: ?source.Diagnostic = null;
    var module = try frontend.parse(allocator, .{ .name = "fixture", .text = @embedFile("fixtures/constant-jump.ssa") }, &diagnostic);
    defer module.deinit();
    var issue: ?Issue = null;
    for (module.functions.items) |f| try validate(allocator, f, &issue);
}

test "every SSA allocation failure cleans up analysis storage" {
    try @import("test_support.zig").checkAllocationFailures(exercise);
}

test "both binary operands and branch conditions require dominance" {
    var module = try parse("function w $f(w %p) {\n@entry\njnz %p, @left, @right\n@left\n%x =w copy 1\njmp @join\n@right\njmp @join\n@join\n%sum =w add 1, %x\njnz %x, @exit, @exit\n@exit\nret 0\n}");
    defer module.deinit();
    const f = module.functions.items[0];
    const join = &f.blocks.items[3];
    const value = join.instructions.items[0].binary.rhs;
    var issue: ?Issue = null;
    try testing.expectError(error.InvalidSSA, validate(testing.allocator, f, &issue));
    try testing.expectEqual(@as(?usize, 0), issue.?.instruction_index);
    join.instructions.items[0].binary.rhs = .{ .constant = .{ .word = 1 } };
    join.instructions.items[0].binary.lhs = value;
    try testing.expectError(error.InvalidSSA, validate(testing.allocator, f, &issue));
    try testing.expectEqual(@as(?usize, 0), issue.?.instruction_index);
    join.instructions.items[0].binary.lhs = .{ .constant = .{ .word = 1 } };
    try testing.expectError(error.InvalidSSA, validate(testing.allocator, f, &issue));
    try testing.expect(issue.?.instruction_index == null);
    join.terminator.?.branch.condition = .{ .constant = .{ .word = 1 } };
    try validate(testing.allocator, f, &issue);
}

fn exerciseInvalid(allocator: std.mem.Allocator) !void {
    var diagnostic: ?source.Diagnostic = null;
    var module = try frontend.parse(allocator, .{ .name = "invalid-ssa", .text = "function w $f() {\n@entry\njnz 1, @left, @join\n@left\n%x =w copy 1\njmp @join\n@join\nret %x\n}" }, &diagnostic);
    defer module.deinit();
    var issue: ?Issue = null;
    validate(allocator, module.functions.items[0], &issue) catch |err| switch (err) {
        error.InvalidSSA => {
            try testing.expectEqual(.non_dominating_definition, issue.?.code);
            return;
        },
        else => |resource| return resource,
    };
    return error.ExpectedInvalidSSA;
}

test "invalid SSA paths free analysis under every allocation failure" {
    try @import("test_support.zig").checkAllocationFailures(exerciseInvalid);
}
