//! One-to-one translation of main.c
const std = @import("std");
const assert = std.debug.assert;
const C = @import("libc.zig");
const amd64 = @import("amd64/all.zig");
const arm64 = @import("arm64/all.zig");
// -- imports --
const all = @import("all.zig");
const DEnd = all.DEnd;
const Dat = all.Dat;
const FILE = all.FILE;
const Fn = all.Fn;
const Target = all.Target;
const coalesce = all.coalesce;
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
    tlist = .{
        &amd64.targ.T_amd64_sysv,
        &amd64.targ.T_amd64_apple,
        &amd64.targ.T_amd64_win,
        &arm64.targ.T_arm64,
        &arm64.targ.T_arm64_apple,
        null, // T_rv64 (todo)
        null,
    };
}

var outf: *FILE = undefined;
var dbg = false;

fn data(d: [*c]Dat) void {
    if (dbg)
        return;
    emitdat(d, outf);
    if (d.*.type == DEnd) {
        _ = C.fputs("/* end data */\n\n", outf);
        freeall();
    }
}

fn func(f: [*c]Fn) void {
    if (dbg)
        _ = C.fprintf(C.stderr, "**** Function %s ****", f.*.name);
    if (all.debug['P'] != 0) {
        _ = C.fprintf(C.stderr, "\n> After parsing:\n");
        printfn(f, C.stderr);
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
        all.T.emitfn(f, outf);
        _ = C.fprintf(outf, "/* end function %s */\n\n", f.*.name);
    } else _ = C.fprintf(C.stderr, "\n");
    freeall();
}

fn dbgfile(f: [*c]u8) void {
    emitdbgfile(f, outf);
}

pub fn main(init: std.process.Init.Minimal) u8 {
    const av: [*c][*c]u8 = @ptrCast(@constCast(init.args.vector.ptr));
    const ac: c_int = @intCast(init.args.vector.len);

    inittargets();
    all.T = Deftgt().*;
    outf = C.stdout;
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
                    outf = C.fopen(C.optarg, "w") orelse {
                        _ = C.fprintf(C.stderr, "cannot open '%s'\n", C.optarg);
                        C.exit(1);
                    };
                }
            },
            't' => {
                if (C.strcmp(C.optarg, "?") == 0) {
                    _ = C.puts(&all.T.name);
                    C.exit(0);
                }
                var t: usize = 0;
                while (true) : (t += 1) {
                    if (t == tlist.len or tlist[t] == null) {
                        _ = C.fprintf(C.stderr, "unknown target '%s'\n", C.optarg);
                        C.exit(1);
                    }
                    if (C.strcmp(C.optarg, &tlist[t].?.name) == 0) {
                        all.T = tlist[t].?.*;
                        break;
                    }
                }
            },
            else => {
                const hf = if (c != 'h') C.stderr else C.stdout;
                _ = C.fprintf(hf, "%s [OPTIONS] {file.ssa, -}\n", av[0]);
                _ = C.fprintf(hf, "\t%-11s prints this help\n", "-h");
                _ = C.fprintf(hf, "\t%-11s output to file\n", "-o file");
                _ = C.fprintf(hf, "\t%-11s generate for a target among:\n", "-t <target>");
                _ = C.fprintf(hf, "\t%-11s ", "");
                var t: usize = 0;
                var sep: [*c]const u8 = "";
                while (tlist[t] != null) : ({
                    t += 1;
                    sep = ", ";
                }) {
                    _ = C.fprintf(hf, "%s%s", sep, &tlist[t].?.name);
                    if (tlist[t].? == Deftgt())
                        _ = C.fputs(" (default)", hf);
                }
                _ = C.fprintf(hf, "\n");
                _ = C.fprintf(hf, "\t%-11s dump debug information\n", "-d <flags>");
                C.exit(@intFromBool(c != 'h'));
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
                _ = C.fprintf(C.stderr, "cannot open '%s'\n", f);
                C.exit(1);
            };
        }
        parse(inf, f, &dbgfile, &data, &func);
        _ = C.fclose(inf);
        C.optind += 1;
        if (!(C.optind < ac)) break;
    }

    if (!dbg)
        all.T.emitfin(outf);

    C.exit(0);
}
