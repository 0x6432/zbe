//! One-to-one translation of gvn.c
const std = @import("std");
const assert = std.debug.assert;
// -- imports --
const all = @import("all.zig");
const Cls = all.Cls;
const J = all.J;
const U = all.U;
const Opc = all.Opc;
const Blk = all.Blk;
const CBits = all.CBits;
const CON_Z = all.CON_Z;
const Con = all.Con;
const Fn = all.Fn;
const INS0 = all.INS0;
const Ins = all.Ins;
const KBASE = all.KBASE;
const KWIDE = all.KWIDE;
const Phi = all.Phi;
const R = all.R;
const RCon = all.RCon;
const RTmp = all.RTmp;
const Ref = all.Ref;
const Tmp = all.Tmp;
const UXXX = all.UXXX;
const Use = all.Use;
const addins = all.addins;
const adduse = all.adduse;
const argcls = all.argcls;
const copyref = all.copyref;
const die = all.die;
const dom = all.dom;
const dprint = all.dprint;
const ealloc = all.ealloc;
const efree = all.efree;
const fillcfg = all.fillcfg;
const fillloop = all.fillloop;
const filluse = all.filluse;
const foldint = all.foldint;
const foldref = all.foldref;
const getcon = all.getcon;
const isconbits = all.isconbits;
const narrowpars = all.narrowpars;
const newcon = all.newcon;
const phicopyref = all.phicopyref;
const pinned = all.pinned;
const printfn = all.printfn;
const reachesnotvia = all.reachesnotvia;
const req = all.req;
const rtype = all.rtype;
const ssacheck = all.ssacheck;
const uint = all.uint;
// -- end imports --

const NOID: uint = std.math.maxInt(uint);

inline fn mix(x0: uint, x1: uint) uint {
    return x0 +% 17 *% x1;
}

inline fn rhash(r: Ref) uint {
    return mix(r.type, r.val);
}

fn ihash(i: *Ins) uint {
    var h = mix(i.op.int(), @as(u32, @intCast(i.cls.int())));
    h = mix(h, rhash(i.arg[0]));
    h = mix(h, rhash(i.arg[1]));
    return h;
}

fn ieq(ia: *Ins, ib: *Ins) bool {
    return ia.op == ib.op and ia.cls == ib.cls and
        req(ia.arg[0], ib.arg[0]) and req(ia.arg[1], ib.arg[1]);
}

var gvntbl: []?*Ins = &.{};

fn gvndup(i: *Ins, insert: bool) ?*Ins {
    var idx = ihash(i) % gvntbl.len;
    while (gvntbl[idx]) |ii| {
        if (ieq(i, ii))
            return ii;
        idx += 1;
        if (idx == gvntbl.len)
            idx = 0;
    }
    if (insert)
        gvntbl[idx] = i;
    return null;
}

fn replaceuse(f: *Fn, u: *Use, r1: Ref, r2: Ref) void {
    const t2: ?*Tmp = if (rtype(r2) == RTmp) &f.tmp[r2.val] else null;
    const b = f.rpo[u.bid];
    switch (u.type) {
        .phi => {
            const p = u.u.phi;
            for (p.arg[0..p.narg]) |*pr|
                if (req(pr.*, r1)) {
                    pr.* = r2;
                };
            if (t2) |t|
                adduse(t, .phi, b, (p));
        },
        .ins => {
            const i = u.u.ins;
            var n: usize = 0;
            while (n < 2) : (n += 1)
                if (req(i.arg[n], r1)) {
                    i.arg[n] = r2;
                };
            if (t2) |t|
                adduse(t, .ins, b, (i));
        },
        .jmp => {
            if (req(b.jmp.arg, r1))
                b.jmp.arg = r2;
            if (t2) |t|
                adduse(t, .jmp, b, null);
        },
        UXXX => die("unreachable", .{}),
    }
}

fn replaceuses(f: *Fn, r1: Ref, r2: Ref) void {
    assert(rtype(r1) == RTmp);
    const t1 = &f.tmp[r1.val];
    for (t1.use.?[0..t1.nuse]) |*u|
        replaceuse(f, u, r1, r2);
    t1.nuse = 0;
}

fn dedupphi(f: *Fn, b: *Blk) void {
    var pp: *?*Phi = &b.phi;
    while (pp.*) |p| {
        const r = phicopyref(f, b, p);
        if (!req(r, R)) {
            replaceuses(f, p.to, r);
            p.to = R;
            pp.* = p.link;
        } else pp = &p.link;
    }
}

fn rcmp(a: Ref, b: Ref) i32 {
    if (rtype(a) != rtype(b))
        return rtype(a) - rtype(b);
    return @as(i32, (a.val)) - @as(i32, (b.val));
}

