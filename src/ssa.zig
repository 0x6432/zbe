//! One-to-one translation of ssa.c
const std = @import("std");
const assert = std.debug.assert;
// -- imports --
const all = @import("all.zig");
const BSet = all.BSet;
const Blk = all.Blk;
const Fn = all.Fn;
const Kw = all.Kw;
const Kx = all.Kx;
const Oextsb = all.ops.Oextsb;
const Oload = all.ops.Oload;
const Oloadsb = all.ops.Oloadsb;
const Oparsb = all.ops.Oparsb;
const PFn = all.PFn;
const Phi = all.Phi;
const R = all.R;
const RTmp = all.RTmp;
const Ref = all.Ref;
const TMP = all.TMP;
const Tmp = all.Tmp;
const Tmp0 = all.Tmp0;
const UIns = all.UIns;
const UJmp = all.UJmp;
const UNDEF = all.UNDEF;
const UPhi = all.UPhi;
const Use = all.Use;
const WFull = all.WFull;
const Wsb = all.Wsb;
const Wsw = all.Wsw;
const Wub = all.Wub;
const Wuw = all.Wuw;
const bsclr = all.bsclr;
const bscopy = all.bscopy;
const bshas = all.bshas;
const bsinit = all.bsinit;
const bsset = all.bsset;
const bszero = all.bszero;
const clsmerge = all.clsmerge;
const cs = all.cs;
const die = all.die;
const dom = all.dom;
const dprint = all.dprint;
const ealloc = all.ealloc;
const efree = all.efree;
const err = all.err;
const filldom = all.filldom;
const fillfron = all.fillfron;
const filllive = all.filllive;
const iscmp = all.iscmp;
const isext = all.isext;
const isload = all.isload;
const isparbh = all.isparbh;
const newtmp = all.newtmp;
const palloc = all.palloc;
const phicls = all.phicls;
const printfn = all.printfn;
const ptrdiff = all.ptrdiff;
const req = all.req;
const rtype = all.rtype;
const sdom = all.sdom;
const uint = all.uint;
const vgrow = all.vgrow;
const vnewT = all.vnewT;
// -- end imports --

const NOID: uint = std.math.maxInt(uint);

/// C: adduse(Tmp *, int, Blk *, ...); the variadic argument is the
/// Phi* (UPhi) or Ins* (UIns), and absent (null) for UJmp
pub fn adduse(tmp: *Tmp, ty: i32, b: *Blk, x: ?*anyopaque) void {
    if (tmp.use == null)
        return;
    const n = tmp.nuse;
    tmp.nuse += 1;
    vgrow(&tmp.use, tmp.nuse);
    const u = &tmp.use[n];
    u.*.type = ty;
    u.*.bid = b.id;
    switch (ty) {
        UPhi => u.*.u.phi = @ptrCast(@alignCast(x)),
        UIns => u.*.u.ins = @ptrCast(@alignCast(x)),
        UJmp => {},
        else => die("unreachable", .{}),
    }
}

