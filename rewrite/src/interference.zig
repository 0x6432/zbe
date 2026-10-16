//! Owned, target-independent scalar interference. No register assignment.
const std = @import("std");
const ir = @import("ir.zig");
const liveness = @import("liveness.zig");
const BitSet = std.bit_set.Dynamic;
const word_bits = @bitSizeOf(usize);
pub const Error = liveness.Error || error{InterferenceTooLarge};
pub const Options = struct {
    max_graph_bytes: usize = 64 * 1024 * 1024,
    max_liveness_matrix_bytes: usize = 64 * 1024 * 1024,
};

/// Independent snapshot, immutable by convention; rebuild after IR mutation.
/// IDs remain function-scoped. Different register banks are not filtered here.
pub const Graph = struct {
    allocator: std.mem.Allocator,
    value_count: usize,
    words_per_row: usize,
    masks: []usize,

    pub fn init(allocator: std.mem.Allocator, function: *const ir.Function, options: Options) Error!Graph {
        const values = function.values.items.len;
        const shape = try storageShape(values);
        if (shape.bytes > options.max_graph_bytes) return error.InterferenceTooLarge;
        var live = try liveness.Snapshot.init(allocator, function, .{ .max_matrix_bytes = options.max_liveness_matrix_bytes });
        defer live.deinit();
        const masks = try allocator.alloc(usize, shape.words);
        errdefer allocator.free(masks);
        @memset(masks, 0);
        var graph: Graph = .{ .allocator = allocator, .value_count = values, .words_per_row = shape.words_per_row, .masks = masks };
        var current = try BitSet.initEmpty(allocator, values);
        defer current.deinit(allocator);
        for (function.blocks.items, 0..) |block, b| {
            current.unsetAll();
            current.setUnion(live.live_out[b]);
            switch (block.terminator.?) {
                .jump, .halt => {},
                .branch => |branch| addUse(&current, branch.condition),
                .return_value => |operand| if (operand) |value| addUse(&current, value),
            }
            var n = block.instructions.items.len;
            while (n != 0) {
                n -= 1;
                const instruction = block.instructions.items[n];
                const result = @backingInt(instruction.result());
                graph.connectLive(result, current);
                current.unset(result);
                switch (instruction) {
                    .copy => |c| addUse(&current, c.operand),
                    .unary => |u| addUse(&current, u.operand),
                    .binary => |bin| {
                        addUse(&current, bin.lhs);
                        addUse(&current, bin.rhs);
                    },
                    .shift => |s| {
                        addUse(&current, s.value);
                        addUse(&current, s.amount);
                    },
                    .compare_integer => |c| {
                        addUse(&current, c.lhs);
                        addUse(&current, c.rhs);
                    },
                    .compare_float => |c| {
                        addUse(&current, c.lhs);
                        addUse(&current, c.rhs);
                    },
                }
            }
            // Phi definitions happen together. Even a dead result must not
            // clobber another result when the complete bundle is materialized.
            for (block.phis.items, 0..) |phi, i| {
                const result = @backingInt(phi.result);
                graph.connectLive(result, current);
                for (block.phis.items[0..i]) |other| graph.connect(result, @backingInt(other.result));
            }
            for (block.phis.items) |phi| current.unset(@backingInt(phi.result));
            if (b == 0) {
                // Model the full incoming-parameter bundle, including dead
                // parameters, rather than assuming a future DCE pass.
                for (function.parameters.items, 0..) |parameter, i| {
                    const result = @backingInt(parameter);
                    graph.connectLive(result, current);
                    for (function.parameters.items[0..i]) |other| graph.connect(result, @backingInt(other));
                }
            }
        }
        return graph;
    }

    pub fn deinit(self: *Graph) void {
        self.allocator.free(self.masks);
        self.* = undefined;
    }

    pub fn interferes(self: *const Graph, a: ir.ValueId, b: ir.ValueId) ?bool {
        const x = @backingInt(a);
        const y = @backingInt(b);
        if (x >= self.value_count or y >= self.value_count) return null;
        return self.masks[x * self.words_per_row + y / word_bits] & (@as(usize, 1) << @intCast(y % word_bits)) != 0;
    }

    pub fn degree(self: *const Graph, value: ir.ValueId) ?usize {
        const index = @backingInt(value);
        if (index >= self.value_count) return null;
        var total: usize = 0;
        for (self.masks[index * self.words_per_row ..][0..self.words_per_row]) |mask| total += @popCount(mask);
        return total;
    }

    fn connect(self: *Graph, a: usize, b: usize) void {
        if (a == b) return;
        self.masks[a * self.words_per_row + b / word_bits] |= @as(usize, 1) << @intCast(b % word_bits);
        self.masks[b * self.words_per_row + a / word_bits] |= @as(usize, 1) << @intCast(a % word_bits);
    }

    fn connectLive(self: *Graph, definition: usize, live: BitSet) void {
        var iterator = live.iterator(.{});
        while (iterator.next()) |value| self.connect(definition, value);
    }
};

