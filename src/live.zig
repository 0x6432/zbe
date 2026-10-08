//! One-to-one translation of live.c
const std = @import("std");
const assert = std.debug.assert;
// -- imports --
const all = @import("all.zig");
const BSet = all.BSet;
const Blk = all.Blk;
const Fn = all.Fn;
const Ins = all.Ins;
const KBASE = all.KBASE;
const Ocall = all.ops.Ocall;
const Phi = all.Phi;
const R = all.R;
const RCall = all.RCall;
const RMem = all.RMem;
const RTmp = all.RTmp;
const Ref = all.Ref;
const Tmp = all.Tmp;
const bsclr = all.bsclr;
const bscopy = all.bscopy;
const bscount = all.bscount;
const bsequal = all.bsequal;
const bshas = all.bshas;
const bsinit = all.bsinit;
const bsiter = all.bsiter;
const bsset = all.bsset;
const bsunion = all.bsunion;
const cs = all.cs;
const dprint = all.dprint;
const dumpts = all.dumpts;
const req = all.req;
const rtype = all.rtype;
const uint = all.uint;
// -- end imports --

pub fn liveon(v: *BSet, b: [*c]Blk, s: *Blk) void {
    bscopy(v, &s.in);
    var p_it: ?*Phi = s.phi;
    while (p_it) |p| : (p_it = p.link) {
        if (rtype(p.to) == RTmp)
            bsclr(v, p.to.val);
    }
    p_it = s.phi;
    while (p_it) |p| : (p_it = p.link) {
        var a: uint = 0;
        while (a < p.narg) : (a += 1) {
            if (p.blk[a] == b)
                if (rtype(p.arg[a]) == RTmp) {
                    bsset(v, p.arg[a].val);
                    bsset(&b.*.gen, p.arg[a].val);
                };
        }
    }
}

fn bset(r: Ref, b: *Blk, nlv: *[2]i32, tmp: [*c]Tmp) void {
    if (rtype(r) != RTmp)
        return;
    bsset(&b.gen, r.val);
    if (!bshas(&b.in, r.val)) {
        nlv[@intCast(KBASE(tmp[r.val].cls))] += 1;
        bsset(&b.in, r.val);
    }
}

/// liveness analysis
/// requires rpo computation
pub fn filllive(f: *Fn) void {
    var m: [2]i32 = undefined;
    var nlv: [2]i32 = undefined;
    var u: BSet = undefined;
    var v: BSet = undefined;

    bsinit(&u, @intCast(f.ntmp));
    bsinit(&v, @intCast(f.ntmp));
    var b: [*c]Blk = f.start;
    while (b != null) : (b = b.*.link) {
        bsinit(&b.*.in, @intCast(f.ntmp));
        bsinit(&b.*.out, @intCast(f.ntmp));
        bsinit(&b.*.gen, @intCast(f.ntmp));
    }
    var chg = true;
    while (true) {
        var n: i32 = @as(i32, @intCast(f.nblk)) - 1;
        while (n >= 0) : (n -= 1) {
            b = f.rpo[@intCast(n)];

            bscopy(&u, &b.*.out);
            if (b.*.s1 != null) {
                liveon(&v, b, b.*.s1.?);
                bsunion(&b.*.out, &v);
            }
            if (b.*.s2 != null) {
                liveon(&v, b, b.*.s2.?);
                bsunion(&b.*.out, &v);
            }
            chg = chg or !bsequal(&b.*.out, &u);

            nlv = .{ 0, 0 };
            b.*.out.t[0] |= all.T.rglob;
            bscopy(&b.*.in, &b.*.out);
            var t: i32 = 0;
            while (bsiter(&b.*.in, &t)) : (t += 1)
                nlv[@intCast(KBASE(f.tmp[@intCast(t)].cls))] += 1;
            if (rtype(b.*.jmp.arg) == RCall) {
                assert(@as(i32, @intCast(bscount(&b.*.in))) == all.T.nrglob and
                    b.*.in.t[0] == all.T.rglob);
                b.*.in.t[0] |= all.T.retregs(b.*.jmp.arg, &nlv);
            } else bset(b.*.jmp.arg, b, &nlv, f.tmp);
            var k: usize = 0;
            while (k < 2) : (k += 1)
                b.*.nlive[k] = nlv[k];
            var i_n = b.*.nins;
            while (i_n > 0) {
                i_n -= 1;
                const i = &b.*.ins[i_n];
                if (i.op == Ocall and rtype(i.arg[1]) == RCall) {
                    b.*.in.t[0] &= ~all.T.retregs(i.arg[1], &m);
                    k = 0;
                    while (k < 2) : (k += 1) {
                        nlv[k] -= m[k];
                        // caller-save registers are used
                        // by the callee, in that sense,
                        // right in the middle of the call,
                        // they are live:
                        nlv[k] += all.T.nrsave[k];
                        if (nlv[k] > b.*.nlive[k])
                            b.*.nlive[k] = nlv[k];
                    }
                    b.*.in.t[0] |= all.T.argregs(i.arg[1], &m);
                    k = 0;
                    while (k < 2) : (k += 1) {
                        nlv[k] -= all.T.nrsave[k];
                        nlv[k] += m[k];
                    }
                }
                if (!req(i.to, R)) {
                    assert(rtype(i.to) == RTmp);
                    const tt = i.to.val;
                    if (bshas(&b.*.in, tt))
                        nlv[@intCast(KBASE(f.tmp[tt].cls))] -= 1;
                    bsset(&b.*.gen, tt);
                    bsclr(&b.*.in, tt);
                }
                k = 0;
                while (k < 2) : (k += 1) {
                    switch (rtype(i.arg[k])) {
                        RMem => {
                            const ma = &f.mem[i.arg[k].val];
                            bset(ma.base, b, &nlv, f.tmp);
                            bset(ma.index, b, &nlv, f.tmp);
                        },
                        else => bset(i.arg[k], b, &nlv, f.tmp),
                    }
                }
                k = 0;
                while (k < 2) : (k += 1) {
                    if (nlv[k] > b.*.nlive[k])
                        b.*.nlive[k] = nlv[k];
                }
            }
        }
        if (chg) {
            chg = false;
            continue;
        }
        break;
    }

    if (all.debug['L'] != 0) {
        dprint("\n> Liveness analysis:\n", .{});
        b = f.start;
        while (b != null) : (b = b.*.link) {
            dprint("\t{s:<10}in:   ", .{cs(b.*.name)});
            dumpts(&b.*.in, f.tmp, all.dbg) catch {};
            dprint("\t          out:  ", .{});
            dumpts(&b.*.out, f.tmp, all.dbg) catch {};
            dprint("\t          gen:  ", .{});
            dumpts(&b.*.gen, f.tmp, all.dbg) catch {};
            dprint("\t          live: ", .{});
            dprint("{d} {d}\n", .{b.*.nlive[0], b.*.nlive[1]});
        }
    }
}
