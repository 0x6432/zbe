const std = @import("std");
const ir = @import("ir.zig");
const Allocator = std.mem.Allocator;
pub const Error = Allocator.Error || ir.ValidationError || error{GraphTooLarge};

pub const Successors = struct {
    targets: [2]ir.BlockId = undefined,
    len: u2 = 0,

    pub fn slice(self: *const Successors) []const ir.BlockId {
        return self.targets[0..self.len];
    }
};

/// Owned immutable-by-convention CFG snapshot, independent of function storage.
/// Entry is block zero. Duplicate branch destinations represent a single edge.
/// Rebuild after changing the function; this does not track mutation epochs.
pub const Graph = struct {
    allocator: Allocator,
    successors: []const Successors,
    predecessor_offsets: []const usize,
    predecessor_storage: []const ir.BlockId,
    reachable: []const bool,
    order_storage: []const ir.BlockId,
    reachable_count: usize,

    pub fn init(allocator: Allocator, function: *const ir.Function) Error!Graph {
        try function.validateStructure();
        const count = function.blocks.items.len;
        const offset_count = std.math.add(usize, count, 1) catch return error.GraphTooLarge;
        const successors = try allocator.alloc(Successors, count);
        errdefer allocator.free(successors);
        const offsets = try allocator.alloc(usize, offset_count);
        errdefer allocator.free(offsets);
        @memset(offsets, 0);
        var edge_count: usize = 0;
        for (function.blocks.items, 0..) |block, index| {
            successors[index] = .{};
            const edges = &successors[index];
            switch (block.terminator.?) {
                .return_value => {},
                .jump => |target| {
                    edges.targets[0] = target;
                    edges.len = 1;
                },
                .branch => |branch| {
                    edges.targets[0] = branch.taken;
                    edges.len = 1;
                    if (branch.taken != branch.not_taken) {
                        edges.targets[1] = branch.not_taken;
                        edges.len = 2;
                    }
                },
            }
            edge_count = std.math.add(usize, edge_count, edges.len) catch return error.GraphTooLarge;
            for (edges.slice()) |target| offsets[@as(usize, @backingInt(target)) + 1] += 1;
        }
        for (1..offsets.len) |index| offsets[index] += offsets[index - 1];
        const predecessor_storage = try allocator.alloc(ir.BlockId, edge_count);
        errdefer allocator.free(predecessor_storage);
        const cursors = try allocator.dupe(usize, offsets[0..count]);
        defer allocator.free(cursors);
        for (successors, 0..) |*edges, index| {
            for (edges.slice()) |target| {
                const target_index = @backingInt(target);
                predecessor_storage[cursors[target_index]] = blockId(index);
                cursors[target_index] += 1;
            }
        }
        const reachable = try allocator.alloc(bool, count);
        errdefer allocator.free(reachable);
        @memset(reachable, false);
        const order = try allocator.alloc(ir.BlockId, count);
        errdefer allocator.free(order);
        const Frame = struct { block: ir.BlockId, next: u2 = 0 };
        // An explicit DFS stack bounds native stack use, including deep CFGs.
        const stack = try allocator.alloc(Frame, count);
        defer allocator.free(stack);
        var depth: usize = 1;
        stack[0] = .{ .block = blockId(0) };
        reachable[0] = true;
        var reached: usize = 0;
        while (depth != 0) {
            const frame = &stack[depth - 1];
            const edges = &successors[@backingInt(frame.block)];
            if (frame.next < edges.len) {
                const target = edges.targets[frame.next];
                frame.next += 1;
                if (!reachable[@backingInt(target)]) {
                    reachable[@backingInt(target)] = true;
                    stack[depth] = .{ .block = target };
                    depth += 1;
                }
            } else {
                order[reached] = frame.block;
                reached += 1;
                depth -= 1;
            }
        }
        std.mem.reverse(ir.BlockId, order[0..reached]);
        return .{
            .allocator = allocator,
            .successors = successors,
            .predecessor_offsets = offsets,
            .predecessor_storage = predecessor_storage,
            .reachable = reachable,
            .order_storage = order,
            .reachable_count = reached,
        };
    }

    pub fn deinit(self: *Graph) void {
        self.allocator.free(self.order_storage);
        self.allocator.free(self.reachable);
        self.allocator.free(self.predecessor_storage);
        self.allocator.free(self.predecessor_offsets);
        self.allocator.free(self.successors);
        self.* = undefined;
    }

    pub fn predecessors(self: *const Graph, block: ir.BlockId) ?[]const ir.BlockId {
        const index: usize = @backingInt(block);
        if (index >= self.successors.len) return null;
        return self.predecessor_storage[self.predecessor_offsets[index]..self.predecessor_offsets[index + 1]];
    }

    pub fn reversePostorder(self: *const Graph) []const ir.BlockId {
        return self.order_storage[0..self.reachable_count];
    }
};

