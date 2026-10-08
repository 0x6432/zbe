//! One-to-one translation of main.c
const std = @import("std");
const assert = std.debug.assert;
const amd64 = @import("amd64/all.zig");
const arm64 = @import("arm64/all.zig");
const rv64 = @import("rv64/all.zig");
// -- imports --
const all = @import("all.zig");
const DEnd = all.DEnd;
const Dat = all.Dat;
const Fn = all.Fn;
const Target = all.Target;
const Writer = all.Writer;
const coalesce = all.coalesce;
const cs = all.cs;
const dprint = all.dprint;
const emitdat = all.emitdat;
const emitdbgfile = all.emitdbgfile;
const fillalias = all.fillalias;
const fillcfg = all.fillcfg;
const fillcost = all.fillcost;
const filldom = all.filldom;
const filllive = all.filllive;
const fillloop = all.fillloop;
const filluse = all.filluse;
const freeall = all.freeall;
const gcm = all.gcm;
const gvn = all.gvn;
const ifconvert = all.ifconvert;
const loadopt = all.loadopt;
const parse = all.parse;
const printfn = all.printfn;
const promote = all.promote;
const rega = all.rega;
const simpl = all.simpl;
const simplcfg = all.simplcfg;
const simpljmp = all.simpljmp;
const spill = all.spill;
const ssa = all.ssa;
const ssacheck = all.ssacheck;
const uint = all.uint;
// -- end imports --

// debug flags (all.debug):
//   'P' parsing, 'M' memory optimization, 'N' ssa construction,
//   'C' copy elimination, 'G' gvn/gcm, 'K' if-conversion,
//   'A' abi lowering, 'I' instruction selection, 'L' liveness,
//   'S' spilling, 'R' reg. allocation

/// config.h: default target
fn Deftgt() *Target {
    return &amd64.targ.T_amd64_sysv;
}

var tlist: [7]?*Target = undefined;

fn inittargets() void {
    amd64.targ.init();
    arm64.targ.init();
    rv64.targ.init();
    tlist = .{
        &amd64.targ.T_amd64_sysv,
        &amd64.targ.T_amd64_apple,
        &amd64.targ.T_amd64_win,
        &arm64.targ.T_arm64,
        &arm64.targ.T_arm64_apple,
        &rv64.targ.T_rv64,
        null,
    };
}

var outf: *Writer = undefined;
var dbg = false;

var stdout_buf: [64 * 1024]u8 = undefined;
var stderr_buf: [4096]u8 = undefined;
var out_fw: std.Io.File.Writer = undefined;
var err_fw: std.Io.File.Writer = undefined;

fn writeFailed() noreturn {
    dprint("qbe: write error\n", .{});
    all.dbg.flush() catch {};
    std.process.exit(1);
}

fn data(d: [*c]Dat) void {
    if (dbg)
        return;
    emitdat(d, outf) catch writeFailed();
    if (d.*.type == DEnd) {
        outf.writeAll("/* end data */\n\n") catch writeFailed();
        freeall();
    }
}

fn func(f: *Fn) void {
    if (dbg)
        dprint("**** Function {s} ****", .{cs(f.name)});
    if (all.debug['P'] != 0) {
        dprint("\n> After parsing:\n", .{});
        printfn(f, all.dbg) catch {};
    }
    all.T.abi0(f);
    fillcfg(f);
    filluse(f);
    promote(f);
    filluse(f);
    ssa(f);
    filluse(f);
    ssacheck(f);
    fillalias(f);
    loadopt(f);
    filluse(f);
    fillalias(f);
    coalesce(f);
    filluse(f);
    filldom(f);
    ssacheck(f);
    gvn(f);
    fillcfg(f);
    simplcfg(f);
    filluse(f);
    filldom(f);
    gcm(f);
    filluse(f);
    ssacheck(f);
    if (all.T.cansel != 0) {
        ifconvert(f);
        fillcfg(f);
        filluse(f);
        filldom(f);
        ssacheck(f);
    }
    all.T.abi1(f);
    simpl(f);
    fillcfg(f);
    filluse(f);
    all.T.isel(f);
    fillcfg(f);
    filllive(f);
    fillloop(f);
    fillcost(f);
    spill(f);
    rega(f);
    fillcfg(f);
    simpljmp(f);
    fillcfg(f);
    assert(f.rpo[0] == f.start);
    var n: uint = 0;
    while (true) : (n += 1) {
        if (n == f.nblk - 1) {
            f.rpo[n].*.link = null;
            break;
        } else f.rpo[n].*.link = f.rpo[n + 1];
    }
    if (!dbg) {
        all.T.emitfn(f, outf) catch writeFailed();
        outf.print("/* end function {s} */\n\n", .{cs(f.name)}) catch writeFailed();
    } else {
        dprint("\n", .{});
        all.dbg.flush() catch {};
    }
    freeall();
}

fn dbgfile(f: [*c]u8) void {
    emitdbgfile(f, outf) catch writeFailed();
}

fn fail(comptime fmt: []const u8, args: anytype) noreturn {
    dprint(fmt, args);
    all.dbg.flush() catch {};
    std.process.exit(1);
}

