//! One-to-one translation of gcm.c
const std = @import("std");
const assert = std.debug.assert;
// -- imports --
const all = @import("all.zig");
const Blk = all.Blk;
const Fn = all.Fn;
const INS0 = all.INS0;
const Ins = all.Ins;
const KBASE = all.KBASE;
const Oadd = all.ops.Oadd;
const Oand = all.ops.Oand;
const Odiv = all.ops.Odiv;
const Omul = all.ops.Omul;
const Oneg = all.ops.Oneg;
const Onop = all.ops.Onop;
const Oor = all.ops.Oor;
const Orem = all.ops.Orem;
const Osar = all.ops.Osar;
const Oshl = all.ops.Oshl;
const Oshr = all.ops.Oshr;
const Osub = all.ops.Osub;
const Oudiv = all.ops.Oudiv;
const Ourem = all.ops.Ourem;
const Oxor = all.ops.Oxor;
const PFn = all.PFn;
const PHeap = all.PHeap;
const Phi = all.Phi;
const R = all.R;
const RTmp = all.RTmp;
const Ref = all.Ref;
const UIns = all.UIns;
const UJmp = all.UJmp;
const UPhi = all.UPhi;
const UXXX = all.UXXX;
const addins = all.addins;
const die = all.die;
const dom = all.dom;
const dprint = all.dprint;
const emiti = all.emiti;
const filldepth = all.filldepth;
const fillloop = all.fillloop;
const filluse = all.filluse;
const idup = all.idup;
const igroup = all.igroup;
const isalloc = all.isalloc;
const iscmp = all.iscmp;
const isload = all.isload;
const isstore = all.isstore;
const lca = all.lca;
const newtmp = all.newtmp;
const printfn = all.printfn;
const req = all.req;
const rtype = all.rtype;
const uint = all.uint;
const vfree = all.vfree;
const vnewT = all.vnewT;
// -- end imports --

const NOBID: uint = std.math.maxInt(uint);

fn isdivwl(i: *Ins) bool {
    return switch (i.op) {
        Odiv, Orem, Oudiv, Ourem => KBASE(i.cls) == 0,
        else => false,
    };
}

pub fn pinned(i: *Ins) bool {
    return all.optab[i.op].pinned != 0 or isdivwl(i);
}

/// pinned ins that can be eliminated if unused
fn canelim(i: *Ins) bool {
    return isload(i.op) or isalloc(i.op) or isdivwl(i);
}

fn schedearly(f: *Fn, r: Ref) uint {
    if (rtype(r) != RTmp)
        return 0;

    const t = &f.tmp[r.val];
    if (t.gcmbid != NOBID)
        return t.gcmbid;

    const b = f.rpo[t.bid];
    if (t.def != null) {
        assert(@intFromPtr(b.ins) <= @intFromPtr(t.def) and @intFromPtr(t.def) < @intFromPtr(b.ins + b.nins));
        t.gcmbid = 0; // mark as visiting
        t.gcmbid = earlyins(f, b, t.def.?);
    } else {
        // phis do not move
        t.gcmbid = t.bid;
    }

    return t.gcmbid;
}

fn earlyins(f: *Fn, b: *Blk, i: *Ins) uint {
    var b0 = schedearly(f, i.arg[0]);
    assert(b0 != NOBID);
    const b1 = schedearly(f, i.arg[1]);
    assert(b1 != NOBID);
    if (f.rpo[b0].depth < f.rpo[b1].depth) {
        assert(dom(f.rpo[b0], f.rpo[b1]));
        b0 = b1;
    }
    return if (pinned(i)) b.id else b0;
}

fn earlyblk(f: *Fn, bid: uint) void {
    const b = f.rpo[bid];
    var p_it: ?*Phi = b.phi;
    while (p_it) |p| : (p_it = p.link) {
        var n: uint = 0;
        while (n < p.narg) : (n += 1)
            _ = schedearly(f, p.arg[n]);
    }
    for (b.ins[0..b.nins]) |*i| {
        if (pinned(i)) {
            _ = schedearly(f, i.arg[0]);
            _ = schedearly(f, i.arg[1]);
        }
    }
    _ = schedearly(f, b.jmp.arg);
}

/// least common ancestor in dom tree
fn lcabid(f: *Fn, bid1: uint, bid2: uint) uint {
    if (bid1 == NOBID)
        return bid2;
    if (bid2 == NOBID)
        return bid1;

    const b = lca(f.rpo[bid1], f.rpo[bid2]);
    assert(b != null);
    return b.?.id;
}