/// Cooper-style iterative immediate dominators over reachable reverse postorder.
/// Storage is O(blocks + edges), not a quadratic dominance bit matrix.
pub const Dominators = struct {
    allocator: Allocator,
    parents: []const ?ir.BlockId,

    pub fn init(allocator: Allocator, graph: *const Graph) Allocator.Error!Dominators {
        const parents = try allocator.alloc(?ir.BlockId, graph.successors.len);
        errdefer allocator.free(parents);
        @memset(parents, null);
        const ranks = try allocator.alloc(usize, graph.successors.len);
        defer allocator.free(ranks);
        @memset(ranks, std.math.maxInt(usize));
        const order = graph.reversePostorder();
        for (order, 0..) |block, rank| ranks[@backingInt(block)] = rank;
        parents[0] = blockId(0); // Internal root sentinel, hidden by query API.
        var changed = true;
        while (changed) {
            changed = false;
            for (order[1..]) |block| {
                var parent: ?ir.BlockId = null;
                for (graph.predecessors(block).?) |predecessor| {
                    if (parents[@backingInt(predecessor)] == null) continue;
                    parent = if (parent) |previous| intersect(previous, predecessor, parents, ranks) else predecessor;
                }
                std.debug.assert(parent != null);
                if (parents[@backingInt(block)] != parent) {
                    parents[@backingInt(block)] = parent;
                    changed = true;
                }
            }
        }
        return .{ .allocator = allocator, .parents = parents };
    }

    pub fn deinit(self: *Dominators) void {
        self.allocator.free(self.parents);
        self.* = undefined;
    }

    /// Null for the entry, unreachable blocks, or an out-of-range ID.
    pub fn immediateDominator(self: *const Dominators, block: ir.BlockId) ?ir.BlockId {
        const index: usize = @backingInt(block);
        if (index == 0 or index >= self.parents.len) return null;
        return self.parents[index];
    }

    /// Unreachable blocks do not participate, including self-dominance queries.
    pub fn dominates(self: *const Dominators, definition: ir.BlockId, use: ir.BlockId) bool {
        if (@backingInt(definition) >= self.parents.len or @backingInt(use) >= self.parents.len) return false;
        if (self.parents[@backingInt(definition)] == null or self.parents[@backingInt(use)] == null) return false;
        var cursor = use;
        while (true) {
            if (cursor == definition) return true;
            if (@backingInt(cursor) == 0) return false;
            cursor = self.parents[@backingInt(cursor)].?;
        }
    }

    fn intersect(a: ir.BlockId, b: ir.BlockId, parents: []const ?ir.BlockId, ranks: []const usize) ir.BlockId {
        var left = a;
        var right = b;
        while (left != right) {
            while (ranks[@backingInt(left)] > ranks[@backingInt(right)]) left = parents[@backingInt(left)].?;
            while (ranks[@backingInt(right)] > ranks[@backingInt(left)]) right = parents[@backingInt(right)].?;
        }
        return left;
    }
};

fn blockId(index: usize) ir.BlockId {
    return @fromBackingInt(@as(u32, @intCast(index)));
}

const testing = std.testing;
const test_name: @import("symbols.zig").Id = @fromBackingInt(@as(u32, 0));

fn diamond(allocator: Allocator) !ir.Function {
    var f = ir.Function.init(allocator, test_name, null);
    errdefer f.deinit();
    for (0..5) |_| _ = try f.addBlock(null);
    try f.terminate(blockId(0), .{ .branch = .{ .condition = .{ .constant = .{ .word = 1 } }, .taken = blockId(1), .not_taken = blockId(2) } });
    try f.terminate(blockId(1), .{ .jump = blockId(3) });
    try f.terminate(blockId(2), .{ .jump = blockId(3) });
    try f.terminate(blockId(3), .{ .return_value = null });
    try f.terminate(blockId(4), .{ .jump = blockId(4) });
    return f;
}

