//! One-to-one translation of live.c
const std = @import("std");
const assert = std.debug.assert;
// -- imports --
const all = @import("all.zig");
const BSet = all.BSet;
const Blk = all.Blk;
const Fn = all.Fn;
const clsBase = all.clsBase;
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
// -- end imports --

pub fn liveon(v: *BSet, b: *Blk, s: *Blk) void {
    bscopy(v, &s.in);
    var p_it = s.phi;
    while (p_it) |p| : (p_it = p.link) {
        if (rtype(p.to) == RTmp)
            bsclr(v, p.to.val);
    }
    p_it = s.phi;
    while (p_it) |p| : (p_it = p.link) {
        for (p.blks(), p.args()) |pb, a| {
            if (pb == b and rtype(a) == RTmp) {
                bsset(v, a.val);
                bsset(&b.gen, a.val);
            }
        }
    }
}

fn bset(r: Ref, b: *Blk, nlv: *[2]i32, tmp: []const Tmp) void {
    if (rtype(r) != RTmp)
        return;
    bsset(&b.gen, r.val);
    if (!bshas(&b.in, r.val)) {
        nlv[@intCast(clsBase(tmp[r.val].cls))] += 1;
        bsset(&b.in, r.val);
    }
}

/// liveness analysis
/// requires rpo computation
pub fn filllive(f: *Fn) void {
    const tmp = f.tmps();
    var m: [2]i32 = undefined;
    var nlv: [2]i32 = undefined;
    var u: BSet = undefined;
    var v: BSet = undefined;

    bsinit(&u, @intCast(f.ntmp));
    bsinit(&v, @intCast(f.ntmp));
    var b_it = f.start;
    while (b_it) |b| : (b_it = b.link) {
        bsinit(&b.in, @intCast(f.ntmp));
        bsinit(&b.out, @intCast(f.ntmp));
        bsinit(&b.gen, @intCast(f.ntmp));
    }
    var chg = true;
    while (true) {
        var n = f.nblk;
        while (n > 0) {
            n -= 1;
            const b = f.blks()[n];

            bscopy(&u, &b.out);
            for ([2]?*Blk{ b.s1, b.s2 }) |s_| {
                const s = s_ orelse continue;
                liveon(&v, b, s);
                bsunion(&b.out, &v);
            }
            chg = chg or !bsequal(&b.out, &u);

            nlv = .{ 0, 0 };
            b.out.words()[0] |= all.T.rglob;
            bscopy(&b.in, &b.out);
            var t: i32 = 0;
            while (bsiter(&b.in, &t)) : (t += 1)
                nlv[@intCast(clsBase(tmp[@intCast(t)].cls))] += 1;
            if (rtype(b.jmp.arg) == RCall) {
                assert(@as(i32, @intCast(bscount(&b.in))) == all.T.nrglob and
                    b.in.words()[0] == all.T.rglob);
                b.in.words()[0] |= all.T.retregs(b.jmp.arg, &nlv);
            } else bset(b.jmp.arg, b, &nlv, tmp);
            b.nlive = nlv;
            var i_n = b.nins;
            while (i_n > 0) {
                i_n -= 1;
                const i = &b.insns()[i_n];
                if (i.op == .call and rtype(i.arg[1]) == RCall) {
                    b.in.words()[0] &= ~all.T.retregs(i.arg[1], &m);
                    for (0..2) |k| {
                        nlv[k] -= m[k];
                        // caller-save registers are used
                        // by the callee, in that sense,
                        // right in the middle of the call,
                        // they are live:
                        nlv[k] += all.T.nrsave[k];
                        b.nlive[k] = @max(b.nlive[k], nlv[k]);
                    }
                    b.in.words()[0] |= all.T.argregs(i.arg[1], &m);
                    for (0..2) |k| {
                        nlv[k] -= all.T.nrsave[k];
                        nlv[k] += m[k];
                    }
                }
                if (!req(i.to, R)) {
                    assert(rtype(i.to) == RTmp);
                    const tt = i.to.val;
                    if (bshas(&b.in, tt))
                        nlv[@intCast(clsBase(tmp[tt].cls))] -= 1;
                    bsset(&b.gen, tt);
                    bsclr(&b.in, tt);
                }
                for (i.arg) |a| {
                    switch (rtype(a)) {
                        RMem => {
                            const ma = &f.mems()[a.val];
                            bset(ma.base, b, &nlv, tmp);
                            bset(ma.index, b, &nlv, tmp);
                        },
                        else => bset(a, b, &nlv, tmp),
                    }
                }
                for (0..2) |k|
                    b.nlive[k] = @max(b.nlive[k], nlv[k]);
            }
        }
        if (!chg) break;
        chg = false;
    }

    if (all.debug['L'] != 0) {
        dprint("\n> Liveness analysis:\n", .{});
        b_it = f.start;
        while (b_it) |b| : (b_it = b.link) {
            dprint("\t{s:<10}in:   ", .{cs(b.name)});
            dumpts(&b.in, tmp, all.dbg) catch {};
            dprint("\t          out:  ", .{});
            dumpts(&b.out, tmp, all.dbg) catch {};
            dprint("\t          gen:  ", .{});
            dumpts(&b.gen, tmp, all.dbg) catch {};
            dprint("\t          live: ", .{});
            dprint("{d} {d}\n", .{ b.nlive[0], b.nlive[1] });
        }
    }
}

test "bset slices: counts integer and float temps once and ignores constants" {
    var temps = std.mem.zeroes([all.Tmp0 + 2]Tmp);
    temps[all.Tmp0].cls = .l;
    temps[all.Tmp0 + 1].cls = .d;
    const view: []const Tmp = &temps;
    var block = std.mem.zeroes(Blk);
    bsinit(&block.in, temps.len);
    bsinit(&block.gen, temps.len);
    defer all.freeall();
    all.bszero(&block.in);
    all.bszero(&block.gen);
    var count = [2]i32{ 0, 0 };
    bset(all.conRef(1), &block, &count, &.{});
    try std.testing.expectEqual([2]i32{ 0, 0 }, count);
    bset(all.tmpRef(all.Tmp0), &block, &count, view);
    bset(all.tmpRef(all.Tmp0 + 1), &block, &count, view);
    bset(all.tmpRef(all.Tmp0), &block, &count, view);
    bset(all.tmpRef(all.Tmp0 + 1), &block, &count, view);
    try std.testing.expectEqual([2]i32{ 1, 1 }, count);
    try std.testing.expect(bshas(&block.in, all.Tmp0));
    try std.testing.expect(bshas(&block.gen, all.Tmp0 + 1));
}
