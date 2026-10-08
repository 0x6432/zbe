//! One-to-one translation of alias.c
const std = @import("std");
const assert = std.debug.assert;
// -- imports --
const all = @import("all.zig");
const ABot = all.ABot;
const ACon = all.ACon;
const AEsc = all.AEsc;
const ALoc = all.ALoc;
const ASym = all.ASym;
const AUnk = all.AUnk;
const Alias = all.Alias;
const BIT = all.BIT;
const Blk = all.Blk;
const CAddr = all.CAddr;
const CBits = all.CBits;
const Fn = all.Fn;
const Jretc = all.Jretc;
const MayAlias = all.MayAlias;
const MustAlias = all.MustAlias;
const NBit = all.NBit;
const NoAlias = all.NoAlias;
const Oadd = all.ops.Oadd;
const Oalloc = all.Oalloc;
const Oalloc1 = all.Oalloc1;
const Oargc = all.ops.Oargc;
const Oblit0 = all.ops.Oblit0;
const Oblit1 = all.ops.Oblit1;
const Ocopy = all.ops.Ocopy;
const Phi = all.Phi;
const R = all.R;
const RCon = all.RCon;
const RInt = all.RInt;
const RTmp = all.RTmp;
const RType = all.RType;
const Ref = all.Ref;
const astack = all.astack;
const bits = all.bits;
const die = all.die;
const isload = all.isload;
const isstore = all.isstore;
const req = all.req;
const rsval = all.rsval;
const rtype = all.rtype;
const storesz = all.storesz;
const symeq = all.symeq;
const uint = all.uint;
// -- end imports --

pub fn getalias(a: *Alias, r: Ref, f: *Fn) void {
    switch (rtype(r)) {
        RTmp => {
            a.* = f.tmp[r.val].alias;
            if (astack(a.type) != 0)
                a.type = a.slot.*.type;
            assert(a.type != ABot);
        },
        RCon => {
            const c = &f.con[r.val];
            if (c.*.type == CAddr) {
                a.type = ASym;
                a.u.sym = c.*.sym;
            } else a.type = ACon;
            a.offset = c.*.bits.i;
            a.slot = null;
        },
        else => die("unreachable", .{}),
    }
}

pub fn alias(p: Ref, op: i32, sp: i32, q: Ref, sq: i32, delta: *i32, f: *Fn) i32 {
    var ap: Alias = undefined;
    var aq: Alias = undefined;

    getalias(&ap, p, f);
    getalias(&aq, q, f);
    ap.offset +%= op;
    // when delta is meaningful (ovlap == 1),
    // we do not overflow int because sp and
    // sq are bounded by 2^28
    delta.* = @truncate(ap.offset -% aq.offset);
    const ovlap = ap.offset < aq.offset +% sq and aq.offset < ap.offset +% sp;

    if (astack(ap.type) != 0 and astack(aq.type) != 0) {
        // if both are offsets of the same
        // stack slot, they alias iif they
        // overlap
        if (ap.base == aq.base and ovlap)
            return MustAlias;
        return NoAlias;
    }

    if (ap.type == ASym and aq.type == ASym) {
        // they conservatively alias if the
        // symbols are different, or they
        // alias for sure if they overlap
        if (!symeq(ap.u.sym, aq.u.sym))
            return MayAlias;
        if (ovlap)
            return MustAlias;
        return NoAlias;
    }

    if ((ap.type == ACon and aq.type == ACon) or (ap.type == aq.type and ap.base == aq.base)) {
        assert(ap.type == ACon or ap.type == AUnk);
        // if they have the same base, we
        // can rely on the offsets only
        if (ovlap)
            return MustAlias;
        return NoAlias;
    }

    // if one of the two is unknown
    // there may be aliasing unless
    // the other is provably local
    if (ap.type == AUnk and aq.type != ALoc)
        return MayAlias;
    if (aq.type == AUnk and ap.type != ALoc)
        return MayAlias;

    return NoAlias;
}

pub fn escapes(r: Ref, f: *Fn) bool {
    if (rtype(r) != RTmp)
        return true;
    const a = &f.tmp[r.val].alias;
    return astack(a.*.type) == 0 or a.*.slot.*.type == AEsc;
}

