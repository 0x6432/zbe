//! One-to-one translation of mem.c
const std = @import("std");
const assert = std.debug.assert;
// -- imports --
const all = @import("all.zig");
const ALoc = all.ALoc;
const Alias = all.Alias;
const BIT = all.BIT;
const Blk = all.Blk;
const CON_Z = all.CON_Z;
const Fn = all.Fn;
const INS0 = all.INS0;
const INT = all.INT;
const Ins = all.Ins;
const Jret0 = all.Jret0;
const Jretc = all.Jretc;
const KBASE = all.KBASE;
const Kl = all.Kl;
const NBit = all.NBit;
const Oalloc = all.Oalloc;
const Oalloc1 = all.Oalloc1;
const Oargc = all.ops.Oargc;
const Oblit0 = all.ops.Oblit0;
const Oblit1 = all.ops.Oblit1;
const Ocast = all.ops.Ocast;
const Ocopy = all.ops.Ocopy;
const Oextsb = all.ops.Oextsb;
const Oload = all.ops.Oload;
const Oloadsb = all.ops.Oloadsb;
const Oloadsw = all.ops.Oloadsw;
const Oloaduw = all.ops.Oloaduw;
const Onop = all.ops.Onop;
const PHeap = all.PHeap;
const R = all.R;
const RInt = all.RInt;
const RTmp = all.RTmp;
const Ref = all.Ref;
const TMP = all.TMP;
const Tmp = all.Tmp;
const Tmp0 = all.Tmp0;
const UIns = all.UIns;
const UJmp = all.UJmp;
const UNDEF = all.UNDEF;
const bits = all.bits;
const cint = all.cint;
const cs = all.cs;
const dprint = all.dprint;
const ealloc = all.ealloc;
const efree = all.efree;
const err = all.err;
const getalias = all.getalias;
const isarg = all.isarg;
const isload = all.isload;
const isret = all.isret;
const isstore = all.isstore;
const loadsz = all.loadsz;
const loopiter = all.loopiter;
const printfn = all.printfn;
const ptrdiff = all.ptrdiff;
const req = all.req;
const rsval = all.rsval;
const rtype = all.rtype;
const shl64 = all.shl64;
const sort = all.sort;
const storesz = all.storesz;
const uint = all.uint;
const vfree = all.vfree;
const vgrow = all.vgrow;
const vnewT = all.vnewT;
// -- end imports --

/// require use, maintains use counts
pub fn promote(f: *Fn) void {
    // promote uniform stack slots to temporaries
    const b = f.start.?;
    outer: for (b.ins[0..b.nins]) |*i| {
        if (Oalloc > i.op or i.op > Oalloc1)
            continue;
        // specific to NAlign == 3
        assert(rtype(i.to) == RTmp);
        const t = &f.tmp[i.to.val];
        if (t.ndef != 1)
            continue :outer; // goto Skip
        var k: i32 = -1;
        var s: i32 = -1;
        for (t.use.?[0..t.nuse]) |*u| {
            if (u.type != UIns)
                continue :outer;
            const l = u.u.ins;
            if (isload(l.op))
                if (s == -1 or s == loadsz(l)) {
                    s = loadsz(l);
                    continue;
                };
            if (isstore(l.op))
                if (req(i.to, l.arg[1]) and !req(i.to, l.arg[0]))
                    if (s == -1 or s == storesz(l))
                        if (k == -1 or k == all.optab[l.op].argcls[0][0]) {
                            s = storesz(l);
                            k = all.optab[l.op].argcls[0][0];
                            continue;
                        };
            continue :outer;
        }
        // get rid of the alloc and replace uses
        i.* = INS0(Onop);
        t.ndef -= 1;
        for (t.use.?[0..t.nuse]) |*u| {
            const l = u.u.ins;
            if (isstore(l.op)) {
                l.cls = @intCast(k);
                l.op = Ocopy;
                l.to = l.arg[1];
                l.arg[1] = R;
                t.nuse -= 1;
                t.ndef += 1;
            } else {
                if (k == -1)
                    err("slot %{s} is read but never stored to", .{cs(f.tmp[l.arg[0].val].name)});
                // try to turn loads into copies so we
                // can eliminate them later
                sw: switch (l.op) {
                    Oloadsw, Oloaduw => {
                        if (k == Kl)
                            continue :sw 0; // goto Extend
                        continue :sw Oload;
                    },
                    Oload => {
                        if (KBASE(k) != KBASE(l.cls))
                            l.op = Ocast
                        else
                            l.op = Ocopy;
                    },
                    else => { // Extend:
                        l.op = Oextsb + (l.op - Oloadsb);
                    },
                }
            }
        }
    }
    if (all.debug['M'] != 0) {
        dprint("\n> After slot promotion:\n", .{});
        printfn(f, all.dbg) catch {};
    }
}

