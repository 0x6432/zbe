//! One-to-one translation of arm64/abi.c
const std = @import("std");
const assert = std.debug.assert;
// -- imports --
const all = @import("../all.zig");
const tgt = @import("all.zig");
const BIT = all.BIT;
const Blk = all.Blk;
const CALL = all.CALL;
const CON_Z = all.CON_Z;
const Cislt = all.Cislt;
const FEnd = all.FEnd;
const FTyp = all.FTyp;
const Fd = all.Fd;
const Field = all.Field;
const Fn = all.Fn;
const Fs = all.Fs;
const INS = all.INS;
const INT = all.INT;
const Ins = all.Ins;
const Jjmp = all.Jjmp;
const Jjnz = all.Jjnz;
const Jret0 = all.Jret0;
const Jretc = all.Jretc;
const Jretsb = all.Jretsb;
const Jretw = all.Jretw;
const KBASE = all.KBASE;
const KWIDE = all.KWIDE;
const Kd = all.Kd;
const Kl = all.Kl;
const Ks = all.Ks;
const Kw = all.Kw;
const Kx = all.Kx;
const Oadd = all.ops.Oadd;
const Oaddr = all.ops.Oaddr;
const Oalloc = all.Oalloc;
const Oarg = all.ops.Oarg;
const Oargc = all.ops.Oargc;
const Oarge = all.ops.Oarge;
const Oargsb = all.ops.Oargsb;
const Oargsh = all.ops.Oargsh;
const Oargub = all.ops.Oargub;
const Oarguh = all.ops.Oarguh;
const Oargv = all.ops.Oargv;
const Oblit0 = all.ops.Oblit0;
const Oblit1 = all.ops.Oblit1;
const Ocall = all.ops.Ocall;
const Ocmpw = all.Ocmpw;
const Ocopy = all.ops.Ocopy;
const Oextsb = all.ops.Oextsb;
const Oload = all.ops.Oload;
const Oloadsb = all.ops.Oloadsb;
const Oloadsw = all.ops.Oloadsw;
const Opar = all.ops.Opar;
const Oparc = all.ops.Oparc;
const Opare = all.ops.Opare;
const Oparsb = all.ops.Oparsb;
const Oparsh = all.ops.Oparsh;
const Oparub = all.ops.Oparub;
const Oparuh = all.ops.Oparuh;
const Ostoreb = all.ops.Ostoreb;
const Ostored = all.ops.Ostored;
const Ostoreh = all.ops.Ostoreh;
const Ostorel = all.ops.Ostorel;
const Ostores = all.ops.Ostores;
const Ostorew = all.ops.Ostorew;
const Osub = all.ops.Osub;
const Ovaarg = all.ops.Ovaarg;
const Ovastart = all.ops.Ovastart;
const PFn = all.PFn;
const Phi = all.Phi;
const R = all.R;
const R0 = tgt.R0;
const R1 = tgt.R1;
const R2 = tgt.R2;
const R3 = tgt.R3;
const R4 = tgt.R4;
const R5 = tgt.R5;
const R6 = tgt.R6;
const R7 = tgt.R7;
const R8 = tgt.R8;
const R9 = tgt.R9;
const RCall = all.RCall;
const RTmp = all.RTmp;
const Ref = all.Ref;
const SLOT = all.SLOT;
const SP = tgt.SP;
const TMP = all.TMP;
const Typ = all.Typ;
const V0 = tgt.V0;
const V1 = tgt.V1;
const V2 = tgt.V2;
const V3 = tgt.V3;
const V4 = tgt.V4;
const V5 = tgt.V5;
const V6 = tgt.V6;
const V7 = tgt.V7;
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
const isargbh = all.isargbh;
const ispar = all.ispar;
const isparbh = all.isparbh;
const isret = all.isret;
const isretbh = all.isretbh;
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

const Cstk = 1; // pass on the stack
const Cptr = 2; // replaced by a pointer

const Class = struct {
    class: i8,
    ishfa: i8,
    hfa: struct {
        base: i8,
        size: u8,
    },
    size: uint,
    @"align": uint,
    t: [*c]Typ,
    nreg: u8,
    ngp: u8,
    nfp: u8,
    reg: [4]i32,
    cls: [4]i32,
};

