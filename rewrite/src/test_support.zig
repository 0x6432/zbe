const std = @import("std");

/// Exercise normal growth, then inject every allocation failure with in-place
/// resize/remap disabled. Otherwise allocator address/layout decisions can alter
/// the number of allocations between checkAllAllocationFailures iterations.
/// The controlled run still checks every allocation and cleanup byte count.
pub fn checkAllocationFailures(comptime exercise: fn (std.mem.Allocator) anyerror!void) !void {
    try exercise(std.testing.allocator);
    var moving = std.testing.FailingAllocator.init(std.testing.allocator, .{ .resize_fail_index = 0 });
    try std.testing.checkAllAllocationFailures(moving.allocator(), exercise, .{});
    try std.testing.expectEqual(moving.allocated_bytes, moving.freed_bytes);
}
