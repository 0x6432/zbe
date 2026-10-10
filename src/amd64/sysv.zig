//! One-to-one translation of amd64/sysv.c
const std = @import("std");
const assert = std.debug.assert;
// -- imports --
const all = @import("../all.zig");
const Opc = all.Opc;
const tgt = @import("all.zig");
const BIT = all.BIT;
const Blk = all.Blk;
const CALL = all.CALL;
const CON_Z = all.CON_Z;
const Ciult = all.Ciult;
const FEnd = all.FEnd;
const FPad = all.FPad;
const FTyp = all.FTyp;
const Fb = all.Fb;
const Fd = all.Fd;
const Fh = all.Fh;
const Field = all.Field;
const Fl = all.Fl;
const Fn = all.Fn;
const Fs = all.Fs;
const Fw = all.Fw;
const INS = all.INS;
const INT = all.INT;
const Ins = all.Ins;
const Jjmp = all.Jjmp;
const Jjnz = all.Jjnz;
const Jret0 = all.Jret0;
const Jretc = all.Jretc;
const Jretw = all.Jretw;
const KBASE = all.KBASE;
const Kd = all.Kd;
const Kl = all.Kl;
const Kw = all.Kw;
const Kx = all.Kx;
const NCLR_SYSV = tgt.NCLR_SYSV;
const NFPS = tgt.NFPS;
const NGPS_SYSV = tgt.NGPS_SYSV;
const PFn = all.PFn;
const Phi = all.Phi;
const R = all.R;
const R10 = tgt.R10;
const R11 = tgt.R11;
const R12 = tgt.R12;
const R13 = tgt.R13;
const R14 = tgt.R14;
const R15 = tgt.R15;
const R8 = tgt.R8;
const R9 = tgt.R9;
const RAX = tgt.RAX;
const RBP = tgt.RBP;
const RBX = tgt.RBX;
const RCX = tgt.RCX;
const RCall = all.RCall;
const RDI = tgt.RDI;
const RDX = tgt.RDX;
const RSI = tgt.RSI;
const RTmp = all.RTmp;
const RType = all.RType;
const Ref = all.Ref;
const SLOT = all.SLOT;
const TMP = all.TMP;
const Typ = all.Typ;
const XMM0 = tgt.XMM0;
const XMM1 = tgt.XMM1;
const XMM10 = tgt.XMM10;
const XMM11 = tgt.XMM11;
const XMM12 = tgt.XMM12;
const XMM13 = tgt.XMM13;
const XMM14 = tgt.XMM14;
const XMM2 = tgt.XMM2;
const XMM3 = tgt.XMM3;
const XMM4 = tgt.XMM4;
const XMM5 = tgt.XMM5;
const XMM6 = tgt.XMM6;
const XMM7 = tgt.XMM7;
const XMM8 = tgt.XMM8;
const XMM9 = tgt.XMM9;
const bits = all.bits;
const cs = all.cs;
const die = all.die;
const dprint = all.dprint;
const emit = all.emit;
const emiti = all.emiti;
const err = all.err;
const getcon = all.getcon;
const icpy = all.icpy;
const idup = all.idup;
const isarg = all.isarg;
const ispar = all.ispar;
const isret = all.isret;
const newblk = all.newblk;
const newtmp = all.newtmp;
const palloc = all.palloc;
const pnew = all.pnew;
const printfn = all.printfn;
const ptrdiff = all.ptrdiff;
const req = all.req;
const rtype = all.rtype;
const strf = all.strf;
const uint = all.uint;
const vgrow = all.vgrow;
const vnewT = all.vnewT;
// -- end imports --

const AClass = struct {
    type: ?*Typ,
    inmem: i32,
    @"align": i32,
    size: uint,
    cls: [2]i32,
    ref: [2]Ref,
};

const RAlloc = struct {
    i: Ins,
    link: ?*RAlloc,
};