const Insl = struct {
    i: Ins,
    link: [*c]Insl,
};

const Params = struct {
    ngp: uint,
    nfp: uint,
    stk: uint,
};

var gpreg = [12]i32{ R0, R1, R2, R3, R4, R5, R6, R7, 0, 0, 0, 0 };
var fpreg = [12]i32{ V0, V1, V2, V3, V4, V5, V6, V7, 0, 0, 0, 0 };
const store = blk: {
    var s: [4]i32 = undefined;
    s[Kw] = Ostorew;
    s[Kl] = Ostorel;
    s[Ks] = Ostores;
    s[Kd] = Ostored;
    break :blk s;
};

// layout of call's second argument (RCall)
//
//         13
//  29   14 |    9    5   2  0
//  |0.00|x|x|xxxx|xxxx|xxx|xx|                  range
//        | |    |    |   |  ` gp regs returned (0..2)
//        | |    |    |   ` fp regs returned    (0..4)
//        | |    |    ` gp regs passed          (0..8)
//        | |     ` fp regs passed              (0..8)
//        | ` indirect result register x8 used  (0..1)
//        ` env pointer passed in x9            (0..1)

fn isfloatv(t: [*c]Typ, cls: *i8) bool {
    var n: uint = 0;
    while (n < t.*.nunion) : (n += 1) {
        var f: [*c]Field = &t.*.fields[n];
        while (f.*.type != FEnd) : (f += 1) {
            switch (f.*.type) {
                Fs => {
                    if (cls.* == Kd)
                        return false;
                    cls.* = Ks;
                },
                Fd => {
                    if (cls.* == Ks)
                        return false;
                    cls.* = Kd;
                },
                FTyp => {
                    if (!isfloatv(&all.typ[f.*.len], cls))
                        return false;
                },
                else => return false,
            }
        }
    }
    return true;
}

fn typclass(c: *Class, t: [*c]Typ, gp_: [*c]i32, fp_: [*c]i32) void {
    var gp = gp_;
    var fp = fp_;
    const sz: u64 = (t.*.size + 7) & ~@as(u64, 7);
    c.t = t;
    c.class = 0;
    c.ngp = 0;
    c.nfp = 0;
    c.@"align" = 8;

    if (t.*.@"align" > 3)
        err("alignments larger than 8 are not supported", .{});

    c.size = @truncate(sz);
    c.hfa.base = Kx;
    var ishfa = isfloatv(t, &c.hfa.base);
    const hfasz: u64 = t.*.size / @as(u64, if (KWIDE(c.hfa.base) != 0) 8 else 4);
    ishfa = ishfa and t.*.isdark == 0 and hfasz <= 4;
    c.ishfa = @intFromBool(ishfa);
    c.hfa.size = @truncate(hfasz);

    if (c.ishfa != 0) {
        var n: uint = 0;
        while (n < hfasz) : ({
            n += 1;
            c.nfp += 1;
        }) {
            c.reg[n] = fp.*;
            fp += 1;
            c.cls[n] = c.hfa.base;
        }
        c.nreg = @intCast(n);
    } else if (t.*.isdark != 0 or sz > 16 or sz == 0) {
        // large structs are replaced by a
        // pointer to some caller-allocated
        // memory
        c.class |= Cptr;
        c.size = 8;
        c.ngp = 1;
        c.reg[0] = gp.*;
        c.cls[0] = Kl;
    } else {
        var n: uint = 0;
        while (n < sz / 8) : ({
            n += 1;
            c.ngp += 1;
        }) {
            c.reg[n] = gp.*;
            gp += 1;
            c.cls[n] = Kl;
        }
        c.nreg = @intCast(n);
    }
}

