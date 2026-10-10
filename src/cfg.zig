//! One-to-one translation of cfg.c
const std = @import("std");
const assert = std.debug.assert;
// -- imports --
const all = @import("all.zig");
const Blk = all.Blk;
const Fn = all.Fn;
const Ins = all.Ins;
const Jjmp = all.Jjmp;
const Jjnz = all.Jjnz;
const Jret0 = all.Jret0;
const PFn = all.PFn;
const Phi = all.Phi;
const Ref = all.Ref;
const addbins = all.addbins;
const addins = all.addins;
const dprint = all.dprint;
const ealloc = all.ealloc;
const efree = all.efree;
const phiarg = all.phiarg;
const phiargn = all.phiargn;
const pnew = all.pnew;
const printfn = all.printfn;
const req = all.req;
const uint = all.uint;
const vgrow = all.vgrow;
const vnewT = all.vnewT;
const J = all.J;
// -- end imports --

const NOID: uint = std.math.maxInt(uint); // -1u

pub fn newblk() *Blk {
    const b = pnew(Blk);
    b.* = std.mem.zeroes(Blk);
    b.ins = vnewT(Ins, 0, PFn);
    b.pred = vnewT(*Blk, 0, PFn);
    return b;
}

fn fixphis(f: *Fn) void {
    var b_it: ?*Blk = f.start;
    while (b_it) |b| : (b_it = b.link) {
        assert(b.id < f.nblk);
        var p_it: ?*Phi = b.phi;
        while (p_it) |p| : (p_it = p.link) {
            var n: uint = 0;
            var n0: uint = 0;
            while (n < p.narg) : (n += 1) {
                const bp = p.blk[n];
                if (bp.id != NOID)
                    if (bp.s1 == b or bp.s2 == b) {
                        p.blk[n0] = bp;
                        p.arg[n0] = p.arg[n];
                        n0 += 1;
                    };
            }
            assert(n0 > 0);
            p.narg = n0;
        }
    }
}

fn addpred(bp: *Blk, b: *Blk) void {
    b.npred += 1;
    vgrow(&b.pred, b.npred);
    b.pred[b.npred - 1] = bp;
}

pub fn fillpreds(f: *Fn) void {
    var b_it: ?*Blk = f.start;
    while (b_it) |b| : (b_it = b.link)
        b.npred = 0;
    b_it = f.start;
    while (b_it) |b| : (b_it = b.link) {
        if (b.s1 != null)
            addpred(b, b.s1.?);
        if (b.s2 != null and b.s2 != b.s1)
            addpred(b, b.s2.?);
    }
}

fn porec(b_: ?*Blk, npo: *uint) void {
    const b = b_ orelse return;
    if (b.id != NOID)
        return;
    b.id = 0; // marker
    var s1 = b.s1;
    var s2 = b.s2;
    if (s1 != null and s2 != null and s1.?.loop > s2.?.loop)
        std.mem.swap(?*Blk, &s1, &s2);
    porec(s1, npo);
    porec(s2, npo);
    b.id = npo.*;
    npo.* += 1;
}

fn fillrpo(f: *Fn) void {
    var b_it = f.start;
    while (b_it) |b| : (b_it = b.link)
        b.id = NOID;
    f.nblk = 0;
    porec(f.start, &f.nblk);
    vgrow(&f.rpo, f.nblk);
    // unlink dead blocks, number live ones in reverse post-order
    var p: *?*Blk = &f.start;
    while (p.*) |b| {
        if (b.id == NOID) {
            p.* = b.link;
        } else {
            b.id = f.nblk - b.id - 1;
            f.rpo[b.id] = b;
            p = &b.link;
        }
    }
}

/// fill rpo, preds; prune dead blks
pub fn fillcfg(f: *Fn) void {
    fillrpo(f);
    fillpreds(f);
    fixphis(f);
}

// for dominators computation, read
// "A Simple, Fast Dominance Algorithm"
// by K. Cooper, T. Harvey, and K. Kennedy.