test "CFG snapshots predecessor edges, reachability and diamond dominance" {
    var f = try diamond(testing.allocator);
    defer f.deinit();
    var graph = try Graph.init(testing.allocator, &f);
    defer graph.deinit();
    var dom = try Dominators.init(testing.allocator, &graph);
    defer dom.deinit();
    try testing.expectEqualSlices(ir.BlockId, &.{ blockId(1), blockId(2) }, graph.predecessors(blockId(3)).?);
    try testing.expectEqual(@as(usize, 4), graph.reversePostorder().len);
    try testing.expect(!graph.reachable[4]);
    try testing.expect(dom.dominates(blockId(0), blockId(3)));
    try testing.expect(!dom.dominates(blockId(1), blockId(3)));
    try testing.expect(!dom.dominates(blockId(4), blockId(4)));
    try testing.expectEqual(blockId(0), dom.immediateDominator(blockId(3)).?);
    try testing.expect(dom.immediateDominator(blockId(0)) == null);
    try testing.expect(dom.immediateDominator(blockId(4)) == null);
    try testing.expect(graph.predecessors(blockId(99)) == null);
    try testing.expect(!dom.dominates(blockId(99), blockId(0)));
}

test "duplicate branch targets count once and CFG owns its snapshot" {
    var graph = snapshot: {
        var f = ir.Function.init(testing.allocator, test_name, null);
        defer f.deinit();
        _ = try f.addBlock(null);
        _ = try f.addBlock(null);
        try f.terminate(blockId(0), .{ .branch = .{ .condition = .{ .constant = .{ .word = 0 } }, .taken = blockId(1), .not_taken = blockId(1) } });
        try f.terminate(blockId(1), .{ .return_value = null });
        break :snapshot try Graph.init(testing.allocator, &f);
    };
    defer graph.deinit();
    try testing.expectEqual(@as(usize, 1), graph.successors[0].slice().len);
    try testing.expectEqualSlices(ir.BlockId, &.{blockId(0)}, graph.predecessors(blockId(1)).?);
}

test "invalid IR is rejected before graph allocation" {
    var f = ir.Function.init(testing.allocator, test_name, null);
    defer f.deinit();
    var failing = testing.FailingAllocator.init(testing.allocator, .{ .fail_index = 0 });
    try testing.expectError(error.NoBlocks, Graph.init(failing.allocator(), &f));
    _ = try f.addBlock(null);
    try testing.expectError(error.MissingTerminator, Graph.init(failing.allocator(), &f));
}

test "deep CFG uses iterative traversal, not the native call stack" {
    var f = ir.Function.init(testing.allocator, test_name, null);
    defer f.deinit();
    for (0..4096) |_| _ = try f.addBlock(null);
    for (0..4095) |index| try f.terminate(blockId(index), .{ .jump = blockId(index + 1) });
    try f.terminate(blockId(4095), .{ .return_value = null });
    var graph = try Graph.init(testing.allocator, &f);
    defer graph.deinit();
    var dom = try Dominators.init(testing.allocator, &graph);
    defer dom.deinit();
    try testing.expectEqual(@as(usize, 4096), graph.reversePostorder().len);
    try testing.expectEqual(blockId(4094), dom.immediateDominator(blockId(4095)).?);
    try testing.expect(dom.dominates(blockId(0), blockId(4095)));
}

fn exercise(allocator: Allocator) !void {
    var f = try diamond(allocator);
    defer f.deinit();
    var graph = try Graph.init(allocator, &f);
    defer graph.deinit();
    var dom = try Dominators.init(allocator, &graph);
    defer dom.deinit();
    try testing.expect(dom.dominates(blockId(0), blockId(3)));
}

test "all CFG and dominance allocation failures clean up" {
    try @import("test_support.zig").checkAllocationFailures(exercise);
}

/// Independent oracle: remove a candidate vertex and search from entry. It
/// dominates a reachable block exactly when removal disconnects that block.
fn oracleReachable(graph: *const Graph, removed: usize, target: usize) bool {
    var seen: [8]bool = @splat(false);
    var queue: [8]usize = undefined;
    if (removed == 0) return false;
    var head: usize = 0;
    var tail: usize = 1;
    queue[0] = 0;
    seen[0] = true;
    while (head < tail) : (head += 1) {
        const block = queue[head];
        if (block == target) return true;
        for (graph.successors[block].slice()) |successor| {
            const index = @backingInt(successor);
            if (index == removed or seen[index]) continue;
            seen[index] = true;
            queue[tail] = index;
            tail += 1;
        }
    }
    return false;
}

