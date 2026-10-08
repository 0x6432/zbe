//! One-to-one translation of rv64/abi.c
//! the risc-v lp64d abi
const std = @import("std");
const assert = std.debug.assert;
// -- imports --
const all = @import("../all.zig");
const tgt = @import("all.zig");
const A0 = tgt.A0;
const A1 = tgt.A1;
const A2 = tgt.A2;
const A3 = tgt.A3;
const A4 = tgt.A4;
const A5 = tgt.A5;
const A6 = tgt.A6;
const A7 = tgt.A7;
const BIT = all.BIT;
const Blk = all.Blk;
const CALL = all.CALL;
const FA0 = tgt.FA0;
const FA1 = tgt.FA1;
const FA2 = tgt.FA2;
const FA3 = tgt.FA3;
const FA4 = tgt.FA4;
const FA5 = tgt.FA5;
const FA6 = tgt.FA6;
const FA7 = tgt.FA7;
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
const Jret0 = all.Jret0;
const Jretc = all.Jretc;
const Jretw = all.Jretw;
const KBASE = all.KBASE;
const KWIDE = all.KWIDE;
const Kd = all.Kd;
const Kl = all.Kl;
const Ks = all.Ks;
const Kw = all.Kw;
const Oadd = all.ops.Oadd;
const Oaddr = all.ops.Oaddr;
const Oalloc = all.Oalloc;
const Oarg = all.ops.Oarg;
const Oargc = all.ops.Oargc;
const Oarge = all.ops.Oarge;
const Oargv = all.ops.Oargv;
const Oblit0 = all.ops.Oblit0;
const Oblit1 = all.ops.Oblit1;
const Ocall = all.ops.Ocall;
const Ocast = all.ops.Ocast;
const Ocopy = all.ops.Ocopy;
const Oextsw = all.ops.Oextsw;
const Oload = all.ops.Oload;
const Opar = all.ops.Opar;
const Oparc = all.ops.Oparc;
const Opare = all.ops.Opare;
const Osalloc = all.ops.Osalloc;
const Ostored = all.ops.Ostored;
const Ostorel = all.ops.Ostorel;
const Ostores = all.ops.Ostores;
const Ostorew = all.ops.Ostorew;
const Ovaarg = all.ops.Ovaarg;
const Ovastart = all.ops.Ovastart;
const R = all.R;
const RCall = all.RCall;
const RTmp = all.RTmp;
const Ref = all.Ref;
const SLOT = all.SLOT;
const T5 = tgt.T5;
const TMP = all.TMP;
const Typ = all.Typ;
const bits = all.bits;
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
const newtmp = all.newtmp;
const palloc = all.palloc;
const pnew = all.pnew;
const printfn = all.printfn;
const ptrdiff = all.ptrdiff;
const req = all.req;
const rtype = all.rtype;
const uint = all.uint;
const vgrow = all.vgrow;
// -- end imports --

const Cptr = 1; // replaced by a pointer
const Cstk1 = 2; // pass first XLEN on the stack
const Cstk2 = 4; // pass second XLEN on the stack
const Cstk = Cstk1 | Cstk2;
const Cfpint = 8; // float passed like integer

const Class = struct {
    class: i8,
    type: ?*Typ,
    reg: [2]i32,
    cls: [2]i32,
    off: [2]i32,
    ngp: i8, // only valid after typclass()
    nfp: i8, // ditto
    nreg: i8,
};

const Insl = struct {
    i: Ins,
    link: ?*Insl,
};

const Params = struct {
    ngp: i32,
    nfp: i32,
    stk: i32, // stack offset for varargs
};

var gpreg = [10]i32{ A0, A1, A2, A3, A4, A5, A6, A7, 0, 0 };
var fpreg = [10]i32{ FA0, FA1, FA2, FA3, FA4, FA5, FA6, FA7, 0, 0 };

