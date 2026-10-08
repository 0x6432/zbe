//! One-to-one translation of copy.c
const std = @import("std");
const assert = std.debug.assert;
// -- imports --
const all = @import("all.zig");
const BIT = all.BIT;
const Blk = all.Blk;
const CON_Z = all.CON_Z;
const Fn = all.Fn;
const INS0 = all.INS0;
const Ins = all.Ins;
const Jjmp = all.Jjmp;
const Jjnz = all.Jjnz;
const KBASE = all.KBASE;
const KWIDE = all.KWIDE;
const Kw = all.Kw;
const Oand = all.ops.Oand;
const Ocopy = all.ops.Ocopy;
const Oextsb = all.ops.Oextsb;
const Oextsw = all.ops.Oextsw;
const Oextub = all.ops.Oextub;
const Oextuh = all.ops.Oextuh;
const Oextuw = all.ops.Oextuw;
const Onop = all.ops.Onop;
const Oor = all.ops.Oor;
const Osar = all.ops.Osar;
const Oshr = all.ops.Oshr;
const Oxor = all.ops.Oxor;
const PFn = all.PFn;
const Phi = all.Phi;
const R = all.R;
const RTmp = all.RTmp;
const Ref = all.Ref;
const UIns = all.UIns;
const UPhi = all.UPhi;
const WFull = all.WFull;
const Wsb = all.Wsb;
const Wsh = all.Wsh;
const Wsw = all.Wsw;
const Wub = all.Wub;
const Wuh = all.Wuh;
const Wuw = all.Wuw;
const argcls = all.argcls;
const bits = all.bits;
const icpy = all.icpy;
const iscmp = all.iscmp;
const isconbits = all.isconbits;
const isext = all.isext;
const ispar = all.ispar;
const newtmp = all.newtmp;
const phiarg = all.phiarg;
const req = all.req;
const rtype = all.rtype;
const uint = all.uint;
const vnewT = all.vnewT;
const zeroval = all.zeroval;
// -- end imports --

const Ext = extern struct {
    zext: i8,
    nopw: i8, // is a no-op if arg width is <= nopw
    usew: i8, // uses only the low usew bits of arg
};

const ext_tbl = [_]Ext{
    .{ .zext = 0, .nopw = 7, .usew = 8 }, // extsb
    .{ .zext = 1, .nopw = 8, .usew = 8 }, // extub
    .{ .zext = 0, .nopw = 15, .usew = 16 }, // extsh
    .{ .zext = 1, .nopw = 16, .usew = 16 }, // extuh
    .{ .zext = 0, .nopw = 31, .usew = 32 }, // extsw
    .{ .zext = 1, .nopw = 32, .usew = 32 }, // extuw
};

fn ext(i: *Ins, e: *Ext) bool {
    if (!isext(i.op))
        return false;
    e.* = ext_tbl[i.op - Oextsb];
    return true;
}

/// number of significant bits in v
fn bitwidth(v: u64) i32 {
    return 64 - @as(i32, @clz(v));
}

fn visit(f: *Fn, r: Ref, w: i32, func: *const fn (*Fn, Ref, i32) bool) bool {
    const ret = func(f, r, w);
    var b_it: ?*Blk = f.start;
    while (b_it) |b| : (b_it = b.link) {
        var p_it: ?*Phi = b.phi;
        while (p_it) |p| : (p_it = p.link)
            p.visit = 0;
    }
    return ret;
}

fn uwl(f: *Fn, r: Ref, w: i32) bool {
    var e: Ext = undefined;
    var rc: Ref = undefined;
    var v: i64 = undefined;

    assert(rtype(r) == RTmp);
    const t = &f.tmp[r.val];
    for (t.use[0..t.nuse]) |*u| {
        switch (u.type) {
            UPhi => {
                const p = u.u.phi;
                // during gvn, phi nodes may be
                // replaced by other temps; in
                // this case, the replaced phi
                // uses are added to the
                // replacement temp uses and
                // Phi.to is set to R
                if (p.visit != 0 or req(p.to, R))
                    continue;
                p.visit = 1;
                if (uwl(f, p.to, w))
                    continue;
            },
            UIns => {
                const i = u.u.ins;
                if (i.op == Ocopy)
                    if (uwl(f, i.to, w))
                        continue;
                if (ext(i, &e)) {
                    if (e.usew <= w)
                        continue;
                    if (uwl(f, i.to, w))
                        continue;
                }
                if (i.op == Oand) {
                    if (req(r, i.arg[0]))
                        rc = i.arg[1]
                    else {
                        assert(req(r, i.arg[1]));
                        rc = i.arg[0];
                    }
                    if (isconbits(f, rc, &v) and bitwidth(@bitCast(v)) <= w)
                        continue;
                }
            },
            else => {},
        }
        return false;
    }
    return true;
}