fn sttmps(tmp: [*c]Ref, cls: [*c]i32, nreg: uint, mem: Ref, f: *Fn) void {
    assert(nreg <= 4);
    var off: u64 = 0;
    var n: uint = 0;
    while (n < nreg) : (n += 1) {
        tmp[n] = newtmp("abi", cls[n], f);
        const r = newtmp("abi", Kl, f);
        emit(store[@intCast(cls[n])], 0, R, tmp[n], r);
        emit(Oadd, Kl, r, mem, getcon(@bitCast(off), f));
        off += if (KWIDE(cls[n]) != 0) 8 else 4;
    }
}

// todo, may read out of bounds
fn ldregs(reg: [*c]i32, cls: [*c]i32, n: i32, mem: Ref, f: *Fn) void {
    var off: u64 = 0;
    var i: usize = 0;
    while (i < @as(usize, @intCast(n))) : (i += 1) {
        const r = newtmp("abi", Kl, f);
        emit(Oload, cls[i], TMP(reg[i]), r, R);
        emit(Oadd, Kl, r, mem, getcon(@bitCast(off), f));
        off += if (KWIDE(cls[i]) != 0) 8 else 4;
    }
}

fn selret(b: [*c]Blk, f: *Fn) void {
    var cr: Class = undefined;
    var cty: i32 = undefined;

    const j: i32 = @intCast(b.*.jmp.type);

    if (!isret(j) or j == Jret0)
        return;

    const r = b.*.jmp.arg;
    b.*.jmp.type = Jret0;

    if (j == Jretc) {
        typclass(&cr, &all.typ[@intCast(f.retty)], &gpreg, &fpreg);
        if ((cr.class & Cptr) != 0) {
            assert(rtype(f.retr) == RTmp);
            emit(Oblit1, 0, R, INT(cr.t.*.size), R);
            emit(Oblit0, 0, R, r, f.retr);
            cty = 0;
        } else {
            ldregs(&cr.reg, &cr.cls, cr.nreg, r, f);
            cty = (@as(i32, cr.nfp) << 2) | cr.ngp;
        }
    } else {
        const k = j - Jretw;
        if (KBASE(k) == 0) {
            emit(Ocopy, k, TMP(R0), r, R);
            cty = 1;
        } else {
            emit(Ocopy, k, TMP(V0), r, R);
            cty = 1 << 2;
        }
    }

    b.*.jmp.arg = CALL(cty);
}

fn argsclass(i_0: [*c]Ins, i_1: [*c]Ins, carg: [*c]Class) i32 {
    var va = false;
    var envc: i32 = 0;
    var gp: [*c]i32 = &gpreg;
    var fp: [*c]i32 = &fpreg;
    var ngp: i32 = 8;
    var nfp: i32 = 8;
    var i = i_0;
    var c = carg;
    while (i < i_1) : ({
        i += 1;
        c += 1;
    }) {
        var scalar = false;
        switch (i.*.op) {
            Oargsb, Oargub, Oparsb, Oparub => {
                c.*.size = 1;
                scalar = true;
            },
            Oargsh, Oarguh, Oparsh, Oparuh => {
                c.*.size = 2;
                scalar = true;
            },
            Opar, Oarg => {
                c.*.size = 8;
                if (all.T.apple != 0 and KWIDE(i.*.cls) == 0)
                    c.*.size = 4;
                scalar = true;
            },
            Oparc, Oargc => {
                typclass(c, &all.typ[i.*.arg[0].val], gp, fp);
                if (c.*.ngp <= ngp) {
                    if (c.*.nfp <= nfp) {
                        ngp -= c.*.ngp;
                        nfp -= c.*.nfp;
                        gp += c.*.ngp;
                        fp += c.*.nfp;
                        continue;
                    } else nfp = 0;
                } else ngp = 0;
                c.*.class |= Cstk;
            },
            Opare, Oarge => {
                c.*.reg[0] = R9;
                c.*.cls[0] = Kl;
                envc = 1;
            },
            Oargv => {
                va = all.T.apple != 0;
            },
            else => die("unreachable", .{}),
        }
        if (scalar) {
            c.*.@"align" = c.*.size;
            c.*.cls[0] = @intCast(i.*.cls);
            if (va) {
                c.*.class |= Cstk;
                c.*.size = 8;
                c.*.@"align" = 8;
                continue;
            }
            if (KBASE(i.*.cls) == 0 and ngp > 0) {
                ngp -= 1;
                c.*.reg[0] = gp.*;
                gp += 1;
                continue;
            }
            if (KBASE(i.*.cls) == 1 and nfp > 0) {
                nfp -= 1;
                c.*.reg[0] = fp.*;
                fp += 1;
                continue;
            }
            c.*.class |= Cstk;
        }
    }

    const ngpu: i32 = @intCast(ptrdiff(gp, @as([*c]i32, &gpreg)));
    const nfpu: i32 = @intCast(ptrdiff(fp, @as([*c]i32, &fpreg)));
    return envc << 14 | ngpu << 5 | nfpu << 9;
}

