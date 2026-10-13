//! One-to-one translation of load.c
const std = @import("std");
const assert = std.debug.assert;
// -- imports --
const all = @import("all.zig");
const Cls = all.Cls;
const Opc = all.Opc;
const ACon = all.ACon;
const AEsc = all.AEsc;
const ALoc = all.ALoc;
const ASym = all.ASym;
const AUnk = all.AUnk;
const bitAt = all.bitAt;
const Blk = all.Blk;
const CAddr = all.CAddr;
const Con = all.Con;
const Fn = all.Fn;
const mkIns = all.mkIns;
const Ins = all.Ins;
const clsWide = all.clsWide;
const MayAlias = all.MayAlias;
const MustAlias = all.MustAlias;
const NoAlias = all.NoAlias;
const PFn = all.PFn;
const PHeap = all.PHeap;
const Phi = all.Phi;
const R = all.R;
const RCon = all.RCon;
const RInt = all.RInt;
const RTmp = all.RTmp;
const Ref = all.Ref;
const tmpRef = all.tmpRef;
const alias = all.alias;
const bits = all.bits;
const die = all.die;
const dom = all.dom;
const dprint = all.dprint;
const escapes = all.escapes;
const getcon = all.getcon;
const idup = all.idup;
const isload = all.isload;
const isstore = all.isstore;
const newcon = all.newcon;
const newtmp = all.newtmp;
const pnew = all.pnew;
const printfn = all.printfn;
const ptrdiff = all.ptrdiff;
const req = all.req;
const rsval = all.rsval;
const rtype = all.rtype;
const shl64 = all.shl64;
const sort = all.sort;
const uint = all.uint;
const vfree = all.vfree;
const vgrow = all.vgrow;
const vnewT = all.vnewT;
// -- end imports --

/// must work when w==8
inline fn lowMask(w: anytype) bits {
    return bitAt(8 * @as(i32, (w)) - 1) *% 2 -% 1;
}

const LRoot = 0; // right above the original load
const LLoad = 1; // inserting a load is allowed
const LNoLoad = 2; // only scalar operations allowed

const Loc = struct {
    type: i32,
    off: uint,
    blk: *Blk,
};

const Slice = extern struct {
    ref: Ref,
    off: i32,
    sz: i16,
    cls: Cls, // load class
};

const Insert = extern struct {
    isphi: u32, // C: uint isphi:1
    num: u32, // C: uint num:31
    bid: uint,
    off: uint,
    new: extern union {
        ins: Ins,
        phi: extern struct {
            m: Slice,
            p: *Phi,
        },
    },
};

/// Load-elimination state for the function being processed.
const State = struct {
    curf: *Fn = undefined,
    inum: uint = 0, // current insertion number
    ilog: [*]Insert = undefined, // global insertion log
    nlog: uint = 0, // number of entries in the log
};
var st: State = .{};

pub fn loadsz(l: *Ins) i32 {
    switch (l.op) {
        .loadsb, .loadub => return 1,
        .loadsh, .loaduh => return 2,
        .loadsw, .loaduw => return 4,
        .load => return if (clsWide(l.cls) != 0) 8 else 4,
        else => {},
    }
    die("unreachable", .{});
}

pub fn storesz(s: *Ins) i32 {
    switch (s.op) {
        .storeb => return 1,
        .storeh => return 2,
        .storew, .stores => return 4,
        .storel, .stored => return 8,
        else => {},
    }
    die("unreachable", .{});
}

fn iins(cls: Cls, op: Opc, a0: Ref, a1: Ref, l: *Loc) Ref {
    st.nlog += 1;
    vgrow(&st.ilog, st.nlog);
    const ist = &st.ilog[st.nlog - 1];
    ist.isphi = 0;
    ist.num = st.inum;
    st.inum += 1;
    ist.bid = l.blk.id;
    ist.off = l.off;
    ist.new.ins = mkIns(op, cls, R, a0, a1);
    ist.new.ins.to = newtmp("ld", cls, st.curf);
    return ist.new.ins.to;
}

