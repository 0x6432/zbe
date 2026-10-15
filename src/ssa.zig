//! One-to-one translation of ssa.c
const std = @import("std");
const assert = std.debug.assert;
// -- imports --
const all = @import("all.zig");
const Cls = all.Cls;
const U = all.U;
const BSet = all.BSet;
const Blk = all.Blk;
const Fn = all.Fn;
const PFn = all.PFn;
const Phi = all.Phi;
const Ins = all.Ins;
const R = all.R;
const RTmp = all.RTmp;
const Ref = all.Ref;
const tmpRef = all.tmpRef;
const Tmp = all.Tmp;
const Tmp0 = all.Tmp0;
const UNDEF = all.UNDEF;
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
const eallocSlice = all.eallocSlice;
const efree = all.efree;
const enew = all.enew;
const fail = all.fail;
const filldom = all.filldom;
const fillfron = all.fillfron;
const filllive = all.filllive;
const iscmp = all.iscmp;
const isext = all.isext;
const isload = all.isload;
const isparbh = all.isparbh;
const newtmp = all.newtmp;
const phicls = all.phicls;
const pnew = all.pnew;
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

/// Typed payload for registering a temporary's use. The stored Use ABI stays
/// unchanged; callers cannot pair a use kind with the wrong pointer type.
pub const UseTarget = union(enum) {
    phi: *Phi,
    ins: *Ins,
    jmp: void,
};

pub fn adduse(tmp: *Tmp, b: *Blk, target: UseTarget) void {
    if (tmp.use == null)
        return;
    const n = tmp.nuse;
    tmp.nuse += 1;
    vgrow(&tmp.use, tmp.nuse);
    const u = &tmp.use.?[n];
    u.bid = b.id;
    switch (target) {
        .phi => |p| {
            u.type = .phi;
            u.u.phi = p;
        },
        .ins => |i| {
            u.type = .ins;
            u.u.ins = i;
        },
        .jmp => u.type = .jmp,
    }
}

/// fill usage, width, phi, and class information
/// must not change .visit fields
pub fn filluse(f: *Fn) void {
    var t: i32 = undefined;
    var tp: i32 = undefined;
    var w: i32 = undefined;
    var x: i32 = undefined;
    var xk: Cls = undefined;

    const tmp = f.tmps();
    t = Tmp0;
    while (t < f.ntmp) : (t += 1) {
        const tt = &tmp[@intCast(t)];
        tt.def = null;
        tt.bid = NOID;
        tt.ndef = 0;
        tt.nuse = 0;
        tt.cls = .w;
        tt.phi = 0;
        tt.width = WFull;
        if (tt.use == null)
            tt.use = vnewT(Use, 0, PFn);
    }
    var b_it: ?*Blk = f.start;
    while (b_it) |b| : (b_it = b.link) {
        var p_it: ?*Phi = b.phi;
        while (p_it) |p| : (p_it = p.link) {
            assert(rtype(p.to) == RTmp);
            tp = p.to.val;
            tmp[@intCast(tp)].bid = b.id;
            tmp[@intCast(tp)].ndef += 1;
            tmp[@intCast(tp)].cls = p.cls;
            tp = phicls(tp, tmp);
            for (p.args()) |a|
                if (rtype(a) == RTmp) {
                    t = a.val;
                    adduse(&tmp[@intCast(t)], b, .{ .phi = p });
                    t = phicls(t, tmp);
                    if (t != tp)
                        tmp[@intCast(t)].phi = tp;
                };
        }
        for (b.insns()) |*i| {
            if (!req(i.to, R)) {
                assert(rtype(i.to) == RTmp);
                w = WFull;
                if (isparbh(i.op))
                    w = @intCast(Wsb + i.op.diff(.parsb));
                if (isload(i.op) and i.op != .load)
                    w = @intCast(Wsb + i.op.diff(.loadsb));
                if (isext(i.op))
                    w = @intCast(Wsb + i.op.diff(.extsb));
                if (iscmp(i.op, &xk, &x))
                    w = Wub;
                if (w == Wsw or w == Wuw)
                    if (i.cls == .w) {
                        w = WFull;
                    };
                t = i.to.val;
                tmp[@intCast(t)].width = w;
                tmp[@intCast(t)].def = i;
                tmp[@intCast(t)].bid = b.id;
                tmp[@intCast(t)].ndef += 1;
                tmp[@intCast(t)].cls = i.cls;
            }
            var m: usize = 0;
            while (m < 2) : (m += 1)
                if (rtype(i.arg[m]) == RTmp) {
                    t = (i.arg[m].val);
                    adduse(&tmp[@intCast(t)], b, .{ .ins = i });
                };
        }
        if (rtype(b.jmp.arg) == RTmp)
            adduse(&tmp[b.jmp.arg.val], b, .jmp);
    }
}

fn refindex(t: i32, f: *Fn) Ref {
    return newtmp(f.tmp[@intCast(t)].name, f.tmp[@intCast(t)].cls, f);
}