/// fill usage, width, phi, and class information
/// must not change .visit fields
pub fn filluse(f: *Fn) void {
    var t: i32 = undefined;
    var tp: i32 = undefined;
    var w: i32 = undefined;
    var x: i32 = undefined;

    const tmp = f.tmp;
    t = Tmp0;
    while (t < f.ntmp) : (t += 1) {
        const tt = &tmp[@intCast(t)];
        tt.*.def = null;
        tt.*.bid = NOID;
        tt.*.ndef = 0;
        tt.*.nuse = 0;
        tt.*.cls = 0;
        tt.*.phi = 0;
        tt.*.width = WFull;
        if (tt.*.use == null)
            tt.*.use = vnewT(Use, 0, PFn);
    }
    var b_it: ?*Blk = f.start;
    while (b_it) |b| : (b_it = b.link) {
        var p_it: ?*Phi = b.phi;
        while (p_it) |p| : (p_it = p.link) {
            assert(rtype(p.to) == RTmp);
            tp = @intCast(p.to.val);
            tmp[@intCast(tp)].bid = b.id;
            tmp[@intCast(tp)].ndef += 1;
            tmp[@intCast(tp)].cls = p.cls;
            tp = phicls(tp, f.tmp);
            var a: uint = 0;
            while (a < p.narg) : (a += 1)
                if (rtype(p.arg[a]) == RTmp) {
                    t = @intCast(p.arg[a].val);
                    adduse(&tmp[@intCast(t)], UPhi, b, @ptrCast(p));
                    t = phicls(t, f.tmp);
                    if (t != tp)
                        tmp[@intCast(t)].phi = tp;
                };
        }
        for (b.ins[0..b.nins]) |*i| {
            if (!req(i.to, R)) {
                assert(rtype(i.to) == RTmp);
                w = WFull;
                if (isparbh(i.op))
                    w = @intCast(Wsb + (i.op - Oparsb));
                if (isload(i.op) and i.op != Oload)
                    w = @intCast(Wsb + (i.op - Oloadsb));
                if (isext(i.op))
                    w = @intCast(Wsb + (i.op - Oextsb));
                if (iscmp(i.op, &x, &x))
                    w = Wub;
                if (w == Wsw or w == Wuw)
                    if (i.cls == Kw) {
                        w = WFull;
                    };
                t = @intCast(i.to.val);
                tmp[@intCast(t)].width = w;
                tmp[@intCast(t)].def = i;
                tmp[@intCast(t)].bid = b.id;
                tmp[@intCast(t)].ndef += 1;
                tmp[@intCast(t)].cls = @intCast(i.cls);
            }
            var m: usize = 0;
            while (m < 2) : (m += 1)
                if (rtype(i.arg[m]) == RTmp) {
                    t = @intCast(i.arg[m].val);
                    adduse(&tmp[@intCast(t)], UIns, b, @ptrCast(i));
                };
        }
        if (rtype(b.jmp.arg) == RTmp)
            adduse(&tmp[b.jmp.arg.val], UJmp, b, null);
    }
}

fn refindex(t: i32, f: *Fn) Ref {
    return newtmp(f.tmp[@intCast(t)].name, f.tmp[@intCast(t)].cls, f);
}

fn phiins(f: *Fn) void {
    var u: [1]BSet = undefined;
    var defs: [1]BSet = undefined;
    var k: i16 = undefined;

    bsinit(&u, f.nblk);
    bsinit(&defs, f.nblk);
    const blist: [*c][*c]Blk = ealloc([*c]Blk, f.nblk);
    const be = blist + f.nblk;
    const nt = f.ntmp;
    var t: i32 = Tmp0;
    while (t < nt) : (t += 1) {
        const tt = &f.tmp[@intCast(t)];
        tt.*.visit = 0;
        if (tt.*.phi != 0)
            continue;
        if (tt.*.ndef == 1) {
            var ok = true;
            const defb = tt.*.bid;
            var use = tt.*.use;
            var n = tt.*.nuse;
            while (n != 0) : (use += 1) {
                n -= 1;
                ok = ok and (use.*.bid == defb);
            }
            if (ok or defb == f.start.*.id)
                continue;
        }
        bszero(&u);
        k = Kx;
        var bp = be;
        var b = f.start;
        while (b != null) : (b = b.*.link) {
            b.*.visit = 0;
            var r = R;
            for (b.*.ins[0..b.*.nins]) |*i| {
                if (!req(r, R)) {
                    if (req(i.arg[0], TMP(t)))
                        i.arg[0] = r;
                    if (req(i.arg[1], TMP(t)))
                        i.arg[1] = r;
                }
                if (req(i.to, TMP(t))) {
                    if (!bshas(&b.*.out, t)) {
                        r = refindex(t, f);
                        i.to = r;
                    } else {
                        if (!bshas(&u, b.*.id)) {
                            bsset(&u, b.*.id);
                            bp -= 1;
                            bp.* = b;
                        }
                        if (clsmerge(&k, @intCast(i.cls)))
                            die("invalid input", .{});
                    }
                }
            }
            if (!req(r, R) and req(b.*.jmp.arg, TMP(t)))
                b.*.jmp.arg = r;
        }
        bscopy(&defs, &u);
        while (bp != be) {
            f.tmp[@intCast(t)].visit = t;
            b = bp.*;
            bp += 1;
            bsclr(&u, b.*.id);
            var n: uint = 0;
            while (n < b.*.nfron) : (n += 1) {
                const a = b.*.fron[n];
                const v = a.*.visit;
                a.*.visit += 1;
                if (v == 0)
                    if (bshas(&a.*.in, t)) {
                        const p: [*c]Phi = palloc(Phi, 1);
                        p.*.cls = k;
                        p.*.to = TMP(t);
                        p.*.link = a.*.phi;
                        p.*.arg = vnewT(Ref, 0, PFn);
                        p.*.blk = vnewT([*c]Blk, 0, PFn);
                        a.*.phi = p;
                        if (!bshas(&defs, a.*.id))
                            if (!bshas(&u, a.*.id)) {
                                bsset(&u, a.*.id);
                                bp -= 1;
                                bp.* = a;
                            };
                    };
            }
        }
    }
    efree(@ptrCast(blist));
}

