//! Standalone adversarial tests: not imported into root.zig until integration.
//! Oracle uses logical byte cells and u128 half-open intervals, not runtime
//! span/width/initialization helpers. No host pointers or native claims.
const std = @import("std");
const testing = std.testing;
const runtime = @import("evaluation_memory.zig");
const memory = @import("memory.zig");
const interpreter = @import("interpreter.zig");
const Module = @import("module.zig").Module;
const entry: @import("module.zig").FunctionId = @fromBackingInt(@as(u32, 0));

fn parse(allocator: std.mem.Allocator, text: []const u8) !Module {
    var diagnostic: ?@import("source.zig").Diagnostic = null;
    return @import("frontend.zig").parse(allocator, .{ .name = "adversarial_memory", .text = text }, &diagnostic);
}

const Region = struct {
    base: u64,
    bytes: [17]u8,
    defined: [17]bool,
};
const Cell = struct { region: usize, offset: usize };
const Oracle = struct {
    regions: [4]Region,

    fn locate(self: *const Oracle, address: u64, count: usize) ?Cell {
        for (self.regions, 0..) |region, index| {
            const lo: u128 = region.base;
            const hi = lo + region.bytes.len;
            const begin: u128 = address;
            const end = begin + count;
            if (begin >= lo and end <= hi) return .{ .region = index, .offset = @intCast(begin - lo) };
        }
        return null;
    }
    fn copy(self: *Oracle, src: u64, dst: u64, count: usize) !void {
        if (count == 0) return;
        const from = self.locate(src, count) orelse return error.MemoryOutOfBounds;
        const to = self.locate(dst, count) orelse return error.MemoryOutOfBounds;
        const source_end = @as(u128, src) + count;
        const destination_end = @as(u128, dst) + count;
        if (src != dst and @as(u128, src) < destination_end and @as(u128, dst) < source_end) return error.PartialMemoryOverlap;
        for (0..count) |i| if (!self.regions[from.region].defined[from.offset + i]) return error.UninitializedMemory;
        // Snapshot instead of sharing the implementation's copy primitive.
        var snapshot: [17]u8 = undefined;
        for (0..count) |i| snapshot[i] = self.regions[from.region].bytes[from.offset + i];
        for (0..count) |i| {
            self.regions[to.region].bytes[to.offset + i] = snapshot[i];
            self.regions[to.region].defined[to.offset + i] = true;
        }
    }
    fn audit(self: *const Oracle, space: *runtime.Space, dead: u64) !void {
        for (self.regions) |region| for (0..region.bytes.len) |i| {
            const actual = space.read(.unsigned_byte, .word, region.base + i);
            if (region.defined[i]) {
                try testing.expectEqual(@as(u32, region.bytes[i]), (try actual).word);
            } else try testing.expectError(error.UninitializedMemory, actual);
        };
        for (0..17) |i| try testing.expectError(error.MemoryOutOfBounds, space.read(.unsigned_byte, .word, dead + i));
    }
};

fn checkCase(module: *const Module, src: u64, dst: u64, count: usize) !void {
    var image = try memory.Image.init(testing.allocator, 17, .{ .base = 0x10000 });
    defer image.deinit();
    @memset(image.bytes, 0xa5);
    var space = try runtime.Space.initForModule(testing.allocator, &image, .{ .base = 0x100000000, .max_bytes = 192 }, module, .{ .base = 0x200000000, .max_bytes = 33, .endian = .big });
    defer space.deinit();
    const caller = try space.allocate(17); // charge 48, all except byte 0 undefined
    try space.write(.byte, .{ .word = 0x31 }, caller);
    const mark = space.mark();
    const dead = try space.allocate(17); // charge 48, freed but never recycled
    try space.write(.long, .{ .long = 0x8877665544332211 }, dead);
    space.releaseTo(mark);
    const sibling = try space.allocate(17); // charge 48, no stale address authority
    try testing.expectEqual(@as(u64, 0x100000060), sibling);
    for (0..17) |i| try space.write(.byte, .{ .word = @as(u32, @intCast(i)) + 0x40 }, sibling + i);
    var oracle: Oracle = .{ .regions = .{
        .{ .base = 0x10000, .bytes = @splat(0xa5), .defined = @splat(true) },
        .{ .base = 0x200000000, .bytes = "abcdefghijklmnopq".*, .defined = @splat(true) },
        .{ .base = 0x100000000, .bytes = @splat(0), .defined = @splat(false) },
        .{ .base = 0x100000060, .bytes = undefined, .defined = @splat(true) },
    } };
    oracle.regions[2].bytes[0] = 0x31;
    oracle.regions[2].defined[0] = true;
    for (0..17) |i| oracle.regions[3].bytes[i] = @as(u8, @intCast(i)) + 0x40;
    const expected = oracle.copy(src, dst, count);
    const actual = space.copy(src, dst, count);
    if (expected) |_| {
        try actual;
    } else |err| try testing.expectError(err, actual);
    // Every byte and its initialization state is checked after success OR fault.
    try oracle.audit(&space, dead);
    try testing.expectEqual(@as(usize, 144), space.used);
    try testing.expectEqual(@as(usize, 2), space.mark());
}