fn phiins(f: *Fn) void {
    var u: BSet = undefined;
    var defs: BSet = undefined;
    var k: all.Cls = undefined;

    bsinit(&u, f.nblk);
    bsinit(&defs, f.nblk);
    // work stack of blocks
    const blist = eallocSlice(*Blk, f.nblk);
    var nb: usize = 0;
    const nt = f.ntmp;
    var t: i32 = Tmp0;
    while (t < nt) : (t += 1) {
        const tt = &f.tmp[@intCast(t)];
        tt.visit = 0;
        if (tt.phi != 0)
            continue;
        if (tt.ndef == 1) {
            var ok = true;
            const defb = tt.bid;
            for (tt.use.?[0..tt.nuse]) |use|
                ok = ok and (use.bid == defb);
            if (ok or defb == f.start.?.id)
                continue;
        }
        bszero(&u);
        k = .x;
        var b_it = f.start;
        while (b_it) |b| : (b_it = b.link) {
            b.visit = 0;
            var r = R;
            for (b.insns()) |*i| {
                if (!req(r, R)) {
                    if (req(i.arg[0], tmpRef(t)))
                        i.arg[0] = r;
                    if (req(i.arg[1], tmpRef(t)))
                        i.arg[1] = r;
                }
                if (req(i.to, tmpRef(t))) {
                    if (!bshas(&b.out, t)) {
                        r = refindex(t, f);
                        i.to = r;
                    } else {
                        if (!bshas(&u, b.id)) {
                            bsset(&u, b.id);
                            blist[nb] = b;
                            nb += 1;
                        }
                        if (clsmerge(&k, i.cls))
                            die("invalid input", .{});
                    }
                }
            }
            if (!req(r, R) and req(b.jmp.arg, tmpRef(t)))
                b.jmp.arg = r;
        }
        bscopy(&defs, &u);
        while (nb > 0) {
            f.tmp[@intCast(t)].visit = t;
            nb -= 1;
            const b = blist[nb];
            bsclr(&u, b.id);
            for (b.frons()) |a| {
                const v = a.visit;
                a.visit += 1;
                if (v == 0 and bshas(&a.in, t)) {
                    const p = pnew(Phi);
                    p.cls = k;
                    p.to = tmpRef(t);
                    p.link = a.phi;
                    p.arg = vnewT(Ref, 0, PFn);
                    p.blk = vnewT(*Blk, 0, PFn);
                    a.phi = p;
                    if (!bshas(&defs, a.id) and !bshas(&u, a.id)) {
                        bsset(&u, a.id);
                        blist[nb] = a;
                        nb += 1;
                    }
                }
            }
        }
    }
    efree(@ptrCast(blist.ptr));
}

/// stack of renamed versions of a temporary
const Name = struct {
    r: Ref,
    b: *Blk,
    up: ?*Name,
};

/// free list
/// SSA construction state.
const State = struct {
    namel: ?*Name = null,
};
var st: State = .{};

fn nnew(r: Ref, b: *Blk, up: ?*Name) *Name {
    const n = if (st.namel) |n| blk: {
        st.namel = n.up;
        break :blk n;
    } else
        // could use alloc, here
        // but namel should be reset
        enew(Name);
    n.* = .{ .r = r, .b = b, .up = up };
    return n;
}

fn nfree(n: *Name) void {
    n.up = st.namel;
    st.namel = n;
}

fn rendef(r: *Ref, b: *Blk, stk: []?*Name, f: *Fn) void {
    const t = r.val;
    if (req(r.*, R) or f.tmp[t].visit == 0)
        return;
    const r1 = refindex((t), f);
    f.tmp[r1.val].visit = t;
    stk[t] = nnew(r1, b, stk[t]);
    r.* = r1;
}

fn getstk(t: anytype, b: *Blk, stk: []?*Name) Ref {
    var n_ = stk[@intCast(t)];
    while (n_) |n| {
        if (dom(n.b, b)) break;
        n_ = n.up;
        nfree(n);
    }
    stk[@intCast(t)] = n_;
    // uh, oh, warn if null
    return if (n_) |n| n.r else UNDEF;
}

fn renblk(b: *Blk, stk: []?*Name, f: *Fn) void {
    var p_it = b.phi;
    while (p_it) |p| : (p_it = p.link)
        rendef(&p.to, b, stk, f);
    for (b.insns()) |*i| {
        for (&i.arg) |*a| {
            if (rtype(a.*) == RTmp and f.tmp[a.val].visit != 0)
                a.* = getstk(a.val, b, stk);
        }
        rendef(&i.to, b, stk, f);
    }
    if (rtype(b.jmp.arg) == RTmp and f.tmp[b.jmp.arg.val].visit != 0)
        b.jmp.arg = getstk(b.jmp.arg.val, b, stk);
    const succ = [2]?*Blk{ b.s1, if (b.s2 == b.s1) null else b.s2 };
    for (succ) |s_| {
        const s = s_ orelse break;
        p_it = s.phi;
        while (p_it) |p| : (p_it = p.link) {
            const t = f.tmp[p.to.val].visit;
            if (t != 0) {
                const m = p.narg;
                p.narg += 1;
                vgrow(&p.arg, p.narg);
                vgrow(&p.blk, p.narg);
                p.arg[m] = getstk(t, b, stk);
                p.blk[m] = b;
            }
        }
    }
    var s_it = b.dom;
    while (s_it) |s| : (s_it = s.dlink)
        renblk(s, stk, f);
}

