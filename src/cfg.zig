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
const Ocopy = all.ops.Ocopy;
const Odbgloc = all.ops.Odbgloc;
const Onop = all.ops.Onop;
const PFn = all.PFn;
const Ref = all.Ref;
const addbins = all.addbins;
const addins = all.addins;
const dprint = all.dprint;
const ealloc = all.ealloc;
const efree = all.efree;
const palloc = all.palloc;
const phiarg = all.phiarg;
const phiargn = all.phiargn;
const printfn = all.printfn;
const req = all.req;
const uint = all.uint;
const vgrow = all.vgrow;
const vnewT = all.vnewT;
// -- end imports --

const NOID: uint = std.math.maxInt(uint); // -1u

pub fn newblk() [*c]Blk {
    const b: [*c]Blk = palloc(Blk, 1);
    b.* = std.mem.zeroes(Blk);
    b.*.ins = vnewT(Ins, 0, PFn);
    b.*.pred = vnewT([*c]Blk, 0, PFn);
    return b;
}

fn fixphis(f: [*c]Fn) void {
    var b = f.*.start;
    while (b != null) : (b = b.*.link) {
        assert(b.*.id < f.*.nblk);
        var p = b.*.phi;
        while (p != null) : (p = p.*.link) {
            var n: uint = 0;
            var n0: uint = 0;
            while (n < p.*.narg) : (n += 1) {
                const bp = p.*.blk[n];
                if (bp.*.id != NOID)
                    if (bp.*.s1 == b or bp.*.s2 == b) {
                        p.*.blk[n0] = bp;
                        p.*.arg[n0] = p.*.arg[n];
                        n0 += 1;
                    };
            }
            assert(n0 > 0);
            p.*.narg = n0;
        }
    }
}

fn addpred(bp: [*c]Blk, b: [*c]Blk) void {
    b.*.npred += 1;
    vgrow(&b.*.pred, b.*.npred);
    b.*.pred[b.*.npred - 1] = bp;
}

pub fn fillpreds(f: [*c]Fn) void {
    var b = f.*.start;
    while (b != null) : (b = b.*.link)
        b.*.npred = 0;
    b = f.*.start;
    while (b != null) : (b = b.*.link) {
        if (b.*.s1 != null)
            addpred(b, b.*.s1);
        if (b.*.s2 != null and b.*.s2 != b.*.s1)
            addpred(b, b.*.s2);
    }
}

fn porec(b: [*c]Blk, npo: *uint) void {
    if (b == null or b.*.id != NOID)
        return;
    b.*.id = 0; // marker
    var s1 = b.*.s1;
    var s2 = b.*.s2;
    if (s1 != null and s2 != null and s1.*.loop > s2.*.loop) {
        s1 = b.*.s2;
        s2 = b.*.s1;
    }
    porec(s1, npo);
    porec(s2, npo);
    b.*.id = npo.*;
    npo.* += 1;
}