const Name = extern struct {
    r: Ref,
    b: [*c]Blk,
    up: [*c]Name,
};

var namel: [*c]Name = null;

fn nnew(r: Ref, b: [*c]Blk, up: [*c]Name) [*c]Name {
    var n: [*c]Name = undefined;
    if (namel != null) {
        n = namel;
        namel = n.*.up;
    } else
        // could use alloc, here
        // but namel should be reset
        n = ealloc(Name, 1);
    n.*.r = r;
    n.*.b = b;
    n.*.up = up;
    return n;
}

fn nfree(n: [*c]Name) void {
    n.*.up = namel;
    namel = n;
}

fn rendef(r: *Ref, b: *Blk, stk: [*c][*c]Name, f: *Fn) void {
    const t = r.*.val;
    if (req(r.*, R) or f.tmp[t].visit == 0)
        return;
    const r1 = refindex(@intCast(t), f);
    f.tmp[r1.val].visit = @intCast(t);
    stk[t] = nnew(r1, b, stk[t]);
    r.* = r1;
}

fn getstk(t: anytype, b: *Blk, stk: [*c][*c]Name) Ref {
    var n = stk[@intCast(t)];
    while (n != null and !dom(n.*.b, b)) {
        const n1 = n;
        n = n.*.up;
        nfree(n1);
    }
    stk[@intCast(t)] = n;
    if (n == null) {
        // uh, oh, warn
        return UNDEF;
    } else return n.*.r;
}

fn renblk(b: *Blk, stk: [*c][*c]Name, f: *Fn) void {
    var succ: [3][*c]Blk = undefined;
    var t: i32 = undefined;

    var p = b.phi;
    while (p != null) : (p = p.*.link)
        rendef(&p.*.to, b, stk, f);
    var i = b.ins;
    while (i < &b.ins[b.nins]) : (i += 1) {
        var m: usize = 0;
        while (m < 2) : (m += 1) {
            const tv = i.*.arg[m].val;
            if (rtype(i.*.arg[m]) == RTmp)
                if (f.tmp[tv].visit != 0) {
                    i.*.arg[m] = getstk(tv, b, stk);
                };
        }
        rendef(&i.*.to, b, stk, f);
    }
    const jv = b.jmp.arg.val;
    if (rtype(b.jmp.arg) == RTmp)
        if (f.tmp[jv].visit != 0) {
            b.jmp.arg = getstk(jv, b, stk);
        };
    succ[0] = b.s1;
    succ[1] = if (b.s2 == b.s1) null else b.s2;
    succ[2] = null;
    var ps: [*c][*c]Blk = &succ;
    while (ps.* != null) : (ps += 1) {
        const s = ps.*;
        p = s.*.phi;
        while (p != null) : (p = p.*.link) {
            t = f.tmp[p.*.to.val].visit;
            if (t != 0) {
                const m = p.*.narg;
                p.*.narg += 1;
                vgrow(&p.*.arg, p.*.narg);
                vgrow(&p.*.blk, p.*.narg);
                p.*.arg[m] = getstk(t, b, stk);
                p.*.blk[m] = b;
            }
        }
    }
    var s_it: ?*Blk = b.dom;
    while (s_it) |s| : (s_it = s.dlink)
        renblk(s, stk, f);
}