fn bestbid(f: *Fn, earlybid: uint, latebid: uint) uint {
    if (latebid == NOBID)
        return NOBID; // unused

    assert(earlybid != NOBID);

    const earlyb = f.rpo[earlybid];
    var curb = f.rpo[latebid];
    var bestb = curb;
    assert(dom(earlyb, curb));

    while (curb != earlyb) {
        curb = curb.idom.?;
        if (curb.loop < bestb.loop)
            bestb = curb;
    }
    return bestb.id;
}

/// return lca bid of ref uses
fn schedlate(f: *Fn, r: Ref) uint {
    if (rtype(r) != RTmp)
        return NOBID;

    const t = &f.tmp[r.val];
    if (t.visit != 0)
        return t.gcmbid;

    t.visit = 1;
    const earlybid = t.gcmbid;
    if (earlybid == NOBID)
        return NOBID; // not used

    // reuse gcmbid for late bid
    t.gcmbid = t.bid;
    var latebid: uint = NOBID;
    for (t.use[0..t.nuse]) |*u| {
        assert(u.bid < f.nblk);
        const b = f.rpo[u.bid];
        var uselatebid: uint = undefined;
        switch (u.type) {
            UXXX => die("unreachable", .{}),
            UPhi => uselatebid = latephi(f, u.u.phi, r),
            UIns => uselatebid = lateins(f, b, u.u.ins, r),
            UJmp => uselatebid = latejmp(b, r),
            else => unreachable,
        }
        latebid = lcabid(f, latebid, uselatebid);
    }
    // latebid may be NOBID if the temp is used
    // in fixed instructions that may be eliminated
    // and are themselves unused transitively

    if (t.def != null and !pinned(t.def.?))
        t.gcmbid = bestbid(f, earlybid, latebid);
    // else, keep the early one

    // now, gcmbid is the best bid
    return t.gcmbid;
}

/// returns lca bid of uses or NOBID if
/// the definition can be eliminated
fn lateins(f: *Fn, b: *Blk, i: [*c]Ins, r: Ref) uint {
    assert(b.ins <= i and i < b.ins + b.nins);
    assert(req(i.*.arg[0], r) or req(i.*.arg[1], r));

    const latebid = schedlate(f, i.*.to);
    if (pinned(i)) {
        if (latebid == NOBID)
            if (canelim(i))
                return NOBID;
        return b.id;
    }

    return latebid;
}

fn latephi(f: *Fn, p: *Phi, r: Ref) uint {
    if (p.narg == 0)
        return NOBID; // marked as unused

    var latebid: uint = NOBID;
    var n: uint = 0;
    while (n < p.narg) : (n += 1) {
        if (req(p.arg[n], r))
            latebid = lcabid(f, latebid, p.blk[n].id);
    }

    assert(latebid != NOBID);
    return latebid;
}

fn latejmp(b: *Blk, r: Ref) uint {
    if (req(b.jmp.arg, R)) {
        return NOBID;
    } else {
        assert(req(b.jmp.arg, r));
        return b.id;
    }
}

fn lateblk(f: *Fn, bid: uint) void {
    const b = f.rpo[bid];
    var pp: *[*c]Phi = &b.phi;
    while (pp.* != null) {
        if (schedlate(f, pp.*.*.to) == NOBID) {
            pp.*.*.narg = 0; // mark unused
            pp.* = pp.*.*.link; // remove phi
        } else pp = &pp.*.*.link;
    }

    for (b.ins[0..b.nins]) |*i| {
        if (pinned(i))
            _ = schedlate(f, i.to);
    }
}

fn addgcmins(f: *Fn, vins: [*c]Ins, nins: uint) void {
    for (vins[0..nins]) |*i| {
        assert(rtype(i.to) == RTmp);
        const t = &f.tmp[i.to.val];
        const b = f.rpo[t.gcmbid];
        addins(&b.ins, &b.nins, i);
    }
}

