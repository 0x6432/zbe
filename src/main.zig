//! One-to-one translation of main.c
const std = @import("std");
const assert = std.debug.assert;
const C = @import("libc.zig");
const amd64 = @import("amd64/all.zig");
const arm64 = @import("arm64/all.zig");
const rv64 = @import("rv64/all.zig");
// -- imports --
const all = @import("all.zig");
const DEnd = all.DEnd;
const Dat = all.Dat;
const FILE = all.FILE;
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

fn func(f: [*c]Fn) void {
    if (dbg)
        dprint("**** Function {s} ****", .{cs(f.*.name)});
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
    assert(f.*.rpo[0] == f.*.start);
    var n: uint = 0;
    while (true) : (n += 1) {
        if (n == f.*.nblk - 1) {
            f.*.rpo[n].*.link = null;
            break;
        } else f.*.rpo[n].*.link = f.*.rpo[n + 1];
    }
    if (!dbg) {
        all.T.emitfn(f, outf) catch writeFailed();
        outf.print("/* end function {s} */\n\n", .{cs(f.*.name)}) catch writeFailed();
    } else {
        dprint("\n", .{});
        all.dbg.flush() catch {};
    }
    freeall();
}

fn dbgfile(f: [*c]u8) void {
    emitdbgfile(f, outf) catch writeFailed();
}

pub fn main(init: std.process.Init) u8 {
    const io = init.io;
    const av: [*c][*c]u8 = @ptrCast(@constCast(init.minimal.args.vector.ptr));
    const ac: c_int = @intCast(init.minimal.args.vector.len);

    err_fw = std.Io.File.stderr().writerStreaming(io, &stderr_buf);
    all.dbg = &err_fw.interface;
    out_fw = std.Io.File.stdout().writerStreaming(io, &stdout_buf);
    outf = &out_fw.interface;
    all.outw = outf;

    inittargets();
    all.T = Deftgt().*;
    while (true) {
        const c = C.getopt(ac, av, "hd:o:t:");
        if (c == -1) break;
        switch (c) {
            'd' => {
                while (C.optarg.* != 0) : (C.optarg += 1) {
                    if (C.isalpha(C.optarg.*) != 0) {
                        all.debug[@intCast(C.toupper(C.optarg.*))] = 1;
                        dbg = true;
                    }
                }
            },
            'o' => {
                if (C.strcmp(C.optarg, "-") != 0) {
                    const file = std.Io.Dir.cwd().createFile(io, cs(C.optarg), .{}) catch {
                        dprint("cannot open '{s}'\n", .{cs(C.optarg)});
                        all.dbg.flush() catch {};
                        std.process.exit(1);
                    };
                    out_fw = file.writerStreaming(io, &stdout_buf);
                }
            },
            't' => {
                if (C.strcmp(C.optarg, "?") == 0) {
                    outf.print("{s}\n", .{cs(&all.T.name)}) catch writeFailed();
                    outf.flush() catch writeFailed();
                    std.process.exit(0);
                }
                var t: usize = 0;
                while (true) : (t += 1) {
                    if (t == tlist.len or tlist[t] == null) {
                        dprint("unknown target '{s}'\n", .{cs(C.optarg)});
                        all.dbg.flush() catch {};
                        std.process.exit(1);
                    }
                    if (C.strcmp(C.optarg, &tlist[t].?.name) == 0) {
                        all.T = tlist[t].?.*;
                        break;
                    }
                }
            },
            else => {
                const hf = if (c != 'h') all.dbg else outf;
                usage(hf, cs(av[0])) catch writeFailed();
                hf.flush() catch writeFailed();
                std.process.exit(@intFromBool(c != 'h'));
            },
        }
    }

    while (true) {
        var f: [*c]u8 = av[@intCast(C.optind)];
        var inf: *FILE = undefined;
        if (f == null or C.strcmp(f, "-") == 0) {
            inf = C.stdin;
            f = @constCast("-");
        } else {
            inf = C.fopen(f, "r") orelse {
                dprint("cannot open '{s}'\n", .{cs(f)});
                all.dbg.flush() catch {};
                std.process.exit(1);
            };
        }
        parse(inf, f, &dbgfile, &data, &func);
        _ = C.fclose(inf);
        C.optind += 1;
        if (!(C.optind < ac)) break;
    }

    if (!dbg)
        all.T.emitfin(outf) catch writeFailed();

    outf.flush() catch writeFailed();
    all.dbg.flush() catch {};
    return 0;
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
