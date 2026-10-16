//! Owned block-boundary liveness; phi inputs are uses on incoming edges.
const std = @import("std");
const ir = @import("ir.zig");
const cfg = @import("cfg.zig");
const ssa = @import("ssa.zig");
const BitSet = std.bit_set.Dynamic;
pub const Error = ssa.Error || error{LivenessTooLarge};
pub const Options = struct { max_matrix_bytes: usize = 64 * 1024 * 1024 };

/// Independent snapshot, immutable by convention. Rebuild after IR mutation.
/// IDs remain function-scoped caller invariants; queries check ordinal bounds.
pub const Snapshot = struct {
    allocator: std.mem.Allocator,
    value_count: usize,
    live_in: []const BitSet,
    live_out: []const BitSet,

    pub fn init(allocator: std.mem.Allocator, function: *const ir.Function, options: Options) Error!Snapshot {
        const blocks = function.blocks.items.len;
        const values = function.values.items.len;
        if (try matrixBytes(blocks, values) > options.max_matrix_bytes) return error.LivenessTooLarge;
        var issue: ?ssa.Issue = null;
        try ssa.validate(allocator, function, &issue);
        var graph = try cfg.Graph.init(allocator, function);
        defer graph.deinit();
        const uses = try createSets(allocator, blocks, values);
        defer destroySets(allocator, uses);
        const defs = try createSets(allocator, blocks, values);
        defer destroySets(allocator, defs);
        const live_in = try createSets(allocator, blocks, values);
        errdefer destroySets(allocator, live_in);
        const live_out = try createSets(allocator, blocks, values);
        errdefer destroySets(allocator, live_out);
        var next_in = try BitSet.initEmpty(allocator, values);
        defer next_in.deinit(allocator);
        var next_out = try BitSet.initEmpty(allocator, values);
        defer next_out.deinit(allocator);
        for (function.parameters.items) |parameter| defs[0].set(@backingInt(parameter));
        for (function.blocks.items, 0..) |block, index| {
            for (block.phis.items) |phi| defs[index].set(@backingInt(phi.result));
            for (block.instructions.items) |instruction| {
                var operands = instruction.operands();
                while (operands.next()) |operand| addUse(&uses[index], defs[index], operand);
                if (instruction.result()) |result| defs[index].set(@backingInt(result));
            }
            switch (block.terminator.?) {
                .jump, .halt => {},
                .branch => |b| addUse(&uses[index], defs[index], b.condition),
                .return_value => |value| if (value) |operand| addUse(&uses[index], defs[index], operand),
            }
        }
        var solver: Solver = .{ .function = function, .graph = &graph, .uses = uses, .defs = defs, .live_in = live_in, .live_out = live_out, .next_in = &next_in, .next_out = &next_out };
        var changed = true;
        while (changed) {
            changed = false;
            const order = graph.reversePostorder();
            var n = order.len;
            while (n != 0) {
                n -= 1;
                changed = solver.transfer(@backingInt(order[n])) or changed;
            }
            n = blocks;
            while (n != 0) {
                n -= 1;
                if (!graph.reachable[n]) changed = solver.transfer(n) or changed;
            }
        }
        return .{ .allocator = allocator, .value_count = values, .live_in = live_in, .live_out = live_out };
    }

    pub fn deinit(self: *Snapshot) void {
        destroySets(self.allocator, self.live_in);
        destroySets(self.allocator, self.live_out);
        self.* = undefined;
    }
    pub fn isLiveIn(self: *const Snapshot, block: ir.BlockId, value: ir.ValueId) ?bool {
        const b = @backingInt(block);
        const v = @backingInt(value);
        if (b >= self.live_in.len or v >= self.value_count) return null;
        return self.live_in[b].isSet(v);
    }
    pub fn isLiveOut(self: *const Snapshot, block: ir.BlockId, value: ir.ValueId) ?bool {
        const b = @backingInt(block);
        const v = @backingInt(value);
        if (b >= self.live_out.len or v >= self.value_count) return null;
        return self.live_out[b].isSet(v);
    }
};