pub fn arm64_retregs(r: Ref, p: [*c]i32) bits {
    assert(rtype(r) == RCall);
    var ngp: i32 = @intCast(r.val & 3);
    var nfp: i32 = @intCast((r.val >> 2) & 7);
    if (p != null) {
        p[0] = ngp;
        p[1] = nfp;
    }
    var b: bits = 0;
    while (ngp > 0) {
        ngp -= 1;
        b |= BIT(R0 + ngp);
    }
    while (nfp > 0) {
        nfp -= 1;
        b |= BIT(V0 + nfp);
    }
    return b;
}

pub fn arm64_argregs(r: Ref, p: [*c]i32) bits {
    assert(rtype(r) == RCall);
    var ngp: i32 = @intCast((r.val >> 5) & 15);
    var nfp: i32 = @intCast((r.val >> 9) & 15);
    const x8: i32 = @intCast((r.val >> 13) & 1);
    const x9: i32 = @intCast((r.val >> 14) & 1);
    if (p != null) {
        p[0] = ngp + x8 + x9;
        p[1] = nfp;
    }
    var b: bits = 0;
    while (ngp > 0) {
        ngp -= 1;
        b |= BIT(R0 + ngp);
    }
    while (nfp > 0) {
        nfp -= 1;
        b |= BIT(V0 + nfp);
    }
    return b | (@as(bits, @intCast(x8)) << R8) | (@as(bits, @intCast(x9)) << R9);
}

fn stkblob(r: Ref, c: [*c]Class, f: *Fn, ilp: *[*c]Insl) void {
    const il: [*c]Insl = palloc(Insl, 1);
    var al: i32 = c.*.t.*.@"align" - 2; // NAlign == 3
    if (al < 0)
        al = 0;
    const sz: u64 = if ((c.*.class & Cptr) != 0) c.*.t.*.size else c.*.size;
    il.*.i = INS(Oalloc + al, Kl, r, getcon(@bitCast(sz), f), R);
    il.*.link = ilp.*;
    ilp.* = il;
}

fn alignu(x: uint, al: uint) uint {
    return (x +% al -% 1) & (0 -% al);
}