// layout of call's second argument (RCall)
//
//  29   12    8    4  2  0
//  |0.00|x|xxxx|xxxx|xx|xx|                  range
//        |   |    |  |  ` gp regs returned (0..2)
//        |   |    |  ` fp regs returned    (0..2)
//        |   |    ` gp regs passed         (0..8)
//        |    ` fp regs passed             (0..8)
//        ` env pointer passed in t5        (0..1)

pub fn rv64_retregs(r: Ref, p: ?*[2]i32) bits {
    assert(rtype(r) == RCall);
    var ngp: i32 = @intCast(r.val & 3);
    var nfp: i32 = @intCast((r.val >> 2) & 3);
    if (p) |q|
        q.* = .{ ngp, nfp };
    var b: bits = 0;
    while (ngp > 0) {
        ngp -= 1;
        b |= BIT(A0 + ngp);
    }
    while (nfp > 0) {
        nfp -= 1;
        b |= BIT(FA0 + nfp);
    }
    return b;
}

pub fn rv64_argregs(r: Ref, p: ?*[2]i32) bits {
    assert(rtype(r) == RCall);
    var ngp: i32 = @intCast((r.val >> 4) & 15);
    var nfp: i32 = @intCast((r.val >> 8) & 15);
    const t5: i32 = @intCast((r.val >> 12) & 1);
    if (p) |q|
        q.* = .{ ngp + t5, nfp };
    var b: bits = 0;
    while (ngp > 0) {
        ngp -= 1;
        b |= BIT(A0 + ngp);
    }
    while (nfp > 0) {
        nfp -= 1;
        b |= BIT(FA0 + nfp);
    }
    return b | (@as(bits, @intCast(t5)) << T5);
}

fn fpstruct(t: *Typ, off_: i32, c: *Class) i32 {
    var off = off_;
    if (t.isunion != 0)
        return -1;

    for (&t.fields[0]) |*f| {
        if (f.type == FEnd) break;
        if (f.type == FPad) {
            off += @intCast(f.len);
        } else if (f.type == FTyp) {
            if (fpstruct(&all.typ[f.len], off, c) == -1)
                return -1;
        } else {
            const n: usize = @intCast(c.nfp + c.ngp);
            if (n == 2)
                return -1;
            switch (f.type) {
                else => die("unreachable", .{}),
                Fb, Fh, Fw => {
                    c.cls[n] = Kw;
                    c.ngp += 1;
                },
                Fl => {
                    c.cls[n] = Kl;
                    c.ngp += 1;
                },
                Fs => {
                    c.cls[n] = Ks;
                    c.nfp += 1;
                },
                Fd => {
                    c.cls[n] = Kd;
                    c.nfp += 1;
                },
            }
            c.off[n] = off;
            off += @intCast(f.len);
        }
    }

    return c.nfp;
}

fn typclass(c: *Class, t: *Typ, fpabi: bool, gp: []const i32, fp: []const i32) void {
    c.type = t;
    c.class = 0;
    c.ngp = 0;
    c.nfp = 0;

    if (t.@"align" > 4)
        err("alignments larger than 16 are not supported", .{});

    if (t.isdark != 0 or t.size > 16 or t.size == 0) {
        // large structs are replaced by a
        // pointer to some caller-allocated
        // memory
        c.class |= Cptr;
        c.cls[0] = Kl;
        c.off[0] = 0;
        c.ngp = 1;
    } else if (!fpabi or fpstruct(t, 0, c) <= 0) {
        var n: uint = 0;
        while (8 * @as(u64, n) < t.size) : (n += 1) {
            c.cls[n] = Kl;
            c.off[n] = @intCast(8 * n);
        }
        c.nfp = 0;
        c.ngp = @intCast(n);
    }

    c.nreg = c.nfp + c.ngp;
    var ngp: usize = 0;
    var nfp: usize = 0;
    var i: usize = 0;
    while (i < c.nreg) : (i += 1) {
        if (KBASE(c.cls[i]) == 0) {
            c.reg[i] = gp[ngp];
            ngp += 1;
        } else {
            c.reg[i] = fp[nfp];
            nfp += 1;
        }
    }
}

