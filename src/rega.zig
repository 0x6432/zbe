//! One-to-one translation of rega.c
const std = @import("std");
const assert = std.debug.assert;
// -- imports --
const all = @import("all.zig");
const BIT = all.BIT;
const BSet = all.BSet;
const Blk = all.Blk;
const Fn = all.Fn;
const Ins = all.Ins;
const Jjmp = all.Jjmp;
const KBASE = all.KBASE;
const Kd = all.Kd;
const Kl = all.Kl;
const Ks = all.Ks;
const Kw = all.Kw;
const Mem = all.Mem;
const Ocall = all.ops.Ocall;
const Ocopy = all.ops.Ocopy;
const Oswap = all.ops.Oswap;
const PFn = all.PFn;
const Phi = all.Phi;
const R = all.R;
const RMem = all.RMem;
const RSlot = all.RSlot;
const RTmp = all.RTmp;
const Ref = all.Ref;
const SLOT = all.SLOT;
const TMP = all.TMP;
const Tmp = all.Tmp;
const Tmp0 = all.Tmp0;
const bits = all.bits;
const bsclr = all.bsclr;
const bscopy = all.bscopy;
const bshas = all.bshas;
const bsinit = all.bsinit;
const bsiter = all.bsiter;
const bsset = all.bsset;
const bszero = all.bszero;
const cs = all.cs;
const die = all.die;
const dprint = all.dprint;
const emit = all.emit;
const emiti = all.emiti;
const icpy = all.icpy;
const idup = all.idup;
const isreg = all.isreg;
const newblk = all.newblk;
const palloc = all.palloc;
const phicls = all.phicls;
const printfn = all.printfn;
const ptrdiff = all.ptrdiff;
const req = all.req;
const rtype = all.rtype;
const sort = all.sort;
const strf = all.strf;
const uint = all.uint;
// -- end imports --

const RMap = extern struct {
    t: [Tmp0]i32,
    r: [Tmp0]i32,
    w: [Tmp0]i32, // wait list, for unmatched hints
    b: BSet,
    n: i32,
};

const NPm = 64; // max copies in a parallel move

var regu: bits = 0; // registers used
var tmp: [*c]Tmp = null; // function temporaries
var mem: [*c]Mem = null; // function mem references
const PMove = struct {
    src: Ref,
    dst: Ref,
    cls: i32,
};
var pm: [NPm]PMove = undefined; // parallel move constructed
var npm: i32 = 0; // size of pm
var loop: i32 = 0; // current loop level

var stmov: uint = 0; // stats: added moves
var stblk: uint = 0; // stats: added blocks

fn hint(t: i32) [*c]i32 {
    return &tmp[@intCast(phicls(t, tmp))].hint.r;
}

fn sethint(t: i32, r: i32) void {
    const p = &tmp[@intCast(phicls(t, tmp))];
    if (p.hint.r == -1 or p.hint.w > loop) {
        p.hint.r = r;
        p.hint.w = loop;
        tmp[@intCast(t)].visit = -1;
    }
}

fn rcopy(ma: *RMap, mb: *RMap) void {
    ma.t = mb.t;
    ma.r = mb.r;
    ma.w = mb.w;
    bscopy(&ma.b, &mb.b);
    ma.n = mb.n;
}

fn rfind(m: *RMap, t: i32) i32 {
    var i: usize = 0;
    while (i < m.n) : (i += 1) {
        if (m.t[i] == t)
            return m.r[i];
    }
    return -1;
}

fn rref(m: *RMap, t: i32) Ref {
    const r = rfind(m, t);
    if (r == -1) {
        const s = tmp[@intCast(t)].slot;
        assert(s != -1); // should have spilled
        return SLOT(s);
    } else return TMP(r);
}

fn radd(m: *RMap, t: i32, r: i32) void {
    assert(t >= Tmp0 or t == r); // invalid temporary
    assert((all.T.gpr0 <= r and r < all.T.gpr0 + all.T.ngpr) or
        (all.T.fpr0 <= r and r < all.T.fpr0 + all.T.nfpr)); // invalid register
    assert(!bshas(&m.b, t)); // temporary has mapping
    assert(!bshas(&m.b, r)); // register already allocated
    assert(m.n <= all.T.ngpr + all.T.nfpr); // too many mappings
    bsset(&m.b, t);
    bsset(&m.b, r);
    m.t[@intCast(m.n)] = t;
    m.r[@intCast(m.n)] = r;
    m.n += 1;
    regu |= BIT(r);
}