fn matrixBytes(blocks: usize, values: usize) error{LivenessTooLarge}!usize {
    const rounded = std.math.add(usize, values, @bitSizeOf(usize) - 1) catch return error.LivenessTooLarge;
    const words = rounded / @bitSizeOf(usize);
    const mask_bytes = std.math.mul(usize, words, @sizeOf(usize)) catch return error.LivenessTooLarge;
    const row_bytes = std.math.add(usize, mask_bytes, @sizeOf(BitSet) + @sizeOf(usize)) catch return error.LivenessTooLarge;
    const rows = std.math.add(usize, std.math.mul(usize, blocks, 4) catch return error.LivenessTooLarge, 2) catch return error.LivenessTooLarge;
    return std.math.mul(usize, row_bytes, rows) catch return error.LivenessTooLarge;
}
fn createSets(allocator: std.mem.Allocator, count: usize, values: usize) std.mem.Allocator.Error![]BitSet {
    const sets = try allocator.alloc(BitSet, count);
    errdefer allocator.free(sets);
    var initialized: usize = 0;
    errdefer for (sets[0..initialized]) |*set| set.deinit(allocator);
    for (sets) |*set| {
        set.* = try BitSet.initEmpty(allocator, values);
        initialized += 1;
    }
    return sets;
}
fn destroySets(allocator: std.mem.Allocator, sets: []const BitSet) void {
    for (sets) |set| {
        var owned = set;
        owned.deinit(allocator);
    }
    allocator.free(sets);
}
fn addUse(uses: *BitSet, defs: BitSet, operand: ir.Operand) void {
    if (operand == .value and !defs.isSet(@backingInt(operand.value))) uses.set(@backingInt(operand.value));
}
const Solver = struct {
    function: *const ir.Function,
    graph: *const cfg.Graph,
    uses: []const BitSet,
    defs: []const BitSet,
    live_in: []BitSet,
    live_out: []BitSet,
    next_in: *BitSet,
    next_out: *BitSet,

    fn transfer(self: *Solver, block: usize) bool {
        self.next_out.unsetAll();
        for (self.graph.successors[block].slice()) |successor| {
            const s = @backingInt(successor);
            self.next_out.setUnion(self.live_in[s]);
            for (self.function.blocks.items[s].phis.items) |phi| {
                for (phi.inputs) |input| {
                    if (@backingInt(input.predecessor) == block and input.value == .value) self.next_out.set(@backingInt(input.value.value));
                }
            }
        }
        self.next_in.unsetAll();
        self.next_in.setUnion(self.next_out.*);
        var definitions = self.defs[block].iterator(.{});
        while (definitions.next()) |value| self.next_in.unset(value);
        self.next_in.setUnion(self.uses[block]);
        const changed = !self.live_in[block].eql(self.next_in.*) or !self.live_out[block].eql(self.next_out.*);
        self.live_in[block].unsetAll();
        self.live_in[block].setUnion(self.next_in.*);
        self.live_out[block].unsetAll();
        self.live_out[block].setUnion(self.next_out.*);
        return changed;
    }
};

const testing = std.testing;
const frontend = @import("frontend.zig");
const source = @import("source.zig");
const diamond = "function w $f(w %p) {\n@entry\njnz %p, @left, @right\n@left\n%a =w copy 1\njmp @join\n@right\n%b =w copy 2\njmp @join\n@join\n%r =w phi @left %a, @right %b\nret %r\n}";
fn parse(allocator: std.mem.Allocator, text: []const u8) !@import("module.zig").Module {
    var diagnostic: ?source.Diagnostic = null;
    return frontend.parse(allocator, .{ .name = "live-test", .text = text }, &diagnostic);
}
fn blockId(index: usize) ir.BlockId {
    return @fromBackingInt(@as(u32, @intCast(index)));
}
fn valueId(index: usize) ir.ValueId {
    return @fromBackingInt(@as(u32, @intCast(index)));
}

test "phi inputs are live on their own predecessor edge, not at the join" {
    var module = try parse(testing.allocator, diamond);
    defer module.deinit();
    const f = module.functions.items[0];
    var live = try Snapshot.init(testing.allocator, f, .{});
    defer live.deinit();
    const a = f.blocks.items[1].instructions.items[0].result().?;
    const b = f.blocks.items[2].instructions.items[0].result().?;
    const phi = f.blocks.items[3].phis.items[0].result;
    try testing.expect(live.isLiveOut(blockId(1), a).?);
    try testing.expect(!live.isLiveOut(blockId(1), b).?);
    try testing.expect(live.isLiveOut(blockId(2), b).?);
    try testing.expect(!live.isLiveOut(blockId(2), a).?);
    try testing.expect(!live.isLiveIn(blockId(3), a).?);
    try testing.expect(!live.isLiveIn(blockId(3), b).?);
    try testing.expect(!live.isLiveIn(blockId(3), phi).?);
    try testing.expect(!live.isLiveIn(blockId(0), f.parameters.items[0]).?);
    try testing.expect(live.isLiveIn(blockId(100), a) == null);
    try testing.expect(live.isLiveOut(blockId(1), valueId(100)) == null);
}