const Shape = struct { words: usize, words_per_row: usize, bytes: usize };
fn storageShape(values: usize) error{InterferenceTooLarge}!Shape {
    const rounded = std.math.add(usize, values, word_bits - 1) catch return error.InterferenceTooLarge;
    const words_per_row = rounded / word_bits;
    const words = std.math.mul(usize, values, words_per_row) catch return error.InterferenceTooLarge;
    const with_scratch = std.math.add(usize, words, words_per_row) catch return error.InterferenceTooLarge;
    const mask_bytes = std.math.mul(usize, with_scratch, @sizeOf(usize)) catch return error.InterferenceTooLarge;
    const bytes = std.math.add(usize, mask_bytes, if (values == 0) 0 else @sizeOf(BitSet) + @sizeOf(usize)) catch return error.InterferenceTooLarge;
    return .{ .words = words, .words_per_row = words_per_row, .bytes = bytes };
}
fn addUse(live: *BitSet, operand: ir.Operand) void {
    if (operand == .value) live.set(@backingInt(operand.value));
}

const testing = std.testing;
const cfg = @import("cfg.zig");
const frontend = @import("frontend.zig");
const source = @import("source.zig");
fn parse(allocator: std.mem.Allocator, text: []const u8) !@import("module.zig").Module {
    var diagnostic: ?source.Diagnostic = null;
    return frontend.parse(allocator, .{ .name = "interference-test", .text = text }, &diagnostic);
}
fn id(index: usize) ir.ValueId {
    return @fromBackingInt(@as(u32, @intCast(index)));
}
fn uses(operand: ir.Operand, value: ir.ValueId) bool {
    return operand == .value and operand.value == value;
}
fn instructionUses(instruction: ir.Instruction, value: ir.ValueId) bool {
    return switch (instruction) {
        .copy => |c| uses(c.operand, value),
        .unary => |u| uses(u.operand, value),
        .binary => |b| uses(b.lhs, value) or uses(b.rhs, value),
        .shift => |s| uses(s.value, value) or uses(s.amount, value),
        .compare_integer => |c| uses(c.lhs, value) or uses(c.rhs, value),
        .compare_float => |c| uses(c.lhs, value) or uses(c.rhs, value),
    };
}
// Independent oracle: scan forward from a program point for one value's use,
// stopping at its next definition. Successor searches include phi-edge uses;
// subsequent block entries kill parameter/phi definitions. No production
// liveness sets or backward instruction scan are used to derive expectations.
fn usedAfter(function: *const ir.Function, flow: *const cfg.Graph, block: usize, instruction_index: usize, value: ir.ValueId) !bool {
    const visited = try testing.allocator.alloc(bool, function.blocks.items.len);
    defer testing.allocator.free(visited);
    @memset(visited, false);
    var queue: std.ArrayList(usize) = .empty;
    defer queue.deinit(testing.allocator);
    var first = true;
    var cursor: usize = 0;
    while (first or cursor < queue.items.len) {
        const initial = first;
        const b = if (initial) block else queue.items[cursor];
        if (initial) first = false else cursor += 1;
        const current = function.blocks.items[b];
        if (!initial) {
            if (b == 0 and std.mem.indexOfScalar(ir.ValueId, function.parameters.items, value) != null) continue;
            var killed = false;
            for (current.phis.items) |phi| if (phi.result == value) {
                killed = true;
            };
            if (killed) continue;
        }
        var killed = false;
        for (current.instructions.items[if (initial) instruction_index else 0..]) |instruction| {
            if (instructionUses(instruction, value)) return true;
            if (instruction.result() == value) {
                killed = true;
                break;
            }
        }
        if (killed) continue;
        switch (current.terminator.?) {
            .jump, .halt => {},
            .branch => |branch| if (uses(branch.condition, value)) return true,
            .return_value => |operand| if (operand) |o| {
                if (uses(o, value)) return true;
            },
        }
        for (flow.successors[b].slice()) |successor| {
            const s = @backingInt(successor);
            for (function.blocks.items[s].phis.items) |phi| {
                for (phi.inputs) |input| if (@backingInt(input.predecessor) == b and uses(input.value, value)) return true;
            }
            if (!visited[s]) {
                visited[s] = true;
                try queue.append(testing.allocator, s);
            }
        }
    }
    return false;
}
fn oracleConnect(expected: []bool, count: usize, a: usize, b: usize) void {
    if (a == b) return;
    expected[a * count + b] = true;
    expected[b * count + a] = true;
}
fn compareOracle(function: *const ir.Function) !void {
    var graph = try Graph.init(testing.allocator, function, .{});
    defer graph.deinit();
    var flow = try cfg.Graph.init(testing.allocator, function);
    defer flow.deinit();
    const count = function.values.items.len;
    const expected = try testing.allocator.alloc(bool, count * count);
    defer testing.allocator.free(expected);
    @memset(expected, false);
    for (function.parameters.items, 0..) |parameter, i| {
        for (function.parameters.items[0..i]) |other| oracleConnect(expected, count, @backingInt(parameter), @backingInt(other));
        for (0..count) |v| if (try usedAfter(function, &flow, 0, 0, id(v))) {
            oracleConnect(expected, count, @backingInt(parameter), v);
        };
    }
    for (function.blocks.items, 0..) |block, b| {
        for (block.phis.items, 0..) |phi, i| {
            for (block.phis.items[0..i]) |other| oracleConnect(expected, count, @backingInt(phi.result), @backingInt(other.result));
            for (0..count) |v| if (try usedAfter(function, &flow, b, 0, id(v))) {
                oracleConnect(expected, count, @backingInt(phi.result), v);
            };
        }
        for (block.instructions.items, 0..) |instruction, index| {
            for (0..count) |v| if (try usedAfter(function, &flow, b, index + 1, id(v))) {
                oracleConnect(expected, count, @backingInt(instruction.result()), v);
            };
        }
    }
    for (0..count) |a| {
        var degree: usize = 0;
        for (0..count) |b| {
            const want = expected[a * count + b];
            try testing.expectEqual(want, graph.interferes(id(a), id(b)).?);
            if (want) degree += 1;
        }
        try testing.expectEqual(degree, graph.degree(id(a)).?);
        try testing.expect(!graph.interferes(id(a), id(a)).?);
    }
}