fn classify(a: *AClass, t: *Typ, s_: uint) void {
    var s = s_;
    const s1 = s_;
    var n: uint = 0;
    while (n < t.nunion) : ({
        n += 1;
        s = s1;
    }) {
        for (&t.fields[n]) |*f| {
            if (f.type == FEnd) break;
            assert(s <= 16);
            const cls = &a.cls[s / 8];
            switch (f.type) {
                FEnd => die("unreachable", .{}),
                FPad => {
                    // don't change anything
                    s += f.len;
                },
                Fs, Fd => {
                    if (cls.* == Kx.int())
                        cls.* = all.knum(Kd);
                    s += f.len;
                },
                Fb, Fh, Fw, Fl => {
                    cls.* = all.knum(Kl);
                    s += f.len;
                },
                FTyp => {
                    classify(a, &all.typ[f.len], s);
                    s += @intCast(all.typ[f.len].size);
                },
                else => {},
            }
        }
    }
}

fn typclass(a: *AClass, t: *Typ) void {
    var sz: uint = @intCast(t.size);
    // C: `1 << align` (align == -1 for an empty type); match x86 shift masking
    var al: uint = @as(uint, 1) << @as(u5, @truncate(@as(u32, @bitCast(@as(i32, t.@"align")))));

    // the ABI requires sizes to be rounded
    // up to the nearest multiple of 8, moreover
    // it makes it easy load and store structures
    // in registers
    if (al < 8)
        al = 8;
    sz = (sz + al - 1) & (0 -% al);

    a.type = t;
    a.size = sz;
    a.@"align" = t.@"align";

    if (t.isdark != 0 or sz > 16 or sz == 0) {
        // large or unaligned structures are
        // required to be passed in memory
        a.inmem = 1;
        return;
    }

    a.cls[0] = all.knum(Kx);
    a.cls[1] = all.knum(Kx);
    a.inmem = 0;
    classify(a, t, 0);
}

fn retr(reg: *[2]Ref, aret: *AClass) i32 {
    const retreg = [2][2]i32{ .{ RAX, RDX }, .{ XMM0, XMM0 + 1 } };
    var nr = [2]usize{ 0, 0 };
    var ca: i32 = 0;
    var n: usize = 0;
    while (n * 8 < aret.size) : (n += 1) {
        const k: usize = @intCast(KBASE(aret.cls[n]));
        reg[n] = TMP(retreg[k][nr[k]]);
        nr[k] += 1;
        ca += @as(i32, 1) << @intCast(2 * k);
    }
    return ca;
}

fn selret(b: *Blk, f: *Fn) void {
    var reg: [2]Ref = undefined;
    var aret: AClass = undefined;
    var ca: i32 = undefined;

    const j: i32 = b.jmp.type.int();

    if (!isret(j) or j == Jret0.int())
        return;

    const r0 = b.jmp.arg;
    b.jmp.type = Jret0;

    if (j == Jretc.int()) {
        typclass(&aret, &all.typ[@intCast(f.retty)]);
        if (aret.inmem != 0) {
            assert(rtype(f.retr) == RTmp);
            emit(.copy, Kl, TMP(RAX), f.retr, R);
            emit(.blit1, 0, R, INT(aret.type.?.size), R);
            emit(.blit0, 0, R, r0, f.retr);
            ca = 1;
        } else {
            ca = retr(&reg, &aret);
            if (aret.size > 8) {
                const r = newtmp("abi", Kl, f);
                emit(.load, Kl, reg[1], r, R);
                emit(.add, Kl, r, r0, getcon(8, f));
            }
            emit(.load, Kl, reg[0], r0, R);
        }
    } else {
        const k = j - Jretw.int();
        if (KBASE(k) == 0) {
            emit(.copy, k, TMP(RAX), r0, R);
            ca = 1;
        } else {
            emit(.copy, k, TMP(XMM0), r0, R);
            ca = 1 << 2;
        }
    }

    b.jmp.arg = CALL(ca);
}