fn cast(r: *Ref, cls: Cls, l: *Loc) void {
    if (rtype(r.*) == RCon)
        return;
    assert(rtype(r.*) == RTmp);
    const cls0 = st.curf.tmp[r.val].cls;
    if (cls0 == cls or (cls == .w and cls0 == .l))
        return;
    if (clsWide(cls0) < clsWide(cls)) {
        if (cls0 == .s)
            r.* = iins(.w, .cast, r.*, R, l);
        r.* = iins(.l, .extuw, r.*, R, l);
        if (cls == .d)
            r.* = iins(.d, .cast, r.*, R, l);
    } else {
        if (cls0 == .d and cls != .l)
            r.* = iins(.l, .cast, r.*, R, l);
        if (cls0 != .d or cls != .w)
            r.* = iins(cls, .cast, r.*, R, l);
    }
}

inline fn mask(cls: Cls, r: *Ref, msk: bits, l: *Loc) void {
    cast(r, cls, l);
    r.* = iins(cls, .@"and", r.*, getcon(@bitCast(msk), st.curf), l);
}

fn load(sl: Slice, msk: bits, l: *Loc) Ref {
    var r: Ref = undefined;
    var cls: Cls = undefined;
    var c: Con = undefined;

    const ld: Opc = switch (sl.sz) {
        1 => .loadub,
        2 => .loaduh,
        4 => .loaduw,
        8 => .load,
        else => .xxx,
    };
    const all_ = msk == lowMask(sl.sz);
    if (all_)
        cls = sl.cls
    else
        cls = if (sl.sz > 4) Cls.l else Cls.w;
    r = sl.ref;
    // sl.ref might not be live here,
    // but its alias base ref will be
    // (see killsl() below)
    if (rtype(r) == RTmp) {
        const a = &st.curf.tmp[r.val].alias;
        switch (a.type) {
            ALoc, AEsc, AUnk => {
                r = tmpRef(a.base);
                if (a.offset != 0) {
                    const r1 = getcon(a.offset, st.curf);
                    r = iins(.l, .add, r, r1, l);
                }
            },
            ACon, ASym => {
                c = std.mem.zeroes(Con);
                c.type = CAddr;
                c.sym = a.u.sym;
                c.bits.i = a.offset;
                r = newcon(&c, st.curf);
            },
            else => die("unreachable", .{}),
        }
    }
    r = iins(cls, ld, r, R, l);
    if (!all_)
        mask(cls, &r, msk, l);
    return r;
}

fn rebase(sl: *Slice) void {
    if (rtype(sl.ref) != RTmp)
        return;
    const a = &st.curf.tmp[sl.ref.val].alias;
    if (a.offset == @as(i16, @truncate(a.offset)))
        if (a.type == ALoc or a.type == AEsc or a.type == AUnk) {
            sl.ref = tmpRef(a.base);
            sl.off = @intCast(a.offset);
        };
}

fn killsl(r: Ref, sl: Slice) bool {
    if (rtype(sl.ref) != RTmp)
        return false;
    const a = &st.curf.tmp[sl.ref.val].alias;
    switch (a.type) {
        ALoc, AEsc, AUnk => return req(tmpRef(a.base), r),
        ACon, ASym => return false,
        else => die("unreachable", .{}),
    }
}

/// returns a ref containing the contents of the slice
/// passed as argument, all the bits set to 0 in the
/// mask argument are zeroed in the result;
/// the returned ref has an integer class when the
/// mask does not cover all the bits of the slice,
/// otherwise, it has class sl.cls
/// the procedure returns R when it fails
/// i is the index in b.ins before which to search
/// (null for the end of b)
fn def(sl: Slice, msk: bits, b: *Blk, i: ?uint, il: *Loc) Ref {
    // invariants:
    // -1- b dominates il->blk; so we can use
    //     temporaries of b in il->blk
    // -2- if il->type != LNoLoad, then il->blk
    //     postdominates the original load; so it
    //     is safe to load in il->blk
    // -3- if il->type != LNoLoad, then b
    //     postdominates il->blk (and by 2, the
    //     original load)
    assert(dom(b, il.blk));
    const oldl = st.nlog;
    const oldt = st.curf.ntmp;
    if (defBody(sl, msk, b, i, il)) |r|
        return r;
    // Load:
    st.curf.ntmp = oldt;
    st.nlog = oldl;
    if (il.type != LLoad)
        return R;
    return load(sl, msk, il);
}