/// no more than w bits are used
fn usewidthle(f: *Fn, r: Ref, w: i32) bool {
    return visit(f, r, w, uwl);
}

fn min(v1: i64, v2: i64) i32 {
    return @intCast(@min(v1, v2));
}

fn dwl(f: *Fn, r: Ref, w_: i32) bool {
    var w = w_;
    var e: Ext = undefined;
    var v: i64 = undefined;
    var x: i32 = undefined;

    if (isconbits(f, r, &v) and bitwidth(@bitCast(v)) <= w)
        return true;
    if (w <= 0)
        return false;
    if (rtype(r) != RTmp)
        return false;
    const t = &f.tmp[r.val];
    if (t.cls != Kw)
        return false;

    if (t.def == null) {
        // phi def
        var p_it = f.rpo[t.bid].phi;
        const p = while (p_it) |p| : (p_it = p.link) {
            if (req(p.to, r)) break p;
        } else unreachable;
        if (p.visit != 0 and p.visit <= w)
            return true;
        p.visit = w;
        for (p.arg[0..p.narg]) |a|
            if (!dwl(f, a, w))
                return false;
        return true;
    }

    const i = t.def.?;
    if (i.op == Ocopy)
        return dwl(f, i.arg[0], w);
    if (i.op == Oshr or i.op == Osar) {
        if (isconbits(f, i.arg[1], &v))
            if (0 < v and v <= 32) {
                if (i.op == Oshr and w + v >= 32)
                    return true;
                if (w < 32) {
                    if (i.op == Osar)
                        w = min(31, w + v)
                    else
                        w = min(32, w + v);
                }
            };
        return dwl(f, i.arg[0], w);
    }
    if (iscmp(i.op, &x, &x))
        return w >= 1;
    if (i.op == Oand) {
        if (dwl(f, i.arg[0], w) or dwl(f, i.arg[1], w))
            return true;
        return false;
    }
    if (i.op == Oor or i.op == Oxor) {
        if (dwl(f, i.arg[0], w) and dwl(f, i.arg[1], w))
            return true;
        return false;
    }
    if (ext(i, &e)) {
        if (e.zext != 0 and e.usew <= w)
            return true;
        w = min(w, e.nopw);
        return dwl(f, i.arg[0], w);
    }

    return false;
}

/// is the ref narrower than w bits
fn defwidthle(f: *Fn, r: Ref, w: i32) bool {
    return visit(f, r, w, dwl);
}

fn isw1(f: *Fn, r: Ref) bool {
    return defwidthle(f, r, 1);
}

/// insert early extub/extuh instructions
/// for pars used only narrowly; this
/// helps factoring extensions out of
/// loops
///
/// needs use; breaks use
pub fn narrowpars(f: *Fn) void {
    var e: Ins = undefined;

    // only useful for functions with loops
    var loop = false;
    var b_it = f.start;
    while (b_it) |b| : (b_it = b.link)
        if (b.loop > 1) {
            loop = true;
            break;
        };
    if (!loop)
        return;

    const b = f.start.?;

    var npar: uint = 0;
    for (b.ins[0..b.nins]) |*i| {
        if (!ispar(i.op))
            break;
        npar += 1;
    }
    if (npar == 0)
        return;

    // make room for one (possibly nop) extension per par
    const nins = b.nins + npar;
    const ins = vnewT(Ins, nins, PFn);
    _ = icpy(ins, b.ins, npar);
    _ = icpy(ins + 2 * npar, b.ins + npar, b.nins - npar);
    b.ins = ins;
    b.nins = nins;

    for (b.ins[0..npar], b.ins[npar .. 2 * npar]) |*i, *ext_slot| {
        e = INS0(Onop);
        if (i.cls == Kw)
            if (usewidthle(f, i.to, 16)) {
                e.op = Oextuh;
                if (usewidthle(f, i.to, 8))
                    e.op = Oextub;
                const r = newtmp("vw", i.cls, f);
                e.cls = i.cls;
                e.to = i.to;
                e.arg[0] = r;
                i.to = r;
            };
        ext_slot.* = e;
    }
}