fn ralloctry(m: *RMap, t: i32, try_: bool) Ref {
    if (t < Tmp0) {
        assert(bshas(&m.b, t));
        return TMP(t);
    }
    if (bshas(&m.b, t)) {
        const r = rfind(m, t);
        assert(r != -1);
        return TMP(r);
    }
    var r = tmp[@intCast(t)].visit;
    if (r == -1 or bshas(&m.b, r))
        r = hint(t).*;
    found: {
        if (r == -1 or bshas(&m.b, r)) {
            if (try_)
                return R;
            var regs = tmp[@intCast(phicls(t, tmp))].hint.m;
            regs |= m.b.t[0];
            var r0: i32 = undefined;
            var r1: i32 = undefined;
            if (KBASE(tmp[@intCast(t)].cls) == 0) {
                r0 = all.T.gpr0;
                r1 = r0 + all.T.ngpr;
            } else {
                r0 = all.T.fpr0;
                r1 = r0 + all.T.nfpr;
            }
            r = r0;
            while (r < r1) : (r += 1) {
                if ((regs & BIT(r)) == 0)
                    break :found;
            }
            r = r0;
            while (r < r1) : (r += 1) {
                if (!bshas(&m.b, r))
                    break :found;
            }
            die("no more regs", .{});
        }
    }
    radd(m, t, r);
    sethint(t, r);
    tmp[@intCast(t)].visit = r;
    const h = hint(t).*;
    if (h != -1 and h != r)
        m.w[@intCast(h)] = t;
    return TMP(r);
}

inline fn ralloc(m: *RMap, t: i32) Ref {
    return ralloctry(m, t, false);
}

fn rfree(m: *RMap, t: i32) i32 {
    assert(t >= Tmp0 or (BIT(t) & all.T.rglob) == 0);
    if (!bshas(&m.b, t))
        return -1;
    var i: usize = 0;
    while (m.t[i] != t) : (i += 1)
        assert(i + 1 < m.n);
    const r = m.r[i];
    bsclr(&m.b, t);
    bsclr(&m.b, r);
    m.n -= 1;
    const cnt: usize = @as(usize, @intCast(m.n)) - i;
    if (cnt != 0) std.mem.copyForwards(i32, m.t[i..][0..cnt], m.t[i + 1 ..][0..cnt]);
    if (cnt != 0) std.mem.copyForwards(i32, m.r[i..][0..cnt], m.r[i + 1 ..][0..cnt]);
    assert(t >= Tmp0 or t == r);
    return r;
}

fn mdump(m: *RMap) void {
    var i: usize = 0;
    while (i < m.n) : (i += 1) {
        if (m.t[i] >= Tmp0)
            dprint(" ({s}, R{d})", .{cs(tmp[@intCast(m.t[i])].name), m.r[i]});
    }
    dprint("\n", .{});
}

fn pmadd(src: Ref, dst: Ref, k: i32) void {
    if (npm == NPm)
        die("no more pm slots", .{});
    pm[@intCast(npm)].src = src;
    pm[@intCast(npm)].dst = dst;
    pm[@intCast(npm)].cls = k;
    npm += 1;
}

const PMStat = enum(i32) { ToMove = 0, Moving, Moved };

fn pmrec(status: [*c]PMStat, i: usize, k: *i32) i32 {
    var c: i32 = undefined;

    // note, this routine might emit
    // too many large instructions
    if (req(pm[i].src, pm[i].dst)) {
        status[i] = .Moved;
        return -1;
    }
    assert(KBASE(pm[i].cls) == KBASE(k.*));
    assert((Kw | Kl) == Kl and (Ks | Kd) == Kd);
    k.* |= pm[i].cls;
    var j: usize = 0;
    while (j < npm) : (j += 1) {
        if (req(pm[j].dst, pm[i].src))
            break;
    }
    sw: switch (if (j == npm) PMStat.Moved else status[j]) {
        .Moving => {
            c = @intCast(j); // start of cycle
            emit(Oswap, k.*, R, pm[i].src, pm[i].dst);
        },
        .ToMove => {
            status[i] = .Moving;
            c = pmrec(status, j, k);
            if (c == i) {
                c = -1; // end of cycle
                break :sw;
            }
            if (c != -1) {
                emit(Oswap, k.*, R, pm[i].src, pm[i].dst);
                break :sw;
            }
            continue :sw .Moved;
        },
        .Moved => {
            c = -1;
            emit(Ocopy, pm[i].cls, pm[i].dst, pm[i].src, R);
        },
    }
    status[i] = .Moved;
    return c;
}