/// body of def(); returns null for 'goto Load'
fn defBody(sl: Slice, msk: bits, b: *Blk, i_: ?uint, il: *Loc) ?Ref {
    var sl1: Slice = undefined;
    var msk1: bits = undefined;
    var off: i32 = undefined;
    var cls1: Cls = undefined;
    var op: Opc = undefined;
    var sz: i32 = undefined;
    var r: Ref = undefined;
    var r1: Ref = undefined;
    var l: Loc = undefined;
    var idx = i_ orelse b.nins;
    const cls: Cls = if (sl.sz > 4) Cls.l else Cls.w;
    const msks = lowMask(sl.sz);

    while (idx > 0) {
        idx -= 1;
        var i = &b.ins[idx];
        if (killsl(i.to, sl) or (i.op == .call and escapes(sl.ref, st.curf)))
            return null;
        const ld = isload(i.op);
        if (ld) {
            sz = loadsz(i);
            r1 = i.arg[0];
            r = i.to;
        } else if (isstore(i.op)) {
            sz = storesz(i);
            r1 = i.arg[1];
            r = i.arg[0];
        } else if (i.op == .blit1) {
            assert(rtype(i.arg[0]) == RInt);
            sz = @intCast(@abs(rsval(i.arg[0])));
            assert(idx > 0);
            idx -= 1;
            i = &b.ins[idx];
            assert(i.op == .blit0);
            r1 = i.arg[1];
        } else continue;
        switch (alias(sl.ref, sl.off, sl.sz, r1, sz, &off, st.curf)) {
            MustAlias => {
                if (i.op == .blit0) {
                    sl1 = sl;
                    sl1.ref = i.arg[0];
                    if (off >= 0) {
                        assert(off < sz);
                        sl1.off = off;
                        sz -= off;
                        off = 0;
                    } else {
                        sl1.off = 0;
                        sl1.sz = @intCast(sl1.sz + off);
                    }
                    if (sz > sl1.sz)
                        sz = sl1.sz;
                    assert(sz <= 8);
                    sl1.sz = @intCast(sz);
                }
                if (off < 0) {
                    off = -off;
                    msk1 = shl64(lowMask(sz), 8 * off) & msks;
                    op = .shl;
                } else {
                    msk1 = (lowMask(sz) >> @intCast(8 * off)) & msks;
                    op = .shr;
                }
                if ((msk1 & msk) == 0)
                    continue;
                if (i.op == .blit0) {
                    r = def(sl1, lowMask(sz), b, idx, il);
                    if (req(r, R))
                        return null;
                }
                if (off != 0) {
                    cls1 = cls;
                    if (op == .shr and off + sl.sz > 4)
                        cls1 = .l;
                    cast(&r, cls1, il);
                    r1 = getcon(8 * off, st.curf);
                    r = iins(cls1, op, r, r1, il);
                }
                if ((msk1 & msk) != msk1 or off + sz < sl.sz)
                    mask(cls, &r, msk1 & msk, il);
                if ((msk & ~msk1) != 0) {
                    r1 = def(sl, msk & ~msk1, b, idx, il);
                    if (req(r1, R))
                        return null;
                    r = iins(cls, .@"or", r, r1, il);
                }
                if (msk == msks)
                    cast(&r, sl.cls, il);
                return r;
            },
            MayAlias => {
                if (ld)
                    continue
                else
                    return null;
            },
            NoAlias => continue,
        }
    }

    for (st.ilog[0..st.nlog]) |*ist|
        if (ist.isphi != 0 and ist.bid == b.id)
            if (req(ist.new.phi.m.ref, sl.ref))
                if (ist.new.phi.m.off == sl.off)
                    if (ist.new.phi.m.sz == sl.sz) {
                        r = ist.new.phi.p.to;
                        if (msk != msks)
                            mask(cls, &r, msk, il)
                        else
                            cast(&r, sl.cls, il);
                        return r;
                    };

    var p_it = b.phi;
    while (p_it) |p| : (p_it = p.link)
        if (killsl(p.to, sl))
            // scanning predecessors in that
            // case would be unsafe
            return null;

    if (b.npred == 0)
        return null;
    if (b.npred == 1) {
        const bp = b.pred[0];
        assert(bp.loop >= il.blk.loop);
        l = il.*;
        if (bp.s2 != null)
            l.type = LNoLoad;
        r1 = def(sl, msk, bp, null, &l);
        if (req(r1, R))
            return null;
        return r1;
    }

    r = newtmp("ld", sl.cls, st.curf);
    const p = pnew(Phi);
    st.nlog += 1;
    vgrow(&st.ilog, st.nlog);
    const ist = &st.ilog[st.nlog - 1];
    ist.isphi = 1;
    ist.bid = b.id;
    ist.new.phi.m = sl;
    ist.new.phi.p = p;
    p.to = r;
    p.cls = sl.cls;
    p.narg = b.npred;
    p.arg = vnewT(Ref, p.narg, PFn);
    p.blk = vnewT(*Blk, p.narg, PFn);
    for (0..b.npred) |np| {
        const bp = b.pred[np];
        if (bp.s2 == null and il.type != LNoLoad and bp.loop < il.blk.loop)
            l.type = LLoad
        else
            l.type = LNoLoad;
        l.blk = bp;
        l.off = bp.nins;
        r1 = def(sl, msks, bp, null, &l);
        if (req(r1, R))
            return null;
        p.arg[np] = r1;
        p.blk[np] = bp;
        // XXX - multiplicity in predecessors!!!
    }
    if (msk != msks)
        mask(cls, &r, msk, il);
    return r;
}

