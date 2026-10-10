//! One-to-one translation of spill.c
const std = @import("std");
const assert = std.debug.assert;
// -- imports --
const all = @import("all.zig");
const Opc = all.Opc;
const BIT = all.BIT;
const BSet = all.BSet;
const Blk = all.Blk;
const Fn = all.Fn;
const Ins = all.Ins;
const KBASE = all.KBASE;
const KWIDE = all.KWIDE;
const Phi = all.Phi;
const R = all.R;
const RCall = all.RCall;
const RMem = all.RMem;
const RTmp = all.RTmp;
const Ref = all.Ref;
const SLOT = all.SLOT;
const TMP = all.TMP;
const Tmp = all.Tmp;
const Tmp0 = all.Tmp0;
const bits = all.bits;
const bsclr = all.bsclr;
const bscopy = all.bscopy;
const bscount = all.bscount;
const bsdiff = all.bsdiff;
const bshas = all.bshas;
const bsinit = all.bsinit;
const bsinter = all.bsinter;
const bsiter = all.bsiter;
const bsset = all.bsset;
const bsunion = all.bsunion;
const bszero = all.bszero;
const cint = all.cint;
const cs = all.cs;
const dprint = all.dprint;
const dumpts = all.dumpts;
const ealloc = all.ealloc;
const efree = all.efree;
const emit = all.emit;
const emiti = all.emiti;
const idup = all.idup;
const isreg = all.isreg;
const liveon = all.liveon;
const loopiter = all.loopiter;
const phicls = all.phicls;
const printfn = all.printfn;
const req = all.req;
const rtype = all.rtype;
const sort = all.sort;
const uint = all.uint;
// -- end imports --

fn aggreg(hd: *Blk, b: *Blk) void {
    // aggregate looping information at
    // loop headers
    bsunion(&hd.gen, &b.gen);
    for (0..2) |k| {
        if (b.nlive[k] > hd.nlive[k])
            hd.nlive[k] = b.nlive[k];
    }
}

fn tmpuse(r: Ref, use: bool, loop: i32, f: *Fn) void {
    if (rtype(r) == RMem) {
        const m = &f.mem[r.val];
        tmpuse(m.base, true, loop, f);
        tmpuse(m.index, true, loop, f);
    } else if (rtype(r) == RTmp and r.val >= Tmp0) {
        const t = &f.tmp[r.val];
        t.nuse += @intFromBool(use);
        t.ndef += @intFromBool(!use);
        t.cost +%= @bitCast(loop);
    }
}

/// evaluate spill costs of temporaries,
/// this also fills usage information
/// requires rpo, preds
pub fn fillcost(f: *Fn) void {
    loopiter(f, &aggreg);
    if (all.debug['S'] != 0) {
        dprint("\n> Loop information:\n", .{});
        var b_it: ?*Blk = f.start;
        while (b_it) |b| : (b_it = b.link) {
            var a: uint = 0;
            while (a < b.npred) : (a += 1) {
                if (b.id <= b.pred[a].id)
                    break;
            }
            if (a != b.npred) {
                dprint("\t{s:<10}", .{cs(b.name)});
                dprint(" ({f} ", .{cint(b.nlive[0], 3)});
                dprint("{f}) ", .{cint(b.nlive[1], 3)});
                dumpts(&b.gen, f.tmp, all.dbg) catch {};
            }
        }
    }
    var ti: i32 = 0;
    while (ti < f.ntmp) : (ti += 1) {
        const t = &f.tmp[@intCast(ti)];
        t.cost = if (ti < Tmp0) std.math.maxInt(uint) else 0;
        t.nuse = 0;
        t.ndef = 0;
    }
    var b_it: ?*Blk = f.start;
    while (b_it) |b| : (b_it = b.link) {
        var p_it: ?*Phi = b.phi;
        while (p_it) |p| : (p_it = p.link) {
            const t = &f.tmp[p.to.val];
            tmpuse(p.to, false, 0, f);
            for (0..p.narg) |a| {
                const n = p.blk[a].loop;
                t.cost +%= @bitCast(n);
                tmpuse(p.arg[a], true, n, f);
            }
        }
        const n = b.loop;
        for (b.ins[0..b.nins]) |*i| {
            tmpuse(i.to, false, n, f);
            tmpuse(i.arg[0], true, n, f);
            tmpuse(i.arg[1], true, n, f);
        }
        tmpuse(b.jmp.arg, true, n, f);
    }
    if (all.debug['S'] != 0) {
        dprint("\n> Spill costs:\n", .{});
        var n: i32 = Tmp0;
        while (n < f.ntmp) : (n += 1)
            dprint("\t{s:<10} {d}\n", .{cs(f.tmp[@intCast(n)].name), @as(i32, @bitCast(f.tmp[@intCast(n)].cost))});
        dprint("\n", .{});
    }
}