const bundle = "function w $f(w %p, w %unused) {\n@entry\n%a =w copy 1\n%dead =w copy 2\n%r =w add %p, %a\nret %r\n}";
test "dead definitions cannot clobber live values but dying operands can share a home" {
    var module = try parse(testing.allocator, bundle);
    defer module.deinit();
    var graph = try Graph.init(testing.allocator, module.functions.items[0], .{});
    defer graph.deinit();
    try testing.expect(graph.interferes(id(0), id(1)).?); // incoming bundle
    try testing.expect(graph.interferes(id(3), id(0)).?); // dead result vs live p
    try testing.expect(graph.interferes(id(3), id(2)).?); // dead result vs live a
    try testing.expect(!graph.interferes(id(4), id(0)).?); // p dies at add
    try testing.expect(!graph.interferes(id(4), id(2)).?);
    try compareOracle(module.functions.items[0]);
}

test "parallel phi results interfere even when dead and incoming edges stay distinct" {
    var module = try parse(testing.allocator, "function w $f(w %p) {\n@entry\njnz %p, @a, @b\n@a\n%x =w copy 1\njmp @join\n@b\n%y =w copy 2\njmp @join\n@join\n%r =w phi @a %x, @b %y\n%dead =w phi @a 0, @b 1\n%sum =w add %r, %p\nret %sum\n}");
    defer module.deinit();
    var graph = try Graph.init(testing.allocator, module.functions.items[0], .{});
    defer graph.deinit();
    try testing.expect(graph.interferes(id(3), id(4)).?);
    try testing.expect(graph.interferes(id(4), id(0)).?); // dead phi vs live-through parameter
    try testing.expect(!graph.interferes(id(1), id(2)).?);
    try testing.expect(!graph.interferes(id(1), id(3)).?);
    try compareOracle(module.functions.items[0]);
}

test "class-independent snapshots outlive input IR with bounds and empty frames" {
    var module = try parse(testing.allocator, "function w $f(w %p, d %q) {\n@b\nret %p\n}");
    var graph = try Graph.init(testing.allocator, module.functions.items[0], .{});
    defer graph.deinit();
    module.deinit();
    try testing.expect(graph.interferes(id(0), id(1)).?);
    try testing.expectEqual(@as(usize, 1), graph.degree(id(0)).?);
    try testing.expect(graph.interferes(id(0), id(2)) == null);
    try testing.expect(graph.interferes(id(2), id(0)) == null);
    try testing.expect(graph.degree(id(2)) == null);
    var empty = try parse(testing.allocator, "function $f() {\n@b\nret\n}");
    defer empty.deinit();
    var empty_graph = try Graph.init(testing.allocator, empty.functions.items[0], .{ .max_graph_bytes = 0 });
    defer empty_graph.deinit();
    try testing.expectEqual(@as(usize, 0), empty_graph.masks.len);
    try testing.expect(empty_graph.degree(id(0)) == null);
}

