//! One-to-one translation of amd64/sysv.c
const std = @import("std");
const assert = std.debug.assert;
// -- imports --
const all = @import("../all.zig");
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
const Oadd = all.ops.Oadd;
const Oalloc = all.Oalloc;
const Oarg = all.ops.Oarg;
const Oargc = all.ops.Oargc;
const Oarge = all.ops.Oarge;
const Oargv = all.ops.Oargv;
const Oblit0 = all.ops.Oblit0;
const Oblit1 = all.ops.Oblit1;
const Ocall = all.ops.Ocall;
const Ocmpw = all.Ocmpw;
const Ocopy = all.ops.Ocopy;
const Oload = all.ops.Oload;
const Oloadsw = all.ops.Oloadsw;
const Opar = all.ops.Opar;
const Oparc = all.ops.Oparc;
const Opare = all.ops.Opare;
const Osalloc = all.ops.Osalloc;
const Ostorel = all.ops.Ostorel;
const Ostorew = all.ops.Ostorew;
const Ovaarg = all.ops.Ovaarg;
const Ovastart = all.ops.Ovastart;
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
const printfn = all.printfn;
const ptrdiff = all.ptrdiff;
const req = all.req;
const rtype = all.rtype;
const strf = all.strf;
const uint = all.uint;
const vgrow = all.vgrow;
const vnewT = all.vnewT;
// -- end imports --

const AClass = extern struct {
    type: [*c]Typ,
    inmem: i32,
    @"align": i32,
    size: uint,
    cls: [2]i32,
    ref: [2]Ref,
};

const RAlloc = extern struct {
    i: Ins,
    link: [*c]RAlloc,
};

fn classify(a: [*c]AClass, t: *Typ, s_: uint) void {
    var s = s_;
    const s1 = s_;
    var n: uint = 0;
    while (n < t.nunion) : ({
        n += 1;
        s = s1;
    }) {
        var f: [*c]Field = &t.fields[n];
        while (f.*.type != FEnd) : (f += 1) {
            assert(s <= 16);
            const cls = &a.*.cls[s / 8];
            switch (f.*.type) {
                FEnd => die("unreachable", .{}),
                FPad => {
                    // don't change anything
                    s += f.*.len;
                },
                Fs, Fd => {
                    if (cls.* == Kx)
                        cls.* = Kd;
                    s += f.*.len;
                },
                Fb, Fh, Fw, Fl => {
                    cls.* = Kl;
                    s += f.*.len;
                },
                FTyp => {
                    classify(a, &all.typ[f.*.len], s);
                    s += @intCast(all.typ[f.*.len].size);
                },
                else => {},
            }
        }
    }
}

fn typclass(a: [*c]AClass, t: *Typ) void {
    var sz: uint = @intCast(t.size);
    var al: uint = @as(uint, 1) << @intCast(t.@"align");

    // the ABI requires sizes to be rounded
    // up to the nearest multiple of 8, moreover
    // it makes it easy load and store structures
    // in registers
    if (al < 8)
        al = 8;
    sz = (sz + al - 1) & (0 -% al);

    a.*.type = t;
    a.*.size = sz;
    a.*.@"align" = t.@"align";

    if (t.isdark != 0 or sz > 16 or sz == 0) {
        // large or unaligned structures are
        // required to be passed in memory
        a.*.inmem = 1;
        return;
    }

    a.*.cls[0] = Kx;
    a.*.cls[1] = Kx;
    a.*.inmem = 0;
    classify(a, t, 0);
}