/// [a, b) with 0 <= a
const Range = extern struct {
    a: i32,
    b: i32,
};

const Store = struct {
    ip: i32,
    i: [*]Ins, // points into a block's ins (blits span two)
};

const Slot = struct {
    t: i32,
    sz: i32,
    m: bits,
    l: bits,
    r: Range,
    s: ?*Slot,
    st: [*]Store,
    nst: i32,
};

inline fn rin(r: Range, n: i32) bool {
    return r.a <= n and n < r.b;
}

inline fn rovlap(r0: Range, r1: Range) bool {
    return r0.b != 0 and r1.b != 0 and r0.a < r1.b and r1.a < r0.b;
}

fn radd(r: *Range, n: i32) void {
    if (r.b == 0)
        r.* = .{ .a = n, .b = n + 1 }
    else if (n < r.a)
        r.a = n
    else if (n >= r.b)
        r.b = n + 1;
}

fn slot(off: *i64, r: Ref, f: *Fn, sl: []Slot) ?*Slot {
    var a: Alias = undefined;

    getalias(&a, r, f);
    if (a.type != ALoc)
        return null;
    const t = &f.tmp[@intCast(a.base)];
    if (t.visit < 0)
        return null;
    off.* = a.offset;
    return &sl[@intCast(t.visit)];
}

fn load(r: Ref, x: bits, ip: i32, f: *Fn, sl: []Slot) void {
    var off: i64 = undefined;
    if (slot(&off, r, f, sl)) |s| {
        s.l |= shl64(x, off);
        s.l &= s.m;
        if (s.l != 0)
            radd(&s.r, ip);
    }
}

fn store(r: Ref, x: bits, ip: i32, i: [*]Ins, f: *Fn, sl: []Slot) void {
    var off: i64 = undefined;
    if (slot(&off, r, f, sl)) |s| {
        if (s.l != 0) {
            radd(&s.r, ip);
            s.l &= ~shl64(x, off);
        } else {
            s.nst += 1;
            vgrow(&s.st, s.nst);
            s.st[@intCast(s.nst - 1)] = .{ .ip = ip, .i = i };
        }
    }
}

fn scmp(a: Slot, b: Slot) std.math.Order {
    // by decreasing size, then increasing start
    if (a.sz != b.sz)
        return std.math.order(b.sz, a.sz);
    return std.math.order(a.r.a, b.r.a);
}

fn scmpLess(_: void, a: Slot, b: Slot) bool {
    return scmp(a, b) == .lt;
}

fn maxrpo(hd: *Blk, b: *Blk) void {
    if (hd.loop < @as(i32, @intCast(b.id)))
        hd.loop = @intCast(b.id);
}

/// kills an instruction; blits are killed as a pair
fn killins(i: [*]Ins) void {
    if (i[0].op == Oblit0)
        i[1] = INS0(Onop);
    i[0] = INS0(Onop);
}