const st = blk: {
    var s: [4]i32 = undefined;
    s[Kw] = Ostorew;
    s[Kl] = Ostorel;
    s[Ks] = Ostores;
    s[Kd] = Ostored;
    break :blk s;
};

fn sttmps(tmp: []Ref, ntmp: i32, c: *Class, mem: Ref, f: *Fn) void {
    assert(ntmp > 0);
    assert(ntmp <= 2);
    var i: usize = 0;
    while (i < ntmp) : (i += 1) {
        tmp[i] = newtmp("abi", c.cls[i], f);
        const r = newtmp("abi", Kl, f);
        emit(st[@intCast(c.cls[i])], 0, R, tmp[i], r);
        emit(Oadd, Kl, r, mem, getcon(c.off[i], f));
    }
}

fn ldregs(c: *Class, mem: Ref, f: *Fn) void {
    var i: usize = 0;
    while (i < c.nreg) : (i += 1) {
        const r = newtmp("abi", Kl, f);
        emit(Oload, c.cls[i], TMP(c.reg[i]), r, R);
        emit(Oadd, Kl, r, mem, getcon(c.off[i], f));
    }
}

fn selret(b: *Blk, f: *Fn) void {
    var cr: Class = undefined;
    var cty: i32 = undefined;

    const j: i32 = @intCast(b.jmp.type);

    if (!isret(j) or j == Jret0)
        return;

    const r = b.jmp.arg;
    b.jmp.type = Jret0;

    if (j == Jretc) {
        typclass(&cr, &all.typ[@intCast(f.retty)], true, &gpreg, &fpreg);
        if ((cr.class & Cptr) != 0) {
            assert(rtype(f.retr) == RTmp);
            emit(Oblit1, 0, R, INT(cr.type.?.size), R);
            emit(Oblit0, 0, R, r, f.retr);
            cty = 0;
        } else {
            ldregs(&cr, r, f);
            cty = (@as(i32, cr.nfp) << 2) | cr.ngp;
        }
    } else {
        const k = j - Jretw;
        if (KBASE(k) == 0) {
            emit(Ocopy, k, TMP(A0), r, R);
            cty = 1;
        } else {
            emit(Ocopy, k, TMP(FA0), r, R);
            cty = 1 << 2;
        }
    }

    b.jmp.arg = CALL(cty);
}

fn argsclass(ins: []const Ins, carg: []Class, retptr: bool) i32 {
    var gp: usize = 0; // next gpreg
    var fp: usize = 0; // next fpreg
    var ngp: i32 = 8;
    var nfp: i32 = 8;
    var vararg = false;
    var envc: i32 = 0;
    if (retptr) {
        gp += 1;
        ngp -= 1;
    }
    for (ins, carg) |*i, *c| {
        switch (i.op) {
            Opar, Oarg => {
                c.cls[0] = @intCast(i.cls);
                if (!vararg and KBASE(i.cls) == 1 and nfp > 0) {
                    nfp -= 1;
                    c.reg[0] = fpreg[fp];
                    fp += 1;
                } else if (ngp > 0) {
                    if (KBASE(i.cls) == 1)
                        c.class |= Cfpint;
                    ngp -= 1;
                    c.reg[0] = gpreg[gp];
                    gp += 1;
                } else c.class |= Cstk1;
            },
            Oargv => vararg = true,
            Oparc, Oargc => {
                const t = &all.typ[i.arg[0].val];
                typclass(c, t, true, gpreg[gp..], fpreg[fp..]);
                if (c.nfp > 0 and (c.nfp >= nfp or c.ngp >= ngp))
                    typclass(c, t, false, gpreg[gp..], fpreg[fp..]);
                assert(c.nfp <= nfp);
                if (c.ngp <= ngp) {
                    ngp -= c.ngp;
                    nfp -= c.nfp;
                    gp += @as(usize, @intCast(c.ngp));
                    fp += @as(usize, @intCast(c.nfp));
                } else if (ngp > 0) {
                    assert(c.ngp == 2);
                    assert(c.class == 0);
                    c.class |= Cstk2;
                    c.nreg = 1;
                    ngp -= 1;
                    gp += 1;
                } else {
                    c.class |= Cstk1;
                    if (c.nreg > 1)
                        c.class |= Cstk2;
                    c.nreg = 0;
                }
            },
            Opare, Oarge => {
                c.reg[0] = T5;
                c.cls[0] = Kl;
                envc = 1;
            },
            else => {},
        }
    }
    const ngpu: i32 = @intCast(gp);
    const nfpu: i32 = @intCast(fp);
    return envc << 12 | ngpu << 4 | nfpu << 8;
}