fn pmgen() void {
    const status: [*c]PMStat = palloc(PMStat, npm);
    assert(npm == 0 or status[@intCast(npm - 1)] == .ToMove);
    var i: usize = 0;
    while (i < npm) : (i += 1) {
        if (status[i] == .ToMove) {
            var k = pm[i].cls;
            _ = pmrec(status, i, &k);
        }
    }
}

fn move(r: i32, to: Ref, m: *RMap) void {
    const r1 = if (req(to, R)) -1 else rfree(m, @intCast(to.val));
    if (bshas(&m.b, r)) {
        // r is used and not by to
        assert(r1 != r);
        var n: usize = 0;
        while (m.r[n] != r) : (n += 1)
            assert(n + 1 < m.n);
        const t = m.t[n];
        _ = rfree(m, t);
        bsset(&m.b, r);
        _ = ralloc(m, t);
        bsclr(&m.b, r);
    }
    const t: i32 = if (req(to, R)) r else @intCast(to.val);
    radd(m, t, r);
}

fn regcpy(i: [*c]Ins) bool {
    return i.*.op == Ocopy and isreg(i.*.arg[0]);
}

fn dopm(b: [*c]Blk, i_: [*c]Ins, m: *RMap) [*c]Ins {
    var m0 = m.*; // okay since we don't use m0.b
    m0.b.t = null;
    var i = i_ + 1;
    const i_1 = i;
    while (true) {
        i -= 1;
        move(@intCast(i.*.arg[0].val), i.*.to, m);
        if (!(i != b.*.ins and regcpy(i - 1))) break;
    }
    assert(m0.n <= m.n);
    if (i != b.*.ins and (i - 1).*.op == Ocall) {
        const def = all.T.retregs((i - 1).*.arg[1], null) | all.T.rglob;
        var r: usize = 0;
        while (all.T.rsave[r] >= 0) : (r += 1) {
            if ((BIT(all.T.rsave[r]) & def) == 0)
                move(all.T.rsave[r], R, m);
        }
    }
    npm = 0;
    var n: usize = 0;
    while (n < m.n) : (n += 1) {
        const t = m.t[n];
        const s = tmp[@intCast(t)].slot;
        const r1 = m.r[n];
        const r = rfind(&m0, t);
        if (r != -1)
            pmadd(TMP(r1), TMP(r), tmp[@intCast(t)].cls)
        else if (s != -1)
            pmadd(TMP(r1), SLOT(s), tmp[@intCast(t)].cls);
    }
    var ip = i;
    while (ip < i_1) : (ip += 1) {
        if (!req(ip.*.to, R))
            _ = rfree(m, @intCast(ip.*.to.val));
        const r: i32 = @intCast(ip.*.arg[0].val);
        if (rfind(m, r) == -1)
            radd(m, r, r);
    }
    pmgen();
    return i;
}

fn prio1(r1: Ref, r2: Ref) bool {
    // trivial heuristic to begin with,
    // later we can use the distance to
    // the definition instruction
    _ = r2;
    return hint(@intCast(r1.val)).* != -1;
}

fn insert(r: [*c]Ref, rs: *[4][*c]Ref, p: usize) void {
    var i = p;
    rs[i] = r;
    while (i > 0) {
        i -= 1;
        if (!prio1(r.*, rs[i].*)) break;
        rs[i + 1] = rs[i];
        rs[i] = r;
    }
}

