//! Evaluation-owned initialized module data; never host/linker addresses.
const std = @import("std");
const data = @import("data.zig");
const Module = @import("module.zig").Module;
const SymbolId = @import("symbols.zig").Id;
pub const Options = struct {
    base: u64 = 0x200000000,
    max_bytes: usize = 1024 * 1024,
    endian: std.builtin.Endian = .little,
};
pub const Error = data.Error || error{
    InvalidGlobalRange,
    GlobalLimitExceeded,
    UnsupportedGlobalInitializer,
    GlobalsRequireModule,
    GlobalAddressOverflow,
};

/// Validate the entire configured reservation, not only initialized payloads.
pub fn lastAddress(options: Options) Error!?u64 {
    if (options.base == 0 or options.base % 64 != 0) return error.InvalidGlobalRange;
    if (options.max_bytes == 0) return null;
    const offset = std.math.cast(u64, options.max_bytes - 1) orelse return error.InvalidGlobalRange;
    return std.math.add(u64, options.base, offset) catch error.InvalidGlobalRange;
}

const Object = struct { symbol: SymbolId, address: u64, bytes: []u8 };
const Placement = struct { offset: usize, next: usize };
fn placement(used: usize, alignment: usize, length: usize, limit: usize) Error!Placement {
    const padded = std.math.add(usize, used, alignment - 1) catch return error.GlobalLimitExceeded;
    const offset = padded & ~(alignment - 1);
    const end = std.math.add(usize, offset, length) catch return error.GlobalLimitExceeded;
    const next = std.math.add(usize, end, 16) catch return error.GlobalLimitExceeded;
    if (next > limit) return error.GlobalLimitExceeded;
    return .{ .offset = offset, .next = next };
}

/// Internal owned value: do not copy. Module validation precedes execution;
/// init also validates data lengths before ever writing packed payload slices.
pub const Space = struct {
    allocator: std.mem.Allocator,
    options: Options,
    objects: []Object,

    pub fn init(allocator: std.mem.Allocator, module: *const Module, options: Options) Error!Space {
        _ = try lastAddress(options);
        _ = try module.dataSize();
        var used: usize = 0;
        // Complete layout/initializer preflight before allocating table/payloads.
        for (module.data.items) |object| {
            for (object.items.items) |item| if (item == .symbol_address) return error.UnsupportedGlobalInitializer;
            used = (try placement(used, object.alignment.bytes(), object.byte_len, options.max_bytes)).next;
        }
        const objects = try allocator.alloc(Object, module.data.items.len);
        var initialized: usize = 0;
        errdefer {
            for (objects[0..initialized]) |object| allocator.free(object.bytes);
            allocator.free(objects);
        }
        used = 0;
        for (module.data.items, objects) |source, *object| {
            const here = try placement(used, source.alignment.bytes(), source.byte_len, options.max_bytes);
            const bytes = try allocator.alloc(u8, source.byte_len);
            @memset(bytes, 0);
            var offset: usize = 0;
            for (source.items.items) |item| {
                switch (item) {
                    .byte => |bits| bytes[offset] = bits,
                    .half => |bits| std.mem.writeInt(u16, bytes[offset..][0..2], bits, options.endian),
                    .word, .single_bits => |bits| std.mem.writeInt(u32, bytes[offset..][0..4], bits, options.endian),
                    .long, .double_bits => |bits| std.mem.writeInt(u64, bytes[offset..][0..8], bits, options.endian),
                    .bytes => |text| std.mem.copyForwards(u8, bytes[offset..][0..text.len], text),
                    .zero => {},
                    .symbol_address => unreachable, // Eager preflight above.
                }
                offset += item.size();
            }
            object.* = .{ .symbol = source.name, .address = options.base + @as(u64, @intCast(here.offset)), .bytes = bytes };
            initialized += 1;
            used = here.next;
        }
        return .{ .allocator = allocator, .options = options, .objects = objects };
    }
    pub fn deinit(self: *Space) void {
        for (self.objects) |object| self.allocator.free(object.bytes);
        self.allocator.free(self.objects);
        self.* = undefined;
    }
    pub fn address(self: *const Space, symbol: SymbolId) ?u64 {
        for (self.objects) |object| if (object.symbol == symbol) return object.address;
        return null;
    }
    pub fn access(self: *Space, address_value: u64, width: usize) ?[]u8 {
        std.debug.assert(width > 0);
        for (self.objects) |object| {
            if (address_value < object.address) continue;
            const offset = std.math.cast(usize, address_value - object.address) orelse continue;
            if (offset <= object.bytes.len and width <= object.bytes.len - offset) return object.bytes[offset..][0..width];
        }
        return null;
    }
};