var fst: ?*BSet = null; // temps to prioritize in registers (for tcmp1)
var tmp: [*]Tmp = undefined; // current temporaries (for tcmpX), set by spill()
var ntmp: i32 = 0; // current # of temps (for limit)
var locs: i32 = 0; // stack size used by locals
var slot4: i32 = 0; // next slot of 4 bytes
var slot8: i32 = 0; // ditto, 8 bytes
var mask: [2]BSet = undefined; // class masks

fn tcmp0(a: i32, b: i32) std.math.Order {
    // by decreasing cost
    return std.math.order(tmp[@intCast(b)].cost, tmp[@intCast(a)].cost);
}

fn tcmp1(a: i32, b: i32) std.math.Order {
    // live-in temporaries first
    const c = std.math.order(@intFromBool(bshas(fst.?, b)), @intFromBool(bshas(fst.?, a)));
    return if (c != .eq) c else tcmp0(a, b);
}

fn slot(t: i32) Ref {
    assert(t >= Tmp0); // cannot spill register
    var s = tmp[@intCast(t)].slot;
    if (s == -1) {
        // specific to NAlign == 3
        // nice logic to pack stack slots
        // on demand, there can be only
        // one hole and slot4 points to it
        //
        // invariant: slot4 <= slot8
        if (KWIDE(tmp[@intCast(t)].cls) != 0) {
            s = slot8;
            if (slot4 == slot8)
                slot4 += 2;
            slot8 += 2;
        } else {
            s = slot4;
            if (slot4 == slot8) {
                slot8 += 2;
                slot4 += 1;
            } else slot4 = slot8;
        }
        s += locs;
        tmp[@intCast(t)].slot = s;
    }
    return SLOT(s);
}

var limit_tarr: ?[*]i32 = null;
var limit_maxt: i32 = 0;

/// restricts b to hold at most k
/// temporaries, preferring those
/// present in f (if given), then
/// those with the largest spill
/// cost
fn limit(b: *BSet, k: i32, f: ?*BSet) void {
    const nt: i32 = @intCast(bscount(b));
    if (nt <= k)
        return;
    if (nt > limit_maxt) {
        efree((limit_tarr));
        limit_tarr = ealloc(i32, nt);
        limit_maxt = nt;
    }
    // null only while limit_maxt == 0, i.e. nt == 0 (k < 0): nothing to do
    const tarr = limit_tarr orelse return;
    var i: i32 = 0;
    var t: i32 = 0;
    while (bsiter(b, &t)) : (t += 1) {
        bsclr(b, t);
        tarr[@intCast(i)] = t;
        i += 1;
    }
    if (nt > 1) {
        if (f == null) {
            sort(i32, tarr, @intCast(nt), tcmp0);
        } else {
            fst = f;
            sort(i32, tarr, @intCast(nt), tcmp1);
        }
    }
    i = 0;
    while (i < k and i < nt) : (i += 1)
        bsset(b, tarr[@intCast(i)]);
    while (i < nt) : (i += 1)
        _ = slot(tarr[@intCast(i)]);
}

/// spills temporaries to fit the
/// target limits using the same
/// preferences as limit(); assumes
/// that k1 gprs and k2 fprs are
/// currently in use
fn limit2(b1: *BSet, k1: i32, k2: i32, f: ?*BSet) void {
    var b2: BSet = undefined;

    bsinit(&b2, @intCast(ntmp)); // todo, free those
    bscopy(&b2, b1);
    bsinter(b1, &mask[0]);
    bsinter(&b2, &mask[1]);
    limit(b1, all.T.ngpr - k1, f);
    limit(&b2, all.T.nfpr - k2, f);
    bsunion(b1, &b2);
}

fn sethint(u: *BSet, r: bits) void {
    var t: i32 = Tmp0;
    while (bsiter(u, &t)) : (t += 1)
        tmp[@intCast(phicls(t, tmp))].hint.m |= r;
}

/// reloads temporaries in u that are
/// not in v from their slots
fn reloads(u: *BSet, v: *BSet) void {
    var t: i32 = Tmp0;
    while (bsiter(u, &t)) : (t += 1) {
        if (!bshas(v, t))
            emit(.load, tmp[@intCast(t)].cls, TMP(t), slot(t), R);
    }
}

fn store(r: Ref, s: i32) void {
    if (s != -1)
        emit(Opc.storew.offset(tmp[r.val].cls), 0, R, r, SLOT(s));
}

fn regcpy(i: *Ins) bool {
    return i.op == .copy and isreg(i.arg[0]);
}