fn esc(r: Ref, f: *Fn) void {
    assert(rtype(r) <= RType);
    if (rtype(r) == RTmp) {
        const a = &f.tmp[r.val].alias;
        if (astack(a.*.type) != 0)
            a.*.slot.*.type = AEsc;
    }
}

fn store(r: Ref, sz: i32, f: *Fn) void {
    var m: bits = undefined;

    if (rtype(r) == RTmp) {
        const a = &f.tmp[r.val].alias;
        if (a.*.slot != null) {
            assert(astack(a.*.type) != 0);
            const off = a.*.offset;
            if (sz >= NBit or (off < 0 or off >= NBit))
                m = @bitCast(@as(i64, -1))
            else
                m = (BIT(sz) -% 1) << @intCast(off);
            a.*.slot.*.u.loc.m |= m;
        }
    }
}

pub fn fillalias(f: *Fn) void {
    var a0: Alias = undefined;
    var a1: Alias = undefined;

    var t: i32 = 0;
    while (t < f.ntmp) : (t += 1)
        f.tmp[@intCast(t)].alias.type = ABot;
    var n: uint = 0;
    while (n < f.nblk) : (n += 1) {
        const b = f.rpo[n];
        var p: [*c]Phi = b.*.phi;
        while (p != null) : (p = p.*.link) {
            assert(rtype(p.*.to) == RTmp);
            const a = &f.tmp[p.*.to.val].alias;
            assert(a.*.type == ABot);
            a.*.type = AUnk;
            a.*.base = @intCast(p.*.to.val);
            a.*.offset = 0;
            a.*.slot = null;
        }
        var i = b.*.ins;
        while (i < &b.*.ins[b.*.nins]) : (i += 1) {
            var a: [*c]Alias = null;
            if (!req(i.*.to, R)) {
                assert(rtype(i.*.to) == RTmp);
                a = &f.tmp[i.*.to.val].alias;
                assert(a.*.type == ABot);
                if (Oalloc <= i.*.op and i.*.op <= Oalloc1) {
                    a.*.type = ALoc;
                    a.*.slot = a;
                    a.*.u.loc.sz = -1;
                    if (rtype(i.*.arg[0]) == RCon) {
                        const c = &f.con[i.*.arg[0].val];
                        const x = c.*.bits.i;
                        if (c.*.type == CBits)
                            if (0 <= x and x <= NBit) {
                                a.*.u.loc.sz = @intCast(x);
                            };
                    }
                } else {
                    a.*.type = AUnk;
                    a.*.slot = null;
                }
                a.*.base = @intCast(i.*.to.val);
                a.*.offset = 0;
            }
            if (i.*.op == Ocopy) {
                assert(a != null);
                getalias(a, i.*.arg[0], f);
            }
            if (i.*.op == Oadd) {
                getalias(&a0, i.*.arg[0], f);
                getalias(&a1, i.*.arg[1], f);
                if (a0.type == ACon) {
                    a.* = a1;
                    a.*.offset +%= a0.offset;
                } else if (a1.type == ACon) {
                    a.* = a0;
                    a.*.offset +%= a1.offset;
                }
            }
            if (req(i.*.to, R) or a.*.type == AUnk)
                if (i.*.op != Oblit0) {
                    if (!isload(i.*.op))
                        esc(i.*.arg[0], f);
                    if (!isstore(i.*.op))
                        if (i.*.op != Oargc)
                            esc(i.*.arg[1], f);
                };
            if (i.*.op == Oblit0) {
                i += 1;
                assert(i.*.op == Oblit1);
                assert(rtype(i.*.arg[0]) == RInt);
                const sz: i32 = @intCast(@abs(rsval(i.*.arg[0])));
                store((i - 1).*.arg[1], sz, f);
            }
            if (isstore(i.*.op))
                store(i.*.arg[1], storesz(i), f);
        }
        if (b.*.jmp.type != Jretc)
            esc(b.*.jmp.arg, f);
    }
    var b_it: ?*Blk = f.start;
    while (b_it) |b| : (b_it = b.link) {
        var p_it: ?*Phi = b.phi;
        while (p_it) |p| : (p_it = p.link) {
            var k: uint = 0;
            while (k < p.narg) : (k += 1)
                esc(p.arg[k], f);
        }
    }
}