fn argsclass(ins: []const Ins, ac: []AClass, op: i32, aret: ?*const AClass, env: *Ref) i32 {
    var nint: i32 = undefined;
    if (aret != null and aret.?.inmem != 0)
        nint = 5 // hidden argument
    else
        nint = 6;
    var nsse: i32 = 8;
    var varc: i32 = 0;
    var envc: i32 = 0;
    for (ins, ac) |*i, *a| {
        switch (all.ops.num(i.op) - op + all.ops.num(.arg)) {
            all.ops.num(.arg) => {
                const pn: *i32 = if (KBASE(i.cls) == 0) &nint else &nsse;
                if (pn.* > 0) {
                    pn.* -= 1;
                    a.inmem = 0;
                } else a.inmem = 2;
                a.@"align" = 3;
                a.size = 8;
                a.cls[0] = all.knum(i.cls);
            },
            all.ops.num(.argc) => {
                const n0 = i.arg[0].val;
                typclass(a, &all.typ[n0]);
                if (a.inmem != 0)
                    continue;
                var ni: i32 = 0;
                var ns: i32 = 0;
                var n: usize = 0;
                while (n * 8 < a.size) : (n += 1) {
                    if (KBASE(a.cls[n]) == 0)
                        ni += 1
                    else
                        ns += 1;
                }
                if (nint >= ni and nsse >= ns) {
                    nint -= ni;
                    nsse -= ns;
                } else a.inmem = 1;
            },
            all.ops.num(.arge) => {
                envc = 1;
                if (op == Opc.par.int())
                    env.* = i.to
                else
                    env.* = i.arg[0];
            },
            all.ops.num(.argv) => varc = 1,
            else => die("unreachable", .{}),
        }
    }

    if (varc != 0 and envc != 0)
        err("sysv abi does not support variadic env calls", .{});

    return ((varc | envc) << 12) | ((6 - nint) << 4) | ((8 - nsse) << 8);
}

pub var amd64_sysv_rsave = [_]i32{
    RDI,  RSI,  RDX,  RCX,   R8,    R9,    R10,   R11,   RAX,
    XMM0, XMM1, XMM2, XMM3,  XMM4,  XMM5,  XMM6,  XMM7,  XMM8,
    XMM9, XMM10, XMM11, XMM12, XMM13, XMM14, -1,
};
pub var amd64_sysv_rclob = [_]i32{ RBX, R12, R13, R14, R15, -1 };

comptime {
    if (!(amd64_sysv_rsave.len == NGPS_SYSV + NFPS + 1 and
        amd64_sysv_rclob.len == NCLR_SYSV + 1))
        @compileError("sysv_arrays_ok");
}

// layout of call's second argument (RCall)
//
//  29     12    8    4  3  0
//  |0...00|x|xxxx|xxxx|xx|xx|                  range
//          |    |    |  |  ` gp regs returned (0..2)
//          |    |    |  ` sse regs returned   (0..2)
//          |    |    ` gp regs passed         (0..6)
//          |    ` sse regs passed             (0..8)
//          ` 1 if rax is used to pass data    (0..1)

pub fn amd64_sysv_retregs(r: Ref, p: ?*[2]i32) bits {
    assert(rtype(r) == RCall);
    var b: bits = 0;
    const ni: i32 = (r.val & 3);
    const nf: i32 = ((r.val >> 2) & 3);
    if (ni >= 1)
        b |= BIT(RAX);
    if (ni >= 2)
        b |= BIT(RDX);
    if (nf >= 1)
        b |= BIT(XMM0);
    if (nf >= 2)
        b |= BIT(XMM1);
    if (p) |q|
        q.* = .{ ni, nf };
    return b;
}

pub fn amd64_sysv_argregs(r: Ref, p: ?*[2]i32) bits {
    assert(rtype(r) == RCall);
    var b: bits = 0;
    const ni: i32 = ((r.val >> 4) & 15);
    const nf: i32 = ((r.val >> 8) & 15);
    const ra: i32 = ((r.val >> 12) & 1);
    var j: i32 = 0;
    while (j < ni) : (j += 1)
        b |= BIT(amd64_sysv_rsave[@intCast(j)]);
    j = 0;
    while (j < nf) : (j += 1)
        b |= BIT(XMM0 + j);
    if (p) |q|
        q.* = .{ ni + ra, nf };
    return b | (if (ra != 0) BIT(RAX) else 0);
}