fn inter(b1_: ?*Blk, b2_: *Blk) *Blk {
    var b1 = b1_ orelse return b2_;
    var b2 = b2_;
    while (b1 != b2) {
        if (b1.id < b2.id)
            std.mem.swap(*Blk, &b1, &b2);
        while (b1.id > b2.id)
            b1 = b1.idom.?;
    }
    return b1;
}

pub fn filldom(f: *Fn) void {
    var b_it = f.start;
    while (b_it) |b| : (b_it = b.link) {
        b.idom = null;
        b.dom = null;
        b.dlink = null;
    }
    while (true) {
        var changed = false;
        var n: uint = 1;
        while (n < f.nblk) : (n += 1) {
            const b = f.rpo[n];
            var d: ?*Blk = null;
            for (b.pred[0..b.npred]) |p|
                if (p.idom != null or p == f.start) {
                    d = inter(d, p);
                };
            if (d != b.idom) {
                changed = true;
                b.idom = d;
            }
        }
        if (!changed) break;
    }
    b_it = f.start;
    while (b_it) |b| : (b_it = b.link) {
        if (b.idom) |d| {
            assert(d != b);
            b.dlink = d.dom;
            d.dom = b;
        }
    }
}

pub fn sdom(b1: *Blk, b2_: *Blk) bool {
    var b2 = b2_;
    if (b1 == b2)
        return false;
    while (b2.id > b1.id)
        b2 = b2.idom.?;
    return b1 == b2;
}

pub fn dom(b1: *Blk, b2: *Blk) bool {
    return b1 == b2 or sdom(b1, b2);
}

fn addfron(a: *Blk, b: *Blk) void {
    for (a.fron[0..a.nfron]) |x|
        if (x == b)
            return;
    a.nfron += 1;
    if (a.nfron == 1)
        a.fron = vnewT(*Blk, a.nfron, PFn)
    else
        vgrow(&a.fron, a.nfron);
    a.fron[a.nfron - 1] = b;
}

/// fill the dominance frontier
pub fn fillfron(f: *Fn) void {
    var b_it = f.start;
    while (b_it) |b| : (b_it = b.link)
        b.nfron = 0;
    b_it = f.start;
    while (b_it) |b| : (b_it = b.link) {
        for ([2]?*Blk{ b.s1, b.s2 }) |s_| {
            const s = s_ orelse continue;
            var a = b;
            while (!sdom(a, s)) : (a = a.idom.?)
                addfron(a, s);
        }
    }
}

fn loopmark(hd: *Blk, b: *Blk, f: *const fn (*Blk, *Blk) void) void {
    if (b.id < hd.id or b.visit == hd.id)
        return;
    b.visit = hd.id;
    f(hd, b);
    for (b.pred[0..b.npred]) |p|
        loopmark(hd, p, f);
}

pub fn loopiter(f: *Fn, func: *const fn (*Blk, *Blk) void) void {
    var b_it = f.start;
    while (b_it) |b| : (b_it = b.link)
        b.visit = NOID;
    for (f.rpo[0..f.nblk], 0..) |b, n| {
        for (b.pred[0..b.npred]) |p|
            if (p.id >= n)
                loopmark(b, p, func);
    }
}

/// dominator tree depth
pub fn filldepth(f: *Fn) void {
    var b_it = f.start;
    while (b_it) |b| : (b_it = b.link)
        b.depth = -1;

    f.start.?.depth = 0;

    b_it = f.start;
    while (b_it) |b| : (b_it = b.link) {
        if (b.depth != -1)
            continue;
        var depth: i32 = 1;
        var d = b.idom.?;
        while (d.depth == -1) : (d = d.idom.?)
            depth += 1;
        depth += d.depth;
        b.depth = depth;
        d = b.idom.?;
        while (d.depth == -1) : (d = d.idom.?) {
            depth -= 1;
            d.depth = depth;
        }
    }
}

