const std = @import("std");
const Allocator = std.mem.Allocator;

/// Scoped to its owning Pool. Not interchangeable with a value or block ID.
pub const Id = enum(u32) { _ };

/// Bounded source/native spelling, not Pool's general string-key contract.
/// Reserve private labels and ELF relocation/version syntax even inside quotes.
pub fn validPortableName(name: []const u8) bool {
    if (name.len == 0 or std.mem.eql(u8, name, ".") or std.mem.startsWith(u8, name, ".Lzbe@")) return false;
    for (name) |byte| if (byte < 32 or byte > 126 or byte == '@') return false;
    return true;
}

/// Owns strings individually: returned string slices survive table growth.
/// The allocator must outlive this pool; deinit exactly once after use.
pub const Pool = struct {
    allocator: Allocator,
    names: std.ArrayList([]const u8) = .empty,
    index: std.StringHashMapUnmanaged(Id) = .empty,

    pub fn init(allocator: Allocator) Pool {
        return .{ .allocator = allocator };
    }

    pub fn deinit(self: *Pool) void {
        self.index.deinit(self.allocator);
        for (self.names.items) |name| self.allocator.free(name);
        self.names.deinit(self.allocator);
        self.* = undefined;
    }

    pub fn intern(self: *Pool, name: []const u8) (Allocator.Error || error{TooManySymbols})!Id {
        if (self.index.get(name)) |id| return id;
        const number = std.math.cast(u32, self.names.items.len) orelse return error.TooManySymbols;
        // Reserve first: failure may grow capacity but cannot publish half an entry.
        try self.names.ensureUnusedCapacity(self.allocator, 1);
        try self.index.ensureUnusedCapacity(self.allocator, 1);
        const owned = try self.allocator.dupe(u8, name);
        const id: Id = @fromBackingInt(@intCast(number));
        self.names.appendAssumeCapacity(owned);
        self.index.putAssumeCapacity(owned, id);
        return id;
    }

    pub fn get(self: *const Pool, id: Id) ?[]const u8 {
        const number = @backingInt(id);
        return if (number < self.names.items.len) self.names.items[number] else null;
    }
};

test "symbols own input, deduplicate and reject out-of-range IDs" {
    var pool = Pool.init(std.testing.allocator);
    defer pool.deinit();
    var input = "alpha".*;
    const a = try pool.intern(&input);
    @memset(&input, 'x');
    try std.testing.expectEqualStrings("alpha", pool.get(a).?);
    try std.testing.expectEqual(a, try pool.intern("alpha"));
    try std.testing.expect(pool.get(@fromBackingInt(@intCast(99))) == null);
    const empty = try pool.intern("");
    try std.testing.expectEqualStrings("", pool.get(empty).?);
}

fn exercise(allocator: Allocator) !void {
    var pool = Pool.init(allocator);
    defer pool.deinit();
    const first = try pool.intern("first");
    const stable = pool.get(first).?;
    var buffer: [32]u8 = undefined;
    for (0..96) |n| {
        const name = try std.fmt.bufPrint(&buffer, "name.{d}", .{n});
        const id = try pool.intern(name);
        try std.testing.expectEqual(id, try pool.intern(name));
        try std.testing.expectEqualStrings(name, pool.get(id).?);
    }
    try std.testing.expectEqualStrings("first", stable);
    try std.testing.expectEqual(@intFromPtr(stable.ptr), @intFromPtr(pool.get(first).?.ptr));
}

test "symbol growth and every allocation failure clean up ownership" {
    try @import("test_support.zig").checkAllocationFailures(exercise);
}
