//! Linux SysV base-scalar argument locations, not aggregate/varargs ABI support.
const std = @import("std");
const ir = @import("ir.zig");
pub const Error = error{StackArgumentsTooLarge};

pub const General = enum {
    rdi,
    rsi,
    rdx,
    rcx,
    r8,
    r9,

    pub fn name(self: General, width: ir.IntegerType) []const u8 {
        return switch (self) {
            .rdi => if (width == .word) "%edi" else "%rdi",
            .rsi => if (width == .word) "%esi" else "%rsi",
            .rdx => if (width == .word) "%edx" else "%rdx",
            .rcx => if (width == .word) "%ecx" else "%rcx",
            .r8 => if (width == .word) "%r8d" else "%r8",
            .r9 => if (width == .word) "%r9d" else "%r9",
        };
    }
};
pub const Vector = enum {
    xmm0,
    xmm1,
    xmm2,
    xmm3,
    xmm4,
    xmm5,
    xmm6,
    xmm7,

    pub fn name(self: Vector) []const u8 {
        return switch (self) {
            .xmm0 => "%xmm0",
            .xmm1 => "%xmm1",
            .xmm2 => "%xmm2",
            .xmm3 => "%xmm3",
            .xmm4 => "%xmm4",
            .xmm5 => "%xmm5",
            .xmm6 => "%xmm6",
            .xmm7 => "%xmm7",
        };
    }
};
const max_stack_index = (std.math.maxInt(i32) - 16) / 8;
pub const StackSlot = enum(u32) {
    _,

    /// Positive frame-pointer displacement after return-address/RBP saves.
    /// Check forged ordinals too; offsets must fit an AMD64 signed displacement.
    pub fn incomingOffset(self: StackSlot) Error!u32 {
        const index: usize = @backingInt(self);
        if (index > max_stack_index) return error.StackArgumentsTooLarge;
        return @intCast(16 + index * 8);
    }
};
pub const Location = union(enum) { general: General, vector: Vector, stack: StackSlot };
const general_bank = [_]General{ .rdi, .rsi, .rdx, .rcx, .r8, .r9 };
const vector_bank = [_]Vector{ .xmm0, .xmm1, .xmm2, .xmm3, .xmm4, .xmm5, .xmm6, .xmm7 };

/// One allocation-free cursor per signature, in declaration order. The banks
/// exhaust independently; overflow slots are shared in declaration order.
/// Initialize with .{}; manually editing fields is a caller invariant.
pub const ArgumentCursor = struct {
    general_used: usize = 0,
    vector_used: usize = 0,
    stack_used: usize = 0,

    pub fn next(self: *ArgumentCursor, ty: ir.ScalarType) Error!Location {
        if (ty.isInteger() and self.general_used < general_bank.len) {
            const register = general_bank[self.general_used];
            self.general_used += 1;
            return .{ .general = register };
        }
        if (!ty.isInteger() and self.vector_used < vector_bank.len) {
            const register = vector_bank[self.vector_used];
            self.vector_used += 1;
            return .{ .vector = register };
        }
        if (self.stack_used > max_stack_index) return error.StackArgumentsTooLarge;
        const slot: StackSlot = @fromBackingInt(@as(u32, @intCast(self.stack_used)));
        self.stack_used += 1;
        return .{ .stack = slot };
    }
};

const testing = std.testing;
test "base-scalar argument names use the correct physical width" {
    const words = [_][]const u8{ "%edi", "%esi", "%edx", "%ecx", "%r8d", "%r9d" };
    const longs = [_][]const u8{ "%rdi", "%rsi", "%rdx", "%rcx", "%r8", "%r9" };
    for (general_bank, words, longs) |register, word, long| {
        try testing.expectEqualStrings(word, register.name(.word));
        try testing.expectEqualStrings(long, register.name(.long));
    }
    const vectors = [_][]const u8{ "%xmm0", "%xmm1", "%xmm2", "%xmm3", "%xmm4", "%xmm5", "%xmm6", "%xmm7" };
    for (vector_bank, vectors) |register, expected| try testing.expectEqualStrings(expected, register.name());
}

test "all 65536 sixteen-argument class signatures match an independent prefix oracle" {
    // Recount each prefix rather than tracking production cursor state. Widths
    // alternate within each class; no production bank array derives expected IDs.
    const gp = [_]General{ .rdi, .rsi, .rdx, .rcx, .r8, .r9 };
    const fp = [_]Vector{ .xmm0, .xmm1, .xmm2, .xmm3, .xmm4, .xmm5, .xmm6, .xmm7 };
    for (0..65536) |bits| {
        var types: [16]ir.ScalarType = undefined;
        for (&types, 0..) |*ty, index| ty.* = if (bits & (@as(usize, 1) << @intCast(index)) == 0)
            (if (index % 2 == 0) .word else .long)
        else
            (if (index % 2 == 0) .single else .double);
        var cursor: ArgumentCursor = .{};
        for (types, 0..) |ty, index| {
            var integers: usize = 0;
            var floats: usize = 0;
            for (types[0..index]) |prior| {
                switch (prior) {
                    .word, .long => integers += 1,
                    .single, .double => floats += 1,
                }
            }
            const location = try cursor.next(ty);
            if (ty == .word or ty == .long) {
                if (integers < 6) {
                    try testing.expect(location == .general);
                    try testing.expectEqual(gp[integers], location.general);
                    continue;
                }
            } else if (floats < 8) {
                try testing.expect(location == .vector);
                try testing.expectEqual(fp[floats], location.vector);
                continue;
            }
            try testing.expect(location == .stack);
            const ordinal = (integers -| 6) + (floats -| 8);
            try testing.expectEqual(ordinal, @as(usize, @backingInt(location.stack)));
            try testing.expectEqual(@as(u32, @intCast(16 + ordinal * 8)), try location.stack.incomingOffset());
        }
    }
}

test "stack displacement limits are checked and cursor failures are atomic" {
    var cursor: ArgumentCursor = .{ .general_used = 6, .vector_used = 8, .stack_used = max_stack_index };
    const last = try cursor.next(.word);
    try testing.expectEqual(@as(u32, 2147483640), try last.stack.incomingOffset());
    const before = cursor;
    try testing.expectError(error.StackArgumentsTooLarge, cursor.next(.long));
    try testing.expectEqualDeep(before, cursor);
    try testing.expectError(error.StackArgumentsTooLarge, cursor.next(.double));
    try testing.expectEqualDeep(before, cursor);
    const forged: StackSlot = @fromBackingInt(std.math.maxInt(u32));
    try testing.expectError(error.StackArgumentsTooLarge, forged.incomingOffset());
    var independent: ArgumentCursor = .{ .general_used = 6, .stack_used = max_stack_index + 1 };
    try testing.expectError(error.StackArgumentsTooLarge, independent.next(.word));
    try testing.expectEqual(Vector.xmm0, (try independent.next(.double)).vector);
}

test "signature cursors have no shared mutable classification state" {
    var first: ArgumentCursor = .{};
    var second: ArgumentCursor = .{};
    for (0..9) |_| _ = try first.next(.double);
    try testing.expectEqual(General.rdi, (try second.next(.long)).general);
    try testing.expectEqual(Vector.xmm0, (try second.next(.single)).vector);
    try testing.expectEqual(General.rdi, (try first.next(.word)).general);
    try testing.expectEqual(@as(usize, 1), first.stack_used);
    try testing.expectEqual(@as(usize, 0), second.stack_used);
}