pub fn main(init: std.process.Init) u8 {
    const io = init.io;
    const arena = init.arena.allocator();
    const argv = init.minimal.args.vector;
    const prog = std.mem.span(argv[0]);

    err_fw = std.Io.File.stderr().writerStreaming(io, &stderr_buf);
    all.dbg = &err_fw.interface;
    out_fw = std.Io.File.stdout().writerStreaming(io, &stdout_buf);
    outf = &out_fw.interface;
    all.outw = outf;

    inittargets();
    all.T = Deftgt().*;

    // command line, getopt("hd:o:t:")-compatible (GNU style: options and
    // operands may be mixed, "--" ends options)
    var files: std.ArrayList([]const u8) = .empty;
    var a: usize = 1;
    var noopts = false;
    while (a < argv.len) : (a += 1) {
        const arg = std.mem.span(argv[a]);
        if (noopts or arg.len < 2 or arg[0] != '-') {
            files.append(arena, arg) catch fail("out of memory\n", .{});
            continue;
        }
        if (std.mem.eql(u8, arg, "--")) {
            noopts = true;
            continue;
        }
        var k: usize = 1;
        while (k < arg.len) : (k += 1) {
            const c = arg[k];
            var optarg: []const u8 = "";
            if (c == 'd' or c == 'o' or c == 't') {
                if (k + 1 < arg.len) {
                    optarg = arg[k + 1 ..];
                } else if (a + 1 < argv.len) {
                    a += 1;
                    optarg = std.mem.span(argv[a]);
                } else {
                    dprint("{s}: option requires an argument -- '{c}'\n", .{ prog, c });
                    usageExit(prog, 1);
                }
                k = arg.len;
            }
            switch (c) {
                'd' => for (optarg) |ch| {
                    if (std.ascii.isAlphabetic(ch)) {
                        all.debug[std.ascii.toUpper(ch)] = 1;
                        dbg = true;
                    }
                },
                'o' => if (!std.mem.eql(u8, optarg, "-")) {
                    const file = std.Io.Dir.cwd().createFile(io, optarg, .{}) catch
                        fail("cannot open '{s}'\n", .{optarg});
                    out_fw = file.writerStreaming(io, &stdout_buf);
                },
                't' => {
                    if (std.mem.eql(u8, optarg, "?")) {
                        outf.print("{s}\n", .{cs(&all.T.name)}) catch writeFailed();
                        outf.flush() catch writeFailed();
                        std.process.exit(0);
                    }
                    for (tlist) |tp| {
                        const t = tp orelse fail("unknown target '{s}'\n", .{optarg});
                        if (std.mem.eql(u8, optarg, cs(&t.name))) {
                            all.T = t.*;
                            break;
                        }
                    }
                },
                'h' => usageExit(prog, 0),
                else => {
                    dprint("{s}: invalid option -- '{c}'\n", .{ prog, c });
                    usageExit(prog, 1);
                },
            }
        }
    }
    if (files.items.len == 0)
        files.append(arena, "-") catch fail("out of memory\n", .{});

    for (files.items) |path| {
        var text: []const u8 = undefined;
        if (std.mem.eql(u8, path, "-")) {
            var rbuf: [4096]u8 = undefined;
            var r = std.Io.File.stdin().readerStreaming(io, &rbuf);
            text = r.interface.allocRemaining(arena, .unlimited) catch
                fail("cannot read stdin\n", .{});
        } else {
            text = std.Io.Dir.cwd().readFileAlloc(io, path, arena, .unlimited) catch
                fail("cannot open '{s}'\n", .{path});
        }
        parse(text, path, &dbgfile, &data, &func);
    }

    if (!dbg)
        all.T.emitfin(outf) catch writeFailed();

    outf.flush() catch writeFailed();
    all.dbg.flush() catch {};
    return 0;
}

fn usageExit(prog: []const u8, code: u8) noreturn {
    const hf = if (code != 0) all.dbg else outf;
    usage(hf, prog) catch writeFailed();
    hf.flush() catch writeFailed();
    std.process.exit(code);
}

fn usage(hf: *Writer, prog: []const u8) Writer.Error!void {
    try hf.print("{s} [OPTIONS] {{file.ssa, -}}\n", .{prog});
    try hf.print("\t{s:<11} prints this help\n", .{"-h"});
    try hf.print("\t{s:<11} output to file\n", .{"-o file"});
    try hf.print("\t{s:<11} generate for a target among:\n", .{"-t <target>"});
    try hf.print("\t{s:<11} ", .{""});
    var t: usize = 0;
    var sep: []const u8 = "";
    while (tlist[t] != null) : ({
        t += 1;
        sep = ", ";
    }) {
        try hf.print("{s}{s}", .{ sep, cs(&tlist[t].?.name) });
        if (tlist[t].? == Deftgt())
            try hf.writeAll(" (default)");
    }
    try hf.print("\n", .{});
    try hf.print("\t{s:<11} dump debug information\n", .{"-d <flags>"});
}