fn selcall(f: *Fn, i_0: [*c]Ins, i_1: [*c]Ins, ilp: *[*c]Insl) void {
    var cr: Class = undefined;
    var tmp: [4]Ref = undefined;
    var op: i32 = undefined;

    const nca: usize = @intCast(ptrdiff(i_1, i_0));
    const ca: [*c]Class = palloc(Class, nca);
    var cty = argsclass(i_0, i_1, ca);

    var stk: uint = 0;
    var i = i_0;
    var c = ca;
    while (i < i_1) : ({
        i += 1;
        c += 1;
    }) {
        if ((c.*.class & Cptr) != 0) {
            i.*.arg[0] = newtmp("abi", Kl, f);
            stkblob(i.*.arg[0], c, f, ilp);
            i.*.op = Oarg;
        }
        if ((c.*.class & Cstk) != 0) {
            stk = alignu(stk, c.*.@"align");
            stk += c.*.size;
        }
    }
    stk = alignu(stk, 16);
    const rstk = getcon(stk, f);
    if (stk != 0)
        emit(Oadd, Kl, TMP(SP), TMP(SP), rstk);

    if (!req(i_1.*.arg[1], R)) {
        typclass(&cr, &all.typ[i_1.*.arg[1].val], &gpreg, &fpreg);
        stkblob(i_1.*.to, &cr, f, ilp);
        cty |= (@as(i32, cr.nfp) << 2) | cr.ngp;
        if ((cr.class & Cptr) != 0) {
            // spill & rega expect calls to be
            // followed by copies from regs,
            // so we emit a dummy
            cty |= 1 << 13 | 1;
            emit(Ocopy, Kw, R, TMP(R0), R);
        } else {
            sttmps(&tmp, &cr.cls, cr.nreg, i_1.*.to, f);
            var n: uint = 0;
            while (n < cr.nreg) : (n += 1) {
                const r = TMP(cr.reg[n]);
                emit(Ocopy, cr.cls[n], tmp[n], r, R);
            }
        }
    } else {
        if (KBASE(i_1.*.cls) == 0) {
            emit(Ocopy, i_1.*.cls, i_1.*.to, TMP(R0), R);
            cty |= 1;
        } else {
            emit(Ocopy, i_1.*.cls, i_1.*.to, TMP(V0), R);
            cty |= 1 << 2;
        }
    }

    emit(Ocall, 0, R, i_1.*.arg[0], CALL(cty));

    if ((cty & (1 << 13)) != 0)
        // struct return argument
        emit(Ocopy, Kl, TMP(R8), i_1.*.to, R);

    i = i_0;
    c = ca;
    while (i < i_1) : ({
        i += 1;
        c += 1;
    }) {
        if ((c.*.class & Cstk) != 0)
            continue;
        if (i.*.op == Oarg or i.*.op == Oarge or isargbh(i.*.op))
            emit(Ocopy, c.*.cls[0], TMP(c.*.reg[0]), i.*.arg[0], R);
        if (i.*.op == Oargc)
            ldregs(&c.*.reg, &c.*.cls, c.*.nreg, i.*.arg[1], f);
    }

    // populate the stack
    var off: uint = 0;
    i = i_0;
    c = ca;
    while (i < i_1) : ({
        i += 1;
        c += 1;
    }) {
        if ((c.*.class & Cstk) == 0)
            continue;
        off = alignu(off, c.*.@"align");
        const r = newtmp("abi", Kl, f);
        if (i.*.op == Oarg or isargbh(i.*.op)) {
            switch (c.*.size) {
                1 => op = Ostoreb,
                2 => op = Ostoreh,
                4, 8 => op = store[@intCast(c.*.cls[0])],
                else => die("unreachable", .{}),
            }
            emit(op, 0, R, i.*.arg[0], r);
        } else {
            assert(i.*.op == Oargc);
            emit(Oblit1, 0, R, INT(c.*.size), R);
            emit(Oblit0, 0, R, i.*.arg[1], r);
        }
        emit(Oadd, Kl, r, TMP(SP), getcon(off, f));
        off += c.*.size;
    }
    if (stk != 0)
        emit(Osub, Kl, TMP(SP), TMP(SP), rstk);

    i = i_0;
    c = ca;
    while (i < i_1) : ({
        i += 1;
        c += 1;
    }) {
        if ((c.*.class & Cptr) != 0) {
            emit(Oblit1, 0, R, INT(c.*.t.*.size), R);
            emit(Oblit0, 0, R, i.*.arg[1], i.*.arg[0]);
        }
    }
}