test "graph and liveness limits are separate and invalid SSA is rejected" {
    var module = try parse(testing.allocator, bundle);
    defer module.deinit();
    const f = module.functions.items[0];
    const size = try storageShape(f.values.items.len);
    var exact = try Graph.init(testing.allocator, f, .{ .max_graph_bytes = size.bytes });
    defer exact.deinit();
    try testing.expectError(error.InterferenceTooLarge, Graph.init(testing.allocator, f, .{ .max_graph_bytes = size.bytes - 1 }));
    try testing.expectError(error.InterferenceTooLarge, Graph.init(testing.allocator, f, .{ .max_graph_bytes = 0 }));
    try testing.expectError(error.LivenessTooLarge, Graph.init(testing.allocator, f, .{ .max_liveness_matrix_bytes = 0 }));
    try testing.expectError(error.InterferenceTooLarge, storageShape(std.math.maxInt(usize)));
    try testing.expectError(error.InterferenceTooLarge, storageShape(std.math.maxInt(usize) / 2));
    var invalid = try parse(testing.allocator, "function w $f() {\n@b\n%x =w add %y, 1\n%y =w copy 2\nret %x\n}");
    defer invalid.deinit();
    try testing.expectError(error.InvalidSSA, Graph.init(testing.allocator, invalid.functions.items[0], .{}));
}

fn exercise(allocator: std.mem.Allocator) !void {
    var module = try parse(allocator, bundle);
    defer module.deinit();
    var graph = try Graph.init(allocator, module.functions.items[0], .{});
    defer graph.deinit();
    try testing.expect(graph.interferes(id(3), id(0)).?);
}
test "every interference allocation failure frees graph and analysis scratch" {
    try @import("test_support.zig").checkAllocationFailures(exercise);
}

test "program-point oracle covers phi loops float operations and unreachable blocks" {
    var module = try parse(testing.allocator, @embedFile("fixtures/phi-loop.ssa") ++ "\n" ++ @embedFile("fixtures/compare-loop.ssa") ++ "\n" ++ @embedFile("fixtures/float-operations.ssa") ++ "\n" ++ @embedFile("fixtures/halt.ssa") ++ "\nfunction w $dead(w %p) {\n@entry\nret %p\n@unreachable\n%x =w copy 2\n%y =w add %p, %x\nret %y\n}");
    defer module.deinit();
    for (module.functions.items) |f| try compareOracle(f);
}

test "all mixed-program interference graphs agree with forward use-search oracle" {
    var module = try parse(testing.allocator, @embedFile("fixtures/mixed-programs.ssa"));
    defer module.deinit();
    for (module.functions.items) |f| try compareOracle(f);
}

test "packed adjacency crosses word boundaries without self edges or padding bits" {
    var f = ir.Function.init(testing.allocator, @fromBackingInt(@as(u32, 0)), .word);
    defer f.deinit();
    const count = word_bits + 3;
    for (0..count) |_| _ = try f.addParameter(.word);
    const block = try f.addBlock(null);
    try f.terminate(block, .{ .return_value = .{ .value = id(0) } });
    var graph = try Graph.init(testing.allocator, &f, .{});
    defer graph.deinit();
    for (0..count) |a| {
        try testing.expectEqual(count - 1, graph.degree(id(a)).?);
        for (0..count) |b| try testing.expectEqual(a != b, graph.interferes(id(a), id(b)).?);
    }
}

test "generated cyclic graphs match program-point oracle including dead local results" {
    for (0..32) |seed| {
        var f = ir.Function.init(testing.allocator, @fromBackingInt(@as(u32, 0)), .word);
        defer f.deinit();
        const parameter = try f.addParameter(.word);
        const count = 5 + seed % 4;
        var blocks: [8]ir.BlockId = undefined;
        for (blocks[0..count]) |*b| b.* = try f.addBlock(null);
        const base = try f.appendCopy(blocks[0], .word, .{ .constant = .{ .word = @intCast(seed) } });
        var state: u32 = @intCast(seed + 1);
        for (blocks[0..count], 0..) |b, index| {
            const local = try f.appendBinary(b, .word, .add, .{ .value = base }, .{ .value = parameter });
            _ = try f.appendCopy(b, .word, .{ .constant = .{ .word = 42 } });
            state = state *% 1664525 +% 1013904223;
            if (index == count - 1 and seed % 2 == 0) {
                try f.terminate(b, .{ .return_value = .{ .value = local } });
            } else {
                try f.terminate(b, .{ .branch = .{ .condition = .{ .value = if (state & 1 == 0) local else parameter }, .taken = blocks[1 + index % (count - 1)], .not_taken = blocks[1 + state % (count - 1)] } });
            }
        }
        try compareOracle(&f);
    }
}
