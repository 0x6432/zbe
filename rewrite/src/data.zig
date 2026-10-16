//! Owned numeric/zero-fill data, independent of target endian encoding.
const std = @import("std");
const symbols = @import("symbols.zig");
pub const max_object_bytes = 16 * 1024 * 1024;
pub const max_module_bytes = 64 * 1024 * 1024;
pub const Error = std.mem.Allocator.Error || error{ DataTooLarge, InvalidDataSize };
pub const Alignment = enum(u8) {
    one = 1,
    two = 2,
    four = 4,
    eight = 8,
    sixteen = 16,
    thirty_two = 32,
    sixty_four = 64,
    pub fn fromBytes(count: u64) error{InvalidAlignment}!Alignment {
        return switch (count) {
            1 => .one,
            2 => .two,
            4 => .four,
            8 => .eight,
            16 => .sixteen,
            32 => .thirty_two,
            64 => .sixty_four,
            else => error.InvalidAlignment,
        };
    }
    pub fn bytes(self: Alignment) u8 {
        return @backingInt(self);
    }
};
/// Numeric fields retain exact width/bit patterns. No implicit field padding.
pub const Item = union(enum) {
    byte: u8,
    half: u16,
    word: u32,
    long: u64,
    single_bits: u32,
    double_bits: u64,
    zero: u32,
    pub fn size(self: Item) usize {
        return switch (self) {
            .byte => 1,
            .half => 2,
            .word, .single_bits => 4,
            .long, .double_bits => 8,
            .zero => |count| count,
        };
    }
};
pub const Data = struct {
    allocator: std.mem.Allocator,
    name: symbols.Id,
    linkage: enum { internal, exported } = .internal,
    alignment: Alignment = .eight,
    items: std.ArrayList(Item) = .empty,
    byte_len: usize = 0,
    pub fn init(allocator: std.mem.Allocator, name: symbols.Id) Data {
        return .{ .allocator = allocator, .name = name };
    }
    pub fn deinit(self: *Data) void {
        self.items.deinit(self.allocator);
        self.* = undefined;
    }
    /// Reserve before publishing either the item or its checked logical size.
    pub fn append(self: *Data, item: Item) Error!void {
        const total = std.math.add(usize, self.byte_len, item.size()) catch return error.DataTooLarge;
        if (total > max_object_bytes) return error.DataTooLarge;
        try self.items.append(self.allocator, item);
        self.byte_len = total;
    }
    /// Public storage may have been edited: never trust the cached size.
    pub fn validate(self: *const Data) Error!usize {
        var total: usize = 0;
        for (self.items.items) |item| {
            total = std.math.add(usize, total, item.size()) catch return error.DataTooLarge;
            if (total > max_object_bytes) return error.DataTooLarge;
        }
        if (total != self.byte_len) return error.InvalidDataSize;
        return total;
    }
};