fn matches(operand: ir.Operand, value: ir.ValueId) bool {
    return operand == .value and operand.value == value;
}
fn instructionUses(instruction: ir.Instruction, value: ir.ValueId) bool {
    return switch (instruction) {
        .blit => |blit| matches(blit.source, value) or matches(blit.destination, value),
        .load => |load| matches(load.address, value),
        .store => |store| matches(store.value, value) or matches(store.address, value),
        .call => |call| found: {
            if (call.callee.addressOperand()) |address| if (matches(address, value)) break :found true;
            for (call.arguments) |argument| if (matches(argument.operand, value)) break :found true;
            break :found false;
        },
        .copy => |c| matches(c.operand, value),
        .unary => |u| matches(u.operand, value),
        .convert => |c| matches(c.operand, value),
        .binary => |b| matches(b.lhs, value) or matches(b.rhs, value),
        .shift => |s| matches(s.value, value) or matches(s.amount, value),
        .compare_integer => |c| matches(c.lhs, value) or matches(c.rhs, value),
        .compare_float => |c| matches(c.lhs, value) or matches(c.rhs, value),
    };
}
// Separate reachability oracle: search for a use before redefinition, one value
// at a time. It neither constructs block-use sets nor solves bitset equations.
fn oracle(function: *const ir.Function, graph: *const cfg.Graph, block: usize, value: ir.ValueId, at_exit: bool) !bool {
    const visited = try testing.allocator.alloc(bool, function.blocks.items.len);
    defer testing.allocator.free(visited);
    @memset(visited, false);
    var queue: std.ArrayList(usize) = .empty;
    defer queue.deinit(testing.allocator);
    if (!at_exit) {
        try queue.append(testing.allocator, block);
        visited[block] = true;
    }
    const begin: ?usize = if (at_exit) block else null;
    var initial = begin;
    var cursor: usize = 0;
    while (initial != null or cursor < queue.items.len) {
        const exit_only = initial != null;
        const b = initial orelse queue.items[cursor];
        if (initial != null) initial = null else cursor += 1;
        const current = function.blocks.items[b];
        if (!exit_only) {
            if (b == 0 and std.mem.indexOfScalar(ir.ValueId, function.parameters.items, value) != null) continue;
            var killed = false;
            for (current.phis.items) |phi| {
                if (phi.result == value) {
                    killed = true;
                    break;
                }
            }
            if (killed) continue;
            for (current.instructions.items) |instruction| {
                if (instructionUses(instruction, value)) return true;
                if (instruction.result() == value) {
                    killed = true;
                    break;
                }
            }
            if (killed) continue;
            switch (current.terminator.?) {
                .jump, .halt => {},
                .branch => |branch| if (matches(branch.condition, value)) return true,
                .return_value => |operand| if (operand) |o| {
                    if (matches(o, value)) return true;
                },
            }
        }
        for (graph.successors[b].slice()) |successor| {
            const s = @backingInt(successor);
            for (function.blocks.items[s].phis.items) |phi| {
                for (phi.inputs) |input| if (@backingInt(input.predecessor) == b and matches(input.value, value)) return true;
            }
            if (!visited[s]) {
                visited[s] = true;
                try queue.append(testing.allocator, s);
            }
        }
    }
    return false;
}
fn compareOracle(function: *const ir.Function) !void {
    var graph = try cfg.Graph.init(testing.allocator, function);
    defer graph.deinit();
    var live = try Snapshot.init(testing.allocator, function, .{});
    defer live.deinit();
    for (0..function.blocks.items.len) |b| for (0..function.values.items.len) |v| {
        try testing.expectEqual(try oracle(function, &graph, b, valueId(v), false), live.isLiveIn(blockId(b), valueId(v)).?);
        try testing.expectEqual(try oracle(function, &graph, b, valueId(v), true), live.isLiveOut(blockId(b), valueId(v)).?);
    };
}