/// least common ancestor in dom tree
pub fn lca(b1_: ?*Blk, b2_: ?*Blk) ?*Blk {
    var b1 = b1_ orelse return b2_;
    var b2 = b2_ orelse return b1;
    while (b1.depth > b2.depth)
        b1 = b1.idom.?;
    while (b2.depth > b1.depth)
        b2 = b2.idom.?;
    while (b1 != b2) {
        b1 = b1.idom.?;
        b2 = b2.idom.?;
    }
    return b1;
}

pub fn multloop(hd: *Blk, b: *Blk) void {
    _ = hd;
    b.loop *= 10;
}

pub fn fillloop(f: *Fn) void {
    var b_it: ?*Blk = f.start;
    while (b_it) |b| : (b_it = b.link)
        b.loop = 1;
    loopiter(f, multloop);
}

fn uffind(pb: **Blk, uf: []?*Blk) void {
    if (uf[pb.*.id]) |*pb1| {
        uffind(pb1, uf);
        pb.* = pb1.*;
    }
}

/// requires rpo and no phis, breaks cfg
pub fn simpljmp(f: *Fn) void {
    const ret = newblk();
    ret.id = f.nblk;
    f.nblk += 1;
    ret.jmp.type = Jret0;
    const uf = ealloc(?*Blk, f.nblk)[0..f.nblk]; // union-find
    var b_it = f.start;
    while (b_it) |b| : (b_it = b.link) {
        assert(b.phi == null);
        if (b.jmp.type == Jret0) {
            b.jmp.type = Jjmp;
            b.s1 = ret;
        }
        if (b.nins == 0)
            if (b.jmp.type == Jjmp) {
                uffind(@ptrCast(&b.s1), uf);
                if (b.s1 != b)
                    uf[b.id] = b.s1;
            };
    }
    var p: *?*Blk = &f.start;
    while (p.*) |b| : (p = &b.link) {
        if (b.s1 != null)
            uffind(@ptrCast(&b.s1), uf);
        if (b.s2 != null)
            uffind(@ptrCast(&b.s2), uf);
        if (b.s1 != null and b.s1 == b.s2) {
            b.jmp.type = Jjmp;
            b.s2 = null;
        }
    }
    p.* = ret;
    efree(@ptrCast(uf.ptr));
}

fn reachrec(b: ?*Blk, to: ?*Blk) bool {
    if (b == to)
        return true;
    if (b == null or b.?.visit != 0)
        return false;

    b.?.visit = 1;
    if (reachrec(b.?.s1, to))
        return true;
    if (reachrec(b.?.s2, to))
        return true;

    return false;
}

/// Blk.visit needs to be clear at entry
pub fn reaches(f: *Fn, b_: *Blk, to: ?*Blk) bool {
    assert(to != null);
    const r = reachrec(b_, to);
    var b_it: ?*Blk = f.start;
    while (b_it) |b| : (b_it = b.link)
        b.visit = 0;
    return r;
}

/// can b reach 'to' not through excl
/// Blk.visit needs to be clear at entry
pub fn reachesnotvia(f: *Fn, b: *Blk, to: *Blk, excl: *Blk) bool {
    excl.visit = 1;
    return reaches(f, b, to);
}

pub fn ifgraph(ifb: *Blk, pthenb_: **Blk, pelseb_: **Blk, pjoinb: **Blk) bool {
    var pthenb = pthenb_;
    var pelseb = pelseb_;
    if (ifb.jmp.type != Jjnz)
        return false;

    var s1 = ifb.s1.?;
    var s2 = ifb.s2.?;
    if (s1.id > s2.id) {
        std.mem.swap(*Blk, &s1, &s2);
        std.mem.swap(**Blk, &pthenb, &pelseb);
    }
    if (s1 == s2)
        return false;

    if (s1.jmp.type != Jjmp or s1.npred != 1)
        return false;

    if (s1.s1 == s2) {
        // if-then / if-else
        if (s2.npred != 2)
            return false;
        pthenb.* = s1;
        pelseb.* = ifb;
        pjoinb.* = s2;
        return true;
    }

    if (s2.jmp.type != Jjmp or s2.npred != 1)
        return false;
    if (s1.s1 != s2.s1 or s1.s1.?.npred != 2)
        return false;

    assert(s1.s1 != ifb);
    pthenb.* = s1;
    pelseb.* = s2;
    pjoinb.* = s1.s1.?;
    return true;
}

