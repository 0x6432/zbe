//! Experimental base-scalar Linux AMD64 compiler driver; not QBE CLI parity.
const std = @import("std");
const core = @import("root.zig");

pub fn main(init: std.process.Init) u8 {
    return run(init) catch |err| {
        report(init.io, "zbe-native: {s}\n", .{@errorName(err)});
        return 1;
    };
}

fn run(init: std.process.Init) !u8 {
    const args = try init.minimal.args.toSlice(init.arena.allocator());
    const fold = args.len > 1 and std.mem.eql(u8, args[1], "--fold-integers");
    if (args.len != @as(usize, if (fold) 4 else 3)) {
        report(init.io, "usage: zbe-native [--fold-integers] input.ssa output.s (Linux AMD64 scalar subset)\n", .{});
        return 2;
    }
    const input_path = args[if (fold) 2 else 1];
    const output_path = args[if (fold) 3 else 2];
    if (std.mem.eql(u8, input_path, output_path)) return error.SameInputAndOutput;
    const text = try std.Io.Dir.cwd().readFileAlloc(init.io, input_path, init.gpa, .limited(16 * 1024 * 1024));
    defer init.gpa.free(text);
    const input: core.source.Source = .{ .name = input_path, .text = text };
    var diagnostic: ?core.source.Diagnostic = null;
    var module = core.frontend.parse(init.gpa, input, &diagnostic) catch |err| {
        if (diagnostic) |problem| {
            const location = input.location(problem.span.start).?;
            report(init.io, "{s}:{d}:{d}: {s}\n", .{ input.name, location.line, location.column, @tagName(problem.code) });
            return 1;
        }
        return err;
    };
    defer module.deinit();
    if (fold) for (module.functions.items) |function| {
        _ = try core.optimize.foldIntegerConstants(init.gpa, function);
    };
    const assembly = try core.amd64.emit(init.gpa, &module);
    defer init.gpa.free(assembly);
    // No output is created/truncated until parsing, validation and emission succeed.
    try std.Io.Dir.cwd().writeFile(init.io, .{ .sub_path = output_path, .data = assembly });
    return 0;
}

fn report(io: std.Io, comptime format: []const u8, args: anytype) void {
    var buffer: [512]u8 = undefined;
    var output = std.Io.File.stderr().writerStreaming(io, &buffer);
    output.interface.print(format, args) catch return;
    output.interface.flush() catch {};
}