/// move live instructions to the
/// end of their target block; use-
/// before-def errors are fixed by
/// schedblk
fn gcmmove(f: *Fn) void {
    var nins: uint = 0;
    var vins: [*]Ins = vnewT(Ins, nins, PFn);

    for (f.tmp[0..@intCast(f.ntmp)]) |*t| {
        if (t.def == null)
            continue;
        if (t.bid == t.gcmbid)
            continue;
        const i: [*c]Ins = t.def;
        if (pinned(i) and !canelim(i))
            continue;
        assert(rtype(i.*.to) == RTmp);
        assert(t == &f.tmp[i.*.to.val]);
        if (t.gcmbid != NOBID)
            addins(&vins, &nins, i);
        i.* = INS0(Onop);
    }
    addgcmins(f, vins, nins);
}

/// dfs ordering
fn schedins(f: *Fn, b: *Blk, i_: *Ins, pvins: *[*]Ins, pnins: *uint) [*c]Ins {
    var i_0: [*c]Ins = undefined;
    var i_1: [*c]Ins = undefined;
    igroup(b, i_, &i_0, &i_1);
    var i = i_0;
    while (i < i_1) : (i += 1) {
        var n: usize = 0;
        while (n < 2) : (n += 1) {
            if (rtype(i.*.arg[n]) != RTmp)
                continue;
            const t = &f.tmp[i.*.arg[n].val];
            if (t.bid != b.id or t.def == null)
                continue;
            _ = schedins(f, b, t.def.?, pvins, pnins);
        }
    }
    i = i_0;
    while (i < i_1) : (i += 1) {
        addins(pvins, pnins, i);
        i.* = INS0(Onop);
    }
    return i_1;
}

/// order ins within a block
fn schedblk(f: *Fn) void {
    var vins = vnewT(Ins, 0, PHeap);
    var b_it: ?*Blk = f.start;
    while (b_it) |b| : (b_it = b.link) {
        var nins: uint = 0;
        var i: [*c]Ins = b.ins;
        while (i < b.ins + b.nins)
            i = schedins(f, b, i, &vins, &nins);
        idup(b, vins, nins);
    }
    vfree(@ptrCast(vins));
}

fn cheap(i: *Ins) bool {
    var x: i32 = undefined;

    if (KBASE(i.cls) != 0)
        return false;
    return switch (i.op) {
        Oneg, Oadd, Osub, Omul, Oand, Oor, Oxor, Osar, Oshr, Oshl => true,
        else => iscmp(i.op, &x, &x),
    };
}

fn sinkref(f: *Fn, b: *Blk, pr: *Ref) void {
    if (rtype(pr.*) != RTmp)
        return;
    const t = &f.tmp[pr.val];
    if (t.def == null or
        t.bid == b.id or
        pinned(t.def.?) or
        !cheap(t.def.?))
        return;

    // sink t->def to b
    var i = t.def.?.*;
    const r = newtmp("snk", t.cls, f);
    // t invalidated
    pr.* = r;
    i.to = r;
    f.tmp[r.val].gcmbid = b.id;
    emiti(i);
    sinkref(f, b, &i.arg[0]);
    sinkref(f, b, &i.arg[1]);
}

/// redistribute trivial ops to point of
/// use to reduce register pressure
/// requires rpo, use; breaks use
fn sink(f: *Fn) void {
    var b_it: ?*Blk = f.start;
    while (b_it) |b| : (b_it = b.link) {
        for (b.ins[0..b.nins]) |*i| {
            if (isload(i.op))
                sinkref(f, b, &i.arg[0])
            else if (isstore(i.op))
                sinkref(f, b, &i.arg[1]);
        }
        sinkref(f, b, &b.jmp.arg);
    }
    const end: [*c]Ins = all.insbEnd();
    addgcmins(f, all.curi, @intCast(end - all.curi));
}

/// requires use dom
/// maintains rpo pred dom
/// breaks use
pub fn gcm(f: *Fn) void {
    filldepth(f);
    fillloop(f);

    for (f.tmp[0..@as(usize, @intCast(f.ntmp))]) |*t| {
        t.visit = 0;
        t.gcmbid = NOBID;
    }
    var bid: uint = 0;
    while (bid < f.nblk) : (bid += 1)
        earlyblk(f, bid);
    bid = 0;
    while (bid < f.nblk) : (bid += 1)
        lateblk(f, bid);

    gcmmove(f);
    filluse(f);
    all.curi = all.insbEnd();
    sink(f);
    filluse(f);
    schedblk(f);

    if (all.debug['G'] != 0) {
        dprint("\n> After GCM:\n", .{});
        printfn(f, all.dbg) catch {};
    }
}