fn icmp(a: Insert, b: Insert) std.math.Order {
    const c = std.math.order(a.bid, b.bid);
    if (c != .eq)
        return c;
    if (a.isphi != 0 and b.isphi != 0)
        return .eq;
    if (a.isphi != 0)
        return .lt;
    if (b.isphi != 0)
        return .gt;
    const d = std.math.order(a.off, b.off);
    if (d != .eq)
        return d;
    return std.math.order(a.num, b.num);
}

/// require rpo ssa alias
pub fn loadopt(f: *Fn) void {
    st.curf = f;
    st.ilog = vnewT(Insert, 0, PHeap);
    st.nlog = 0;
    st.inum = 0;
    var b_it = f.start;
    while (b_it) |b| : (b_it = b.link) {
        for (b.insns(), 0..) |*i, n| {
            if (!isload(i.op))
                continue;
            const sz = loadsz(i);
            var sl: Slice = .{ .ref = i.arg[0], .off = 0, .sz = @intCast(sz), .cls = i.cls };
            var l: Loc = .{ .type = LRoot, .off = @intCast(n), .blk = b };
            rebase(&sl);
            i.arg[1] = def(sl, lowMask(sz), b, @intCast(n), &l);
        }
    }
    sort(Insert, st.ilog[0..st.nlog], icmp);
    vgrow(&st.ilog, st.nlog + 1);
    st.ilog[st.nlog].bid = f.nblk; // add a sentinel
    var ib = vnewT(Ins, 0, PHeap);
    var ist: [*]Insert = st.ilog;
    for (f.blks(), 0..) |b, n| {
        while (ist[0].bid == n and ist[0].isphi != 0) : (ist += 1) {
            ist[0].new.phi.p.link = b.phi;
            b.phi = ist[0].new.phi.p;
        }
        var ni: uint = 0;
        var nt: uint = 0;
        while (true) {
            var i: *Ins = undefined;
            if (ist[0].bid == n and ist[0].off == ni) {
                i = &ist[0].new.ins;
                ist += 1;
            } else {
                if (ni == b.nins)
                    break;
                i = &b.ins[ni];
                ni += 1;
                if (isload(i.op) and !req(i.arg[1], R)) {
                    const ext = Opc.extsb.offset(i.op.diff(.loadsb));
                    sw: switch (i.op) {
                        .loadsb, .loadub, .loadsh, .loaduh => i.op = ext,
                        .loadsw, .loaduw => {
                            if (i.cls == .l) {
                                i.op = ext;
                            } else continue :sw .load;
                        },
                        .load => i.op = .copy,
                        else => die("unreachable", .{}),
                    }
                    i.arg[0] = i.arg[1];
                    i.arg[1] = R;
                }
            }
            nt += 1;
            vgrow(&ib, nt);
            ib[nt - 1] = i.*;
        }
        idup(b, ib[0..nt]);
    }
    vfree(ib);
    vfree(st.ilog);
    if (all.debug['M'] != 0) {
        dprint("\n> After load elimination:\n", .{});
        printfn(f, all.dbg) catch {};
    }
}