fn rarg(ty: i32, ni: *i32, ns: *i32) Ref {
    if (KBASE(ty) == 0) {
        const r = TMP(amd64_sysv_rsave[@intCast(ni.*)]);
        ni.* += 1;
        return r;
    } else {
        const r = TMP(XMM0 + ns.*);
        ns.* += 1;
        return r;
    }
}

/// lowers the call i_1 with its arguments ins
fn selcall(f: *Fn, ins: []Ins, i_1: *Ins, rap: *?*RAlloc) void {
    var aret: AClass = undefined;
    var reg: [2]Ref = undefined;
    var ca: i32 = undefined;
    var r: Ref = undefined;
    var r1: Ref = undefined;
    var ra: ?*RAlloc = undefined;

    var env = R;
    const ac = palloc(AClass, ins.len)[0..ins.len];

    if (!req(i_1.arg[1], R)) {
        assert(rtype(i_1.arg[1]) == RType);
        typclass(&aret, &all.typ[i_1.arg[1].val]);
        ca = argsclass(ins, ac, all.ops.num(.arg), &aret, &env);
    } else ca = argsclass(ins, ac, all.ops.num(.arg), null, &env);

    var stk: uint = 0;
    var k = ac.len;
    while (k > 0) {
        k -= 1;
        const a = &ac[k];
        if (a.inmem != 0) {
            if (a.@"align" > 4)
                err("sysv abi requires alignments of 16 or less", .{});
            stk += a.size;
            if (a.@"align" == 4)
                stk += stk & 15;
        }
    }
    stk += stk & 15;
    if (stk != 0) {
        r = getcon(-@as(i64, stk), f);
        emit(.salloc, Kl, R, r, R);
    }

    if (!req(i_1.arg[1], R)) {
        if (aret.inmem != 0) {
            // get the return location from eax
            // it saves one callee-save reg
            r1 = newtmp("abi", Kl, f);
            emit(.copy, Kl, i_1.to, TMP(RAX), R);
            ca += 1;
        } else {
            // todo, may read out of bounds.
            // gcc did this up until 5.2, but
            // this should still be fixed.
            if (aret.size > 8) {
                r = newtmp("abi", Kl, f);
                aret.ref[1] = newtmp("abi", aret.cls[1], f);
                emit(.storel, 0, R, aret.ref[1], r);
                emit(.add, Kl, r, i_1.to, getcon(8, f));
            }
            aret.ref[0] = newtmp("abi", aret.cls[0], f);
            emit(.storel, 0, R, aret.ref[0], i_1.to);
            ca += retr(&reg, &aret);
            if (aret.size > 8)
                emit(.copy, aret.cls[1], aret.ref[1], reg[1], R);
            emit(.copy, aret.cls[0], aret.ref[0], reg[0], R);
            r1 = i_1.to;
        }
        // allocate return pad
        const ra1 = pnew(RAlloc);
        // specific to NAlign == 3
        const al: i32 = if (aret.@"align" >= 2) aret.@"align" - 2 else 0;
        ra1.i = INS(Opc.alloc_first.offset(al), Kl, r1, getcon(aret.size, f), R);
        ra1.link = rap.*;
        rap.* = ra1;
        ra = ra1;
    } else {
        ra = null;
        if (KBASE(i_1.cls) == 0) {
            emit(.copy, i_1.cls, i_1.to, TMP(RAX), R);
            ca += 1;
        } else {
            emit(.copy, i_1.cls, i_1.to, TMP(XMM0), R);
            ca += 1 << 2;
        }
    }

    emit(.call, i_1.cls, R, i_1.arg[0], CALL(ca));

    if (!req(R, env))
        emit(.copy, Kl, TMP(RAX), env, R)
    else if (((ca >> 12) & 1) != 0) // vararg call
        emit(.copy, Kw, TMP(RAX), getcon((ca >> 8) & 15, f), R);

    var ni: i32 = 0;
    var ns: i32 = 0;
    if (ra != null and aret.inmem != 0)
        emit(.copy, Kl, rarg(all.knum(Kl), &ni, &ns), ra.?.i.to, R); // pass hidden argument

    for (ins, ac) |*i, *a| {
        if (i.op.int() >= Opc.arge.int() or a.inmem != 0)
            continue;
        r1 = rarg(a.cls[0], &ni, &ns);
        if (i.op == .argc) {
            if (a.size > 8) {
                const r2 = rarg(a.cls[1], &ni, &ns);
                r = newtmp("abi", Kl, f);
                emit(.load, a.cls[1], r2, r, R);
                emit(.add, Kl, r, i.arg[1], getcon(8, f));
            }
            emit(.load, a.cls[0], r1, i.arg[1], R);
        } else emit(.copy, i.cls, r1, i.arg[0], R);
    }

    if (stk == 0)
        return;

    r = newtmp("abi", Kl, f);
    var off: uint = 0;
    for (ins, ac) |*i, *a| {
        if (i.op.int() >= Opc.arge.int() or a.inmem == 0)
            continue;
        r1 = newtmp("abi", Kl, f);
        if (i.op == .argc) {
            if (a.@"align" == 4)
                off += off & 15;
            emit(.blit1, 0, R, INT(a.type.?.size), R);
            emit(.blit0, 0, R, i.arg[1], r1);
        } else emit(.storel, 0, R, i.arg[0], r1);
        emit(.add, Kl, r1, r, getcon(off, f));
        off += a.size;
    }
    emit(.salloc, Kl, r, getcon(stk, f), R);
}