fn random(state: *u32) u32 {
    state.* = state.* *% 1664525 +% 1013904223;
    return state.*;
}

test "dominators agree with vertex-removal oracle on 512 cyclic graphs" {
    var state: u32 = 0x84365219;
    for (0..512) |_| {
        var f = ir.Function.init(testing.allocator, test_name, null);
        defer f.deinit();
        const count = 2 + random(&state) % 7;
        for (0..count) |_| _ = try f.addBlock(null);
        for (0..count) |index| {
            const kind = random(&state) % 3;
            const a = blockId(random(&state) % count);
            const b = blockId(random(&state) % count);
            try f.terminate(blockId(index), switch (kind) {
                0 => .{ .return_value = null },
                1 => .{ .jump = a },
                else => .{ .branch = .{ .condition = .{ .constant = .{ .word = 1 } }, .taken = a, .not_taken = b } },
            });
        }
        var graph = try Graph.init(testing.allocator, &f);
        defer graph.deinit();
        var dom = try Dominators.init(testing.allocator, &graph);
        defer dom.deinit();
        // An out-of-range removed vertex leaves the original graph intact.
        for (0..count) |target| try testing.expectEqual(oracleReachable(&graph, count, target), graph.reachable[target]);
        var expected: [8][8]bool = undefined;
        for (0..count) |candidate| for (0..count) |target| {
            expected[candidate][target] = graph.reachable[target] and !oracleReachable(&graph, candidate, target);
            try testing.expectEqual(expected[candidate][target], dom.dominates(blockId(candidate), blockId(target)));
        };
        for (1..count) |target| {
            if (!graph.reachable[target]) {
                try testing.expect(dom.immediateDominator(blockId(target)) == null);
                continue;
            }
            var parent: ?ir.BlockId = null;
            for (0..count) |candidate| {
                if (candidate == target or !expected[candidate][target]) continue;
                var closest = true;
                for (0..count) |other| {
                    if (other != target and other != candidate and expected[other][target] and !expected[other][candidate]) closest = false;
                }
                if (closest) parent = blockId(candidate);
            }
            try testing.expectEqual(parent, dom.immediateDominator(blockId(target)));
        }
    }
}

test "loop dominance uses reverse-postorder ranks, not block IDs" {
    var f = ir.Function.init(testing.allocator, test_name, null);
    defer f.deinit();
    for (0..4) |_| _ = try f.addBlock(null);
    try f.terminate(blockId(0), .{ .jump = blockId(2) });
    try f.terminate(blockId(1), .{ .return_value = null });
    try f.terminate(blockId(2), .{ .branch = .{ .condition = .{ .constant = .{ .word = 1 } }, .taken = blockId(3), .not_taken = blockId(1) } });
    try f.terminate(blockId(3), .{ .jump = blockId(2) });
    var graph = try Graph.init(testing.allocator, &f);
    defer graph.deinit();
    var dom = try Dominators.init(testing.allocator, &graph);
    defer dom.deinit();
    try testing.expectEqual(blockId(0), dom.immediateDominator(blockId(2)).?);
    try testing.expectEqual(blockId(2), dom.immediateDominator(blockId(1)).?);
    try testing.expectEqual(blockId(2), dom.immediateDominator(blockId(3)).?);
    try testing.expect(!dom.dominates(blockId(3), blockId(2)));
}

test "irreducible multi-entry cycle converges to entry dominators" {
    var f = ir.Function.init(testing.allocator, test_name, null);
    defer f.deinit();
    for (0..4) |_| _ = try f.addBlock(null);
    const branch: ir.Terminator = .{ .branch = .{ .condition = .{ .constant = .{ .word = 1 } }, .taken = blockId(1), .not_taken = blockId(2) } };
    try f.terminate(blockId(0), branch);
    try f.terminate(blockId(1), .{ .jump = blockId(3) });
    try f.terminate(blockId(2), .{ .jump = blockId(3) });
    try f.terminate(blockId(3), branch);
    var graph = try Graph.init(testing.allocator, &f);
    defer graph.deinit();
    var dom = try Dominators.init(testing.allocator, &graph);
    defer dom.deinit();
    for (1..4) |index| try testing.expectEqual(blockId(0), dom.immediateDominator(blockId(index)).?);
}