fn stkblob(r: Ref, t: *Typ, f: *Fn, ilp: *?*Insl) void {
    const il = pnew(Insl);
    var al: i32 = t.@"align" - 2; // specific to NAlign == 3
    if (al < 0)
        al = 0;
    const sz: u64 = (t.size + 7) & ~@as(u64, 7);
    il.i = INS(Oalloc + al, Kl, r, getcon(@bitCast(sz), f), R);
    il.link = ilp.*;
    ilp.* = il;
}

/// lowers the call i_1 with its arguments ins
fn selcall(f: *Fn, ins: []Ins, i_1: *Ins, ilp: *?*Insl) void {
    var cr: Class = undefined;
    var tmp: [2]Ref = undefined;
    var k: i32 = undefined;
    var r: Ref = undefined;
    var r1: Ref = undefined;
    var r2: Ref = undefined;

    const ca = palloc(Class, ins.len)[0..ins.len];
    cr.class = 0;

    if (!req(i_1.arg[1], R))
        typclass(&cr, &all.typ[i_1.arg[1].val], true, &gpreg, &fpreg);

    var cty = argsclass(ins, ca, (cr.class & Cptr) != 0);
    var stk: u64 = 0;
    for (ins, ca) |*i, *c| {
        if (i.op == Oargv)
            continue;
        if ((c.class & Cptr) != 0) {
            i.arg[0] = newtmp("abi", Kl, f);
            stkblob(i.arg[0], c.type.?, f, ilp);
            i.op = Oarg;
        }
        if ((c.class & Cstk1) != 0)
            stk += 8;
        if ((c.class & Cstk2) != 0)
            stk += 8;
    }
    stk += stk & 15;
    if (stk != 0)
        emit(Osalloc, Kl, R, getcon(-%@as(i64, @bitCast(stk)), f), R);

    if (!req(i_1.arg[1], R)) {
        stkblob(i_1.to, cr.type.?, f, ilp);
        cty |= (@as(i32, cr.nfp) << 2) | cr.ngp;
        if ((cr.class & Cptr) != 0) {
            // spill & rega expect calls to be
            // followed by copies from regs,
            // so we emit a dummy
            emit(Ocopy, Kw, R, TMP(A0), R);
        } else {
            sttmps(&tmp, cr.nreg, &cr, i_1.to, f);
            var j: usize = 0;
            while (j < cr.nreg) : (j += 1) {
                r = TMP(cr.reg[j]);
                emit(Ocopy, cr.cls[j], tmp[j], r, R);
            }
        }
    } else if (KBASE(i_1.cls) == 0) {
        emit(Ocopy, i_1.cls, i_1.to, TMP(A0), R);
        cty |= 1;
    } else {
        emit(Ocopy, i_1.cls, i_1.to, TMP(FA0), R);
        cty |= 1 << 2;
    }

    emit(Ocall, 0, R, i_1.arg[0], CALL(cty));

    if ((cr.class & Cptr) != 0)
        // struct return argument
        emit(Ocopy, Kl, TMP(A0), i_1.to, R);

    // move arguments into registers
    for (ins, ca) |*i, *c| {
        if (i.op == Oargv or (c.class & Cstk1) != 0)
            continue;
        if (i.op == Oargc) {
            ldregs(c, i.arg[1], f);
        } else if ((c.class & Cfpint) != 0) {
            k = if (KWIDE(c.cls[0]) != 0) Kl else Kw;
            r = newtmp("abi", k, f);
            emit(Ocopy, k, TMP(c.reg[0]), r, R);
            c.reg[0] = @intCast(r.val);
        } else {
            emit(Ocopy, c.cls[0], TMP(c.reg[0]), i.arg[0], R);
        }
    }

    for (ins, ca) |*i, *c| {
        if ((c.class & Cfpint) != 0) {
            k = if (KWIDE(c.cls[0]) != 0) Kl else Kw;
            emit(Ocast, k, TMP(c.reg[0]), i.arg[0], R);
        }
        if ((c.class & Cptr) != 0) {
            emit(Oblit1, 0, R, INT(c.type.?.size), R);
            emit(Oblit0, 0, R, i.arg[1], i.arg[0]);
        }
    }

    if (stk == 0)
        return;

    // populate the stack
    var off: u64 = 0;
    r = newtmp("abi", Kl, f);
    for (ins, ca) |*i, *c| {
        if (i.op == Oargv or (c.class & Cstk) == 0)
            continue;
        if (i.op == Oarg) {
            r1 = newtmp("abi", Kl, f);
            emit(Ostorew + i.cls, Kw, R, i.arg[0], r1);
            if (i.cls == Kw) {
                // TODO: we only need this sign
                // extension for l temps passed
                // as w arguments
                // (see rv64/isel.c:fixarg)
                all.curi[0].op = Ostorel;
                all.curi[0].arg[0] = newtmp("abi", Kl, f);
                emit(Oextsw, Kl, all.curi[0].arg[0], i.arg[0], R);
            }
            emit(Oadd, Kl, r1, r, getcon(@bitCast(off), f));
            off += 8;
        }
        if (i.op == Oargc) {
            if ((c.class & Cstk1) != 0) {
                r1 = newtmp("abi", Kl, f);
                r2 = newtmp("abi", Kl, f);
                emit(Ostorel, 0, R, r2, r1);
                emit(Oadd, Kl, r1, r, getcon(@bitCast(off), f));
                emit(Oload, Kl, r2, i.arg[1], R);
                off += 8;
            }
            if ((c.class & Cstk2) != 0) {
                r1 = newtmp("abi", Kl, f);
                r2 = newtmp("abi", Kl, f);
                emit(Ostorel, 0, R, r2, r1);
                emit(Oadd, Kl, r1, r, getcon(@bitCast(off), f));
                r1 = newtmp("abi", Kl, f);
                emit(Oload, Kl, r2, r1, R);
                emit(Oadd, Kl, r1, i.arg[1], getcon(8, f));
                off += 8;
            }
        }
    }
    emit(Osalloc, Kl, r, getcon(@bitCast(stk), f), R);
}