test "adversarial_memory independent byte-cell oracle checks 5400 cross-region fault atomicity cases" {
    var module = try parse(testing.allocator, "data $adversarial_global = { b \"abcdefghijklmnopq\" }");
    defer module.deinit();
    const bases = [_]u64{ 0x10000, 0x200000000, 0x100000000, 0x100000060, 0x100000030 };
    const offsets = [_]i64{ -1, 0, 1, 16, 17, 18 };
    const counts = [_]usize{ 0, 1, 2, 8, 17, 18 };
    var cases: usize = 0;
    for (bases) |source_base| for (offsets) |source_offset| {
        const src: u64 = @intCast(@as(i128, source_base) + source_offset);
        for (bases) |destination_base| for (offsets) |destination_offset| {
            const dst: u64 = @intCast(@as(i128, destination_base) + destination_offset);
            for (counts) |count| {
                checkCase(&module, src, dst, count) catch |err| {
                    std.debug.print("adversarial_memory case src=0x{x} dst=0x{x} count={d}\n", .{ src, dst, count });
                    return err;
                };
                cases += 1;
            }
        };
    };
    try testing.expectEqual(@as(usize, 5400), cases);
}

const escaped = @embedFile("fixtures/adversarial_escaped_stack.ssa");
fn exerciseEscaped(allocator: std.mem.Allocator) !void {
    var module = try parse(allocator, escaped);
    defer module.deinit();
    var image = try memory.Image.init(allocator, 24, .{});
    defer image.deinit();
    @memset(image.bytes, 0xa5);
    const result = interpreter.evaluateModule(allocator, &module, entry, &.{.{ .long = image.base }}, .{ .memory_image = &image, .stack_memory = .{} });
    if (result) |_| return error.ExpectedStaleAddressFault else |err| {
        // Injected OOM is propagated, never accepted as the desired fault.
        if (err != error.MemoryOutOfBounds) return err;
    }
    // Constants are hand-computed: caller=base, escaped child=base+32;
    // sibling allocation is base+64 and must not revive base+32.
    try testing.expectEqualSlices(u8, &.{ 0x20, 0, 0, 0, 1, 0, 0, 0 }, image.bytes[0..8]);
    try testing.expectEqualSlices(u8, &.{ 73, 0, 0, 0, 0, 0, 0, 0 }, image.bytes[8..16]);
    try testing.expectEqualSlices(u8, &.{ 0x5a, 0, 0, 0, 0, 0, 0, 0 }, image.bytes[16..24]);
    // Fresh evaluation reuses namespace, not memory ownership or mutated module.
    @memset(image.bytes, 0xa5);
    const again = interpreter.evaluateModule(allocator, &module, entry, &.{.{ .long = image.base }}, .{ .memory_image = &image, .stack_memory = .{}, .max_steps = 0 });
    if (again) |_| return error.ExpectedStepLimit else |err| {
        if (err != error.StepLimitExceeded) return err;
    }
    for (image.bytes) |byte| try testing.expectEqual(@as(u8, 0xa5), byte);
}

test "adversarial_memory escaped child pointer cannot be revived by sibling frame" {
    try exerciseEscaped(testing.allocator);
}

test "adversarial_memory escaped-pointer parse frames publication and errors free every injected allocation" {
    try @import("test_support.zig").checkAllocationFailures(exerciseEscaped);
}