fn retr(reg: *[2]Ref, aret: [*c]AClass) i32 {
    const retreg = [2][2]i32{ .{ RAX, RDX }, .{ XMM0, XMM0 + 1 } };
    var nr = [2]usize{ 0, 0 };
    var ca: i32 = 0;
    var n: usize = 0;
    while (n * 8 < aret.*.size) : (n += 1) {
        const k: usize = @intCast(KBASE(aret.*.cls[n]));
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

    const j: i32 = @intCast(b.jmp.type);

    if (!isret(j) or j == Jret0)
        return;

    const r0 = b.jmp.arg;
    b.jmp.type = Jret0;

    if (j == Jretc) {
        typclass(&aret, &all.typ[@intCast(f.retty)]);
        if (aret.inmem != 0) {
            assert(rtype(f.retr) == RTmp);
            emit(Ocopy, Kl, TMP(RAX), f.retr, R);
            emit(Oblit1, 0, R, INT(aret.type.*.size), R);
            emit(Oblit0, 0, R, r0, f.retr);
            ca = 1;
        } else {
            ca = retr(&reg, &aret);
            if (aret.size > 8) {
                const r = newtmp("abi", Kl, f);
                emit(Oload, Kl, reg[1], r, R);
                emit(Oadd, Kl, r, r0, getcon(8, f));
            }
            emit(Oload, Kl, reg[0], r0, R);
        }
    } else {
        const k = j - Jretw;
        if (KBASE(k) == 0) {
            emit(Ocopy, k, TMP(RAX), r0, R);
            ca = 1;
        } else {
            emit(Ocopy, k, TMP(XMM0), r0, R);
            ca = 1 << 2;
        }
    }

    b.jmp.arg = CALL(ca);
}

fn argsclass(i_0: [*c]Ins, i_1: [*c]Ins, ac: [*c]AClass, op: i32, aret: [*c]AClass, env: *Ref) i32 {
    var nint: i32 = undefined;
    if (aret != null and aret.*.inmem != 0)
        nint = 5 // hidden argument
    else
        nint = 6;
    var nsse: i32 = 8;
    var varc: i32 = 0;
    var envc: i32 = 0;
    var i = i_0;
    var a = ac;
    while (i < i_1) : ({
        i += 1;
        a += 1;
    }) {
        switch (@as(i32, @intCast(i.*.op)) - op + Oarg) {
            Oarg => {
                const pn: *i32 = if (KBASE(i.*.cls) == 0) &nint else &nsse;
                if (pn.* > 0) {
                    pn.* -= 1;
                    a.*.inmem = 0;
                } else a.*.inmem = 2;
                a.*.@"align" = 3;
                a.*.size = 8;
                a.*.cls[0] = @intCast(i.*.cls);
            },
            Oargc => {
                const n0 = i.*.arg[0].val;
                typclass(a, &all.typ[n0]);
                if (a.*.inmem != 0)
                    continue;
                var ni: i32 = 0;
                var ns: i32 = 0;
                var n: usize = 0;
                while (n * 8 < a.*.size) : (n += 1) {
                    if (KBASE(a.*.cls[n]) == 0)
                        ni += 1
                    else
                        ns += 1;
                }
                if (nint >= ni and nsse >= ns) {
                    nint -= ni;
                    nsse -= ns;
                } else a.*.inmem = 1;
            },
            Oarge => {
                envc = 1;
                if (op == Opar)
                    env.* = i.*.to
                else
                    env.* = i.*.arg[0];
            },
            Oargv => varc = 1,
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

pub fn amd64_sysv_retregs(r: Ref, p: [*c]i32) bits {
    assert(rtype(r) == RCall);
    var b: bits = 0;
    const ni: i32 = @intCast(r.val & 3);
    const nf: i32 = @intCast((r.val >> 2) & 3);
    if (ni >= 1)
        b |= BIT(RAX);
    if (ni >= 2)
        b |= BIT(RDX);
    if (nf >= 1)
        b |= BIT(XMM0);
    if (nf >= 2)
        b |= BIT(XMM1);
    if (p != null) {
        p[0] = ni;
        p[1] = nf;
    }
    return b;
}

pub fn amd64_sysv_argregs(r: Ref, p: [*c]i32) bits {
    assert(rtype(r) == RCall);
    var b: bits = 0;
    const ni: i32 = @intCast((r.val >> 4) & 15);
    const nf: i32 = @intCast((r.val >> 8) & 15);
    const ra: i32 = @intCast((r.val >> 12) & 1);
    var j: i32 = 0;
    while (j < ni) : (j += 1)
        b |= BIT(amd64_sysv_rsave[@intCast(j)]);
    j = 0;
    while (j < nf) : (j += 1)
        b |= BIT(XMM0 + j);
    if (p != null) {
        p[0] = ni + ra;
        p[1] = nf;
    }
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

fn selcall(f: *Fn, i_0: [*c]Ins, i_1: [*c]Ins, rap: *[*c]RAlloc) void {
    var aret: AClass = undefined;
    var reg: [2]Ref = undefined;
    var ca: i32 = undefined;
    var r: Ref = undefined;
    var r1: Ref = undefined;
    var ra: [*c]RAlloc = undefined;

    var env = R;
    const nac: usize = @intCast(ptrdiff(i_1, i_0));
    const ac: [*c]AClass = palloc(AClass, nac);

    if (!req(i_1.*.arg[1], R)) {
        assert(rtype(i_1.*.arg[1]) == RType);
        typclass(&aret, &all.typ[i_1.*.arg[1].val]);
        ca = argsclass(i_0, i_1, ac, Oarg, &aret, &env);
    } else ca = argsclass(i_0, i_1, ac, Oarg, null, &env);

    var stk: uint = 0;
    var a = ac + nac;
    while (a > ac) {
        a -= 1;
        if (a.*.inmem != 0) {
            if (a.*.@"align" > 4)
                err("sysv abi requires alignments of 16 or less", .{});
            stk += a.*.size;
            if (a.*.@"align" == 4)
                stk += stk & 15;
        }
    }
    stk += stk & 15;
    if (stk != 0) {
        r = getcon(-@as(i64, stk), f);
        emit(Osalloc, Kl, R, r, R);
    }

    if (!req(i_1.*.arg[1], R)) {
        if (aret.inmem != 0) {
            // get the return location from eax
            // it saves one callee-save reg
            r1 = newtmp("abi", Kl, f);
            emit(Ocopy, Kl, i_1.*.to, TMP(RAX), R);
            ca += 1;
        } else {
            // todo, may read out of bounds.
            // gcc did this up until 5.2, but
            // this should still be fixed.
            if (aret.size > 8) {
                r = newtmp("abi", Kl, f);
                aret.ref[1] = newtmp("abi", aret.cls[1], f);
                emit(Ostorel, 0, R, aret.ref[1], r);
                emit(Oadd, Kl, r, i_1.*.to, getcon(8, f));
            }
            aret.ref[0] = newtmp("abi", aret.cls[0], f);
            emit(Ostorel, 0, R, aret.ref[0], i_1.*.to);
            ca += retr(&reg, &aret);
            if (aret.size > 8)
                emit(Ocopy, aret.cls[1], aret.ref[1], reg[1], R);
            emit(Ocopy, aret.cls[0], aret.ref[0], reg[0], R);
            r1 = i_1.*.to;
        }
        // allocate return pad
        ra = palloc(RAlloc, 1);
        // specific to NAlign == 3
        const al: i32 = if (aret.@"align" >= 2) aret.@"align" - 2 else 0;
        ra.*.i = INS(Oalloc + al, Kl, r1, getcon(aret.size, f), R);
        ra.*.link = rap.*;
        rap.* = ra;
    } else {
        ra = null;
        if (KBASE(i_1.*.cls) == 0) {
            emit(Ocopy, i_1.*.cls, i_1.*.to, TMP(RAX), R);
            ca += 1;
        } else {
            emit(Ocopy, i_1.*.cls, i_1.*.to, TMP(XMM0), R);
            ca += 1 << 2;
        }
    }

    emit(Ocall, i_1.*.cls, R, i_1.*.arg[0], CALL(ca));

    if (!req(R, env))
        emit(Ocopy, Kl, TMP(RAX), env, R)
    else if (((ca >> 12) & 1) != 0) // vararg call
        emit(Ocopy, Kw, TMP(RAX), getcon((ca >> 8) & 15, f), R);

    var ni: i32 = 0;
    var ns: i32 = 0;
    if (ra != null and aret.inmem != 0)
        emit(Ocopy, Kl, rarg(Kl, &ni, &ns), ra.*.i.to, R); // pass hidden argument

    var i = i_0;
    a = ac;
    while (i < i_1) : ({
        i += 1;
        a += 1;
    }) {
        if (i.*.op >= Oarge or a.*.inmem != 0)
            continue;
        r1 = rarg(a.*.cls[0], &ni, &ns);
        if (i.*.op == Oargc) {
            if (a.*.size > 8) {
                const r2 = rarg(a.*.cls[1], &ni, &ns);
                r = newtmp("abi", Kl, f);
                emit(Oload, a.*.cls[1], r2, r, R);
                emit(Oadd, Kl, r, i.*.arg[1], getcon(8, f));
            }
            emit(Oload, a.*.cls[0], r1, i.*.arg[1], R);
        } else emit(Ocopy, i.*.cls, r1, i.*.arg[0], R);
    }

    if (stk == 0)
        return;

    r = newtmp("abi", Kl, f);
    i = i_0;
    a = ac;
    var off: uint = 0;
    while (i < i_1) : ({
        i += 1;
        a += 1;
    }) {
        if (i.*.op >= Oarge or a.*.inmem == 0)
            continue;
        r1 = newtmp("abi", Kl, f);
        if (i.*.op == Oargc) {
            if (a.*.@"align" == 4)
                off += off & 15;
            emit(Oblit1, 0, R, INT(a.*.type.*.size), R);
            emit(Oblit0, 0, R, i.*.arg[1], r1);
        } else emit(Ostorel, 0, R, i.*.arg[0], r1);
        emit(Oadd, Kl, r1, r, getcon(off, f));
        off += a.*.size;
    }
    emit(Osalloc, Kl, r, getcon(stk, f), R);
}

fn selpar(f: *Fn, i_0: [*c]Ins, i_1: [*c]Ins) i32 {
    var aret: AClass = undefined;
    var fa: i32 = undefined;
    var r: Ref = undefined;

    var env = R;
    const nac: usize = @intCast(ptrdiff(i_1, i_0));
    const ac: [*c]AClass = palloc(AClass, nac);
    all.curi = all.insbEnd();
    var ni: i32 = 0;
    var ns: i32 = 0;

    if (f.retty >= 0) {
        typclass(&aret, &all.typ[@intCast(f.retty)]);
        fa = argsclass(i_0, i_1, ac, Opar, &aret, &env);
    } else fa = argsclass(i_0, i_1, ac, Opar, null, &env);
    f.reg = amd64_sysv_argregs(CALL(fa), null);

    var i = i_0;
    var a = ac;
    while (i < i_1) : ({
        i += 1;
        a += 1;
    }) {
        if (i.*.op != Oparc or a.*.inmem != 0)
            continue;
        if (a.*.size > 8) {
            r = newtmp("abi", Kl, f);
            a.*.ref[1] = newtmp("abi", Kl, f);
            emit(Ostorel, 0, R, a.*.ref[1], r);
            emit(Oadd, Kl, r, i.*.to, getcon(8, f));
        }
        a.*.ref[0] = newtmp("abi", Kl, f);
        emit(Ostorel, 0, R, a.*.ref[0], i.*.to);
        // specific to NAlign == 3
        const al: i32 = if (a.*.@"align" >= 2) a.*.@"align" - 2 else 0;
        emit(Oalloc + al, Kl, i.*.to, getcon(a.*.size, f), R);
    }

    if (f.retty >= 0 and aret.inmem != 0) {
        r = newtmp("abi", Kl, f);
        emit(Ocopy, Kl, r, rarg(Kl, &ni, &ns), R);
        f.retr = r;
    }

    i = i_0;
    a = ac;
    var s: i32 = 4;
    while (i < i_1) : ({
        i += 1;
        a += 1;
    }) {
        switch (a.*.inmem) {
            1 => {
                if (a.*.@"align" > 4)
                    err("sysv abi requires alignments of 16 or less", .{});
                if (a.*.@"align" == 4)
                    s = (s + 3) & -4;
                f.tmp[i.*.to.val].slot = -s;
                s += @intCast(a.*.size / 4);
                continue;
            },
            2 => {
                emit(Oload, i.*.cls, i.*.to, SLOT(-s), R);
                s += 2;
                continue;
            },
            else => {},
        }
        if (i.*.op == Opare)
            continue;
        r = rarg(a.*.cls[0], &ni, &ns);
        if (i.*.op == Oparc) {
            emit(Ocopy, a.*.cls[0], a.*.ref[0], r, R);
            if (a.*.size > 8) {
                r = rarg(a.*.cls[1], &ni, &ns);
                emit(Ocopy, a.*.cls[1], a.*.ref[1], r, R);
            }
        } else emit(Ocopy, i.*.cls, i.*.to, r, R);
    }

    if (!req(R, env))
        emit(Ocopy, Kl, env, TMP(RAX), R);

    return fa | (s * 4) << 12;
}

fn split(f: *Fn, b: *Blk) [*c]Blk {
    f.nblk += 1;
    const bn = newblk();
    idup(bn, all.curi, @intCast(ptrdiff(all.insbEnd(), all.curi)));
    all.curi = all.insbEnd();
    b.visit += 1;
    bn.*.visit = b.visit;
    bn.*.name = strf(PFn, "{s}.{d}", .{ cs(b.name), b.visit });
    bn.*.loop = b.loop;
    bn.*.link = b.link;
    b.link = bn;
    return bn;
}

fn chpred(b: *Blk, bp: [*c]Blk, bp1: *Blk) void {
    var p_it: ?*Phi = b.phi;
    while (p_it) |p| : (p_it = p.link) {
        var a: uint = 0;
        while (p.blk[a] != bp) : (a += 1)
            assert(a + 1 < p.narg);
        p.blk[a] = bp1;
    }
}

fn selvaarg(f: *Fn, b: *Blk, i: [*c]Ins) void {
    const c4 = getcon(4, f);
    const c8 = getcon(8, f);
    const c16 = getcon(16, f);
    const ap = i.*.arg[0];
    const isint = KBASE(i.*.cls) == 0;

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
    emit(Oload, i.*.cls, i.*.to, loc, R);
    const b0 = split(f, b);
    b0.*.jmp = b.jmp;
    b0.*.s1 = b.s1;
    b0.*.s2 = b.s2;
    if (b.s1 != null)
        chpred(b.s1, b, b0);
    if (b.s2 != null and b.s2 != b.s1)
        chpred(b.s2, b, b0);

    const lreg = newtmp("abi", Kl, f);
    const nr = newtmp("abi", Kl, f);
    var r0 = newtmp("abi", Kw, f);
    var r1 = newtmp("abi", Kl, f);
    emit(Ostorew, Kw, R, r0, r1);
    emit(Oadd, Kl, r1, ap, if (isint) CON_Z else c4);
    emit(Oadd, Kw, r0, nr, if (isint) c8 else c16);
    r0 = newtmp("abi", Kl, f);
    r1 = newtmp("abi", Kl, f);
    emit(Oadd, Kl, lreg, r1, nr);
    emit(Oload, Kl, r1, r0, R);
    emit(Oadd, Kl, r0, ap, c16);
    const breg = split(f, b);
    breg.*.jmp.type = Jjmp;
    breg.*.s1 = b0;

    const lstk = newtmp("abi", Kl, f);
    r0 = newtmp("abi", Kl, f);
    r1 = newtmp("abi", Kl, f);
    emit(Ostorel, Kw, R, r1, r0);
    emit(Oadd, Kl, r1, lstk, c8);
    emit(Oload, Kl, lstk, r0, R);
    emit(Oadd, Kl, r0, ap, c8);
    const bstk = split(f, b);
    bstk.*.jmp.type = Jjmp;
    bstk.*.s1 = b0;

    b0.*.phi = palloc(Phi, 1);
    b0.*.phi.* = std.mem.zeroes(Phi);
    b0.*.phi.*.cls = Kl;
    b0.*.phi.*.to = loc;
    b0.*.phi.*.narg = 2;
    b0.*.phi.*.blk = vnewT([*c]Blk, 2, PFn);
    b0.*.phi.*.arg = vnewT(Ref, 2, PFn);
    b0.*.phi.*.blk[0] = bstk;
    b0.*.phi.*.blk[1] = breg;
    b0.*.phi.*.arg[0] = lstk;
    b0.*.phi.*.arg[1] = lreg;
    r0 = newtmp("abi", Kl, f);
    r1 = newtmp("abi", Kw, f);
    b.jmp.type = Jjnz;
    b.jmp.arg = r1;
    b.s1 = breg;
    b.s2 = bstk;
    const c = getcon(if (isint) 48 else 176, f);
    emit(Ocmpw + Ciult, Kw, r1, nr, c);
    emit(Oloadsw, Kl, nr, r0, R);
    emit(Oadd, Kl, r0, ap, if (isint) CON_Z else c4);
}

fn selvastart(f: *Fn, fa: i32, ap: Ref) void {
    const gp = ((fa >> 4) & 15) * 8;
    const fp = 48 + ((fa >> 8) & 15) * 16;
    const sp = fa >> 12;
    var r0 = newtmp("abi", Kl, f);
    var r1 = newtmp("abi", Kl, f);
    emit(Ostorel, Kw, R, r1, r0);
    emit(Oadd, Kl, r1, TMP(RBP), getcon(-176, f));
    emit(Oadd, Kl, r0, ap, getcon(16, f));
    r0 = newtmp("abi", Kl, f);
    r1 = newtmp("abi", Kl, f);
    emit(Ostorel, Kw, R, r1, r0);
    emit(Oadd, Kl, r1, TMP(RBP), getcon(sp, f));
    emit(Oadd, Kl, r0, ap, getcon(8, f));
    r0 = newtmp("abi", Kl, f);
    emit(Ostorew, Kw, R, getcon(fp, f), r0);
    emit(Oadd, Kl, r0, ap, getcon(4, f));
    emit(Ostorew, Kw, R, getcon(gp, f), ap);
}

pub fn amd64_sysv_abi(f: *Fn) void {
    var b = f.start;
    while (b != null) : (b = b.*.link)
        b.*.visit = 0;

    // lower parameters
    b = f.start;
    var i = b.*.ins;
    while (i < b.*.ins + b.*.nins) : (i += 1) {
        if (!ispar(i.*.op))
            break;
    }
    const fa = selpar(f, b.*.ins, i);
    const n0: uint = @intCast(ptrdiff(all.insbEnd(), all.curi));
    const ioff: uint = @intCast(ptrdiff(i, b.*.ins));
    const n1: uint = b.*.nins - ioff;
    vgrow(&b.*.ins, n0 + n1);
    _ = icpy(b.*.ins + n0, b.*.ins + ioff, n1);
    _ = icpy(b.*.ins, all.curi, n0);
    b.*.nins = n0 + n1;

    // lower calls, returns, and vararg instructions
    var ral: [*c]RAlloc = null;
    b = f.start;
    while (true) {
        b = b.*.link;
        if (b == null)
            b = f.start; // do it last
        if (b.*.visit == 0) {
            all.curi = all.insbEnd();
            selret(b, f);
            i = b.*.ins + b.*.nins;
            while (i != b.*.ins) {
                i -= 1;
                switch (i.*.op) {
                    else => emiti(i.*),
                    Ocall => {
                        var i_0 = i;
                        while (i_0 > b.*.ins) : (i_0 -= 1) {
                            if (!isarg((i_0 - 1).*.op))
                                break;
                        }
                        selcall(f, i_0, i, &ral);
                        i = i_0;
                    },
                    Ovastart => selvastart(f, fa, i.*.arg[0]),
                    Ovaarg => selvaarg(f, b, i),
                    Oarg, Oargc => die("unreachable", .{}),
                }
            }
            if (b == f.start) {
                while (ral != null) : (ral = ral.*.link)
                    emiti(ral.*.i);
            }
            idup(b, all.curi, @intCast(ptrdiff(all.insbEnd(), all.curi)));
        }
        if (b == f.start) break;
    }

    if (all.debug['A'] != 0) {
        dprint("\n> After ABI lowering:\n", .{});
        printfn(f, all.dbg) catch {};
    }
}