fn selpar(f: *Fn, i_0: [*c]Ins, i_1: [*c]Ins) Params {
    var cr: Class = undefined;
    var tmp: [16]Ref = undefined;
    var op: i32 = undefined;

    const nca: usize = @intCast(ptrdiff(i_1, i_0));
    const ca: [*c]Class = palloc(Class, nca);
    all.curi = all.insbEnd();

    const cty = argsclass(i_0, i_1, ca);
    f.reg = arm64_argregs(CALL(cty), null);

    var il: [*c]Insl = null;
    var t: [*c]Ref = &tmp;
    var i = i_0;
    var c = ca;
    while (i < i_1) : ({
        i += 1;
        c += 1;
    }) {
        if (i.*.op != Oparc or (c.*.class & (Cptr | Cstk)) != 0)
            continue;
        sttmps(t, &c.*.cls, c.*.nreg, i.*.to, f);
        stkblob(i.*.to, c, f, &il);
        t += c.*.nreg;
    }
    while (il != null) : (il = il.*.link)
        emiti(il.*.i);

    if (f.retty >= 0) {
        typclass(&cr, &all.typ[@intCast(f.retty)], &gpreg, &fpreg);
        if ((cr.class & Cptr) != 0) {
            f.retr = newtmp("abi", Kl, f);
            emit(Ocopy, Kl, f.retr, TMP(R8), R);
            f.reg |= BIT(R8);
        }
    }

    t = &tmp;
    var off: uint = 0;
    i = i_0;
    c = ca;
    while (i < i_1) : ({
        i += 1;
        c += 1;
    }) {
        if (i.*.op == Oparc and (c.*.class & Cptr) == 0) {
            if ((c.*.class & Cstk) != 0) {
                off = alignu(off, c.*.@"align");
                f.tmp[i.*.to.val].slot = -@as(i32, @intCast(off + 2));
                off += c.*.size;
            } else {
                var n: usize = 0;
                while (n < c.*.nreg) : (n += 1) {
                    const r = TMP(c.*.reg[n]);
                    emit(Ocopy, c.*.cls[n], t.*, r, R);
                    t += 1;
                }
            }
        } else if ((c.*.class & Cstk) != 0) {
            off = alignu(off, c.*.@"align");
            if (isparbh(i.*.op))
                op = @intCast(Oloadsb + (i.*.op - Oparsb))
            else
                op = Oload;
            emit(op, c.*.cls[0], i.*.to, SLOT(-@as(i32, @intCast(off + 2))), R);
            off += c.*.size;
        } else {
            emit(Ocopy, c.*.cls[0], i.*.to, TMP(c.*.reg[0]), R);
        }
    }

    return .{
        .stk = alignu(off, 8),
        .ngp = @intCast((cty >> 5) & 15),
        .nfp = @intCast((cty >> 9) & 15),
    };
}

fn split(f: *Fn, b: [*c]Blk) [*c]Blk {
    f.nblk += 1;
    const bn = newblk();
    idup(bn, all.curi, @intCast(ptrdiff(all.insbEnd(), all.curi)));
    all.curi = all.insbEnd();
    b.*.visit += 1;
    bn.*.visit = b.*.visit;
    bn.*.name = strf(PFn, "{s}.{d}", .{ cs(b.*.name), b.*.visit });
    bn.*.loop = b.*.loop;
    bn.*.link = b.*.link;
    b.*.link = bn;
    return bn;
}

fn chpred(b: [*c]Blk, bp: [*c]Blk, bp1: [*c]Blk) void {
    var p = b.*.phi;
    while (p != null) : (p = p.*.link) {
        var a: uint = 0;
        while (p.*.blk[a] != bp) : (a += 1)
            assert(a + 1 < p.*.narg);
        p.*.blk[a] = bp1;
    }
}

fn apple_selvaarg(f: *Fn, b: [*c]Blk, i: [*c]Ins) void {
    _ = b;
    const c8 = getcon(8, f);
    const ap = i.*.arg[0];
    const stk8 = newtmp("abi", Kl, f);
    const stk = newtmp("abi", Kl, f);

    emit(Ostorel, 0, R, stk8, ap);
    emit(Oadd, Kl, stk8, stk, c8);
    emit(Oload, i.*.cls, i.*.to, stk, R);
    emit(Oload, Kl, stk, ap, R);
}

