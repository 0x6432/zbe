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
    var t: [*c]Tmp = undefined;
    var l: [*c]Ins = undefined;
    var s: i32 = undefined;
    var k: i32 = undefined;

    // promote uniform stack slots to temporaries
    const b: [*c]Blk = f.start;
    var i: [*c]Ins = b.*.ins;
    outer: while (i < &b.*.ins[b.*.nins]) : (i += 1) {
        if (Oalloc > i.*.op or i.*.op > Oalloc1)
            continue;
        // specific to NAlign == 3
        assert(rtype(i.*.to) == RTmp);
        t = &f.tmp[i.*.to.val];
        if (t.*.ndef != 1)
            continue :outer; // goto Skip
        k = -1;
        s = -1;
        var u = t.*.use;
        while (u < &t.*.use[t.*.nuse]) : (u += 1) {
            if (u.*.type != UIns)
                continue :outer;
            l = u.*.u.ins;
            if (isload(l.*.op))
                if (s == -1 or s == loadsz(l)) {
                    s = loadsz(l);
                    continue;
                };
            if (isstore(l.*.op))
                if (req(i.*.to, l.*.arg[1]) and !req(i.*.to, l.*.arg[0]))
                    if (s == -1 or s == storesz(l))
                        if (k == -1 or k == all.optab[l.*.op].argcls[0][0]) {
                            s = storesz(l);
                            k = all.optab[l.*.op].argcls[0][0];
                            continue;
                        };
            continue :outer;
        }
        // get rid of the alloc and replace uses
        i.* = INS0(Onop);
        t.*.ndef -= 1;
        const ue = &t.*.use[t.*.nuse];
        u = t.*.use;
        while (u != ue) : (u += 1) {
            l = u.*.u.ins;
            if (isstore(l.*.op)) {
                l.*.cls = @intCast(k);
                l.*.op = Ocopy;
                l.*.to = l.*.arg[1];
                l.*.arg[1] = R;
                t.*.nuse -= 1;
                t.*.ndef += 1;
            } else {
                if (k == -1)
                    err("slot %{s} is read but never stored to", .{cs(f.tmp[l.*.arg[0].val].name)});
                // try to turn loads into copies so we
                // can eliminate them later
                sw: switch (l.*.op) {
                    Oloadsw, Oloaduw => {
                        if (k == Kl)
                            continue :sw 0; // goto Extend
                        continue :sw Oload;
                    },
                    Oload => {
                        if (KBASE(k) != KBASE(l.*.cls))
                            l.*.op = Ocast
                        else
                            l.*.op = Ocopy;
                    },
                    else => { // Extend:
                        l.*.op = Oextsb + (l.*.op - Oloadsb);
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

const Store = extern struct {
    ip: i32,
    i: [*c]Ins,
};

const Slot = extern struct {
    t: i32,
    sz: i32,
    m: bits,
    l: bits,
    r: Range,
    s: [*c]Slot,
    st: [*c]Store,
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

fn slot(ps: *[*c]Slot, off: *i64, r: Ref, f: *Fn, sl: [*c]Slot) bool {
    var a: Alias = undefined;

    getalias(&a, r, f);
    if (a.type != ALoc)
        return false;
    const t = &f.tmp[@intCast(a.base)];
    if (t.visit < 0)
        return false;
    off.* = a.offset;
    ps.* = &sl[@intCast(t.visit)];
    return true;
}

fn load(r: Ref, x: bits, ip: i32, f: *Fn, sl: [*c]Slot) void {
    var off: i64 = undefined;
    var s: [*c]Slot = undefined;

    if (slot(&s, &off, r, f, sl)) {
        s.*.l |= shl64(x, off);
        s.*.l &= s.*.m;
        if (s.*.l != 0)
            radd(&s.*.r, ip);
    }
}

fn store(r: Ref, x: bits, ip: i32, i: [*c]Ins, f: *Fn, sl: [*c]Slot) void {
    var off: i64 = undefined;
    var s: [*c]Slot = undefined;

    if (slot(&s, &off, r, f, sl)) {
        if (s.*.l != 0) {
            radd(&s.*.r, ip);
            s.*.l &= ~shl64(x, off);
        } else {
            s.*.nst += 1;
            vgrow(&s.*.st, s.*.nst);
            s.*.st[@intCast(s.*.nst - 1)].ip = ip;
            s.*.st[@intCast(s.*.nst - 1)].i = i;
        }
    }
}

fn scmp(a: Slot, b: Slot) std.math.Order {
    // by decreasing size, then increasing start
    if (a.sz != b.sz)
        return std.math.order(b.sz, a.sz);
    return std.math.order(a.r.a, b.r.a);
}

fn maxrpo(hd: *Blk, b: *Blk) void {
    if (hd.loop < @as(i32, @intCast(b.id)))
        hd.loop = @intCast(b.id);
}

pub fn coalesce(f: *Fn) void {
    var r: Range = undefined;
    var s: [*c]Slot = undefined;
    var s0: [*c]Slot = undefined;
    var b: [*c]Blk = undefined;
    var succ: [3][*c]Blk = undefined;
    var i: [*c]Ins = undefined;
    var t: [*c]Tmp = undefined;
    var arg: [*c]Ref = undefined;
    var x: bits = undefined;
    var off0: i64 = undefined;
    var off1: i64 = undefined;
    var n: i32 = undefined;
    var m: i32 = undefined;
    var sz: i32 = undefined;

    // minimize the stack usage
    // by coalescing slots
    var nsl: i32 = 0;
    var sl = vnewT(Slot, 0, PHeap);
    n = Tmp0;
    while (n < f.ntmp) : (n += 1) {
        t = &f.tmp[@intCast(n)];
        t.*.visit = -1;
        if (t.*.alias.type == ALoc)
            if (t.*.alias.slot == &t.*.alias)
                if (t.*.bid == f.start.?.id)
                    if (t.*.alias.u.loc.sz != -1) {
                        t.*.visit = nsl;
                        nsl += 1;
                        vgrow(&sl, nsl);
                        s = &sl[@intCast(nsl - 1)];
                        s.*.t = n;
                        s.*.sz = t.*.alias.u.loc.sz;
                        s.*.m = t.*.alias.u.loc.m;
                        s.*.s = null;
                        s.*.st = vnewT(Store, 0, PHeap);
                        s.*.nst = 0;
                    };
    }

    // one-pass liveness analysis
    b = f.start;
    while (b != null) : (b = b.*.link)
        b.*.loop = -1;
    loopiter(f, maxrpo);
    var nbl: i32 = 0;
    var bl = vnewT([*c]Ins, 0, PHeap);
    const br: [*c]Range = ealloc(Range, f.nblk);
    var ip: i32 = std.math.maxInt(c_int) - 1;
    n = @as(i32, @intCast(f.nblk)) - 1;
    while (n >= 0) : (n -= 1) {
        b = f.rpo[@intCast(n)];
        succ[0] = b.*.s1;
        succ[1] = b.*.s2;
        succ[2] = null;
        br[@intCast(n)].b = ip;
        ip -= 1;
        s = sl;
        while (s < &sl[@intCast(nsl)]) : (s += 1) {
            s.*.l = 0;
            var ps: [*c][*c]Blk = &succ;
            while (ps.* != null) : (ps += 1) {
                m = @intCast(ps.*.*.id);
                if (m > n and rin(s.*.r, br[@intCast(m)].a)) {
                    s.*.l = s.*.m;
                    radd(&s.*.r, ip);
                }
            }
        }
        if (b.*.jmp.type == Jretc) {
            ip -= 1;
            load(b.*.jmp.arg, @bitCast(@as(i64, -1)), ip, f, sl);
        }
        i = &b.*.ins[b.*.nins];
        while (i != b.*.ins) {
            i -= 1;
            arg = &i.*.arg;
            if (i.*.op == Oargc) {
                ip -= 1;
                load(arg[1], @bitCast(@as(i64, -1)), ip, f, sl);
            }
            if (isload(i.*.op)) {
                x = BIT(loadsz(i)) -% 1;
                ip -= 1;
                load(arg[0], x, ip, f, sl);
            }
            if (isstore(i.*.op)) {
                x = BIT(storesz(i)) -% 1;
                store(arg[1], x, ip, i, f, sl);
                ip -= 1;
            }
            if (i.*.op == Oblit0) {
                assert((i + 1).*.op == Oblit1);
                assert(rtype((i + 1).*.arg[0]) == RInt);
                sz = @intCast(@abs(rsval((i + 1).*.arg[0])));
                x = if (sz >= NBit) @bitCast(@as(i64, -1)) else BIT(sz) -% 1;
                store(arg[1], x, ip, i, f, sl);
                ip -= 1;
                load(arg[0], x, ip, f, sl);
                nbl += 1;
                vgrow(&bl, nbl);
                bl[@intCast(nbl - 1)] = i;
            }
        }
        s = sl;
        while (s < &sl[@intCast(nsl)]) : (s += 1)
            if (s.*.l != 0) {
                radd(&s.*.r, ip);
                if (b.*.loop != -1) {
                    assert(b.*.loop >= n);
                    radd(&s.*.r, br[@intCast(b.*.loop)].b - 1);
                }
            };
        br[@intCast(n)].a = ip;
    }
    efree(@ptrCast(br));

    // kill dead stores
    s = sl;
    while (s < &sl[@intCast(nsl)]) : (s += 1) {
        n = 0;
        while (n < s.*.nst) : (n += 1)
            if (!rin(s.*.r, s.*.st[@intCast(n)].ip)) {
                i = s.*.st[@intCast(n)].i;
                if (i.*.op == Oblit0)
                    (i + 1).* = INS0(Onop);
                i.* = INS0(Onop);
            };
    }

    // kill slots with an empty live range
    var total: uint = 0;
    var freed: uint = 0;
    var stk = vnewT(i32, 0, PHeap);
    n = 0;
    s = sl;
    s0 = sl;
    while (s < &sl[@intCast(nsl)]) : (s += 1) {
        total +%= @bitCast(s.*.sz);
        if (s.*.r.b == 0) {
            vfree(@ptrCast(s.*.st));
            n += 1;
            vgrow(&stk, n);
            stk[@intCast(n - 1)] = s.*.t;
            freed +%= @bitCast(s.*.sz);
        } else {
            s0.* = s.*;
            s0 += 1;
        }
    }
    nsl = @intCast(ptrdiff(s0, sl));
    if (all.debug['M'] != 0) {
        dprint("\n> Slot coalescing:\n", .{});
        if (n != 0) {
            dprint("\tkill [", .{});
            m = 0;
            while (m < n) : (m += 1)
                dprint(" %{s}", .{cs(f.tmp[@intCast(stk[@intCast(m)])].name)});
            dprint(" ]\n", .{});
        }
    }
    while (n != 0) {
        n -= 1;
        t = &f.tmp[@intCast(stk[@intCast(n)])];
        assert(t.*.ndef == 1 and t.*.def != null);
        i = t.*.def;
        if (isload(i.*.op)) {
            i.*.op = Ocopy;
            i.*.arg[0] = UNDEF;
            continue;
        }
        i.* = INS0(Onop);
        for (t.*.use[0..t.*.nuse]) |*u| {
            if (u.type == UJmp) {
                b = f.rpo[u.bid];
                assert(isret(b.*.jmp.type));
                b.*.jmp.type = Jret0;
                b.*.jmp.arg = R;
                continue;
            }
            assert(u.type == UIns);
            i = u.u.ins;
            if (!req(i.*.to, R)) {
                assert(rtype(i.*.to) == RTmp);
                n += 1;
                vgrow(&stk, n);
                stk[@intCast(n - 1)] = @intCast(i.*.to.val);
            } else if (isarg(i.*.op)) {
                assert(i.*.op == Oargc);
                i.*.arg[1] = CON_Z; // crash
            } else {
                if (i.*.op == Oblit0)
                    (i + 1).* = INS0(Onop);
                i.* = INS0(Onop);
            }
        }
    }
    vfree(@ptrCast(stk));

    // fuse slots by decreasing size
    sort(Slot, sl, @intCast(nsl), scmp);
    var fused: uint = 0;
    n = 0;
    while (n < nsl) : (n += 1) {
        s0 = &sl[@intCast(n)];
        if (s0.*.s != null)
            continue;
        s0.*.s = s0;
        r = s0.*.r;
        s = s0 + 1;
        skip: while (s < &sl[@intCast(nsl)]) : (s += 1) {
            if (s.*.s != null or s.*.r.b == 0)
                continue :skip;
            if (rovlap(r, s.*.r)) {
                // O(n); can be approximated
                // by 'goto Skip;' if need be
                m = n;
                while (&sl[@intCast(m)] < s) : (m += 1)
                    if (sl[@intCast(m)].s == s0)
                        if (rovlap(sl[@intCast(m)].r, s.*.r))
                            continue :skip;
            }
            radd(&r, s.*.r.a);
            radd(&r, s.*.r.b - 1);
            s.*.s = s0;
            fused +%= @bitCast(s.*.sz);
        }
    }

    // substitute fused slots
    s = sl;
    while (s < &sl[@intCast(nsl)]) : (s += 1) {
        t = &f.tmp[@intCast(s.*.t)];
        // the visit link is stale,
        // reset it before the slot()
        // calls below
        t.*.visit = @intCast(ptrdiff(s, sl));
        assert(t.*.ndef == 1 and t.*.def != null);
        if (s.*.s == s)
            continue;
        t.*.def.?.* = INS0(Onop);
        const ts = &f.tmp[@intCast(s.*.s.*.t)];
        assert(t.*.bid == ts.bid);
        if (@intFromPtr(t.*.def) < @intFromPtr(ts.def)) {
            // make sure the slot we
            // selected has a def that
            // dominates its new uses
            t.*.def.?.* = ts.def.?.*;
            ts.def.?.* = INS0(Onop);
            ts.def = t.*.def;
        }
        for (t.*.use[0..t.*.nuse]) |*u| {
            if (u.type == UJmp) {
                b = f.rpo[u.bid];
                b.*.jmp.arg = TMP(s.*.s.*.t);
                continue;
            }
            assert(u.type == UIns);
            arg = &u.u.ins.arg;
            n = 0;
            while (n < 2) : (n += 1) {
                if (req(arg[@intCast(n)], TMP(s.*.t)))
                    arg[@intCast(n)] = TMP(s.*.s.*.t);
            }
        }
    }

    // fix newly overlapping blits
    n = 0;
    while (n < nbl) : (n += 1) {
        i = bl[@intCast(n)];
        if (i.*.op == Oblit0)
            if (slot(&s, &off0, i.*.arg[0], f, sl))
                if (slot(&s0, &off1, i.*.arg[1], f, sl))
                    if (s.*.s == s0.*.s) {
                        if (off0 < off1) {
                            sz = rsval((i + 1).*.arg[0]);
                            assert(sz >= 0);
                            (i + 1).*.arg[0] = INT(-sz);
                        } else if (off0 == off1) {
                            i.* = INS0(Onop);
                            (i + 1).* = INS0(Onop);
                        }
                    };
    }
    vfree(@ptrCast(bl));

    if (all.debug['M'] != 0) {
        s0 = sl;
        while (s0 < &sl[@intCast(nsl)]) : (s0 += 1) {
            if (s0.*.s != s0)
                continue;
            dprint("\tfuse ({f}b) [", .{cint(s0.*.sz, 3)});
            s = s0;
            while (s < &sl[@intCast(nsl)]) : (s += 1) {
                if (s.*.s != s0)
                    continue;
                dprint(" %{s}", .{cs(f.tmp[@intCast(s.*.t)].name)});
                if (s.*.r.b != 0)
                    dprint("[{d},{d})", .{s.*.r.a - ip, s.*.r.b - ip})
                else
                    dprint("{s}", .{"{}"});
            }
            dprint(" ]\n", .{});
        }
        dprint("\tsums {d}/{d}/{d} (killed/fused/total)\n\n", .{freed, fused, total});
        printfn(f, all.dbg) catch {};
    }

    s = sl;
    while (s < &sl[@intCast(nsl)]) : (s += 1)
        vfree(@ptrCast(s.*.st));
    vfree(@ptrCast(sl));
}