fn normins(f: *Fn, i: *Ins) void {
    var v: i64 = undefined;

    // truncate constant bits to
    // 32 bits for s/w uses
    var n: usize = 0;
    while (n < 2) : (n += 1) {
        if (KWIDE(argcls(i, n)) == 0)
            if (isconbits(f, i.arg[n], &v))
                if ((v & 0xffffffff) != v) {
                    i.arg[n] = getcon(v & 0xffffffff, f);
                };
    }
    // order arg[0] <= arg[1] for
    // commutative ops, preferring
    // RTmp in arg[0]
    if (all.optab[i.op.int()].commutes != 0)
        if (rcmp(i.arg[0], i.arg[1]) > 0) {
            const r = i.arg[1];
            i.arg[1] = i.arg[0];
            i.arg[0] = r;
        };
}

fn negcon(cls: anytype, c: *Con) bool {
    var z = std.mem.zeroes(Con);
    z.type = CBits;
    z.bits.i = 0;
    return foldint(c, all.ops.num(.sub), cls != .w, &z, c);
}

fn assoccon(f: *Fn, b: *Blk, i_1: *Ins) void {
    var c: Con = undefined;

    var op: i32 = @intCast(i_1.op.int());
    if (op == Opc.sub.int())
        op = all.ops.num(.add);

    if (all.optab[@intCast(op)].assoc == 0 or KBASE(i_1.cls) != 0 or rtype(i_1.arg[0]) != RTmp or rtype(i_1.arg[1]) != RCon)
        return;
    var c1 = f.con[i_1.arg[1].val];

    const t2 = &f.tmp[i_1.arg[0].val];
    const i_2 = t2.def orelse return;

    if (op != all.ops.num(if (i_2.op == .sub) .add else i_2.op) or rtype(i_2.arg[1]) != RCon)
        return;
    var c2 = f.con[i_2.arg[1].val];

    assert(KBASE(i_2.cls) == 0);
    assert(KWIDE(i_2.cls) >= KWIDE(i_1.cls));

    if (i_1.op == .sub and negcon(i_1.cls, &c1))
        return;
    if (i_2.op == .sub and negcon(i_2.cls, &c2))
        return;
    if (foldint(&c, op, i_1.cls != .w, &c1, &c2))
        return;

    if (op == Opc.add.int() and c.type == CBits)
        if ((i_1.cls == .l and c.bits.i < 0) or (i_1.cls == .w and @as(i32, @truncate(c.bits.i)) < 0)) {
            const fail = negcon(i_1.cls, &c);
            assert(!fail);
            op = all.ops.num(.sub);
        };

    i_1.op = all.ops.of(op);
    i_1.arg[0] = i_2.arg[0];
    i_1.arg[1] = newcon(&c, f);
    adduse(&f.tmp[i_1.arg[0].val], .ins, b, (i_1));
}

fn killins(f: *Fn, i: *Ins, r: Ref) void {
    replaceuses(f, i.to, r);
    i.* = INS0(.nop);
}

fn dedupins(f: *Fn, b: *Blk, i: *Ins) void {
    normins(f, i);
    if (i.op == .nop or pinned(i))
        return;

    // when sel instructions are inserted
    // before gvn, we may want to optimize
    // them here
    assert(i.op != .sel0);
    assert(!req(i.to, R));
    assoccon(f, b, i);

    var r = copyref(f, b, i);
    if (!req(r, R)) {
        killins(f, i, r);
        return;
    }
    r = foldref(f, i);
    if (!req(r, R)) {
        killins(f, i, r);
        return;
    }
    if (gvndup(i, true)) |i_1|
        killins(f, i, i_1.to);
}

pub fn cmpeqz(f: *Fn, r: Ref, arg: *Ref, cls: *i32, eqval: *i32) bool {
    if (rtype(r) != RTmp)
        return false;
    const i = f.tmp[r.val].def orelse return false;
    if (all.optab[i.op.int()].cmpeqwl == 0 or !req(i.arg[1], CON_Z))
        return false;
    arg.* = i.arg[0];
    cls.* = argcls(i, 0);
    eqval.* = all.optab[i.op.int()].eqval;
    return true;
}

fn branchdom(f: *Fn, bif: *Blk, bbr1: *Blk, bbr2: *Blk, b: *Blk) bool {
    assert(bif.jmp.type == .jnz);
    return b != bif and dom(bbr1, b) and !reachesnotvia(f, bbr2, b, bif);
}

fn domzero(f: *Fn, d: *Blk, b: *Blk, z: *i32) bool {
    if (branchdom(f, d, d.s1.?, d.s2.?, b)) {
        z.* = 0;
        return true;
    }
    if (branchdom(f, d, d.s2.?, d.s1.?, b)) {
        z.* = 1;
        return true;
    }
    return false;
}

/// infer 0/non-0 value from dominating jnz
pub fn zeroval(f: *Fn, b: *Blk, r: Ref, cls: i32, z: *i32) bool {
    var arg: Ref = undefined;
    var cls1: i32 = undefined;
    var eqval: i32 = undefined;

    var d_it: ?*Blk = b.idom;
    while (d_it) |d| : (d_it = d.idom) {
        if (d.jmp.type != .jnz)
            continue;
        if (req(r, d.jmp.arg) and cls == Cls.w.int() and domzero(f, d, b, z)) {
            return true;
        }
        if (cmpeqz(f, d.jmp.arg, &arg, &cls1, &eqval) and req(r, arg) and cls == cls1 and domzero(f, d, b, z)) {
            z.* ^= eqval;
            return true;
        }
    }
    return false;
}