fn arm64_selvaarg(f: *Fn, b: [*c]Blk, i: [*c]Ins) void {
    const c8 = getcon(8, f);
    const c16 = getcon(16, f);
    const c24 = getcon(24, f);
    const c28 = getcon(28, f);
    const ap = i.*.arg[0];
    const isgp = KBASE(i.*.cls) == 0;

    // @b [...]
    //     r0 =l add ap, (24 or 28)
    //     nr =l loadsw r0
    //     r1 =w csltw nr, 0
    //     jnz r1, @breg, @bstk
    // @breg
    //     r0 =l add ap, (8 or 16)
    //     r1 =l loadl r0
    //     lreg =l add r1, nr
    //     r0 =w add nr, (8 or 16)
    //     r1 =l add ap, (24 or 28)
    //     storew r0, r1
    // @bstk
    //     lstk =l loadl ap
    //     r0 =l add lstk, 8
    //     storel r0, ap
    // @b0
    //     %loc =l phi @breg %lreg, @bstk %lstk
    //     i->to =(i->cls) load %loc

    const loc = newtmp("abi", Kl, f);
    emit(Oload, i.*.cls, i.*.to, loc, R);
    const b0 = split(f, b);
    b0.*.jmp = b.*.jmp;
    b0.*.s1 = b.*.s1;
    b0.*.s2 = b.*.s2;
    if (b.*.s1 != null)
        chpred(b.*.s1, b, b0);
    if (b.*.s2 != null and b.*.s2 != b.*.s1)
        chpred(b.*.s2, b, b0);

    const lreg = newtmp("abi", Kl, f);
    const nr = newtmp("abi", Kl, f);
    var r0 = newtmp("abi", Kw, f);
    var r1 = newtmp("abi", Kl, f);
    emit(Ostorew, Kw, R, r0, r1);
    emit(Oadd, Kl, r1, ap, if (isgp) c24 else c28);
    emit(Oadd, Kw, r0, nr, if (isgp) c8 else c16);
    r0 = newtmp("abi", Kl, f);
    r1 = newtmp("abi", Kl, f);
    emit(Oadd, Kl, lreg, r1, nr);
    emit(Oload, Kl, r1, r0, R);
    emit(Oadd, Kl, r0, ap, if (isgp) c8 else c16);
    const breg = split(f, b);
    breg.*.jmp.type = Jjmp;
    breg.*.s1 = b0;

    const lstk = newtmp("abi", Kl, f);
    r0 = newtmp("abi", Kl, f);
    emit(Ostorel, Kw, R, r0, ap);
    emit(Oadd, Kl, r0, lstk, c8);
    emit(Oload, Kl, lstk, ap, R);
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
    b.*.jmp.type = Jjnz;
    b.*.jmp.arg = r1;
    b.*.s1 = breg;
    b.*.s2 = bstk;
    emit(Ocmpw + Cislt, Kw, r1, nr, CON_Z);
    emit(Oloadsw, Kl, nr, r0, R);
    emit(Oadd, Kl, r0, ap, if (isgp) c24 else c28);
}

fn apple_selvastart(f: *Fn, p: Params, ap: Ref) void {
    const off = getcon(p.stk, f);
    const stk = newtmp("abi", Kl, f);
    const arg = newtmp("abi", Kl, f);

    emit(Ostorel, 0, R, arg, ap);
    emit(Oadd, Kl, arg, stk, off);
    emit(Oaddr, Kl, stk, SLOT(-1), R);
}

fn arm64_selvastart(f: *Fn, p: Params, ap: Ref) void {
    const rsave = newtmp("abi", Kl, f);

    var r0 = newtmp("abi", Kl, f);
    emit(Ostorel, Kw, R, r0, ap);
    emit(Oadd, Kl, r0, rsave, getcon(p.stk + 192, f));

    r0 = newtmp("abi", Kl, f);
    var r1 = newtmp("abi", Kl, f);
    emit(Ostorel, Kw, R, r1, r0);
    emit(Oadd, Kl, r1, rsave, getcon(64, f));
    emit(Oadd, Kl, r0, ap, getcon(8, f));

    r0 = newtmp("abi", Kl, f);
    r1 = newtmp("abi", Kl, f);
    emit(Ostorel, Kw, R, r1, r0);
    emit(Oadd, Kl, r1, rsave, getcon(192, f));
    emit(Oaddr, Kl, rsave, SLOT(-1), R);
    emit(Oadd, Kl, r0, ap, getcon(16, f));

    // C: (p.ngp-8)*8 computed in uint, then widened to int64_t
    r0 = newtmp("abi", Kl, f);
    emit(Ostorew, Kw, R, getcon(@as(u32, (p.ngp -% 8) *% 8), f), r0);
    emit(Oadd, Kl, r0, ap, getcon(24, f));

    r0 = newtmp("abi", Kl, f);
    emit(Ostorew, Kw, R, getcon(@as(u32, (p.nfp -% 8) *% 16), f), r0);
    emit(Oadd, Kl, r0, ap, getcon(28, f));
}