fn doblk(b: *Blk, cur: *RMap) void {
    var ra: [4][*c]Ref = undefined;

    if (rtype(b.jmp.arg) == RTmp)
        b.jmp.arg = ralloc(cur, @intCast(b.jmp.arg.val));
    all.curi = all.insbEnd();
    var i_1 = b.ins + b.nins;
    while (i_1 != b.ins) {
        i_1 -= 1;
        emiti(i_1.*);
        const i = all.curi;
        var rf: i32 = -1;
        sw: switch (i.*.op) {
            Ocall => {
                const rs = all.T.argregs(i.*.arg[1], null) | all.T.rglob;
                var r: usize = 0;
                while (all.T.rsave[r] >= 0) : (r += 1) {
                    if ((BIT(all.T.rsave[r]) & rs) == 0)
                        _ = rfree(cur, all.T.rsave[r]);
                }
            },
            else => {
                if (i.*.op == Ocopy) {
                    if (regcpy(i)) {
                        all.curi += 1;
                        i_1 = dopm(b, i_1, cur);
                        stmov +%= @truncate(@as(usize, @bitCast(ptrdiff(i + 1, all.curi))));
                        continue;
                    }
                    if (isreg(i.*.to))
                        if (rtype(i.*.arg[0]) == RTmp)
                            sethint(@intCast(i.*.arg[0].val), @intCast(i.*.to.val));
                    // fall through
                }
                if (!req(i.*.to, R)) {
                    assert(rtype(i.*.to) == RTmp);
                    const r: i32 = @intCast(i.*.to.val);
                    if (r < Tmp0 and (BIT(r) & all.T.rglob) != 0)
                        break :sw;
                    rf = rfree(cur, r);
                    if (rf == -1) {
                        assert(!isreg(i.*.to));
                        all.curi += 1;
                        continue;
                    }
                    i.*.to = TMP(rf);
                }
            },
        }
        var nr: usize = 0;
        var x: usize = 0;
        while (x < 2) : (x += 1) {
            switch (rtype(i.*.arg[x])) {
                RMem => {
                    const m = &mem[i.*.arg[x].val];
                    if (rtype(m.base) == RTmp) {
                        insert(&m.base, &ra, nr);
                        nr += 1;
                    }
                    if (rtype(m.index) == RTmp) {
                        insert(&m.index, &ra, nr);
                        nr += 1;
                    }
                },
                RTmp => {
                    insert(&i.*.arg[x], &ra, nr);
                    nr += 1;
                },
                else => {},
            }
        }
        var r: usize = 0;
        while (r < nr) : (r += 1)
            ra[r].* = ralloc(cur, @intCast(ra[r].*.val));
        if (i.*.op == Ocopy and req(i.*.to, i.*.arg[0]))
            all.curi += 1;

        // try to change the register of a hinted
        // temporary if rf is available
        if (rf != -1) {
            const t = cur.w[@intCast(rf)];
            if (t != 0)
                if (!bshas(&cur.b, rf) and hint(t).* == rf) {
                    const rt = rfree(cur, t);
                    if (rt != -1) {
                        tmp[@intCast(t)].visit = -1;
                        _ = ralloc(cur, t);
                        assert(bshas(&cur.b, rf));
                        emit(Ocopy, tmp[@intCast(t)].cls, TMP(rt), TMP(rf), R);
                        stmov += 1;
                        cur.w[@intCast(rf)] = 0;
                        r = 0;
                        while (r < nr) : (r += 1) {
                            if (req(ra[r].*, TMP(rt)))
                                ra[r].* = TMP(rf);
                        }
                        // one could iterate this logic with
                        // the newly freed rt, but in this case
                        // the above loop must be changed
                    }
                };
        }
    }
    idup(b, all.curi, @intCast(ptrdiff(all.insbEnd(), all.curi)));
}

/// qsort() comparison function to peel
/// loop nests from inside out
fn carve(ba: *Blk, bb: *Blk) std.math.Order {
    // todo, evaluate if this order is really
    // better than the simple postorder
    if (ba.loop == bb.loop)
        return std.math.order(bb.id, ba.id);
    return if (ba.loop > bb.loop) .lt else .gt;
}

/// comparison function to order temporaries
/// for allocation at the end of blocks
fn prio2(t1: i32, t2: i32) i32 {
    if ((tmp[@intCast(t1)].visit ^ tmp[@intCast(t2)].visit) < 0) // != signs
        return if (tmp[@intCast(t1)].visit != -1) 1 else -1;
    if ((hint(t1).* ^ hint(t2).*) < 0)
        return if (hint(t1).* != -1) 1 else -1;
    return @bitCast(tmp[@intCast(t1)].cost -% tmp[@intCast(t2)].cost);
}

