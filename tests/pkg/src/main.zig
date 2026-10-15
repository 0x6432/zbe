const std = @import("std");
const qbe = @import("qbe");
pub fn main() !void {
    try checkWriteRecovery();
    var aw: std.Io.Writer.Allocating = .init(std.heap.page_allocator);
    defer aw.deinit();
    const il = "export function w $add(w %a, w %b) {\n@s\n\t%c =w add %a, %b\n\tret %c\n}\n";
    for (qbe.targets()) |t| {
        aw.clearRetainingCapacity();
        try qbe.compile(il, .{ .target = t, .opt = 2 }, &aw.writer);
        std.debug.print("{s}: {d} bytes\n", .{ t, aw.written().len });
    }
}

fn checkWriteRecovery() !void {
    const cases = [_][]const u8{
        "data $value = { w 17 }\n",
        "dbgfile \"recovery.ssa\"\n",
        "export function d $value(d %a) {\n@start\n%x =d add %a, d_3.5\nret %x\n}\n",
    };
    var healthy: std.Io.Writer.Allocating = .init(std.heap.page_allocator);
    defer healthy.deinit();
    var checks: usize = 0;
    for (qbe.targets()) |target| {
        for ([_]u8{ 0, 1, 2 }) |opt| {
            for (cases) |text| {
                healthy.clearRetainingCapacity();
                try qbe.compile(text, .{ .target = target, .opt = opt }, &healthy.writer);
                const expected = try std.heap.page_allocator.dupe(u8, healthy.written());
                defer std.heap.page_allocator.free(expected);
                for ([_]usize{ 0, expected.len / 2, expected.len - 1 }) |limit| {
                    const buffer = try std.heap.page_allocator.alloc(u8, limit);
                    defer std.heap.page_allocator.free(buffer);
                    var failing = std.Io.Writer.fixed(buffer);
                    try std.testing.expectError(error.WriteFailed, qbe.compile(text, .{ .target = target, .opt = opt }, &failing));
                    healthy.clearRetainingCapacity();
                    try qbe.compile(text, .{ .target = target, .opt = opt }, &healthy.writer);
                    try std.testing.expectEqualStrings(expected, healthy.written());
                    checks += 1;
                }
            }
        }
    }
    std.debug.print("writer recovery: {d} checks passed\n", .{checks});
}