fn selpar(f: *Fn, ins: []Ins) i32 {
    var aret: AClass = undefined;
    var fa: i32 = undefined;
    var r: Ref = undefined;

    var env = R;
    const ac = palloc(AClass, ins.len)[0..ins.len];
    all.curi = all.insbEnd();
    var ni: i32 = 0;
    var ns: i32 = 0;

    if (f.retty >= 0) {
        typclass(&aret, &all.typ[@intCast(f.retty)]);
        fa = argsclass(ins, ac, all.ops.num(.par), &aret, &env);
    } else fa = argsclass(ins, ac, all.ops.num(.par), null, &env);
    f.reg = amd64_sysv_argregs(CALL(fa), null);

    for (ins, ac) |*i, *a| {
        if (i.op != .parc or a.inmem != 0)
            continue;
        if (a.size > 8) {
            r = newtmp("abi", Kl, f);
            a.ref[1] = newtmp("abi", Kl, f);
            emit(.storel, 0, R, a.ref[1], r);
            emit(.add, Kl, r, i.to, getcon(8, f));
        }
        a.ref[0] = newtmp("abi", Kl, f);
        emit(.storel, 0, R, a.ref[0], i.to);
        // specific to NAlign == 3
        const al: i32 = if (a.@"align" >= 2) a.@"align" - 2 else 0;
        emit(Opc.alloc_first.offset(al), Kl, i.to, getcon(a.size, f), R);
    }

    if (f.retty >= 0 and aret.inmem != 0) {
        r = newtmp("abi", Kl, f);
        emit(.copy, Kl, r, rarg(all.knum(Kl), &ni, &ns), R);
        f.retr = r;
    }

    var s: i32 = 4;
    for (ins, ac) |*i, *a| {
        switch (a.inmem) {
            1 => {
                if (a.@"align" > 4)
                    err("sysv abi requires alignments of 16 or less", .{});
                if (a.@"align" == 4)
                    s = (s + 3) & -4;
                f.tmp[i.to.val].slot = -s;
                s += @intCast(a.size / 4);
                continue;
            },
            2 => {
                emit(.load, i.cls, i.to, SLOT(-s), R);
                s += 2;
                continue;
            },
            else => {},
        }
        if (i.op == .pare)
            continue;
        r = rarg(a.cls[0], &ni, &ns);
        if (i.op == .parc) {
            emit(.copy, a.cls[0], a.ref[0], r, R);
            if (a.size > 8) {
                r = rarg(a.cls[1], &ni, &ns);
                emit(.copy, a.cls[1], a.ref[1], r, R);
            }
        } else emit(.copy, i.cls, i.to, r, R);
    }

    if (!req(R, env))
        emit(.copy, Kl, env, TMP(RAX), R);

    return fa | (s * 4) << 12;
}

