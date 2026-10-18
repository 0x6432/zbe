//! Invocation-owned synthetic objects plus a borrowed, never resized Image.
const std = @import("std");
const ir = @import("ir.zig");
const memory = @import("memory.zig");
const global_memory = @import("global_memory.zig");
pub const GlobalOptions = global_memory.Options;
pub const StackOptions = struct {
    base: u64 = 0x100000000,
    max_bytes: usize = 1024 * 1024,
    endian: std.builtin.Endian = .little,
};
pub const Error = memory.Error || global_memory.Error || std.mem.Allocator.Error || error{
    InvalidStackRange,
    AllocationSizeOverflow,
    StackLimitExceeded,
    UninitializedMemory,
    UnsupportedAllocation,
    UnsupportedMemory,
};

const Object = struct {
    address: u64,
    bytes: []u8,
    initialized: []bool,

    fn deinit(self: Object, allocator: std.mem.Allocator) void {
        allocator.free(self.bytes);
        allocator.free(self.initialized);
    }
};
const Span = struct {
    bytes: []u8,
    initialized: ?[]bool,
    endian: std.builtin.Endian,

    fn requireInitialized(self: Span) Error!void {
        if (self.initialized) |defined| for (defined) |byte| {
            if (!byte) return error.UninitializedMemory;
        };
    }
    fn define(self: Span) void {
        if (self.initialized) |defined| @memset(defined, true);
    }
};

/// Immutable initial cursors/pointers, not an owner of the backing object.
pub const VariadicState = struct {
    general_offset: u32,
    vector_offset: u32,
    overflow: u64,
    save: u64,
};

// Synthetic layout only: no machine registers or host ABI storage are touched.
const VariadicCursor = struct {
    general: u32 = 0,
    vector: u32 = 0,
    overflow: usize = 0,

    fn next(self: *VariadicCursor, ty: ir.ScalarType) Error!usize {
        if (ty.isInteger() and self.general < 6) {
            const offset = self.general * 8;
            self.general += 1;
            return offset;
        }
        if (!ty.isInteger() and self.vector < 8) {
            const offset = 48 + self.vector * 16;
            self.vector += 1;
            return offset;
        }
        const offset = std.math.mul(usize, self.overflow, 8) catch return error.StackLimitExceeded;
        self.overflow = std.math.add(usize, self.overflow, 1) catch return error.StackLimitExceeded;
        return std.math.add(usize, 176, offset) catch error.StackLimitExceeded;
    }
    fn size(self: VariadicCursor) Error!usize {
        const overflow = std.math.mul(usize, self.overflow, 8) catch return error.StackLimitExceeded;
        return std.math.add(usize, 176, overflow) catch error.StackLimitExceeded;
    }
};