pub fn coalesce(f: *Fn) void {
    const ones: bits = @bitCast(@as(i64, -1));

    // minimize the stack usage
    // by coalescing slots
    var nsl: usize = 0;
    var slv = vnewT(Slot, 0, PHeap);
    var tn: i32 = Tmp0;
    while (tn < f.ntmp) : (tn += 1) {
        const t = &f.tmp[@intCast(tn)];
        t.visit = -1;
        if (t.alias.type == ALoc)
            if (t.alias.slot == &t.alias)
                if (t.bid == f.start.?.id)
                    if (t.alias.u.loc.sz != -1) {
                        t.visit = @intCast(nsl);
                        nsl += 1;
                        vgrow(&slv, nsl);
                        slv[nsl - 1] = .{
                            .t = tn,
                            .sz = t.alias.u.loc.sz,
                            .m = t.alias.u.loc.m,
                            .l = 0,
                            .r = .{ .a = 0, .b = 0 },
                            .s = null,
                            .st = vnewT(Store, 0, PHeap),
                            .nst = 0,
                        };
                    };
    }
    var sl = slv[0..nsl];

    // one-pass liveness analysis
    var b_it = f.start;
    while (b_it) |b| : (b_it = b.link)
        b.loop = -1;
    loopiter(f, maxrpo);
    var nbl: usize = 0;
    var bl = vnewT([*]Ins, 0, PHeap);
    const br = ealloc(Range, f.nblk)[0..f.nblk];
    var ip: i32 = std.math.maxInt(c_int) - 1;
    var bn = f.nblk;
    while (bn > 0) {
        bn -= 1;
        const n: i32 = @intCast(bn);
        const b = f.rpo[bn];
        const succ = [2]?*Blk{ b.s1, b.s2 };
        br[bn].b = ip;
        ip -= 1;
        for (sl) |*s| {
            s.l = 0;
            for (succ) |ps_| {
                const ps = ps_ orelse break;
                const m = ps.id;
                if (m > bn and rin(s.r, br[m].a)) {
                    s.l = s.m;
                    radd(&s.r, ip);
                }
            }
        }
        if (b.jmp.type == Jretc) {
            ip -= 1;
            load(b.jmp.arg, ones, ip, f, sl);
        }
        var idx = b.nins;
        while (idx != 0) {
            idx -= 1;
            const ii = b.ins + idx;
            const i = &ii[0];
            const arg = &i.arg;
            if (i.op == Oargc) {
                ip -= 1;
                load(arg[1], ones, ip, f, sl);
            }
            if (isload(i.op)) {
                const x = BIT(loadsz(i)) -% 1;
                ip -= 1;
                load(arg[0], x, ip, f, sl);
            }
            if (isstore(i.op)) {
                const x = BIT(storesz(i)) -% 1;
                store(arg[1], x, ip, ii, f, sl);
                ip -= 1;
            }
            if (i.op == Oblit0) {
                assert(ii[1].op == Oblit1);
                assert(rtype(ii[1].arg[0]) == RInt);
                const sz: i32 = @intCast(@abs(rsval(ii[1].arg[0])));
                const x = if (sz >= NBit) ones else BIT(sz) -% 1;
                store(arg[1], x, ip, ii, f, sl);
                ip -= 1;
                load(arg[0], x, ip, f, sl);
                nbl += 1;
                vgrow(&bl, nbl);
                bl[nbl - 1] = ii;
            }
        }
        for (sl) |*s|
            if (s.l != 0) {
                radd(&s.r, ip);
                if (b.loop != -1) {
                    assert(b.loop >= n);
                    radd(&s.r, br[@intCast(b.loop)].b - 1);
                }
            };
        br[bn].a = ip;
    }
    efree(@ptrCast(br.ptr));

    // kill dead stores
    for (sl) |*s|
        for (s.st[0..@intCast(s.nst)]) |st|
            if (!rin(s.r, st.ip))
                killins(st.i);

    // kill slots with an empty live range
    var total: uint = 0;
    var freed: uint = 0;
    var nstk: usize = 0;
    var stk = vnewT(i32, 0, PHeap);
    {
        var nkeep: usize = 0;
        for (sl) |*s| {
            total +%= @bitCast(s.sz);
            if (s.r.b == 0) {
                vfree(@ptrCast(s.st));
                nstk += 1;
                vgrow(&stk, nstk);
                stk[nstk - 1] = s.t;
                freed +%= @bitCast(s.sz);
            } else {
                sl[nkeep] = s.*;
                nkeep += 1;
            }
        }
        sl = sl[0..nkeep];
    }
    if (all.debug['M'] != 0) {
        dprint("\n> Slot coalescing:\n", .{});
        if (nstk != 0) {
            dprint("\tkill [", .{});
            for (stk[0..nstk]) |st|
                dprint(" %{s}", .{cs(f.tmp[@intCast(st)].name)});
            dprint(" ]\n", .{});
        }
    }
    while (nstk != 0) {
        nstk -= 1;
        const t = &f.tmp[@intCast(stk[nstk])];
        assert(t.ndef == 1);
        const i = t.def.?;
        if (isload(i.op)) {
            i.op = Ocopy;
            i.arg[0] = UNDEF;
            continue;
        }
        i.* = INS0(Onop);
        for (t.use.?[0..t.nuse]) |*u| {
            if (u.type == UJmp) {
                const b = f.rpo[u.bid];
                assert(isret(b.jmp.type));
                b.jmp.type = Jret0;
                b.jmp.arg = R;
                continue;
            }
            assert(u.type == UIns);
            const ui = u.u.ins;
            if (!req(ui.to, R)) {
                assert(rtype(ui.to) == RTmp);
                nstk += 1;
                vgrow(&stk, nstk);
                stk[nstk - 1] = @intCast(ui.to.val);
            } else if (isarg(ui.op)) {
                assert(ui.op == Oargc);
                ui.arg[1] = CON_Z; // crash
            } else {
                killins(@ptrCast(ui));
            }
        }
    }
    vfree(@ptrCast(stk));

    // fuse slots by decreasing size
    std.sort.block(Slot, sl, {}, scmpLess);
    var fused: uint = 0;
    for (sl, 0..) |*s0, n| {
        if (s0.s != null)
            continue;
        s0.s = s0;
        var r = s0.r;
        skip: for (sl[n + 1 ..], n + 1..) |*s, sn| {
            if (s.s != null or s.r.b == 0)
                continue :skip;
            if (rovlap(r, s.r)) {
                // O(n); can be approximated
                // by 'goto Skip;' if need be
                for (sl[n..sn]) |*sm|
                    if (sm.s == s0)
                        if (rovlap(sm.r, s.r))
                            continue :skip;
            }
            radd(&r, s.r.a);
            radd(&r, s.r.b - 1);
            s.s = s0;
            fused +%= @bitCast(s.sz);
        }
    }

    // substitute fused slots
    for (sl, 0..) |*s, sn| {
        const t = &f.tmp[@intCast(s.t)];
        // the visit link is stale,
        // reset it before the slot()
        // calls below
        t.visit = @intCast(sn);
        assert(t.ndef == 1 and t.def != null);
        const ss = s.s.?;
        if (ss == s)
            continue;
        t.def.?.* = INS0(Onop);
        const ts = &f.tmp[@intCast(ss.t)];
        assert(t.bid == ts.bid);
        if (@intFromPtr(t.def) < @intFromPtr(ts.def)) {
            // make sure the slot we
            // selected has a def that
            // dominates its new uses
            t.def.?.* = ts.def.?.*;
            ts.def.?.* = INS0(Onop);
            ts.def = t.def;
        }
        for (t.use.?[0..t.nuse]) |*u| {
            if (u.type == UJmp) {
                f.rpo[u.bid].jmp.arg = TMP(ss.t);
                continue;
            }
            assert(u.type == UIns);
            for (&u.u.ins.arg) |*arg| {
                if (req(arg.*, TMP(s.t)))
                    arg.* = TMP(ss.t);
            }
        }
    }

    // fix newly overlapping blits
    for (bl[0..nbl]) |i| {
        var off0: i64 = undefined;
        var off1: i64 = undefined;
        if (i[0].op == Oblit0)
            if (slot(&off0, i[0].arg[0], f, sl)) |s|
                if (slot(&off1, i[0].arg[1], f, sl)) |s0|
                    if (s.s == s0.s) {
                        if (off0 < off1) {
                            const sz = rsval(i[1].arg[0]);
                            assert(sz >= 0);
                            i[1].arg[0] = INT(-sz);
                        } else if (off0 == off1) {
                            i[0] = INS0(Onop);
                            i[1] = INS0(Onop);
                        }
                    };
    }
    vfree(@ptrCast(bl));

    if (all.debug['M'] != 0) {
        for (sl, 0..) |*s0, n| {
            if (s0.s != s0)
                continue;
            dprint("\tfuse ({f}b) [", .{cint(s0.sz, 3)});
            for (sl[n..]) |*s| {
                if (s.s != s0)
                    continue;
                dprint(" %{s}", .{cs(f.tmp[@intCast(s.t)].name)});
                if (s.r.b != 0)
                    dprint("[{d},{d})", .{ s.r.a - ip, s.r.b - ip })
                else
                    dprint("{s}", .{"{}"});
            }
            dprint(" ]\n", .{});
        }
        dprint("\tsums {d}/{d}/{d} (killed/fused/total)\n\n", .{ freed, fused, total });
        printfn(f, all.dbg) catch {};
    }

    for (sl) |*s|
        vfree(@ptrCast(s.st));
    vfree(@ptrCast(slv));
}