fn split(f: *Fn, b: *Blk) *Blk {
    f.nblk += 1;
    const bn = newblk();
    idup(bn, all.curi, (all.insbTail()));
    all.curi = all.insbEnd();
    b.visit += 1;
    bn.visit = b.visit;
    bn.name = strf(PFn, "{s}.{d}", .{ cs(b.name), b.visit });
    bn.loop = b.loop;
    bn.link = b.link;
    b.link = bn;
    return bn;
}

fn chpred(b: *Blk, bp: ?*Blk, bp1: *Blk) void {
    var p_it: ?*Phi = b.phi;
    while (p_it) |p| : (p_it = p.link) {
        var a: uint = 0;
        while (p.blk[a] != bp) : (a += 1)
            assert(a + 1 < p.narg);
        p.blk[a] = bp1;
    }
}

fn selvaarg(f: *Fn, b: *Blk, i: *Ins) void {
    const c4 = getcon(4, f);
    const c8 = getcon(8, f);
    const c16 = getcon(16, f);
    const ap = i.arg[0];
    const isint = KBASE(i.cls) == 0;

    // @b [...]
    //     r0 =l add ap, (0 or 4)
    //     nr =l loadsw r0
    //     r1 =w cultw nr, (48 or 176)
    //     jnz r1, @breg, @bstk
    // @breg
    //     r0 =l add ap, 16
    //     r1 =l loadl r0
    //     lreg =l add r1, nr
    //     r0 =w add nr, (8 or 16)
    //     r1 =l add ap, (0 or 4)
    //     storew r0, r1
    // @bstk
    //     r0 =l add ap, 8
    //     lstk =l loadl r0
    //     r1 =l add lstk, 8
    //     storel r1, r0
    // @b0
    //     %loc =l phi @breg %lreg, @bstk %lstk
    //     i->to =(i->cls) load %loc

    const loc = newtmp("abi", Kl, f);
    emit(.load, i.cls, i.to, loc, R);
    const b0 = split(f, b);
    b0.jmp = b.jmp;
    b0.s1 = b.s1;
    b0.s2 = b.s2;
    if (b.s1 != null)
        chpred(b.s1.?, b, b0);
    if (b.s2 != null and b.s2 != b.s1)
        chpred(b.s2.?, b, b0);

    const lreg = newtmp("abi", Kl, f);
    const nr = newtmp("abi", Kl, f);
    var r0 = newtmp("abi", Kw, f);
    var r1 = newtmp("abi", Kl, f);
    emit(.storew, Kw, R, r0, r1);
    emit(.add, Kl, r1, ap, if (isint) CON_Z else c4);
    emit(.add, Kw, r0, nr, if (isint) c8 else c16);
    r0 = newtmp("abi", Kl, f);
    r1 = newtmp("abi", Kl, f);
    emit(.add, Kl, lreg, r1, nr);
    emit(.load, Kl, r1, r0, R);
    emit(.add, Kl, r0, ap, c16);
    const breg = split(f, b);
    breg.jmp.type = Jjmp;
    breg.s1 = b0;

    const lstk = newtmp("abi", Kl, f);
    r0 = newtmp("abi", Kl, f);
    r1 = newtmp("abi", Kl, f);
    emit(.storel, Kw, R, r1, r0);
    emit(.add, Kl, r1, lstk, c8);
    emit(.load, Kl, lstk, r0, R);
    emit(.add, Kl, r0, ap, c8);
    const bstk = split(f, b);
    bstk.jmp.type = Jjmp;
    bstk.s1 = b0;

    const p = pnew(Phi);
    p.* = std.mem.zeroes(Phi);
    p.cls = Kl;
    p.to = loc;
    p.narg = 2;
    p.blk = vnewT(*Blk, 2, PFn);
    p.arg = vnewT(Ref, 2, PFn);
    p.blk[0] = bstk;
    p.blk[1] = breg;
    p.arg[0] = lstk;
    p.arg[1] = lreg;
    b0.phi = p;
    r0 = newtmp("abi", Kl, f);
    r1 = newtmp("abi", Kw, f);
    b.jmp.type = Jjnz;
    b.jmp.arg = r1;
    b.s1 = breg;
    b.s2 = bstk;
    const c = getcon(if (isint) 48 else 176, f);
    emit(Opc.cmpw_first.offset(Ciult), Kw, r1, nr, c);
    emit(.loadsw, Kl, nr, r0, R);
    emit(.add, Kl, r0, ap, if (isint) CON_Z else c4);
}

