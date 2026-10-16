//! Owned simulated bytes. Synthetic IL addresses are never host pointers.
const std = @import("std");
const ir = @import("ir.zig");
pub const Error = error{ InvalidMemoryRange, MemoryOutOfBounds, PartialMemoryOverlap, TypeMismatch };
pub const Options = struct {
    /// Zero stays outside the image, so an IL null address is never valid.
    base: u64 = 0x10000,
    endian: std.builtin.Endian = .little,
};

/// Fixed-size, zero-initialized, caller-owned image. Do not copy ownership.
/// Bytes may be initialized/inspected directly; do not replace the owned slice.
pub const Image = struct {
    allocator: std.mem.Allocator,
    bytes: []u8,
    base: u64,
    endian: std.builtin.Endian,

    pub fn init(allocator: std.mem.Allocator, byte_count: usize, options: Options) (std.mem.Allocator.Error || Error)!Image {
        if (options.base == 0) return error.InvalidMemoryRange;
        if (byte_count != 0 and byte_count - 1 > std.math.maxInt(u64) - options.base) return error.InvalidMemoryRange;
        const bytes = try allocator.alloc(u8, byte_count);
        @memset(bytes, 0);
        return .{ .allocator = allocator, .bytes = bytes, .base = options.base, .endian = options.endian };
    }

    pub fn deinit(self: *Image) void {
        self.allocator.free(self.bytes);
        self.* = undefined;
    }

    /// Only in-image byte addresses; no host conversion or one-past address.
    pub fn addressAt(self: *const Image, offset: usize) Error!u64 {
        if (offset >= self.bytes.len) return error.MemoryOutOfBounds;
        return std.math.add(u64, self.base, std.math.cast(u64, offset) orelse return error.MemoryOutOfBounds) catch error.MemoryOutOfBounds;
    }

    pub fn read(self: *const Image, kind: ir.LoadKind, result_type: ir.ScalarType, address: u64) Error!ir.Constant {
        if (!kind.accepts(result_type)) return error.TypeMismatch;
        const bytes = try self.access(address, loadWidth(kind));
        const bits: u64 = switch (kind) {
            .signed_byte => @bitCast(@as(i64, std.mem.readInt(i8, bytes[0..1], self.endian))),
            .unsigned_byte => bytes[0],
            .signed_half => @bitCast(@as(i64, std.mem.readInt(i16, bytes[0..2], self.endian))),
            .unsigned_half => std.mem.readInt(u16, bytes[0..2], self.endian),
            .signed_word => @bitCast(@as(i64, std.mem.readInt(i32, bytes[0..4], self.endian))),
            .unsigned_word, .single => std.mem.readInt(u32, bytes[0..4], self.endian),
            .long, .double => std.mem.readInt(u64, bytes[0..8], self.endian),
        };
        return switch (result_type) {
            .word => .{ .word = @truncate(bits) },
            .long => .{ .long = bits },
            .single => .{ .single_bits = @truncate(bits) },
            .double => .{ .double_bits = bits },
        };
    }

    /// Check type and entire extent before the first write. No partial failures.
    pub fn write(self: *Image, kind: ir.StoreKind, value: ir.Constant, address: u64) Error!void {
        if (kind.valueType() != value.scalarType()) return error.TypeMismatch;
        const width = storeWidth(kind);
        const bytes = try self.access(address, width);
        const bits: u64 = switch (value) {
            .word => |v| v,
            .long => |v| v,
            .single_bits => |v| v,
            .double_bits => |v| v,
        };
        switch (kind) {
            .byte => bytes[0] = @truncate(bits),
            .half => std.mem.writeInt(u16, bytes[0..2], @truncate(bits), self.endian),
            .word, .single => std.mem.writeInt(u32, bytes[0..4], @truncate(bits), self.endian),
            .long, .double => std.mem.writeInt(u64, bytes[0..8], bits, self.endian),
        }
    }

    /// Zero length touches no address. Check both complete spans and overlap
    /// before mutation. Exact aliases are allowed; partial overlap is not.
    pub fn copy(self: *Image, source_address: u64, destination_address: u64, byte_count: usize) Error!void {
        if (byte_count == 0) return;
        const src = try self.access(source_address, byte_count);
        const dst = try self.access(destination_address, byte_count);
        if (source_address == destination_address) return;
        const distance = if (source_address < destination_address) destination_address - source_address else source_address - destination_address;
        if (distance < byte_count) return error.PartialMemoryOverlap;
        std.mem.copyForwards(u8, dst, src);
    }

    fn access(self: *const Image, address: u64, width: usize) Error![]u8 {
        if (address < self.base or width - 1 > std.math.maxInt(u64) - address) return error.MemoryOutOfBounds;
        const offset = std.math.cast(usize, address - self.base) orelse return error.MemoryOutOfBounds;
        if (offset > self.bytes.len or width > self.bytes.len - offset) return error.MemoryOutOfBounds;
        return self.bytes[offset..][0..width];
    }
};

pub fn loadWidth(kind: ir.LoadKind) usize {
    return switch (kind) {
        .signed_byte, .unsigned_byte => 1,
        .signed_half, .unsigned_half => 2,
        .signed_word, .unsigned_word, .single => 4,
        .long, .double => 8,
    };
}

pub fn storeWidth(kind: ir.StoreKind) usize {
    return switch (kind) {
        .byte => 1,
        .half => 2,
        .word, .single => 4,
        .long, .double => 8,
    };
}
