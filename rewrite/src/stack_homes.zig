//! Deterministic greedy coloring of scalar interference into eight-byte homes.
//! No physical register assignment, spill insertion or minimum-color claim.
const std = @import("std");
const ir = @import("ir.zig");
const interference = @import("interference.zig");
pub const Error = interference.Error;
pub const SlotId = enum(u32) { _ };

/// Owned snapshot. Slot and value IDs are scoped to this function/layout.
pub const Layout = struct {
    allocator: std.mem.Allocator,
    slots: []const SlotId,
    slot_count: usize,

    pub fn init(allocator: std.mem.Allocator, function: *const ir.Function, options: interference.Options) Error!Layout {
        var graph = try interference.Graph.init(allocator, function, options);
        defer graph.deinit();
        const slots = try allocator.alloc(SlotId, graph.value_count);
        errdefer allocator.free(slots);
        var occupied = try std.bit_set.Dynamic.initEmpty(allocator, graph.value_count);
        defer occupied.deinit(allocator);
        var slot_count: usize = 0;
        for (slots, 0..) |*assigned_slot, value| {
            occupied.unsetAll();
            for (slots[0..value], 0..) |previous_slot, previous| {
                if (graph.interferes(valueId(value), valueId(previous)).?) occupied.set(@backingInt(previous_slot));
            }
            var chosen: usize = 0;
            while (chosen < slot_count and occupied.isSet(chosen)) chosen += 1;
            if (chosen == slot_count) slot_count += 1;
            assigned_slot.* = @fromBackingInt(@as(u32, @intCast(chosen)));
        }
        return .{ .allocator = allocator, .slots = slots, .slot_count = slot_count };
    }

    pub fn deinit(self: *Layout) void {
        self.allocator.free(self.slots);
        self.* = undefined;
    }

    pub fn slot(self: *const Layout, value: ir.ValueId) ?SlotId {
        const index = @backingInt(value);
        if (index >= self.slots.len) return null;
        return self.slots[index];
    }
};

fn valueId(index: usize) ir.ValueId {
    return @fromBackingInt(@as(u32, @intCast(index)));
}
const testing = std.testing;
const frontend = @import("frontend.zig");
const source = @import("source.zig");
fn parse(allocator: std.mem.Allocator, text: []const u8) !@import("module.zig").Module {
    var diagnostic: ?source.Diagnostic = null;
    return frontend.parse(allocator, .{ .name = "stack-homes-test", .text = text }, &diagnostic);
}
fn verify(function: *const ir.Function) !void {
    var layout = try Layout.init(testing.allocator, function, .{});
    defer layout.deinit();
    var again = try Layout.init(testing.allocator, function, .{});
    defer again.deinit();
    try testing.expectEqual(layout.slot_count, again.slot_count);
    try testing.expectEqualSlices(SlotId, layout.slots, again.slots);
    var graph = try interference.Graph.init(testing.allocator, function, .{});
    defer graph.deinit();
    var assigned = try std.bit_set.Dynamic.initEmpty(testing.allocator, layout.slot_count);
    defer assigned.deinit(testing.allocator);
    for (layout.slots, 0..) |slot, value| {
        try testing.expect(@backingInt(slot) < layout.slot_count);
        assigned.set(@backingInt(slot));
        for (layout.slots[0..value], 0..) |other, previous| {
            if (graph.interferes(valueId(value), valueId(previous)).?) try testing.expect(slot != other);
        }
    }
    try testing.expectEqual(layout.slot_count, assigned.count());
}

test "a dying scalar chain shares one slot across widths and classes" {
    var module = try parse(testing.allocator, "function l $f(w %a) {\n@entry\n%s =s cast %a\n%d =d exts %s\n%b =l cast %d\n%c =l add %b, 1\nret %c\n}");
    defer module.deinit();
    var layout = try Layout.init(testing.allocator, module.functions.items[0], .{});
    defer layout.deinit();
    try testing.expectEqual(@as(usize, 1), layout.slot_count);
    for (layout.slots) |slot| try testing.expectEqual(@as(u32, 0), @backingInt(slot));
    try verify(module.functions.items[0]);
}

test "dead writes and parameter bundles keep live homes distinct" {
    var module = try parse(testing.allocator, "function w $f(w %p, w %unused) {\n@entry\n%a =w copy 1\n%dead =w copy 2\n%r =w add %p, %a\nret %r\n}");
    defer module.deinit();
    var layout = try Layout.init(testing.allocator, module.functions.items[0], .{});
    defer layout.deinit();
    try testing.expectEqual(@as(usize, 3), layout.slot_count);
    try testing.expect(layout.slot(valueId(0)).? != layout.slot(valueId(1)).?);
    try testing.expect(layout.slot(valueId(3)).? != layout.slot(valueId(0)).?);
    try testing.expect(layout.slot(valueId(3)).? != layout.slot(valueId(2)).?);
    try verify(module.functions.items[0]);
}

test "layout owns slots independently and handles zero values and invalid IDs" {
    var module = try parse(testing.allocator, "function w $f() {\n@b\n%a =w copy 1\nret %a\n}");
    var layout = try Layout.init(testing.allocator, module.functions.items[0], .{});
    defer layout.deinit();
    module.deinit();
    try testing.expectEqual(@as(u32, 0), @backingInt(layout.slot(valueId(0)).?));
    try testing.expect(layout.slot(valueId(1)) == null);
    var empty = try parse(testing.allocator, "function $f() {\n@b\nret\n}");
    defer empty.deinit();
    var no_slots = try Layout.init(testing.allocator, empty.functions.items[0], .{});
    defer no_slots.deinit();
    try testing.expectEqual(@as(usize, 0), no_slots.slot_count);
    try testing.expect(no_slots.slot(valueId(0)) == null);
}

test "all mixed-program and parallel-phi layouts are deterministic proper colorings" {
    var module = try parse(testing.allocator, @embedFile("fixtures/mixed-programs.ssa") ++ "\n" ++ @embedFile("fixtures/phi-loop.ssa") ++ "\n" ++ @embedFile("fixtures/float-operations.ssa"));
    defer module.deinit();
    for (module.functions.items) |f| try verify(f);
}

test "storage limits and invalid SSA do not return partial layouts" {
    var module = try parse(testing.allocator, "function w $f(w %a) {\n@b\nret %a\n}");
    defer module.deinit();
    const f = module.functions.items[0];
    try testing.expectError(error.InterferenceTooLarge, Layout.init(testing.allocator, f, .{ .max_graph_bytes = 0 }));
    try testing.expectError(error.LivenessTooLarge, Layout.init(testing.allocator, f, .{ .max_liveness_matrix_bytes = 0 }));
    var invalid = try parse(testing.allocator, "function w $f() {\n@b\n%x =w add %y, 1\n%y =w copy 2\nret %x\n}");
    defer invalid.deinit();
    try testing.expectError(error.InvalidSSA, Layout.init(testing.allocator, invalid.functions.items[0], .{}));
}

fn exercise(allocator: std.mem.Allocator) !void {
    var module = try parse(allocator, @embedFile("fixtures/phi-loop.ssa"));
    defer module.deinit();
    var layout = try Layout.init(allocator, module.functions.items[0], .{});
    defer layout.deinit();
    try testing.expect(layout.slot_count > 0);
}
test "every layout allocation failure frees colors graph liveness and scratch" {
    try @import("test_support.zig").checkAllocationFailures(exercise);
}