/// require rpo and use
pub fn ssa(f: *Fn) void {
    const stk = eallocSlice(?*Name, f.ntmp);
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
    renblk(f.start.?, stk, f);
    var nt = stk.len;
    while (nt != 0) {
        nt -= 1;
        while (stk[nt]) |n| {
            stk[nt] = n.up;
            nfree(n);
        }
    }
    all.debug['L'] = d;
    efree(@ptrCast(stk.ptr));
    if (all.debug['N'] != 0) {
        dprint("\n> After SSA construction:\n", .{});
        printfn(f, all.dbg) catch {};
    }
}

fn phicheck(p: *Phi, b: *Blk, t: Ref) bool {
    for (p.args(), p.blks()) |a, b1|
        if (req(a, t) and b1 != b and !sdom(b, b1))
            return true;
    return false;
}

/// require use and ssa
pub fn ssacheck(f: *Fn) all.Error!void {
    var t: *Tmp = undefined;
    var bu: ?*Blk = undefined;
    var r: Ref = undefined;

    errblk: {
        for (f.tmp[Tmp0..@intCast(f.ntmp)]) |*tt| {
            t = tt;
            if (t.ndef > 1)
                return fail("ssa temporary %{s} defined more than once", .{cs(t.name)});
            if (t.nuse > 0 and t.ndef == 0) {
                bu = f.rpo[t.use.?[0].bid];
                break :errblk;
            }
        }
        var b_it: ?*Blk = f.start;
        while (b_it) |b| : (b_it = b.link) {
            var p_it: ?*Phi = b.phi;
            while (p_it) |p| : (p_it = p.link) {
                r = p.to;
                t = &f.tmp[r.val];
                for (t.use.?[0..t.nuse]) |*u| {
                    bu = f.rpo[u.bid];
                    if (u.type == .phi) {
                        if (phicheck(u.u.phi, b, r))
                            break :errblk;
                    } else if (bu != b and !sdom(b, bu.?))
                        break :errblk;
                }
            }
            for (b.insns()) |*i| {
                if (rtype(i.to) != RTmp)
                    continue;
                r = i.to;
                t = &f.tmp[r.val];
                for (t.use.?[0..t.nuse]) |*u| {
                    bu = f.rpo[u.bid];
                    if (u.type == .phi) {
                        if (phicheck(u.u.phi, b, r))
                            break :errblk;
                    } else {
                        if (bu == b) {
                            if (u.type == .ins)
                                if (@intFromPtr(u.u.ins) <= @intFromPtr(i))
                                    break :errblk;
                        } else if (!sdom(b, bu.?))
                            break :errblk;
                    }
                }
            }
        }
        return;
    }
    // Err:
    if (t.visit != 0)
        die("%{s} violates ssa invariant", .{cs(t.name)})
    else
        return fail("ssa temporary %{s} is used undefined in @{s}", .{cs(t.name), cs(bu.?.name)});
}

test "typed use registration: payloads, block IDs, and growth" {
    defer all.freeall();
    var temp = std.mem.zeroes(Tmp);
    temp.use = vnewT(Use, 0, PFn);
    var block = std.mem.zeroes(Blk);
    block.id = 7;
    var phi = std.mem.zeroes(Phi);
    var instruction = all.insOp(.copy);
    adduse(&temp, &block, .{ .phi = &phi });
    adduse(&temp, &block, .{ .ins = &instruction });
    adduse(&temp, &block, .jmp);
    try std.testing.expectEqual(@as(uint, 3), temp.nuse);
    try std.testing.expectEqual(all.U.phi, temp.use.?[0].type);
    try std.testing.expectEqual(&phi, temp.use.?[0].u.phi);
    try std.testing.expectEqual(all.U.ins, temp.use.?[1].type);
    try std.testing.expectEqual(&instruction, temp.use.?[1].u.ins);
    try std.testing.expectEqual(all.U.jmp, temp.use.?[2].type);
    for (0..20) |_| adduse(&temp, &block, .{ .ins = &instruction });
    try std.testing.expectEqual(@as(uint, 23), temp.nuse);
    for (temp.use.?[0..temp.nuse]) |use|
        try std.testing.expectEqual(@as(uint, 7), use.bid);
    try std.testing.expectEqual(&phi, temp.use.?[0].u.phi);
    try std.testing.expectEqual(&instruction, temp.use.?[22].u.ins);
}

test "typed use registration: disabled use tracking leaves count unchanged" {
    var temp = std.mem.zeroes(Tmp);
    temp.nuse = 17;
    var block = std.mem.zeroes(Blk);
    var instruction = all.insOp(.copy);
    adduse(&temp, &block, .{ .ins = &instruction });
    adduse(&temp, &block, .jmp);
    try std.testing.expect(temp.use == null);
    try std.testing.expectEqual(@as(uint, 17), temp.nuse);
}