const Jmp = extern struct {
    type: J,
    arg: Ref,
    s1: ?*Blk,
    s2: ?*Blk,
};

fn jmpeq(a: *const Jmp, b: *const Jmp) bool {
    return a.type == b.type and req(a.arg, b.arg) and a.s1 == b.s1 and a.s2 == b.s2;
}

fn jmpnophi(j: *const Jmp) bool {
    if (j.s1 != null and j.s1.?.phi != null)
        return false;
    if (j.s2 != null and j.s2.?.phi != null)
        return false;
    return true;
}

/// require cfg rpo, breaks use
pub fn simplcfg(f: *Fn) void {
    if (all.debug['C'] != 0) {
        dprint("\n> Before CFG simplification:\n", .{});
        printfn(f, all.dbg) catch {};
    }

    var cpy = std.mem.zeroes(Ins);
    cpy.op = .copy;
    var b_it = f.start;
    while (b_it) |b| : (b_it = b.link)
        if (b.npred == 1) {
            const bb = b.pred[0];
            var p_it = b.phi;
            while (p_it) |p| : (p_it = p.link) {
                cpy.cls = p.cls;
                cpy.to = p.to;
                cpy.arg[0] = phiarg(p, bb);
                addins(&bb.ins, &bb.nins, &cpy);
            }
            b.phi = null;
        };

    const jmp = ealloc(Jmp, f.nblk)[0..f.nblk];
    const empty = ealloc(bool, f.nblk)[0..f.nblk];
    b_it = f.start;
    while (b_it) |b| : (b_it = b.link) {
        jmp[b.id] = .{ .type = b.jmp.type, .arg = b.jmp.arg, .s1 = b.s1, .s2 = b.s2 };
        empty[b.id] = b.phi == null;
        for (b.ins[0..b.nins]) |*i|
            if (i.op != .nop and i.op != .dbgloc) {
                empty[b.id] = false;
                break;
            };
    }

    while (true) {
        var done = true;
        b_it = f.start;
        while (b_it) |b| : (b_it = b.link) {
            if (b.id == NOID)
                continue;
            const j = &jmp[b.id];
            if (j.type == Jjmp and j.s1.?.npred == 1) {
                const s = j.s1.?;
                assert(s.phi == null);
                addbins(&b.ins, &b.nins, s);
                empty[b.id] = empty[b.id] and empty[s.id];
                const jj = &jmp[s.id];
                for ([2]?*Blk{ jj.s1, jj.s2 }) |bb_| {
                    const bb = bb_ orelse break;
                    var p_it = bb.phi;
                    while (p_it) |p| : (p_it = p.link)
                        p.blk[phiargn(p, s)] = b;
                }
                s.id = NOID;
                j.* = jj.*;
                done = false;
            } else if (j.type == Jjnz and empty[j.s1.?.id] and empty[j.s2.?.id] and
                jmpeq(&jmp[j.s1.?.id], &jmp[j.s2.?.id]) and
                jmpnophi(&jmp[j.s1.?.id]))
            {
                j.* = jmp[j.s1.?.id];
                done = false;
            }
        }
        if (done) break;
    }

    b_it = f.start;
    while (b_it) |b| : (b_it = b.link)
        if (b.id != NOID) {
            const j = &jmp[b.id];
            b.jmp.type = j.type;
            b.jmp.arg = j.arg;
            b.s1 = j.s1;
            b.s2 = j.s2;
            assert(j.s1 == null or j.s1.?.id != NOID);
            assert(j.s2 == null or j.s2.?.id != NOID);
        };

    fillcfg(f);
    efree((empty.ptr));
    efree((jmp.ptr));

    if (all.debug['C'] != 0) {
        dprint("\n> After CFG simplification:\n", .{});
        printfn(f, all.dbg) catch {};
    }
}