fn usecls(u: *Use, r: Ref, cls: i32) i32 {
    switch (u.type) {
        .ins => {
            var k: i32 = all.knum(.x); // widest use
            if (req(u.u.ins.arg[0], r))
                k = argcls(u.u.ins, 0);
            if (req(u.u.ins.arg[1], r))
                if (k == Cls.x.int() or KWIDE(k) == 0) {
                    k = argcls(u.u.ins, 1);
                };
            return if (k == Cls.x.int()) cls else k;
        },
        .phi => {
            if (req(u.u.phi.to, R))
                return cls; // eliminated
            return u.u.phi.cls.int();
        },
        .jmp => return all.knum(.w),
        else => {},
    }
    die("unreachable", .{});
}

fn propjnz0(f: *Fn, bif: *Blk, s0: *Blk, snon0: *Blk, r: Ref, cls: i32) void {
    if (s0.npred != 1 or rtype(r) != RTmp)
        return;
    const t = &f.tmp[r.val];
    for (t.use.?[0..t.nuse]) |*u| {
        const b = f.rpo[u.bid];
        // we may compare an l temp with a w
        // comparison; so check that the use
        // does not involve high bits
        if (usecls(u, r, cls) == cls)
            if (branchdom(f, bif, s0, snon0, b))
                replaceuse(f, u, r, CON_Z);
    }
}

fn dedupjmp(f: *Fn, b: *Blk) void {
    var v: i64 = undefined;
    var arg: Ref = undefined;
    var cls: i32 = undefined;
    var eqval: i32 = undefined;
    var z: i32 = undefined;

    if (b.jmp.type != .jnz)
        return;

    // propagate jmp arg as 0 through s2
    propjnz0(f, b, b.s2.?, b.s1.?, b.jmp.arg, all.knum(.w));
    // propagate cmp eq/ne 0 def of jmp arg as 0
    if (cmpeqz(f, b.jmp.arg, &arg, &cls, &eqval)) {
        const ps = [2]*Blk{ b.s1.?, b.s2.? };
        propjnz0(f, b, ps[@intCast(eqval ^ 1)], ps[@intCast(eqval)], arg, cls);
    }

    // collapse trivial/constant jnz to jmp
    v = 1;
    z = 0;
    if (b.s1 == b.s2 or isconbits(f, b.jmp.arg, &v) or zeroval(f, b, b.jmp.arg, all.knum(.w), &z)) {
        if (v == 0 or z != 0)
            b.s1 = b.s2;
        // we later move active ins out of dead blks
        b.s2 = null;
        b.jmp.type = .jmp;
        b.jmp.arg = R;
    }
}

fn rebuildcfg(f: *Fn) void {
    const rpo = ealloc(*Blk, f.nblk)[0..f.nblk];
    @memcpy(rpo, f.rpo[0..f.nblk]);

    fillcfg(f);

    // move instructions that were in
    // killed blocks and may be active
    // in the computation in the start
    // block
    const s = f.start.?;
    for (rpo) |b| {
        if (b.id != NOID)
            continue;
        // blk unreachable after GVN
        assert(b != s);
        for (b.ins[0..b.nins]) |*i|
            if (all.optab[i.op.int()].pinned == 0)
                if (gvndup(i, false) == i)
                    addins(&s.ins, &s.nins, i);
    }
    efree(@ptrCast(rpo.ptr));
}

/// requires rpo pred ssa use
/// recreates rpo preds
/// breaks pred use dom ssa (GCM fixes ssa)
pub fn gvn(f: *Fn) void {
    all.con01[0] = getcon(0, f);
    all.con01[1] = getcon(1, f);

    // copy.c uses the visit bit
    var b_it = f.start;
    while (b_it) |b| : (b_it = b.link) {
        var p_it = b.phi;
        while (p_it) |p| : (p_it = p.link)
            p.visit = 0;
    }

    fillloop(f);
    narrowpars(f);
    filluse(f);
    ssacheck(f);

    var nins: uint = 0;
    b_it = f.start;
    while (b_it) |b| : (b_it = b.link) {
        b.visit = 0;
        nins += b.nins;
    }

    const n = nins + nins / 2;
    gvntbl = ealloc(?*Ins, n)[0..n];
    @memset(gvntbl, null);
    for (f.rpo[0..f.nblk]) |b| {
        dedupphi(f, b);
        for (b.ins[0..b.nins]) |*i|
            dedupins(f, b, i);
        dedupjmp(f, b);
    }
    rebuildcfg(f);
    efree(@ptrCast(gvntbl.ptr));
    gvntbl = &.{};

    if (all.debug['G'] != 0) {
        dprint("\n> After GVN:\n", .{});
        printfn(f, all.dbg) catch {};
    }
}