fn fillrpo(f: [*c]Fn) void {
    var b = f.*.start;
    while (b != null) : (b = b.*.link)
        b.*.id = NOID;
    f.*.nblk = 0;
    porec(f.*.start, &f.*.nblk);
    vgrow(&f.*.rpo, f.*.nblk);
    var p: [*c][*c]Blk = &f.*.start;
    while (true) {
        b = p.*;
        if (b == null) break;
        if (b.*.id == NOID) {
            p.* = b.*.link;
        } else {
            b.*.id = f.*.nblk - b.*.id - 1;
            f.*.rpo[b.*.id] = b;
            p = &b.*.link;
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

fn inter(b1_: [*c]Blk, b2_: [*c]Blk) [*c]Blk {
    var b1 = b1_;
    var b2 = b2_;
    if (b1 == null)
        return b2;
    while (b1 != b2) {
        if (b1.*.id < b2.*.id) {
            const bt = b1;
            b1 = b2;
            b2 = bt;
        }
        while (b1.*.id > b2.*.id) {
            b1 = b1.*.idom;
            assert(b1 != null);
        }
    }
    return b1;
}

pub fn filldom(f: [*c]Fn) void {
    var b = f.*.start;
    var d: [*c]Blk = undefined;
    while (b != null) : (b = b.*.link) {
        b.*.idom = null;
        b.*.dom = null;
        b.*.dlink = null;
    }
    while (true) {
        var ch: i32 = 0;
        var n: uint = 1;
        while (n < f.*.nblk) : (n += 1) {
            b = f.*.rpo[n];
            d = null;
            var p: uint = 0;
            while (p < b.*.npred) : (p += 1)
                if (b.*.pred[p].*.idom != null or b.*.pred[p] == f.*.start) {
                    d = inter(d, b.*.pred[p]);
                };
            if (d != b.*.idom) {
                ch += 1;
                b.*.idom = d;
            }
        }
        if (ch == 0) break;
    }
    b = f.*.start;
    while (b != null) : (b = b.*.link) {
        d = b.*.idom;
        if (d != null) {
            assert(d != b);
            b.*.dlink = d.*.dom;
            d.*.dom = b;
        }
    }
}

pub fn sdom(b1: [*c]Blk, b2_: [*c]Blk) bool {
    var b2 = b2_;
    assert(b1 != null and b2 != null);
    if (b1 == b2)
        return false;
    while (b2.*.id > b1.*.id)
        b2 = b2.*.idom;
    return b1 == b2;
}

pub fn dom(b1: [*c]Blk, b2: [*c]Blk) bool {
    return b1 == b2 or sdom(b1, b2);
}

fn addfron(a: [*c]Blk, b: [*c]Blk) void {
    var n: uint = 0;
    while (n < a.*.nfron) : (n += 1)
        if (a.*.fron[n] == b)
            return;
    if (a.*.nfron == 0) {
        a.*.nfron += 1;
        a.*.fron = vnewT([*c]Blk, a.*.nfron, PFn);
    } else {
        a.*.nfron += 1;
        vgrow(&a.*.fron, a.*.nfron);
    }
    a.*.fron[a.*.nfron - 1] = b;
}

/// fill the dominance frontier
pub fn fillfron(f: [*c]Fn) void {
    var b = f.*.start;
    while (b != null) : (b = b.*.link)
        b.*.nfron = 0;
    b = f.*.start;
    while (b != null) : (b = b.*.link) {
        var a: [*c]Blk = undefined;
        if (b.*.s1 != null) {
            a = b;
            while (!sdom(a, b.*.s1)) : (a = a.*.idom)
                addfron(a, b.*.s1);
        }
        if (b.*.s2 != null) {
            a = b;
            while (!sdom(a, b.*.s2)) : (a = a.*.idom)
                addfron(a, b.*.s2);
        }
    }
}

fn loopmark(hd: [*c]Blk, b: [*c]Blk, f: *const fn ([*c]Blk, [*c]Blk) void) void {
    if (b.*.id < hd.*.id or b.*.visit == hd.*.id)
        return;
    b.*.visit = hd.*.id;
    f(hd, b);
    var p: uint = 0;
    while (p < b.*.npred) : (p += 1)
        loopmark(hd, b.*.pred[p], f);
}

pub fn loopiter(f: [*c]Fn, func: *const fn ([*c]Blk, [*c]Blk) void) void {
    var b = f.*.start;
    while (b != null) : (b = b.*.link)
        b.*.visit = NOID;
    var n: uint = 0;
    while (n < f.*.nblk) : (n += 1) {
        b = f.*.rpo[n];
        var p: uint = 0;
        while (p < b.*.npred) : (p += 1)
            if (b.*.pred[p].*.id >= n)
                loopmark(b, b.*.pred[p], func);
    }
}

/// dominator tree depth
pub fn filldepth(f: [*c]Fn) void {
    var b = f.*.start;
    while (b != null) : (b = b.*.link)
        b.*.depth = -1;

    f.*.start.*.depth = 0;

    b = f.*.start;
    while (b != null) : (b = b.*.link) {
        if (b.*.depth != -1)
            continue;
        var depth: i32 = 1;
        var d = b.*.idom;
        while (d.*.depth == -1) : (d = d.*.idom)
            depth += 1;
        depth += d.*.depth;
        b.*.depth = depth;
        d = b.*.idom;
        while (d.*.depth == -1) : (d = d.*.idom) {
            depth -= 1;
            d.*.depth = depth;
        }
    }
}

/// least common ancestor in dom tree
pub fn lca(b1_: [*c]Blk, b2_: [*c]Blk) [*c]Blk {
    var b1 = b1_;
    var b2 = b2_;
    if (b1 == null)
        return b2;
    if (b2 == null)
        return b1;
    while (b1.*.depth > b2.*.depth)
        b1 = b1.*.idom;
    while (b2.*.depth > b1.*.depth)
        b2 = b2.*.idom;
    while (b1 != b2) {
        b1 = b1.*.idom;
        b2 = b2.*.idom;
    }
    return b1;
}

pub fn multloop(hd: [*c]Blk, b: [*c]Blk) void {
    _ = hd;
    b.*.loop *= 10;
}

pub fn fillloop(f: [*c]Fn) void {
    var b = f.*.start;
    while (b != null) : (b = b.*.link)
        b.*.loop = 1;
    loopiter(f, multloop);
}

fn uffind(pb: [*c][*c]Blk, uf: [*c][*c]Blk) void {
    const pb1 = &uf[pb.*.*.id];
    if (pb1.* != null) {
        uffind(pb1, uf);
        pb.* = pb1.*;
    }
}

/// requires rpo and no phis, breaks cfg
pub fn simpljmp(f: [*c]Fn) void {
    const ret = newblk();
    ret.*.id = f.*.nblk;
    f.*.nblk += 1;
    ret.*.jmp.type = Jret0;
    const uf: [*c][*c]Blk = ealloc([*c]Blk, f.*.nblk); // union-find
    var b = f.*.start;
    while (b != null) : (b = b.*.link) {
        assert(b.*.phi == null);
        if (b.*.jmp.type == Jret0) {
            b.*.jmp.type = Jjmp;
            b.*.s1 = ret;
        }
        if (b.*.nins == 0)
            if (b.*.jmp.type == Jjmp) {
                uffind(&b.*.s1, uf);
                if (b.*.s1 != b)
                    uf[b.*.id] = b.*.s1;
            };
    }
    var p: [*c][*c]Blk = &f.*.start;
    while (true) : (p = &b.*.link) {
        b = p.*;
        if (b == null) break;
        if (b.*.s1 != null)
            uffind(&b.*.s1, uf);
        if (b.*.s2 != null)
            uffind(&b.*.s2, uf);
        if (b.*.s1 != null and b.*.s1 == b.*.s2) {
            b.*.jmp.type = Jjmp;
            b.*.s2 = null;
        }
    }
    p.* = ret;
    efree(@ptrCast(uf));
}

fn reachrec(b: [*c]Blk, to: [*c]Blk) bool {
    if (b == to)
        return true;
    if (b == null or b.*.visit != 0)
        return false;

    b.*.visit = 1;
    if (reachrec(b.*.s1, to))
        return true;
    if (reachrec(b.*.s2, to))
        return true;

    return false;
}

/// Blk.visit needs to be clear at entry
pub fn reaches(f: [*c]Fn, b_: [*c]Blk, to: [*c]Blk) bool {
    assert(to != null);
    const r = reachrec(b_, to);
    var b = f.*.start;
    while (b != null) : (b = b.*.link)
        b.*.visit = 0;
    return r;
}

/// can b reach 'to' not through excl
/// Blk.visit needs to be clear at entry
pub fn reachesnotvia(f: *Fn, b: [*c]Blk, to: [*c]Blk, excl: [*c]Blk) bool {
    excl.*.visit = 1;
    return reaches(f, b, to);
}

pub fn ifgraph(ifb: [*c]Blk, pthenb_: *[*c]Blk, pelseb_: *[*c]Blk, pjoinb: *[*c]Blk) bool {
    var pthenb = pthenb_;
    var pelseb = pelseb_;
    if (ifb.*.jmp.type != Jjnz)
        return false;

    var s1 = ifb.*.s1;
    var s2 = ifb.*.s2;
    if (s1.*.id > s2.*.id) {
        s1 = ifb.*.s2;
        s2 = ifb.*.s1;
        const t = pthenb;
        pthenb = pelseb;
        pelseb = t;
    }
    if (s1 == s2)
        return false;

    if (s1.*.jmp.type != Jjmp or s1.*.npred != 1)
        return false;

    if (s1.*.s1 == s2) {
        // if-then / if-else
        if (s2.*.npred != 2)
            return false;
        pthenb.* = s1;
        pelseb.* = ifb;
        pjoinb.* = s2;
        return true;
    }

    if (s2.*.jmp.type != Jjmp or s2.*.npred != 1)
        return false;
    if (s1.*.s1 != s2.*.s1 or s1.*.s1.*.npred != 2)
        return false;

    assert(s1.*.s1 != ifb);
    pthenb.* = s1;
    pelseb.* = s2;
    pjoinb.* = s1.*.s1;
    return true;
}

const Jmp = extern struct {
    type: i32,
    arg: Ref,
    s1: [*c]Blk,
    s2: [*c]Blk,
};

fn jmpeq(a: [*c]Jmp, b: [*c]Jmp) bool {
    return a.*.type == b.*.type and req(a.*.arg, b.*.arg) and a.*.s1 == b.*.s1 and a.*.s2 == b.*.s2;
}

fn jmpnophi(j: [*c]Jmp) bool {
    if (j.*.s1 != null and j.*.s1.*.phi != null)
        return false;
    if (j.*.s2 != null and j.*.s2.*.phi != null)
        return false;
    return true;
}

/// require cfg rpo, breaks use
pub fn simplcfg(f: [*c]Fn) void {
    if (all.debug['C'] != 0) {
        dprint("\n> Before CFG simplification:\n", .{});
        printfn(f, all.dbg) catch {};
    }

    var cpy = std.mem.zeroes(Ins);
    cpy.op = Ocopy;
    var b = f.*.start;
    while (b != null) : (b = b.*.link)
        if (b.*.npred == 1) {
            const bb = b.*.pred[0];
            var p = b.*.phi;
            while (p != null) : (p = p.*.link) {
                cpy.cls = @intCast(p.*.cls);
                cpy.to = p.*.to;
                cpy.arg[0] = phiarg(p, bb);
                addins(&bb.*.ins, &bb.*.nins, &cpy);
            }
            b.*.phi = null;
        };

    const jmp: [*c]Jmp = ealloc(Jmp, f.*.nblk);
    const empty: [*c]i32 = ealloc(i32, f.*.nblk);
    b = f.*.start;
    while (b != null) : (b = b.*.link) {
        jmp[b.*.id].type = b.*.jmp.type;
        jmp[b.*.id].arg = b.*.jmp.arg;
        jmp[b.*.id].s1 = b.*.s1;
        jmp[b.*.id].s2 = b.*.s2;
        empty[b.*.id] = @intFromBool(b.*.phi == null);
        var i = b.*.ins;
        while (i < &b.*.ins[b.*.nins]) : (i += 1)
            if (i.*.op != Onop and i.*.op != Odbgloc) {
                empty[b.*.id] = 0;
                break;
            };
    }

    while (true) {
        var done = true;
        b = f.*.start;
        while (b != null) : (b = b.*.link) {
            if (b.*.id == NOID)
                continue;
            const j = &jmp[b.*.id];
            if (j.*.type == Jjmp and j.*.s1.*.npred == 1) {
                assert(j.*.s1.*.phi == null);
                addbins(&b.*.ins, &b.*.nins, j.*.s1);
                empty[b.*.id] &= empty[j.*.s1.*.id];
                const jj = &jmp[j.*.s1.*.id];
                var pbuf = [3][*c]Blk{ jj.*.s1, jj.*.s2, null };
                var pb: [*c][*c]Blk = &pbuf;
                while (pb.* != null) : (pb += 1) {
                    const bb = pb.*;
                    var p = bb.*.phi;
                    while (p != null) : (p = p.*.link) {
                        const n = phiargn(p, j.*.s1);
                        p.*.blk[n] = b;
                    }
                }
                j.*.s1.*.id = NOID;
                j.* = jj.*;
                done = false;
            } else if (j.*.type == Jjnz and empty[j.*.s1.*.id] != 0 and empty[j.*.s2.*.id] != 0 and
                jmpeq(&jmp[j.*.s1.*.id], &jmp[j.*.s2.*.id]) and
                jmpnophi(&jmp[j.*.s1.*.id]))
            {
                j.* = jmp[j.*.s1.*.id];
                done = false;
            }
        }
        if (done) break;
    }

    b = f.*.start;
    while (b != null) : (b = b.*.link)
        if (b.*.id != NOID) {
            const j = &jmp[b.*.id];
            b.*.jmp.type = @intCast(j.*.type);
            b.*.jmp.arg = j.*.arg;
            b.*.s1 = j.*.s1;
            b.*.s2 = j.*.s2;
            assert(j.*.s1 == null or j.*.s1.*.id != NOID);
            assert(j.*.s2 == null or j.*.s2.*.id != NOID);
        };

    fillcfg(f);
    efree(@ptrCast(empty));
    efree(@ptrCast(jmp));

    if (all.debug['C'] != 0) {
        dprint("\n> After CFG simplification:\n", .{});
        printfn(f, all.dbg) catch {};
    }
}