/// handles the run of register copies ending at b.ins[last];
/// returns the index of the first copy of the run
fn dopm(b: *Blk, last: uint, v: *BSet) uint {
    var u: BSet = undefined;
    var r: bits = undefined;

    bsinit(&u, @intCast(ntmp)); // todo, free those
    // consecutive copies from
    // registers need to be handled
    // as one large instruction
    //
    // fixme: there is an assumption
    // that calls are always followed
    // by copy instructions here, this
    // might not be true if previous
    // passes change
    var n = last + 1;
    while (true) {
        n -= 1;
        const i = &b.ins[n];
        const t = i.to.val;
        if (!req(i.to, R))
            if (bshas(v, t)) {
                bsclr(v, t);
                store(i.to, tmp[t].slot);
            };
        bsset(v, i.arg[0].val);
        if (!(n != 0 and regcpy(&b.ins[n - 1]))) break;
    }
    bscopy(&u, v);
    if (n != 0 and b.ins[n - 1].op == .call) {
        const call = &b.ins[n - 1];
        v.t[0] &= ~all.T.retregs(call.arg[1], null);
        limit2(v, all.T.nrsave[0], all.T.nrsave[1], null);
        r = 0;
        var k: usize = 0;
        while (all.T.rsave[k] >= 0) : (k += 1)
            r |= BIT(all.T.rsave[k]);
        v.t[0] |= all.T.argregs(call.arg[1], null);
    } else {
        limit2(v, 0, 0, null);
        r = v.t[0];
    }
    sethint(v, r);
    reloads(&u, v);
    var k = last + 1;
    while (k > n) {
        k -= 1;
        emiti(b.ins[k]);
    }
    return n;
}

fn merge(u: *BSet, bu: *Blk, v: *BSet, bv: *Blk) void {
    if (bu.loop <= bv.loop) {
        bsunion(u, v);
    } else {
        var t: i32 = 0;
        while (bsiter(v, &t)) : (t += 1) {
            if (tmp[@intCast(t)].slot == -1)
                bsset(u, t);
        }
    }
}

