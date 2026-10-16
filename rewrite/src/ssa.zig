const std = @import("std");
const ir = @import("ir.zig");
const cfg = @import("cfg.zig");

pub const Code = enum { use_before_definition, non_dominating_definition, unreachable_cross_block_use, invalid_phi_predecessors };
pub const UseSite = union(enum) {
    instruction: usize,
    terminator,
    phi: usize,
    phi_input: struct { phi: usize, input: usize },
};
pub const Issue = struct { code: Code, value: ir.ValueId, block: ir.BlockId, site: UseSite };
pub const Error = cfg.Error || error{ InvalidSSA, EntryHasPredecessors };

/// Validate dominance and local ordering for the current scalar IR vocabulary.
/// Phi operands are checked at the end of their incoming predecessor edge.
/// Unreachable blocks permit parameters and ordered local
/// uses, but reject cross-block uses rather than inventing unreachable dominance.
/// Analysis owns its scratch storage and does not mutate the function.
pub fn validate(allocator: std.mem.Allocator, function: *const ir.Function, issue: *?Issue) Error!void {
    issue.* = null;
    var graph = try cfg.Graph.init(allocator, function);
    defer graph.deinit();
    // Parameters are defined once on invocation, not on a CFG backedge.
    // QBE forbids every jump to the first block, including from dead blocks.
    if (graph.predecessors(@fromBackingInt(@as(u32, 0))).?.len != 0) return error.EntryHasPredecessors;
    var dominators = try cfg.Dominators.init(allocator, &graph);
    defer dominators.deinit();
    for (function.blocks.items, 0..) |block, number| {
        const id: ir.BlockId = @fromBackingInt(@as(u32, @intCast(number)));
        const predecessors = graph.predecessors(id).?;
        for (block.phis.items, 0..) |phi, phi_index| {
            if (number == 0 or phi.inputs.len != predecessors.len) {
                issue.* = .{ .code = .invalid_phi_predecessors, .value = phi.result, .block = id, .site = .{ .phi = phi_index } };
                return error.InvalidSSA;
            }
            for (phi.inputs, 0..) |input, input_index| {
                var duplicate = false;
                for (phi.inputs[0..input_index]) |earlier| {
                    if (earlier.predecessor == input.predecessor) duplicate = true;
                }
                if (duplicate or std.mem.indexOfScalar(ir.BlockId, predecessors, input.predecessor) == null) {
                    issue.* = .{ .code = .invalid_phi_predecessors, .value = phi.result, .block = id, .site = .{ .phi_input = .{ .phi = phi_index, .input = input_index } } };
                    return error.InvalidSSA;
                }
                checkUse(function, &graph, &dominators, input.value, input.predecessor, null, issue) catch |err| {
                    issue.*.?.block = id;
                    issue.*.?.site = .{ .phi_input = .{ .phi = phi_index, .input = input_index } };
                    return err;
                };
            }
        }
        for (block.instructions.items, 0..) |instruction, index| switch (instruction) {
            .binary => |binary| {
                try checkUse(function, &graph, &dominators, binary.lhs, id, index, issue);
                try checkUse(function, &graph, &dominators, binary.rhs, id, index, issue);
            },
            .copy => |copy| try checkUse(function, &graph, &dominators, copy.operand, id, index, issue),
            .unary => |unary| try checkUse(function, &graph, &dominators, unary.operand, id, index, issue),
            .shift => |shift| {
                try checkUse(function, &graph, &dominators, shift.value, id, index, issue);
                try checkUse(function, &graph, &dominators, shift.amount, id, index, issue);
            },
            .compare_float => |comparison| {
                try checkUse(function, &graph, &dominators, comparison.lhs, id, index, issue);
                try checkUse(function, &graph, &dominators, comparison.rhs, id, index, issue);
            },
            .compare_integer => |comparison| {
                try checkUse(function, &graph, &dominators, comparison.lhs, id, index, issue);
                try checkUse(function, &graph, &dominators, comparison.rhs, id, index, issue);
            },
        };
        switch (block.terminator.?) {
            .jump, .halt => {},
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
    const site: UseSite = if (index) |number| .{ .instruction = number } else .terminator;
    const defining_block = switch (function.values.items[@backingInt(value)].definition) {
        .pending => unreachable, // Structure validation rejects unfinished values.
        .parameter => return,
        .phi => |definition| definition.block,
        .instruction => |definition| local: {
            if (definition.block == block) {
                const use_index = index orelse function.blocks.items[@backingInt(block)].instructions.items.len;
                if (definition.index < use_index) return;
                issue.* = .{ .code = .use_before_definition, .value = value, .block = block, .site = site };
                return error.InvalidSSA;
            }
            break :local definition.block;
        },
    };
    if (defining_block == block) return; // A phi is available at block entry.
    const code: Code = if (!graph.reachable[@backingInt(block)]) .unreachable_cross_block_use else dominance: {
        if (dominators.dominates(defining_block, block)) return;
        break :dominance .non_dominating_definition;
    };
    issue.* = .{ .code = code, .value = value, .block = block, .site = site };
    return error.InvalidSSA;
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
    try testing.expect(issue.?.site == .terminator);
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
    try testing.expectEqual(@as(usize, 0), issue.?.site.instruction);
    join.instructions.items[0].binary.rhs = .{ .constant = .{ .word = 1 } };
    join.instructions.items[0].binary.lhs = value;
    try testing.expectError(error.InvalidSSA, validate(testing.allocator, f, &issue));
    try testing.expectEqual(@as(usize, 0), issue.?.site.instruction);
    join.instructions.items[0].binary.lhs = .{ .constant = .{ .word = 1 } };
    try testing.expectError(error.InvalidSSA, validate(testing.allocator, f, &issue));
    try testing.expect(issue.?.site == .terminator);
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

const diamond_phi = "function w $f(w %p) {\n@entry\njnz %p, @left, @right\n@left\n%l =w copy 1\njmp @join\n@right\n%r =w copy 2\njmp @join\n@join\n%x =w phi @left %l, @right %r\nret %x\n}";

test "phi predecessor coverage rejects missing, repeated and extraneous edges" {
    const variants = [_][]const u8{
        "@left %l",
        "@left %l, @left %l",
        "@entry 0, @right %r",
    };
    for (variants) |inputs| {
        const text = try std.mem.replaceOwned(u8, testing.allocator, diamond_phi, "@left %l, @right %r", inputs);
        defer testing.allocator.free(text);
        var module = try parse(text);
        defer module.deinit();
        var issue: ?Issue = null;
        try testing.expectError(error.InvalidSSA, validate(testing.allocator, module.functions.items[0], &issue));
        try testing.expectEqual(.invalid_phi_predecessors, issue.?.code);
    }
}

test "phi edge dominance rejects values from the wrong predecessor" {
    const text = try std.mem.replaceOwned(u8, testing.allocator, diamond_phi, "@left %l, @right %r", "@left %r, @right %r");
    defer testing.allocator.free(text);
    var module = try parse(text);
    defer module.deinit();
    var issue: ?Issue = null;
    try testing.expectError(error.InvalidSSA, validate(testing.allocator, module.functions.items[0], &issue));
    try testing.expectEqual(.non_dominating_definition, issue.?.code);
    try testing.expectEqual(@as(usize, 0), issue.?.site.phi_input.input);
    try testing.expectEqual(@as(u32, 3), @backingInt(issue.?.block));
}

test "entry phi is rejected independently of an entry backedge" {
    var module = try parse("function w $f() {\n@entry\n%x =w phi @exit 0\njmp @exit\n@exit\nret %x\n}");
    defer module.deinit();
    var issue: ?Issue = null;
    try testing.expectError(error.InvalidSSA, validate(testing.allocator, module.functions.items[0], &issue));
    try testing.expectEqual(.invalid_phi_predecessors, issue.?.code);
}

test "shift counts and both comparison operands require dominance" {
    for ([_][]const u8{ "shl 1, %x", "ceqw %x, 1", "ceqw 1, %x" }) |operation| {
        const text = try std.fmt.allocPrint(testing.allocator, "function w $f(w %p) {{\n@entry\njnz %p, @left, @join\n@left\n%x =w copy 1\njmp @join\n@join\n%r =w {s}\nret %r\n}}", .{operation});
        defer testing.allocator.free(text);
        var module = try parse(text);
        defer module.deinit();
        var issue: ?Issue = null;
        try testing.expectError(error.InvalidSSA, validate(testing.allocator, module.functions.items[0], &issue));
        try testing.expectEqual(.non_dominating_definition, issue.?.code);
        try testing.expectEqual(@as(usize, 0), issue.?.site.instruction);
    }
}

test "unary operands obey same block ordering and cross block dominance" {
    var module = try parse("function w $f() {\n@b\n%x =w neg %y\n%y =w copy 1\nret %x\n}");
    defer module.deinit();
    var issue: ?Issue = null;
    try testing.expectError(error.InvalidSSA, validate(testing.allocator, module.functions.items[0], &issue));
    try testing.expectEqual(.use_before_definition, issue.?.code);
    var diamond = try parse("function l $f(w %p) {\n@entry\njnz %p, @left, @join\n@left\n%x =w copy 255\njmp @join\n@join\n%r =l extsb %x\nret %r\n}");
    defer diamond.deinit();
    try testing.expectError(error.InvalidSSA, validate(testing.allocator, diamond.functions.items[0], &issue));
    try testing.expectEqual(.non_dominating_definition, issue.?.code);
}

test "both floating comparison operands require dominating definitions" {
    for ([_][]const u8{ "ceqs %x, s_1", "cuos s_1, %x" }) |operation| {
        const text = try std.fmt.allocPrint(testing.allocator, "function w $f(w %p) {{\n@entry\njnz %p, @left, @join\n@left\n%x =s copy s_1\njmp @join\n@join\n%r =w {s}\nret %r\n}}", .{operation});
        defer testing.allocator.free(text);
        var module = try parse(text);
        defer module.deinit();
        var issue: ?Issue = null;
        try testing.expectError(error.InvalidSSA, validate(testing.allocator, module.functions.items[0], &issue));
        try testing.expectEqual(.non_dominating_definition, issue.?.code);
    }
}

test "entry block cannot have self conditional or unreachable predecessors" {
    const cases = [_][]const u8{
        "function $f() {\n@entry\njmp @entry\n}",
        "function w $f(w %p) {\n@entry\njnz %p, @entry, @done\n@done\nret %p\n}",
        "function w $f(w %p) {\n@entry\nret %p\n@dead\njmp @entry\n}",
    };
    for (cases) |text| {
        var diagnostic: ?source.Diagnostic = null;
        var module = try frontend.parse(testing.allocator, .{ .name = "entry-edge", .text = text }, &diagnostic);
        defer module.deinit();
        var graph = try cfg.Graph.init(testing.allocator, module.functions.items[0]);
        defer graph.deinit();
        try testing.expect(graph.predecessors(@fromBackingInt(@as(u32, 0))).?.len != 0);
        var issue: ?Issue = null;
        try testing.expectError(error.EntryHasPredecessors, validate(testing.allocator, module.functions.items[0], &issue));
        try testing.expect(issue == null); // This is a CFG policy error, not a value-use issue.
    }
}