fn selpar(f: *Fn, ins: []Ins) Params {
    var cr: Class = undefined;
    var tmp: [17]Ref = undefined;

    const ca = palloc(Class, ins.len)[0..ins.len];
    cr.class = 0;
    all.curi = all.insbEnd();

    if (f.retty >= 0) {
        typclass(&cr, &all.typ[@intCast(f.retty)], true, &gpreg, &fpreg);
        if ((cr.class & Cptr) != 0) {
            f.retr = newtmp("abi", Kl, f);
            emit(Ocopy, Kl, f.retr, TMP(A0), R);
        }
    }

    const cty = argsclass(ins, ca, (cr.class & Cptr) != 0);
    f.reg = rv64_argregs(CALL(cty), null);

    var il: ?*Insl = null;
    var t: usize = 0; // next tmp
    for (ins, ca) |*i, *c| {
        if ((c.class & Cfpint) != 0) {
            const r = i.to;
            const k = c.cls[0];
            c.cls[0] = if (KWIDE(k) != 0) Kl else Kw;
            i.to = newtmp("abi", k, f);
            emit(Ocast, k, r, i.to, R);
        }
        if (i.op == Oparc and (c.class & Cptr) == 0 and c.nreg != 0) {
            var nt: i32 = c.nreg;
            if ((c.class & Cstk2) != 0) {
                c.cls[1] = Kl;
                c.off[1] = 8;
                assert(nt == 1);
                nt = 2;
            }
            sttmps(tmp[t..], nt, c, i.to, f);
            stkblob(i.to, c.type.?, f, &il);
            t += @as(usize, @intCast(nt));
        }
    }
    while (il) |l| : (il = l.link)
        emiti(l.i);

    t = 0;
    var s: i32 = 2 + 8 * @as(i32, f.vararg);
    for (ins, ca) |*i, *c| {
        if (i.op == Oparc and (c.class & Cptr) == 0) {
            if (c.nreg == 0) {
                f.tmp[i.to.val].slot = -s;
                s += if ((c.class & Cstk2) != 0) 2 else 1;
                continue;
            }
            var j: usize = 0;
            while (j < c.nreg) : (j += 1) {
                const r = TMP(c.reg[j]);
                emit(Ocopy, c.cls[j], tmp[t], r, R);
                t += 1;
            }
            if ((c.class & Cstk2) != 0) {
                emit(Oload, Kl, tmp[t], SLOT(-s), R);
                t += 1;
                s += 1;
            }
        } else if ((c.class & Cstk1) != 0) {
            emit(Oload, c.cls[0], i.to, SLOT(-s), R);
            s += 1;
        } else {
            emit(Ocopy, c.cls[0], i.to, TMP(c.reg[0]), R);
        }
    }

    return .{
        .stk = s,
        .ngp = (cty >> 4) & 15,
        .nfp = (cty >> 8) & 15,
    };
}