/// which extensions are copies for a given
/// argument width
const extcpy = blk: {
    var t: [Wuw + 1]bits = undefined;
    t[WFull] = 0;
    t[Wsb] = BIT(Wsb) | BIT(Wsh) | BIT(Wsw);
    t[Wub] = BIT(Wub) | BIT(Wuh) | BIT(Wuw);
    t[Wsh] = BIT(Wsh) | BIT(Wsw);
    t[Wuh] = BIT(Wuh) | BIT(Wuw);
    t[Wsw] = BIT(Wsw);
    t[Wuw] = BIT(Wuw);
    break :blk t;
};

pub fn copyref(f: *Fn, b: *Blk, i: *Ins) Ref {
    var e: Ext = undefined;
    var v: i64 = undefined;
    var z: i32 = undefined;
    const op = &all.optab[i.op];

    if (i.op == Ocopy)
        return i.arg[0];

    // op identity value
    if (op.hasid != 0 and KBASE(i.cls) == 0 // integer only - fp NaN!
    and req(i.arg[1], all.con01[op.idval]) and (op.cmpeqwl == 0 or isw1(f, i.arg[0])))
        return i.arg[0];

    // idempotent op with identical args
    if (op.idemp != 0 and req(i.arg[0], i.arg[1]))
        return i.arg[0];

    // integer cmp with identical args
    if ((op.cmpeqwl != 0 or op.cmplgtewl != 0) and req(i.arg[0], i.arg[1]))
        return all.con01[op.eqval];

    // cmpeq/ne 0 with 0/non-0 inference
    if (op.cmpeqwl != 0 and req(i.arg[1], CON_Z) and zeroval(f, b, i.arg[0], argcls(i, 0), &z))
        return all.con01[@intCast(op.eqval ^ z ^ 1)];

    // redundant and mask
    if (i.op == Oand and isconbits(f, i.arg[1], &v) and (v > 0 and ((v +% 1) & v) == 0) and defwidthle(f, i.arg[0], bitwidth(@bitCast(v))))
        return i.arg[0];

    if (i.cls == Kw and (i.op == Oextsw or i.op == Oextuw))
        return i.arg[0];

    if (ext(i, &e) and rtype(i.arg[0]) == RTmp) {
        const t = &f.tmp[i.arg[0].val];
        assert(KBASE(t.cls) == 0);

        // do not break typing by returning
        // a narrower temp
        if (KWIDE(i.cls) > KWIDE(t.cls))
            return R;

        const w = Wsb + (i.op - Oextsb);
        if ((BIT(w) & extcpy[@intCast(t.width)]) != 0)
            return i.arg[0];

        // avoid eliding extensions of params
        // inserted in the start block; their
        // point is to make further extensions
        // redundant
        if ((t.def == null or !ispar(t.def.?.op)) and usewidthle(f, i.to, e.usew))
            return i.arg[0];

        if (defwidthle(f, i.arg[0], e.nopw))
            return i.arg[0];
    }

    return R;
}

fn phieq(pa: *Phi, pb: *Phi) bool {
    assert(pa.narg == pb.narg);
    var n: uint = 0;
    while (n < pa.narg) : (n += 1) {
        const r = phiarg(pb, pa.blk[n]);
        if (!req(pa.arg[n], r))
            return false;
    }
    return true;
}

pub fn phicopyref(f: *Fn, b: *Blk, p: *Phi) Ref {
    // identical args
    var r = R;
    for (p.arg[0..p.narg]) |a| {
        if (!req(a, p.to)) {
            if (req(r, R))
                r = a
            else if (!req(a, r))
                break;
        }
    } else return r;

    // same as a previous phi
    var p1 = b.phi.?;
    while (p1 != p) : (p1 = p1.link.?) {
        if (phieq(p1, p))
            return p1.to;
    }

    // can be replaced by a
    // dominating jnz arg
    const d = b.idom.?;
    if (p.narg != 2 or d.jmp.type != Jjnz or !isw1(f, d.jmp.arg))
        return R;

    var s = [2]?*Blk{ null, null };
    for (p.arg[0..2], p.blk[0..2]) |a, pb| {
        for (0..2) |c| {
            if (req(a, all.con01[c]))
                s[c] = pb;
        }
    }

    // if s1 ends with a jnz on either b
    // or s2; the inference below is wrong
    // without the jump type checks
    if (d.s1 == s[1] and d.s2 == s[0] and d.s1.?.jmp.type == Jjmp and d.s2.?.jmp.type == Jjmp)
        return d.jmp.arg;

    return R;
}