fn selvastart(f: *Fn, fa: i32, ap: Ref) void {
    const gp = ((fa >> 4) & 15) * 8;
    const fp = 48 + ((fa >> 8) & 15) * 16;
    const sp = fa >> 12;
    var r0 = newtmp("abi", Kl, f);
    var r1 = newtmp("abi", Kl, f);
    emit(.storel, Kw, R, r1, r0);
    emit(.add, Kl, r1, TMP(RBP), getcon(-176, f));
    emit(.add, Kl, r0, ap, getcon(16, f));
    r0 = newtmp("abi", Kl, f);
    r1 = newtmp("abi", Kl, f);
    emit(.storel, Kw, R, r1, r0);
    emit(.add, Kl, r1, TMP(RBP), getcon(sp, f));
    emit(.add, Kl, r0, ap, getcon(8, f));
    r0 = newtmp("abi", Kl, f);
    emit(.storew, Kw, R, getcon(fp, f), r0);
    emit(.add, Kl, r0, ap, getcon(4, f));
    emit(.storew, Kw, R, getcon(gp, f), ap);
}

pub fn amd64_sysv_abi(f: *Fn) void {
    var b_it = f.start;
    while (b_it) |b| : (b_it = b.link)
        b.visit = 0;

    // lower parameters
    const start = f.start.?;
    var np: uint = 0;
    while (np < start.nins and ispar(start.ins[np].op))
        np += 1;
    const fa = selpar(f, start.ins[0..np]);
    const n0: uint = @intCast(all.insbTail());
    const n1: uint = start.nins - np;
    vgrow(&start.ins, n0 + n1);
    _ = icpy(start.ins + n0, start.ins + np, n1);
    _ = icpy(start.ins, all.curi, n0);
    start.nins = n0 + n1;

    // lower calls, returns, and vararg instructions
    var ral: ?*RAlloc = null;
    var b = start;
    while (true) {
        b = b.link orelse start; // do the start block last
        if (b.visit == 0) {
            all.curi = all.insbEnd();
            selret(b, f);
            var n = b.nins;
            while (n != 0) {
                n -= 1;
                const i = &b.ins[n];
                switch (i.op) {
                    else => emiti(i.*),
                    .call => {
                        var n0_ = n;
                        while (n0_ > 0 and isarg(b.ins[n0_ - 1].op))
                            n0_ -= 1;
                        selcall(f, b.ins[n0_..n], i, &ral);
                        n = n0_;
                    },
                    .vastart => selvastart(f, fa, i.arg[0]),
                    .vaarg => selvaarg(f, b, i),
                    .arg, .argc => die("unreachable", .{}),
                }
            }
            if (b == start) {
                while (ral) |l| : (ral = l.link)
                    emiti(l.i);
            }
            idup(b, all.curi, (all.insbTail()));
        }
        if (b == start) break;
    }

    if (all.debug['A'] != 0) {
        dprint("\n> After ABI lowering:\n", .{});
        printfn(f, all.dbg) catch {};
    }
}