fn selvaarg(f: *Fn, i: *Ins) void {
    const loc = newtmp("abi", Kl, f);
    const newloc = newtmp("abi", Kl, f);
    emit(Ostorel, Kw, R, newloc, i.arg[0]);
    emit(Oadd, Kl, newloc, loc, getcon(8, f));
    emit(Oload, i.cls, i.to, loc, R);
    emit(Oload, Kl, loc, i.arg[0], R);
}

fn selvastart(f: *Fn, p: Params, ap: Ref) void {
    const rsave = newtmp("abi", Kl, f);
    emit(Ostorel, Kw, R, rsave, ap);
    const s: i32 = if (p.stk > 2 + 8 * @as(i32, f.vararg)) p.stk else 2 + p.ngp;
    emit(Oaddr, Kl, rsave, SLOT(-s), R);
}

pub fn rv64_abi(f: *Fn) void {
    var b_it = f.start;
    while (b_it) |b| : (b_it = b.link)
        b.visit = 0;

    // lower parameters
    const start = f.start.?;
    var np: uint = 0;
    while (np < start.nins and ispar(start.ins[np].op))
        np += 1;
    const p = selpar(f, start.ins[0..np]);
    const n0: uint = @intCast(all.insbTail());
    const n1: uint = start.nins - np;
    vgrow(&start.ins, n0 + n1);
    _ = icpy(start.ins + n0, start.ins + np, n1);
    _ = icpy(start.ins, all.curi, n0);
    start.nins = n0 + n1;

    // lower calls, returns, and vararg instructions
    var il: ?*Insl = null;
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
                    Ocall => {
                        var n0_ = n;
                        while (n0_ > 0 and isarg(b.ins[n0_ - 1].op))
                            n0_ -= 1;
                        selcall(f, b.ins[n0_..n], i, &il);
                        n = n0_;
                    },
                    Ovastart => selvastart(f, p, i.arg[0]),
                    Ovaarg => selvaarg(f, i),
                    Oarg, Oargc => die("unreachable", .{}),
                }
            }
            if (b == start) {
                while (il) |l| : (il = l.link)
                    emiti(l.i);
            }
            idup(b, all.curi, @intCast(all.insbTail()));
        }
        if (b == start) break;
    }

    if (all.debug['A'] != 0) {
        dprint("\n> After ABI lowering:\n", .{});
        printfn(f, all.dbg) catch {};
    }
}