/// spill code insertion
/// requires spill costs, rpo, liveness
///
/// Note: this will replace liveness
/// information (in, out) with temporaries
/// that must be in registers at block
/// borders
///
/// Be careful with:
/// - Ocopy instructions to ensure register
///   constraints
pub fn spill(f: *Fn) void {
    var lvarg: [2]bool = .{ false, false };
    var u: BSet = undefined;
    var v: BSet = undefined;
    var w: BSet = undefined;

    tmp = f.tmp;
    ntmp = f.ntmp;
    bsinit(&u, @intCast(ntmp));
    bsinit(&v, @intCast(ntmp));
    bsinit(&w, @intCast(ntmp));
    bsinit(&mask[0], @intCast(ntmp));
    bsinit(&mask[1], @intCast(ntmp));
    locs = f.slot;
    slot4 = 0;
    slot8 = 0;
    var t: i32 = 0;
    while (t < ntmp) : (t += 1) {
        var k: i32 = 0;
        if (t >= all.T.fpr0 and t < all.T.fpr0 + all.T.nfpr)
            k = 1;
        if (t >= Tmp0)
            k = KBASE(tmp[@intCast(t)].cls);
        bsset(&mask[@intCast(k)], t);
    }

    var bn = f.nblk;
    while (bn > 0) {
        bn -= 1;
        const b = f.rpo[bn];
        // invariant: all blocks with bigger rpo got
        // their in,out updated.

        // 1. find temporaries in registers at
        // the end of the block (put them in v)
        const s1 = b.s1;
        const s2 = b.s2;
        var hd_: ?*Blk = null;
        if (s1 != null and s1.?.id <= b.id)
            hd_ = s1;
        if (s2 != null and s2.?.id <= b.id)
            if (hd_ == null or s2.?.id >= hd_.?.id) {
                hd_ = s2;
            };
        if (hd_) |hd| {
            // back-edge
            bszero(&v);
            hd.gen.t[0] |= all.T.rglob; // don't spill registers
            for (0..2) |k| {
                const n: i32 = if (k == 0) all.T.ngpr else all.T.nfpr;
                bscopy(&u, &b.out);
                bsinter(&u, &mask[k]);
                bscopy(&w, &u);
                bsinter(&u, &hd.gen);
                bsdiff(&w, &hd.gen);
                if (@as(i32, @intCast(bscount(&u))) < n) {
                    const j: i32 = @intCast(bscount(&w)); // live through
                    const l = hd.nlive[k];
                    limit(&w, n - (l - j), null);
                    bsunion(&u, &w);
                } else limit(&u, n, null);
                bsunion(&v, &u);
            }
        } else if (s1) |s1b| {
            // avoid reloading temporaries
            // in the middle of loops
            bszero(&v);
            liveon(&w, b, s1b);
            merge(&v, b, &w, s1b);
            if (s2) |s2b| {
                liveon(&u, b, s2b);
                merge(&v, b, &u, s2b);
                bsinter(&w, &u);
            }
            limit2(&v, 0, 0, &w);
        } else {
            bscopy(&v, &b.out);
            if (rtype(b.jmp.arg) == RCall)
                v.t[0] |= all.T.retregs(b.jmp.arg, null);
        }
        if (rtype(b.jmp.arg) == RTmp) {
            t = b.jmp.arg.val;
            assert(KBASE(tmp[@intCast(t)].cls) == 0);
            bsset(&v, t);
            limit2(&v, 0, 0, null);
            if (!bshas(&v, t))
                b.jmp.arg = slot(t);
        }
        t = Tmp0;
        while (bsiter(&b.out, &t)) : (t += 1) {
            if (!bshas(&v, t))
                _ = slot(t);
        }
        bscopy(&b.out, &v);

        // 2. process the block instructions
        all.curi = all.insbEnd();
        var i_n = b.nins;
        while (i_n > 0) {
            i_n -= 1;
            const i = &b.ins[i_n];
            if (regcpy(i)) {
                i_n = dopm(b, i_n, &v);
                continue;
            }
            bszero(&w);
            if (!req(i.to, R)) {
                assert(rtype(i.to) == RTmp);
                t = i.to.val;
                if (bshas(&v, t)) {
                    bsclr(&v, t);
                } else {
                    // make sure we have a reg
                    // for the result
                    assert(t >= Tmp0); // dead reg
                    bsset(&v, t);
                    bsset(&w, t);
                }
            }
            var j = all.T.memargs(@intCast(i.op.int()));
            var n: usize = 0;
            while (n < 2) : (n += 1) {
                if (rtype(i.arg[n]) == RMem)
                    j -= 1;
            }
            n = 0;
            while (n < 2) : (n += 1) {
                switch (rtype(i.arg[n])) {
                    RMem => {
                        t = (i.arg[n].val);
                        const m = &f.mem[@intCast(t)];
                        if (rtype(m.base) == RTmp) {
                            bsset(&v, m.base.val);
                            bsset(&w, m.base.val);
                        }
                        if (rtype(m.index) == RTmp) {
                            bsset(&v, m.index.val);
                            bsset(&w, m.index.val);
                        }
                    },
                    RTmp => {
                        t = (i.arg[n].val);
                        lvarg[n] = bshas(&v, t);
                        bsset(&v, t);
                        const jj = j;
                        j -= 1;
                        if (jj <= 0)
                            bsset(&w, t);
                    },
                    else => {},
                }
            }
            bscopy(&u, &v);
            limit2(&v, 0, 0, &w);
            n = 0;
            while (n < 2) : (n += 1) {
                if (rtype(i.arg[n]) == RTmp) {
                    t = (i.arg[n].val);
                    if (!bshas(&v, t)) {
                        // do not reload if the
                        // argument is dead
                        if (!lvarg[n])
                            bsclr(&u, t);
                        i.arg[n] = slot(t);
                    }
                }
            }
            reloads(&u, &v);
            if (!req(i.to, R)) {
                t = i.to.val;
                store(i.to, tmp[@intCast(t)].slot);
                if (t >= Tmp0)
                    // in case i->to was a
                    // dead temporary
                    bsclr(&v, t);
            }
            emiti(i.*);
            const r = v.t[0]; // Tmp0 is NBit
            if (r != 0)
                sethint(&v, r);
        }
        if (b == f.start)
            assert(v.t[0] == (all.T.rglob | f.reg))
        else
            assert(v.t[0] == all.T.rglob);

        var p_it: ?*Phi = b.phi;
        while (p_it) |p| : (p_it = p.link) {
            assert(rtype(p.to) == RTmp);
            t = p.to.val;
            if (bshas(&v, t)) {
                bsclr(&v, t);
                store(p.to, tmp[@intCast(t)].slot);
            } else if (bshas(&b.in, t))
                // only if the phi is live
                p.to = slot((p.to.val));
        }
        bscopy(&b.in, &v);
        idup(b, all.curi, (all.insbTail()));
    }

    // align the locals to a 16 byte boundary
    // specific to NAlign == 3
    slot8 += slot8 & 3;
    f.slot += slot8;

    if (all.debug['S'] != 0) {
        dprint("\n> Block information:\n", .{});
        var b_it: ?*Blk = f.start;
        while (b_it) |b| : (b_it = b.link) {
            dprint("\t{s:<10} ({f}) ", .{ cs(b.name), cint(b.loop, 5) });
            dumpts(&b.out, f.tmp, all.dbg) catch {};
        }
        dprint("\n> After spilling:\n", .{});
        printfn(f, all.dbg) catch {};
    }
}
