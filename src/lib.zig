//! Library mode: compile QBE IL text to assembly in memory.
//!
//! Zig:  const qbe = @import("qbe");
//!       try qbe.compile(text, .{ .target = "arm64", .opt = 2 }, &writer);
//! C:    see include/qbe.h (qbe_compile / qbe_free / qbe_targets).
//!
//! Limitations (inherited from qbe's design): not thread-safe (global
//! state). Input errors are printed to stderr and returned as InvalidInput
//! (qbe_compile returns 3); internal invariant failures still abort.
const std = @import("std");
const all = @import("all.zig");
const drv = @import("main.zig");
const emit = @import("emit.zig");
const Writer = std.Io.Writer;

pub const version = drv.version;

pub const Options = struct {
    /// Target name (see targets()); null selects the compiler build's default target.
    target: ?[]const u8 = null,
    /// Optimization level 0..2; 0 = byte-identical to the patched C reference.
    opt: u8 = 2,
    /// file name used in diagnostics
    name: []const u8 = "<input>",
};

pub const Error = error{ UnknownTarget, WriteFailed, InvalidInput };

/// Target-name cache, filled on first use.
const State = struct {
    inited: bool = false,
    names: [8][]const u8 = undefined,
    nnames: usize = 0,
};
var st: State = .{};

fn init() void {
    if (st.inited) return;
    drv.inittargets();
    for (drv.tlist) |tp| {
        const t = tp orelse break;
        st.names[st.nnames] = std.mem.sliceTo(&t.name, 0);
        st.nnames += 1;
    }
    st.inited = true;
}

/// Names of all supported targets; the default follows the build platform, not list order.
pub fn targets() []const []const u8 {
    init();
    return st.names[0..st.nnames];
}

/// Compile IL `text` and write the assembly to `out` (not flushed).
/// Writer failures return WriteFailed; partial output must be discarded.
/// A subsequent compile starts a fresh output unit even after an error.
pub fn compile(text: []const u8, opts: Options, out: *Writer) Error!void {
    init();
    all.T = drv.Deftgt().*;
    if (opts.target) |want| {
        for (drv.tlist) |tp| {
            const t = tp orelse return error.UnknownTarget;
            if (std.mem.eql(u8, want, std.mem.sliceTo(&t.name, 0))) {
                all.T = t.*;
                break;
            }
        }
    }
    defer emit.resetCompilation();
    all.compat = false;
    all.optlevel = @min(opts.opt, 2);
    @memset(&all.debug, 0);
    drv.dbg = false;
    drv.outf = out;
    all.outw = out;
    var ebuf: [256]u8 = undefined;
    const ls = std.debug.lockStderr(&ebuf);
    defer std.debug.unlockStderr();
    all.dbg = &ls.file_writer.interface;
    try all.parse(text, opts.name, &drv.dbgfile, &drv.data, &drv.func);
    all.T.emitfin(out) catch return error.WriteFailed;
}

// ---- C ABI ----

/// Returns 0 and a malloc'ed, NUL-terminated buffer in *out (length in
/// *outlen, may be null) on success; 1 = unknown target, 2 = out of memory,
/// 3 = invalid input (the message is printed to stderr).
export fn qbe_compile(text: [*]const u8, len: usize, target: ?[*:0]const u8, opt: c_int, out: *?[*:0]u8, outlen: ?*usize) c_int {
    var aw: Writer.Allocating = .init(std.heap.c_allocator);
    defer aw.deinit();
    compile(text[0..len], .{
        .target = if (target) |t| std.mem.span(t) else null,
        .opt = @intCast(std.math.clamp(opt, 0, 2)),
    }, &aw.writer) catch |e| return switch (e) {
        error.UnknownTarget => 1,
        error.WriteFailed => 2,
        error.InvalidInput => 3,
    };
    const s = aw.toOwnedSliceSentinel(0) catch return 2;
    out.* = s.ptr;
    if (outlen) |p| p.* = s.len;
    return 0;
}

export fn qbe_free(p: ?[*:0]u8) void {
    if (p) |q| std.heap.c_allocator.free(std.mem.span(q));
}

/// Writes the i-th target name to *name; returns 0, or 1 past the end.
export fn qbe_target(i: c_int, name: *[*:0]const u8) c_int {
    const t = targets();
    if (i < 0 or i >= t.len) return 1;
    name.* = @ptrCast(drv.tlist[@intCast(i)].?.name[0..].ptr);
    return 0;
}

export fn qbe_version() [*:0]const u8 {
    return version;
}