pub fn arm64_abi(f: [*c]Fn) void {
    var b = f.*.start;
    while (b != null) : (b = b.*.link)
        b.*.visit = 0;

    // lower parameters
    b = f.*.start;
    var i = b.*.ins;
    while (i < b.*.ins + b.*.nins) : (i += 1) {
        if (!ispar(i.*.op))
            break;
    }
    const p = selpar(f, b.*.ins, i);
    const n0: uint = @intCast(ptrdiff(all.insbEnd(), all.curi));
    const ioff: uint = @intCast(ptrdiff(i, b.*.ins));
    const n1: uint = b.*.nins - ioff;
    vgrow(&b.*.ins, n0 + n1);
    _ = icpy(b.*.ins + n0, b.*.ins + ioff, n1);
    _ = icpy(b.*.ins, all.curi, n0);
    b.*.nins = n0 + n1;

    // lower calls, returns, and vararg instructions
    var il: [*c]Insl = null;
    b = f.*.start;
    while (true) {
        b = b.*.link;
        if (b == null)
            b = f.*.start; // do it last
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
                        selcall(f, i_0, i, &il);
                        i = i_0;
                    },
                    Ovastart => {
                        if (all.T.apple != 0)
                            apple_selvastart(f, p, i.*.arg[0])
                        else
                            arm64_selvastart(f, p, i.*.arg[0]);
                    },
                    Ovaarg => {
                        if (all.T.apple != 0)
                            apple_selvaarg(f, b, i)
                        else
                            arm64_selvaarg(f, b, i);
                    },
                    Oarg, Oargc => die("unreachable", .{}),
                }
            }
            if (b == f.*.start) {
                while (il != null) : (il = il.*.link)
                    emiti(il.*.i);
            }
            idup(b, all.curi, @intCast(ptrdiff(all.insbEnd(), all.curi)));
        }
        if (b == f.*.start) break;
    }

    if (all.debug['A'] != 0) {
        dprint("\n> After ABI lowering:\n", .{});
        printfn(f, all.dbg) catch {};
    }
}

/// abi0 for apple target; introduces
/// necessary sign extensions in calls
/// and returns
pub fn apple_extsb(f: [*c]Fn) void {
    var b = f.*.start;
    while (b != null) : (b = b.*.link) {
        all.curi = all.insbEnd();
        const j: i32 = @intCast(b.*.jmp.type);
        if (isretbh(j)) {
            const r = newtmp("abi", Kw, f);
            const op = Oextsb + (j - Jretsb);
            emit(op, Kw, r, b.*.jmp.arg, R);
            b.*.jmp.arg = r;
            b.*.jmp.type = Jretw;
        }
        var i = b.*.ins + b.*.nins;
        while (i > b.*.ins) {
            i -= 1;
            emiti(i.*);
            if (i.*.op != Ocall)
                continue;
            const i_1 = i;
            var i_0 = i;
            while (i_0 > b.*.ins) : (i_0 -= 1) {
                if (!isarg((i_0 - 1).*.op))
                    break;
            }
            i = i_1;
            while (i > i_0) {
                i -= 1;
                emiti(i.*);
                if (isargbh(i.*.op)) {
                    i.*.to = newtmp("abi", Kl, f);
                    all.curi.*.arg[0] = i.*.to;
                }
            }
            i = i_1;
            while (i > i_0) {
                i -= 1;
                if (isargbh(i.*.op)) {
                    const op = Oextsb + (i.*.op - Oargsb);
                    emit(op, Kw, i.*.to, i.*.arg[0], R);
                }
            }
        }
        idup(b, all.curi, @intCast(ptrdiff(all.insbEnd(), all.curi)));
    }

    if (all.debug['A'] != 0) {
        dprint("\n> After Apple pre-ABI:\n", .{});
        printfn(f, all.dbg) catch {};
    }
}