test "phi swaps loops mixed scalar instructions and diamonds match path oracle" {
    var module = try parse(testing.allocator, diamond ++ "\n" ++ @embedFile("fixtures/phi-loop.ssa") ++ "\n" ++ @embedFile("fixtures/compare-loop.ssa") ++ "\n" ++ @embedFile("fixtures/float-operations.ssa") ++ "\n" ++ @embedFile("fixtures/halt.ssa") ++ "\n" ++ @embedFile("fixtures/direct-calls.ssa") ++ "\n" ++ @embedFile("fixtures/void-calls.ssa") ++ "\n" ++ @embedFile("fixtures/indirect-calls.ssa") ++ "\n" ++ @embedFile("fixtures/scalar-memory.ssa") ++ "\n" ++ @embedFile("fixtures/blit.ssa") ++ "\n" ++ @embedFile("fixtures/signed-conversions.ssa") ++ "\n" ++ @embedFile("fixtures/signed-conversion-loop.ssa") ++ "\n" ++ @embedFile("fixtures/unsigned-conversions.ssa") ++ "\n" ++ @embedFile("fixtures/unsigned-conversion-loop.ssa"));
    defer module.deinit();
    for (module.functions.items) |f| try compareOracle(f);
}

test "snapshot outlives input IR and accounts for unreachable blocks" {
    var module = try parse(testing.allocator, "function w $f(w %p) {\n@entry\nret 1\n@dead\n%x =w add %p, 1\nret %x\n}");
    var live = try Snapshot.init(testing.allocator, module.functions.items[0], .{});
    defer live.deinit();
    module.deinit();
    try testing.expect(live.isLiveIn(blockId(1), valueId(0)).?);
    try testing.expect(!live.isLiveOut(blockId(0), valueId(0)).?);
    try testing.expect(!live.isLiveIn(blockId(0), valueId(0)).?);
}

test "empty value frames limits and invalid SSA are explicit" {
    var module = try parse(testing.allocator, "function $f() {\n@b\nret\n}");
    defer module.deinit();
    var live = try Snapshot.init(testing.allocator, module.functions.items[0], .{});
    defer live.deinit();
    try testing.expect(live.isLiveIn(blockId(0), valueId(0)) == null);
    try testing.expectError(error.LivenessTooLarge, Snapshot.init(testing.allocator, module.functions.items[0], .{ .max_matrix_bytes = 0 }));
    try testing.expectError(error.LivenessTooLarge, matrixBytes(std.math.maxInt(usize), 1));
    try testing.expectError(error.LivenessTooLarge, matrixBytes(1, std.math.maxInt(usize)));
    var invalid = try parse(testing.allocator, "function w $f() {\n@b\n%x =w add %y, 1\n%y =w copy 2\nret %x\n}");
    defer invalid.deinit();
    try testing.expectError(error.InvalidSSA, Snapshot.init(testing.allocator, invalid.functions.items[0], .{}));
}

fn exercise(allocator: std.mem.Allocator) !void {
    var module = try parse(allocator, diamond);
    defer module.deinit();
    var live = try Snapshot.init(allocator, module.functions.items[0], .{});
    defer live.deinit();
    try testing.expect(live.isLiveOut(blockId(1), valueId(1)).?);
}

test "every liveness allocation failure frees partial bitset rows and CFG scratch" {
    try @import("test_support.zig").checkAllocationFailures(exercise);
}

test "64 generated cyclic CFGs agree with per-value use-before-definition search" {
    for (0..64) |seed| {
        var f = ir.Function.init(testing.allocator, @fromBackingInt(@as(u32, 0)), .word);
        defer f.deinit();
        const parameter = try f.addParameter(.word);
        const count = 5 + seed % 5;
        var blocks: [9]ir.BlockId = undefined;
        for (blocks[0..count]) |*b| b.* = try f.addBlock(null);
        var bases: [3]ir.ValueId = undefined;
        for (&bases, 0..) |*v, i| v.* = try f.appendCopy(blocks[0], .word, .{ .constant = .{ .word = @intCast(i) } });
        var state: u32 = @intCast(seed + 1);
        for (blocks[0..count], 0..) |b, index| {
            state = state *% 1664525 +% 1013904223;
            const local = try f.appendBinary(b, .word, .add, .{ .value = bases[state % bases.len] }, .{ .value = parameter });
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

test "mixed scalar corpus liveness matches path oracle without altering IR" {
    var module = try parse(testing.allocator, @embedFile("fixtures/mixed-programs.ssa"));
    defer module.deinit();
    for (module.functions.items) |f| try compareOracle(f);
}