/// require rpo and use
pub fn ssa(f: *Fn) void {
    var nt = f.ntmp;
    const stk: [*c][*c]Name = ealloc([*c]Name, nt);
    const d = all.debug['L'];
    all.debug['L'] = 0;
    filldom(f);
    if (all.debug['N'] != 0) {
        dprint("\n> Dominators:\n", .{});
        var b1_it: ?*Blk = f.start;
        while (b1_it) |b1| : (b1_it = b1.link) {
            if (b1.dom == null)
                continue;
            dprint("{s:>10}:", .{cs(b1.name)});
            var b_it: ?*Blk = b1.dom;
            while (b_it) |b| : (b_it = b.dlink)
                dprint(" {s}", .{cs(b.name)});
            dprint("\n", .{});
        }
    }
    fillfron(f);
    filllive(f);
    phiins(f);
    renblk(f.start, stk, f);
    while (nt != 0) {
        nt -= 1;
        while (true) {
            const n = stk[@intCast(nt)];
            if (n == null) break;
            stk[@intCast(nt)] = n.*.up;
            nfree(n);
        }
    }
    all.debug['L'] = d;
    efree(@ptrCast(stk));
    if (all.debug['N'] != 0) {
        dprint("\n> After SSA construction:\n", .{});
        printfn(f, all.dbg) catch {};
    }
}

fn phicheck(p: *Phi, b: [*c]Blk, t: Ref) bool {
    var n: uint = 0;
    while (n < p.narg) : (n += 1)
        if (req(p.arg[n], t)) {
            const b1 = p.blk[n];
            if (b1 != b and !sdom(b, b1))
                return true;
        };
    return false;
}

/// require use and ssa
pub fn ssacheck(f: *Fn) void {
    var t: [*c]Tmp = undefined;
    var bu: [*c]Blk = undefined;
    var r: Ref = undefined;

    errblk: {
        t = &f.tmp[Tmp0];
        while (ptrdiff(t, f.tmp) < f.ntmp) : (t += 1) {
            if (t.*.ndef > 1)
                err("ssa temporary %{s} defined more than once", .{cs(t.*.name)});
            if (t.*.nuse > 0 and t.*.ndef == 0) {
                bu = f.rpo[t.*.use[0].bid];
                break :errblk;
            }
        }
        var b_it: ?*Blk = f.start;
        while (b_it) |b| : (b_it = b.link) {
            var p_it: ?*Phi = b.phi;
            while (p_it) |p| : (p_it = p.link) {
                r = p.to;
                t = &f.tmp[r.val];
                var u = t.*.use;
                while (u < &t.*.use[t.*.nuse]) : (u += 1) {
                    bu = f.rpo[u.*.bid];
                    if (u.*.type == UPhi) {
                        if (phicheck(u.*.u.phi, b, r))
                            break :errblk;
                    } else if (bu != b and !sdom(b, bu))
                        break :errblk;
                }
            }
            for (b.ins[0..b.nins]) |*i| {
                if (rtype(i.to) != RTmp)
                    continue;
                r = i.to;
                t = &f.tmp[r.val];
                for (t.*.use[0..t.*.nuse]) |*u| {
                    bu = f.rpo[u.bid];
                    if (u.type == UPhi) {
                        if (phicheck(u.u.phi, b, r))
                            break :errblk;
                    } else {
                        if (bu == b) {
                            if (u.type == UIns)
                                if (u.u.ins <= i)
                                    break :errblk;
                        } else if (!sdom(b, bu))
                            break :errblk;
                    }
                }
            }
        }
        return;
    }
    // Err:
    if (t.*.visit != 0)
        die("%{s} violates ssa invariant", .{cs(t.*.name)})
    else
        err("ssa temporary %{s} is used undefined in @{s}", .{cs(t.*.name), cs(bu.*.name)});
}