/// register allocation
/// depends on rpo, phi, cost, (and obviously spill)
pub fn rega(f: *Fn) void {
    var rl: [Tmp0]i32 = undefined;
    var cur: RMap = undefined;
    var old: RMap = undefined;

    // 1. setup
    stmov = 0;
    stblk = 0;
    regu = 0;
    tmp = f.tmp;
    mem = f.mem;
    const blk: [*c][*c]Blk = palloc([*c]Blk, f.nblk);
    const end: [*]RMap = palloc(RMap, f.nblk);
    const beg: [*]RMap = palloc(RMap, f.nblk);
    var n: uint = 0;
    while (n < f.nblk) : (n += 1) {
        bsinit(&end[n].b, @intCast(f.ntmp));
        bsinit(&beg[n].b, @intCast(f.ntmp));
    }
    bsinit(&cur.b, @intCast(f.ntmp));
    bsinit(&old.b, @intCast(f.ntmp));

    loop = std.math.maxInt(i32);
    var t: i32 = 0;
    while (t < f.ntmp) : (t += 1) {
        tmp[@intCast(t)].hint.r = if (t < Tmp0) t else -1;
        tmp[@intCast(t)].hint.w = loop;
        tmp[@intCast(t)].visit = -1;
    }
    var bp = blk;
    var b: [*c]Blk = f.start;
    while (b != null) : (b = b.*.link) {
        bp.* = b;
        bp += 1;
    }
    sort(*Blk, @ptrCast(blk), f.nblk, carve);
    b = f.start;
    var i = b.*.ins;
    while (i < b.*.ins + b.*.nins) : (i += 1) {
        if (i.*.op != Ocopy or !isreg(i.*.arg[0])) {
            break;
        } else {
            assert(rtype(i.*.to) == RTmp);
            sethint(@intCast(i.*.to.val), @intCast(i.*.arg[0].val));
        }
    }

    // 2. assign registers
    bp = blk;
    while (bp < blk + f.nblk) : (bp += 1) {
        b = bp.*;
        n = b.*.id;
        loop = b.*.loop;
        cur.n = 0;
        bszero(&cur.b);
        cur.w = @splat(0);
        var x: usize = 0;
        t = Tmp0;
        while (bsiter(&b.*.out, &t)) : (t += 1) {
            var j = x;
            x += 1;
            rl[j] = t;
            while (j > 0) {
                j -= 1;
                if (!(prio2(t, rl[j]) > 0)) break;
                rl[j + 1] = rl[j];
                rl[j] = t;
            }
        }
        var r: i32 = 0;
        while (bsiter(&b.*.out, &r) and r < Tmp0) : (r += 1)
            radd(&cur, r, r);
        var j: usize = 0;
        while (j < x) : (j += 1)
            _ = ralloctry(&cur, rl[j], true);
        j = 0;
        while (j < x) : (j += 1)
            _ = ralloc(&cur, rl[j]);
        rcopy(&end[n], &cur);
        doblk(b, &cur);
        bscopy(&b.*.in, &cur.b);
        var p_it: ?*Phi = b.*.phi;
        while (p_it) |p| : (p_it = p.link) {
            if (rtype(p.to) == RTmp)
                bsclr(&b.*.in, p.to.val);
        }
        rcopy(&beg[n], &cur);
    }

    // 3. emit copies shared by multiple edges
    // to the same block
    var s: [*c]Blk = f.start;
    while (s != null) : (s = s.*.link) {
        if (s.*.npred <= 1)
            continue;
        const m = &beg[s.*.id];

        // rl maps a register that is live at the
        // beginning of s to the one used in all
        // predecessors (if any, -1 otherwise)
        rl = @splat(0);

        // to find the register of a phi in a
        // predecessor, we have to find the
        // corresponding argument
        var p_it: ?*Phi = s.*.phi;
        while (p_it) |p| : (p_it = p.link) {
            if (rtype(p.to) != RTmp)
                continue;
            const r = rfind(m, @intCast(p.to.val));
            if (r == -1)
                continue;
            const ru: usize = @intCast(r);
            var u: uint = 0;
            while (u < p.narg) : (u += 1) {
                b = p.blk[u];
                const src = p.arg[u];
                if (rtype(src) != RTmp)
                    continue;
                const x = rfind(&end[b.*.id], @intCast(src.val));
                if (x == -1) // spilled
                    continue;
                rl[ru] = if (rl[ru] == 0 or rl[ru] == x) x else -1;
            }
            if (rl[ru] == 0)
                rl[ru] = -1;
        }

        // process non-phis temporaries
        var j: usize = 0;
        while (j < m.n) : (j += 1) {
            t = m.t[j];
            const ru: usize = @intCast(m.r[j]);
            if (rl[ru] != 0 or t < Tmp0) // todo, remove this
                continue;
            for (s.*.pred[0..s.*.npred]) |pp| {
                const x = rfind(&end[pp.id], t);
                if (x == -1) // spilled
                    continue;
                rl[ru] = if (rl[ru] == 0 or rl[ru] == x) x else -1;
            }
            if (rl[ru] == 0)
                rl[ru] = -1;
        }

        npm = 0;
        j = 0;
        while (j < m.n) : (j += 1) {
            t = m.t[j];
            const r = m.r[j];
            const x = rl[@intCast(r)];
            assert(x != 0 or t < Tmp0); // todo, ditto
            if (x > 0 and !bshas(&m.b, x)) {
                pmadd(TMP(x), TMP(r), tmp[@intCast(t)].cls);
                m.r[j] = x;
                bsset(&m.b, x);
            }
        }
        all.curi = all.insbEnd();
        pmgen();
        const jj: uint = @intCast(ptrdiff(all.insbEnd(), all.curi));
        if (jj == 0)
            continue;
        stmov += jj;
        s.*.nins += jj;
        i = palloc(Ins, s.*.nins);
        _ = icpy(icpy(i, all.curi, jj), s.*.ins, s.*.nins - jj);
        s.*.ins = i;
    }

    if (all.debug['R'] != 0) {
        dprint("\n> Register mappings:\n", .{});
        n = 0;
        while (n < f.nblk) : (n += 1) {
            b = f.rpo[n];
            dprint("\t{s:<10} beg", .{cs(b.*.name)});
            mdump(&beg[n]);
            dprint("\t           end", .{});
            mdump(&end[n]);
        }
        dprint("\n", .{});
    }

    // 4. emit remaining copies in new blocks
    var blist: [*c]Blk = null;
    b = f.start;
    while (true) : (b = b.*.link) {
        var zero: [*c]Blk = null;
        const psa = [3]*[*c]Blk{ &b.*.s1, &b.*.s2, &zero };
        var pi: usize = 0;
        while (true) : (pi += 1) {
            s = psa[pi].*;
            if (s == null) break;
            npm = 0;
            var p_it: ?*Phi = s.*.phi;
            while (p_it) |p| : (p_it = p.link) {
                var dst = p.to;
                assert(rtype(dst) == RSlot or rtype(dst) == RTmp);
                if (rtype(dst) == RTmp) {
                    const r = rfind(&beg[s.*.id], @intCast(dst.val));
                    if (r == -1)
                        continue;
                    dst = TMP(r);
                }
                var u: uint = 0;
                while (p.blk[u] != b) : (u += 1)
                    assert(u + 1 < p.narg);
                var src = p.arg[u];
                if (rtype(src) == RTmp)
                    src = rref(&end[b.*.id], @intCast(src.val));
                pmadd(src, dst, p.cls);
            }
            t = Tmp0;
            while (bsiter(&s.*.in, &t)) : (t += 1) {
                const src = rref(&end[b.*.id], t);
                const dst = rref(&beg[s.*.id], t);
                pmadd(src, dst, tmp[@intCast(t)].cls);
            }
            all.curi = all.insbEnd();
            pmgen();
            if (all.curi == all.insbEnd())
                continue;
            const b1 = newblk();
            b1.*.loop = @divTrunc(b.*.loop + s.*.loop, 2);
            b1.*.link = blist;
            blist = b1;
            f.nblk += 1;
            b1.*.name = strf(PFn, "{s}_{s}", .{ cs(b.*.name), cs(s.*.name) });
            stmov += @intCast(ptrdiff(all.insbEnd(), all.curi));
            stblk += 1;
            idup(b1, all.curi, @intCast(ptrdiff(all.insbEnd(), all.curi)));
            b1.*.jmp.type = Jjmp;
            b1.*.s1 = s;
            psa[pi].* = b1;
        }
        if (b.*.link == null) {
            b.*.link = blist;
            break;
        }
    }
    b = f.start;
    while (b != null) : (b = b.*.link)
        b.*.phi = null;
    f.reg = regu;

    if (all.debug['R'] != 0) {
        dprint("\n> Register allocation statistics:\n", .{});
        dprint("\tnew moves:  {d}\n", .{stmov});
        dprint("\tnew blocks: {d}\n", .{stblk});
        dprint("\n> After register allocation:\n", .{});
        printfn(f, all.dbg) catch {};
    }
}