/// Owns all stack bytes/metadata. Image remains caller-owned. Do not copy.
/// Public for direct internal tests; the supported caller API is Options.
pub const Space = struct {
    allocator: std.mem.Allocator,
    image: ?*memory.Image,
    stack: ?StackOptions,
    globals: ?global_memory.Space = null,
    used: usize = 0,
    objects: std.ArrayList(Object) = .empty,

    pub fn init(allocator: std.mem.Allocator, image: ?*memory.Image, stack: ?StackOptions) Error!Space {
        if (stack) |options| {
            if (options.base == 0 or options.base % 16 != 0) return error.InvalidStackRange;
            if (options.max_bytes != 0) {
                const last_offset = std.math.cast(u64, options.max_bytes - 1) orelse return error.InvalidStackRange;
                const last = std.math.add(u64, options.base, last_offset) catch return error.InvalidStackRange;
                if (image) |borrowed| if (borrowed.bytes.len != 0) {
                    const image_last = borrowed.base + @as(u64, @intCast(borrowed.bytes.len - 1));
                    if (options.base <= image_last and borrowed.base <= last) return error.InvalidStackRange;
                };
            }
        }
        return .{ .allocator = allocator, .image = image, .stack = stack };
    }

    pub fn initForModule(allocator: std.mem.Allocator, image: ?*memory.Image, stack: ?StackOptions, module: ?*const @import("module.zig").Module, globals: ?GlobalOptions) Error!Space {
        var space = try init(allocator, image, stack);
        errdefer space.deinit();
        if (globals) |options| {
            const owner = module orelse return error.GlobalsRequireModule;
            if (try global_memory.lastAddress(options)) |last| {
                if (image) |borrowed| if (borrowed.bytes.len != 0) {
                    const image_last = borrowed.base + @as(u64, @intCast(borrowed.bytes.len - 1));
                    if (options.base <= image_last and borrowed.base <= last) return error.InvalidGlobalRange;
                };
                if (stack) |reserved| if (reserved.max_bytes != 0) {
                    const stack_last = reserved.base + @as(u64, @intCast(reserved.max_bytes - 1));
                    if (options.base <= stack_last and reserved.base <= last) return error.InvalidGlobalRange;
                };
            }
            space.globals = try global_memory.Space.init(allocator, owner, options);
        }
        return space;
    }

    pub fn symbolAddress(self: *const Space, symbol: @import("symbols.zig").Id, addend: i32) (global_memory.Error || error{UnsupportedSymbolAddress})!u64 {
        const globals = if (self.globals) |*globals| globals else return error.UnsupportedSymbolAddress;
        const address = globals.address(symbol) orelse return error.UnsupportedSymbolAddress;
        return if (addend < 0)
            std.math.sub(u64, address, @intCast(-@as(i64, addend))) catch error.GlobalAddressOverflow
        else
            std.math.add(u64, address, @intCast(addend)) catch error.GlobalAddressOverflow;
    }

    pub fn deinit(self: *Space) void {
        if (self.globals) |*globals| globals.deinit();
        self.releaseTo(0);
        self.objects.deinit(self.allocator);
        self.* = undefined;
    }
    pub fn mark(self: *const Space) usize {
        return self.objects.items.len;
    }
    pub fn releaseTo(self: *Space, object_count: usize) void {
        std.debug.assert(object_count <= self.objects.items.len);
        while (self.objects.items.len > object_count) self.objects.pop().?.deinit(self.allocator);
        // Do not rewind used: a later invocation must not revive stale addresses.
    }
    pub fn allocate(self: *Space, size: u64) Error!u64 {
        const options = self.stack orelse return error.UnsupportedAllocation;
        if (size == 0) return 0;
        const sum = std.math.add(u64, size, 15) catch return error.AllocationSizeOverflow;
        const rounded = sum & ~@as(u64, 15);
        const charge = std.math.add(u64, rounded, 16) catch return error.StackLimitExceeded;
        if (charge > options.max_bytes - self.used) return error.StackLimitExceeded;
        const count = std.math.cast(usize, size) orelse return error.StackLimitExceeded;
        const bytes = try self.allocator.alloc(u8, count);
        errdefer self.allocator.free(bytes);
        const initialized = try self.allocator.alloc(bool, count);
        errdefer self.allocator.free(initialized);
        @memset(initialized, false);
        const address = options.base + @as(u64, @intCast(self.used));
        try self.objects.append(self.allocator, .{ .address = address, .bytes = bytes, .initialized = initialized });
        self.used += @intCast(charge);
        return address;
    }
    pub fn read(self: *Space, kind: ir.LoadKind, ty: ir.ScalarType, address: u64) Error!ir.Constant {
        try self.requireEnabled();
        if (!kind.accepts(ty)) return error.TypeMismatch;
        const span = try self.access(address, memory.loadWidth(kind));
        try span.requireInitialized();
        const borrowed = self.view(span, address);
        return borrowed.read(kind, ty, address);
    }
    pub fn write(self: *Space, kind: ir.StoreKind, value: ir.Constant, address: u64) Error!void {
        try self.requireEnabled();
        if (kind.valueType() != value.scalarType()) return error.TypeMismatch;
        const span = try self.access(address, memory.storeWidth(kind));
        var borrowed = self.view(span, address);
        try borrowed.write(kind, value, address);
        span.define();
    }
    /// Invocation-specific explicit tail. A bad complete descriptor span fails before
    /// source allocation; no partially initialized descriptor is published.
    pub fn startVaArgs(self: *Space, state: *?VariadicState, list: u64, named: []const ir.Constant, tail: []const ir.Constant) Error!void {
        try self.requireEnabled();
        const span = try self.access(list, 24);
        const initial = state.* orelse try self.materializeVaArgs(named, tail);
        var borrowed = self.view(span, list);
        try borrowed.write(.word, .{ .word = initial.general_offset }, list);
        try borrowed.write(.word, .{ .word = initial.vector_offset }, list + 4);
        try borrowed.write(.long, .{ .long = initial.overflow }, list + 8);
        try borrowed.write(.long, .{ .long = initial.save }, list + 16);
        span.define();
        state.* = initial;
    }
    fn materializeVaArgs(self: *Space, named: []const ir.Constant, tail: []const ir.Constant) Error!VariadicState {
        var cursor: VariadicCursor = .{};
        for (named) |argument| _ = try cursor.next(argument.scalarType());
        const prefix = cursor;
        for (tail) |argument| _ = try cursor.next(argument.scalarType());
        const size = try cursor.size();
        const address = try self.allocate(std.math.cast(u64, size) orelse return error.StackLimitExceeded);
        cursor = .{};
        for ([_][]const ir.Constant{ named, tail }) |arguments| for (arguments) |argument| {
            const offset = try cursor.next(argument.scalarType());
            const kind: ir.StoreKind = switch (argument.scalarType()) {
                .word => .word,
                .long => .long,
                .single => .single,
                .double => .double,
            };
            try self.write(kind, argument, address + @as(u64, @intCast(offset)));
        };
        return .{
            .general_offset = prefix.general * 8,
            .vector_offset = 48 + prefix.vector * 16,
            .overflow = address + @as(u64, @intCast(try prefix.size())),
            .save = address,
        };
    }
    /// Consumer-only synthetic layout. Never resolves a native va_list/pointer.
    /// Checked arithmetic precedes the cursor write; a later source fault does
    /// not roll that successful write back. Byte order belongs to each region.
    pub fn consumeVaArg(self: *Space, ty: ir.ScalarType, list: u64) Error!ir.Constant {
        try self.requireEnabled();
        const field: u64 = if (ty.isInteger()) 0 else 4;
        const limit: u32 = if (ty.isInteger()) 48 else 176;
        const stride: u32 = if (ty.isInteger()) 8 else 16;
        const field_address = std.math.add(u64, list, field) catch return error.MemoryOutOfBounds;
        const offset = (try self.read(.unsigned_word, .word, field_address)).word;
        const source = if (offset < limit) register: {
            const save_field = std.math.add(u64, list, 16) catch return error.MemoryOutOfBounds;
            const save = (try self.read(.long, .long, save_field)).long;
            const address = std.math.add(u64, save, offset) catch return error.MemoryOutOfBounds;
            try self.write(.word, .{ .word = offset + stride }, field_address);
            break :register address;
        } else overflow: {
            const stack_field = std.math.add(u64, list, 8) catch return error.MemoryOutOfBounds;
            const address = (try self.read(.long, .long, stack_field)).long;
            const next = std.math.add(u64, address, 8) catch return error.MemoryOutOfBounds;
            try self.write(.long, .{ .long = next }, stack_field);
            break :overflow address;
        };
        const kind: ir.LoadKind = switch (ty) {
            .word => .unsigned_word,
            .long => .long,
            .single => .single,
            .double => .double,
        };
        return self.read(kind, ty, source);
    }
    pub fn copy(self: *Space, src: u64, dst: u64, count: usize) Error!void {
        try self.requireEnabled();
        if (count == 0) return;
        const source = try self.access(src, count);
        const destination = try self.access(dst, count);
        const distance = if (src < dst) dst - src else src - dst;
        if (src != dst and distance < count) return error.PartialMemoryOverlap;
        try source.requireInitialized();
        if (src != dst) std.mem.copyForwards(u8, destination.bytes, source.bytes);
        destination.define();
    }
    fn requireEnabled(self: *const Space) Error!void {
        if (self.image == null and self.stack == null and self.globals == null) return error.UnsupportedMemory;
    }
    fn view(self: *const Space, span: Span, address: u64) memory.Image {
        // Borrowed checked view only. Never deinit it or expose it to callers.
        return .{ .allocator = self.allocator, .bytes = span.bytes, .base = address, .endian = span.endian };
    }
    fn access(self: *Space, address: u64, width: usize) Error!Span {
        std.debug.assert(width > 0);
        if (width - 1 > std.math.maxInt(u64) - address) return error.MemoryOutOfBounds;
        if (self.image) |image| if (offsetIn(image.base, image.bytes.len, address, width)) |offset| {
            return .{ .bytes = image.bytes[offset..][0..width], .initialized = null, .endian = image.endian };
        };
        if (self.globals) |*globals| if (globals.access(address, width)) |bytes| {
            return .{ .bytes = bytes, .initialized = null, .endian = globals.options.endian };
        };
        for (self.objects.items) |object| if (offsetIn(object.address, object.bytes.len, address, width)) |offset| {
            return .{
                .bytes = object.bytes[offset..][0..width],
                .initialized = object.initialized[offset..][0..width],
                .endian = self.stack.?.endian,
            };
        };
        return error.MemoryOutOfBounds;
    }
};

fn offsetIn(base: u64, length: usize, address: u64, width: usize) ?usize {
    if (address < base) return null;
    const offset = std.math.cast(usize, address - base) orelse return null;
    if (offset > length or width > length - offset) return null;
    return offset;
}
