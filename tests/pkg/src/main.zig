const std = @import("std");
const qbe = @import("qbe");
pub fn main() !void {
    var aw: std.Io.Writer.Allocating = .init(std.heap.page_allocator);
    defer aw.deinit();
    const il = "export function w $add(w %a, w %b) {\n@s\n\t%c =w add %a, %b\n\tret %c\n}\n";
    for (qbe.targets()) |t| {
        aw.clearRetainingCapacity();
        try qbe.compile(il, .{ .target = t, .opt = 2 }, &aw.writer);
        std.debug.print("{s}: {d} bytes\n", .{ t, aw.written().len });
    }
}
