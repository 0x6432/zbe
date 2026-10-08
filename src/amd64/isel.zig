//! One-to-one translation of amd64/isel.c
const std = @import("std");
const assert = std.debug.assert;
// -- imports --
const all = @import("../all.zig");
const tgt = @import("all.zig");
const Addr = all.Addr;
const BIT = all.BIT;
const Blk = all.Blk;
const CALL = all.CALL;
const CAddr = all.CAddr;
const CBits = all.CBits;
const CON_Z = all.CON_Z;
const CUndef = all.CUndef;
const Cfeq = all.Cfeq;
const Cfge = all.Cfge;
const Cfgt = all.Cfgt;
const Cfle = all.Cfle;
const Cflt = all.Cflt;
const Cfne = all.Cfne;
const Cine = all.Cine;
const Con = all.Con;
const Fn = all.Fn;
const INS0 = all.INS0;
const Ins = all.Ins;
const Jhlt = all.Jhlt;
const Jjf = all.Jjf;
const Jjmp = all.Jjmp;
const Jjnz = all.Jjnz;
const Jret0 = all.Jret0;
const KBASE = all.KBASE;
const KWIDE = all.KWIDE;
const Kd = all.Kd;
const Kl = all.Kl;
const Ks = all.Ks;
const Kw = all.Kw;
const MEM = all.MEM;
const NCmpI = all.NCmpI;
const Num = all.Num;
const Oadd = all.ops.Oadd;
const Oaddr = all.ops.Oaddr;
const Oalloc = all.Oalloc;
const Oalloc1 = all.Oalloc1;
const Oalloc16 = all.ops.Oalloc16;
const Oalloc4 = all.ops.Oalloc4;
const Oalloc8 = all.ops.Oalloc8;
const Oand = all.ops.Oand;
const Ocall = all.ops.Ocall;
const Ocast = all.ops.Ocast;
const Ocopy = all.ops.Ocopy;
const Odbgloc = all.ops.Odbgloc;
const Odiv = all.ops.Odiv;
const Odtosi = all.ops.Odtosi;
const Odtoui = all.ops.Odtoui;
const Oexts = all.ops.Oexts;
const Oextuw = all.ops.Oextuw;
const Oflag = all.Oflag;
const Oflagfo = all.ops.Oflagfo;
const Oflagfuo = all.ops.Oflagfuo;
const Oload = all.ops.Oload;
const Omul = all.ops.Omul;
const Oneg = all.ops.Oneg;
const Onop = all.ops.Onop;
const Oor = all.ops.Oor;
const Orem = all.ops.Orem;
const Osalloc = all.ops.Osalloc;
const Osar = all.ops.Osar;
const Osel0 = all.ops.Osel0;
const Osel1 = all.ops.Osel1;
const Oshl = all.ops.Oshl;
const Oshr = all.ops.Oshr;
const Osign = all.ops.Osign;
const Osltof = all.ops.Osltof;
const Ostoreb = all.ops.Ostoreb;
const Ostored = all.ops.Ostored;
const Ostoreh = all.ops.Ostoreh;
const Ostorel = all.ops.Ostorel;
const Ostores = all.ops.Ostores;
const Ostorew = all.ops.Ostorew;
const Ostosi = all.ops.Ostosi;
const Ostoui = all.ops.Ostoui;
const Osub = all.ops.Osub;
const Oswtof = all.ops.Oswtof;
const Otruncd = all.ops.Otruncd;
const Oudiv = all.ops.Oudiv;
const Oultof = all.ops.Oultof;
const Ourem = all.ops.Ourem;
const Ouwtof = all.ops.Ouwtof;
const Oxcmp = all.ops.Oxcmp;
const Oxdiv = all.ops.Oxdiv;
const Oxidiv = all.ops.Oxidiv;
const Oxor = all.ops.Oxor;
const Oxsel = all.Oxsel;
const Oxtest = all.ops.Oxtest;
const R = all.R;
const RAX = tgt.RAX;
const RCX = tgt.RCX;
const RCon = all.RCon;
const RDI = tgt.RDI;
const RDX = tgt.RDX;
const RMem = all.RMem;
const RTmp = all.RTmp;
const Ref = all.Ref;
const SExt = all.SExt;
const SLOT = all.SLOT;
const SThr = all.SThr;
const TMP = all.TMP;
const addcon = all.addcon;
const amd64_op = tgt.amd64_op;
const argcls = all.argcls;
const bits = all.bits;
const bufPrintZ = all.bufPrintZ;
const chuse = all.chuse;
const cmpop = all.cmpop;
const cs = all.cs;
const die = all.die;
const dprint = all.dprint;
const ealloc = all.ealloc;
const efree = all.efree;
const emit = all.emit;
const emiti = all.emiti;
const err = all.err;
const getcon = all.getcon;
const idup = all.idup;
const intern = all.intern;
const iscmp = all.iscmp;
const isext = all.isext;
const isload = all.isload;
const isreg = all.isreg;
const isstore = all.isstore;
const isxsel = all.isxsel;
const newcon = all.newcon;
const newtmp = all.newtmp;
const printfn = all.printfn;
const ptrdiff = all.ptrdiff;
const req = all.req;
const rtype = all.rtype;
const runmatch = all.runmatch;
const salloc = all.salloc;
const stashbits = all.stashbits;
const uchar = all.uchar;
const uint = all.uint;
const vgrow = all.vgrow;
// -- end imports --

// For x86_64, do the following:
//
// - check that constants are used only in
//   places allowed
// - ensure immediates always fit in 32b
// - expose machine register contraints
//   on instructions like division.
// - implement fast locals (the streak of
//   constant allocX in the first basic block)
// - recognize complex addressing modes
//
// Invariant: the use counts that are used
//            in sel() must be sound.  This
//            is not so trivial, maybe the
//            dce should be moved out...

fn noimm(r: Ref, f: *Fn) bool {
    if (rtype(r) != RCon)
        return false;
    switch (f.con[r.val].type) {
        CAddr => {
            // we only support the 'small'
            // code model of the ABI, this
            // means that we can always
            // address data with 32bits
            return false;
        },
        CBits => {
            const val = f.con[r.val].bits.i;
            return (val < std.math.minInt(i32) or val > std.math.maxInt(i32));
        },
        else => die("invalid constant", .{}),
    }
}

fn rslot(r: Ref, f: *Fn) i32 {
    if (rtype(r) != RTmp)
        return -1;
    return f.tmp[r.val].slot;
}

fn hascon(r: Ref, pc: *[*c]Con, f: *Fn) bool {
    switch (rtype(r)) {
        RCon => {
            pc.* = &f.con[r.val];
            return true;
        },
        RMem => {
            pc.* = &f.mem[r.val].offset;
            return true;
        },
        else => return false,
    }
}

fn fixarg(r: [*c]Ref, k: i32, i: [*c]Ins, f: *Fn) void {
    var buf: [32]u8 = undefined;
    var a: Addr = undefined;
    var cc: Con = undefined;
    var c: [*c]Con = undefined;

    var r0 = r.*;
    var r1 = r0;
    const s = rslot(r0, f);
    const op: i32 = if (i != null) @intCast(i.*.op) else Ocopy;
    if (KBASE(k) == 1 and rtype(r0) == RCon) {
        // load floating points from memory
        // slots, they can't be used as
        // immediates
        r1 = MEM(f.nmem);
        f.nmem += 1;
        vgrow(&f.mem, f.nmem);
        a = std.mem.zeroes(Addr);
        a.offset.type = CAddr;
        const n = stashbits(@bitCast(f.con[r0.val].bits.i), if (KWIDE(k) != 0) 8 else 4);
        // quote the name so that we do not
        // add symbol prefixes on the apple
        // target variant
        bufPrintZ(&buf, "\"{s}fp{d}\"", .{cs(&all.T.asloc), n});
        a.offset.sym.id = intern(&buf);
        f.mem[@intCast(f.nmem - 1)] = a;
    } else if (op == Ocall and r == &i.*.arg[0] and
        rtype(r0) == RCon and f.con[r0.val].type != CAddr)
    {
        // use a temporary register so that we
        // produce an indirect call
        r1 = newtmp("isel", Kl, f);
        emit(Ocopy, Kl, r1, r0, R);
    } else if (op != Ocopy and k == Kl and noimm(r0, f)) {
        // load constants that do not fit in
        // a 32bit signed integer into a
        // long temporary
        r1 = newtmp("isel", Kl, f);
        emit(Ocopy, Kl, r1, r0, R);
    } else if (s != -1) {
        // load fast locals' addresses into
        // temporaries right before the
        // instruction
        r1 = newtmp("isel", Kl, f);
        emit(Oaddr, Kl, r1, SLOT(s), R);
    } else if (op != Ocall and hascon(r0, &c, f) and
        c.*.type == CAddr and ((c.*.sym.type & SExt) != 0 or
        (all.T.apple != 0 and c.*.sym.type == SThr)))
    {
        r1 = newtmp("isel", Kl, f);
        var r2: Ref = undefined;
        var r3: Ref = undefined;
        if (c.*.bits.i != 0) {
            r2 = newtmp("isel", Kl, f);
            cc = std.mem.zeroes(Con);
            cc.type = CBits;
            cc.bits.i = c.*.bits.i;
            r3 = newcon(&cc, f);
            emit(Oadd, Kl, r1, r2, r3);
        } else r2 = r1;
        if (all.T.apple != 0 and (c.*.sym.type & SThr) != 0) {
            emit(Ocopy, Kl, r2, TMP(RAX), R);
            r2 = newtmp("isel", Kl, f);
            r3 = newtmp("isel", Kl, f);
            emit(Ocall, 0, R, r3, CALL(17));
            emit(Ocopy, Kl, TMP(RDI), r2, R);
            emit(Oload, Kl, r3, r2, R);
        }
        cc = c.*;
        cc.bits.i = 0;
        r3 = newcon(&cc, f);
        emit(Oaddr, Kl, r2, r3, R);
        if (rtype(r0) == RMem) {
            const m = &f.mem[r0.val];
            m.*.offset.type = CUndef;
            m.*.base = r1;
            r1 = r0;
        }
    } else if (!(isstore(op) and r == &i.*.arg[1]) and
        !isload(op) and op != Ocall and rtype(r0) == RCon and
        f.con[r0.val].type == CAddr)
    {
        // turn address operands into
        // lea/mov instructions
        r1 = newtmp("isel", Kl, f);
        emit(Oaddr, Kl, r1, r0, R);
    } else if (rtype(r0) == RMem) {
        // eliminate memory operands of
        // the form $foo(%rip, ...)
        const m = &f.mem[r0.val];
        if (req(m.*.base, R))
            if (m.*.offset.type == CAddr) {
                r0 = newtmp("isel", Kl, f);
                emit(Oaddr, Kl, r0, newcon(&m.*.offset, f), R);
                m.*.offset.type = CUndef;
                m.*.base = r0;
            };
    } else if (isxsel(op) and rtype(r.*) == RCon) {
        r1 = newtmp("isel", i.*.cls, f);
        emit(Ocopy, i.*.cls, r1, r.*, R);
    }
    r.* = r1;
}

fn seladdr(r: [*c]Ref, tn: [*c]Num, f: *Fn) void {
    var a: Addr = undefined;

    const r0 = r.*;
    if (rtype(r0) == RTmp) {
        a = std.mem.zeroes(Addr);
        if (!amatch(&a, tn, r0, f))
            return;
        if (!req(a.base, R))
            if (a.offset.type == CAddr) {
                // apple as does not support
                // $foo(%r0, %r1, M); try to
                // rewrite it or bail out if
                // impossible
                if (!req(a.index, R) or rtype(a.base) != RTmp) {
                    return;
                } else {
                    a.index = a.base;
                    a.scale = 1;
                    a.base = R;
                }
            };
        chuse(r0, -1, f);
        f.nmem += 1;
        vgrow(&f.mem, f.nmem);
        f.mem[@intCast(f.nmem - 1)] = a;
        chuse(a.base, 1, f);
        chuse(a.index, 1, f);
        r.* = MEM(f.nmem - 1);
    }
}

fn cmpswap(arg: [*c]Ref, op: i32) bool {
    switch (op) {
        NCmpI + Cflt, NCmpI + Cfle => return true,
        NCmpI + Cfgt, NCmpI + Cfge => return false,
        else => {},
    }
    return rtype(arg[0]) == RCon;
}

fn selcmp(arg: [*c]Ref, k: i32, swap: bool, f: *Fn) void {
    if (swap) {
        const r = arg[1];
        arg[1] = arg[0];
        arg[0] = r;
    }
    emit(Oxcmp, k, R, arg[1], arg[0]);
    const icmp = all.curi;
    if (rtype(arg[0]) == RCon) {
        assert(k != Kw);
        icmp.*.arg[1] = newtmp("isel", k, f);
        emit(Ocopy, k, icmp.*.arg[1], arg[0], R);
        fixarg(&all.curi.*.arg[0], k, all.curi, f);
    }
    fixarg(&icmp.*.arg[0], k, icmp, f);
    fixarg(&icmp.*.arg[1], k, icmp, f);
}

fn sel(i_: Ins, tn: [*c]Num, f: *Fn) void {
    var i = i_;
    var r0: Ref = undefined;
    var r1: Ref = undefined;
    var tmp: [7]Ref = undefined;
    var x: i32 = undefined;
    var kc: i32 = undefined;
    var i_1: [*c]Ins = undefined;

    if (rtype(i.to) == RTmp)
        if (!isreg(i.to) and !isreg(i.arg[0]) and !isreg(i.arg[1]))
            if (f.tmp[i.to.val].nuse == 0) {
                chuse(i.arg[0], -1, f);
                chuse(i.arg[1], -1, f);
                return;
            };
    var i_0 = all.curi;
    const k: i32 = @intCast(i.cls);
    sw: switch (i.op) {
        Odiv, Orem, Oudiv, Ourem => {
            if (KBASE(k) == 1)
                continue :sw Ocopy; // goto Emit
            if (i.op == Odiv or i.op == Oudiv) {
                r0 = TMP(RAX);
                r1 = TMP(RDX);
            } else {
                r0 = TMP(RDX);
                r1 = TMP(RAX);
            }
            emit(Ocopy, k, i.to, r0, R);
            emit(Ocopy, k, R, r1, R);
            if (rtype(i.arg[1]) == RCon) {
                // immediates not allowed for
                // divisions in x86
                r0 = newtmp("isel", k, f);
            } else r0 = i.arg[1];
            if (f.tmp[r0.val].slot != -1)
                err("unlikely argument %{s} in {s}", .{cs(f.tmp[r0.val].name), cs(all.optab[i.op].name)});
            if (i.op == Odiv or i.op == Orem) {
                emit(Oxidiv, k, R, r0, R);
                emit(Osign, k, TMP(RDX), TMP(RAX), R);
            } else {
                emit(Oxdiv, k, R, r0, R);
                emit(Ocopy, k, TMP(RDX), CON_Z, R);
            }
            emit(Ocopy, k, TMP(RAX), i.arg[0], R);
            fixarg(&all.curi.*.arg[0], k, all.curi, f);
            if (rtype(i.arg[1]) == RCon)
                emit(Ocopy, k, r0, i.arg[1], R);
        },
        Osar, Oshr, Oshl => {
            r0 = i.arg[1];
            if (rtype(r0) == RCon)
                continue :sw Ocopy; // goto Emit
            if (f.tmp[r0.val].slot != -1)
                err("unlikely argument %{s} in {s}", .{cs(f.tmp[r0.val].name), cs(all.optab[i.op].name)});
            i.arg[1] = TMP(RCX);
            emit(Ocopy, Kw, R, TMP(RCX), R);
            emiti(i);
            i_1 = all.curi;
            emit(Ocopy, Kw, TMP(RCX), r0, R);
            fixarg(&i_1.*.arg[0], argcls(&i, 0), i_1, f);
        },
        Ouwtof => {
            r0 = newtmp("utof", Kl, f);
            emit(Osltof, k, i.to, r0, R);
            emit(Oextuw, Kl, r0, i.arg[0], R);
            fixarg(&all.curi.*.arg[0], k, all.curi, f);
        },
        Oultof => {
            // %mask =l and %arg.0, 1
            // %isbig =l shr %arg.0, 63
            // %divided =l shr %arg.0, %isbig
            // %or =l or %mask, %divided
            // %float =d sltof %or
            // %cast =l cast %float
            // %addend =l shl %isbig, 52
            // %sum =l add %cast, %addend
            // %result =d cast %sum
            r0 = newtmp("utof", k, f);
            var sh: i32 = undefined;
            if (k == Ks) {
                kc = Kw;
                sh = 23;
            } else {
                kc = Kl;
                sh = 52;
            }
            var j: usize = 0;
            while (j < 4) : (j += 1)
                tmp[j] = newtmp("utof", Kl, f);
            while (j < 7) : (j += 1)
                tmp[j] = newtmp("utof", kc, f);
            emit(Ocast, k, i.to, tmp[6], R);
            emit(Oadd, kc, tmp[6], tmp[4], tmp[5]);
            emit(Oshl, kc, tmp[5], tmp[1], getcon(sh, f));
            emit(Ocast, kc, tmp[4], r0, R);
            emit(Osltof, k, r0, tmp[3], R);
            emit(Oor, Kl, tmp[3], tmp[0], tmp[2]);
            emit(Oshr, Kl, tmp[2], i.arg[0], tmp[1]);
            const ci = all.curi;
            all.curi += 1;
            sel(ci.*, null, f);
            emit(Oshr, Kl, tmp[1], i.arg[0], getcon(63, f));
            fixarg(&all.curi.*.arg[0], Kl, all.curi, f);
            emit(Oand, Kl, tmp[0], i.arg[0], getcon(1, f));
            fixarg(&all.curi.*.arg[0], Kl, all.curi, f);
        },
        Ostoui, Odtoui => {
            if (i.op == Ostoui) {
                i.op = Ostosi;
                kc = Ks;
                tmp[4] = getcon(0xdf000000, f);
            } else {
                i.op = Odtosi;
                kc = Kd;
                tmp[4] = getcon(@bitCast(@as(u64, 0xc3e0000000000000)), f);
            }
            // Oftoui:
            if (k == Kw) {
                r0 = newtmp("ftou", Kl, f);
                emit(Ocopy, Kw, i.to, r0, R);
                i.cls = Kl;
                i.to = r0;
                continue :sw Ocopy; // goto Emit
            }
            // %try0 =l {s,d}tosi %fp
            // %mask =l sar %try0, 63
            //
            //    mask is all ones if the first
            //    try was oob, all zeroes o.w.
            //
            // %fps ={s,d} sub %fp, (1<<63)
            // %try1 =l {s,d}tosi %fps
            //
            // %tmp =l and %mask, %try1
            // %res =l or %tmp, %try0
            r0 = newtmp("ftou", kc, f);
            var j: usize = 0;
            while (j < 4) : (j += 1)
                tmp[j] = newtmp("ftou", Kl, f);
            emit(Oor, Kl, i.to, tmp[0], tmp[3]);
            emit(Oand, Kl, tmp[3], tmp[2], tmp[1]);
            emit(i.op, Kl, tmp[2], r0, R);
            emit(Oadd, kc, r0, tmp[4], i.arg[0]);
            i_1 = all.curi; // fixarg() can change curi
            fixarg(&i_1.*.arg[0], kc, i_1, f);
            fixarg(&i_1.*.arg[1], kc, i_1, f);
            emit(Osar, Kl, tmp[1], tmp[0], getcon(63, f));
            emit(i.op, Kl, tmp[0], i.arg[0], R);
            fixarg(&all.curi.*.arg[0], Kl, all.curi, f);
        },
        Onop => {},
        Ostored, Ostores, Ostorel, Ostorew, Ostoreh, Ostoreb => {
            if (rtype(i.arg[0]) == RCon) {
                if (i.op == Ostored)
                    i.op = Ostorel;
                if (i.op == Ostores)
                    i.op = Ostorew;
            }
            seladdr(&i.arg[1], tn, f);
            continue :sw Ocopy; // goto Emit
        },
        Odbgloc, Ocall, Osalloc, Ocopy, Oadd, Osub, Oneg, Omul, Oand, Oor, Oxor, Oxtest, Ostosi, Odtosi, Oswtof, Osltof, Oexts, Otruncd, Ocast => {
            // Emit:
            emiti(i);
            i_1 = all.curi; // fixarg() can change curi
            fixarg(&i_1.*.arg[0], argcls(&i, 0), i_1, f);
            fixarg(&i_1.*.arg[1], argcls(&i, 1), i_1, f);
        },
        Oalloc4, Oalloc8, Oalloc16 => salloc(i.to, i.arg[0], f),
        else => {
            if (isext(i.op))
                continue :sw Ocopy; // goto case_Oext
            if (isxsel(i.op))
                continue :sw Ocopy; // goto case_Oxsel
            if (isload(i.op)) {
                // case_Oload:
                seladdr(&i.arg[0], tn, f);
                continue :sw Ocopy; // goto Emit
            }
            if (iscmp(i.op, &kc, &x)) {
                switch (x) {
                    NCmpI + Cfeq => {
                        // zf is set when operands are
                        // unordered, so we may have to
                        // check pf
                        r0 = newtmp("isel", Kw, f);
                        r1 = newtmp("isel", Kw, f);
                        emit(Oand, Kw, i.to, r0, r1);
                        emit(Oflagfo, k, r1, R, R);
                        i.to = r0;
                    },
                    NCmpI + Cfne => {
                        r0 = newtmp("isel", Kw, f);
                        r1 = newtmp("isel", Kw, f);
                        emit(Oor, Kw, i.to, r0, r1);
                        emit(Oflagfuo, k, r1, R, R);
                        i.to = r0;
                    },
                    else => {},
                }
                const swap = cmpswap(&i.arg, x);
                if (swap)
                    x = cmpop(x);
                emit(Oflag + x, k, i.to, R, R);
                selcmp(&i.arg, kc, swap, f);
                break :sw;
            }
            die("unknown instruction {s}", .{cs(all.optab[i.op].name)});
        },
    }

    while (i_0 > all.curi) {
        i_0 -= 1;
        assert(rslot(i_0.*.arg[0], f) == -1);
        assert(rslot(i_0.*.arg[1], f) == -1);
    }
}

fn flagi(i_0: [*c]Ins, i_: [*c]Ins) [*c]Ins {
    var i = i_;
    while (i > i_0) {
        i -= 1;
        if (amd64_op[i.*.op].zflag != 0)
            return i;
        if (amd64_op[i.*.op].lflag != 0)
            continue;
        return null;
    }
    return null;
}

fn selsel(f: *Fn, b: *Blk, i: [*c]Ins, tn: [*c]Num) [*c]Ins {
    var cr: [2]Ref = undefined;

    assert(i.*.op == Osel1);
    var isel0 = i;
    while (b.ins < isel0) : (isel0 -= 1) {
        if (isel0.*.op == Osel0)
            break;
        assert(isel0.*.op == Osel1);
    }
    assert(isel0.*.op == Osel0);
    var r = isel0.*.arg[0];
    assert(rtype(r) == RTmp);
    const t = &f.tmp[r.val];
    const fi = flagi(b.ins, isel0);
    cr[0] = R;
    cr[1] = R;
    var gencmp = false;
    var gencpy = false;
    var swap = false;
    var k: i32 = Kw;
    var c: i32 = Cine;
    var other = false;
    if (fi == null or !req(fi.*.to, r)) {
        gencmp = true;
        cr[0] = r;
        cr[1] = CON_Z;
    } else if (iscmp(fi.*.op, &k, &c)) {
        if (c == NCmpI + Cfeq or
            c == NCmpI + Cfne)
        {
            // these are selected as 'and'
            // or 'or', so we check their
            // result with Cine
            c = Cine;
            other = true;
        } else {
            swap = cmpswap(&fi.*.arg, c);
            if (swap)
                c = cmpop(c);
            if (t.*.nuse == 1) {
                gencmp = true;
                cr[0] = fi.*.arg[0];
                cr[1] = fi.*.arg[1];
                fi.* = INS0(Onop);
            }
        }
    } else if (fi.*.op == Oand and t.*.nuse == 1 and
        (rtype(fi.*.arg[0]) == RTmp or
        rtype(fi.*.arg[1]) == RTmp))
    {
        fi.*.op = Oxtest;
        fi.*.to = R;
        if (rtype(fi.*.arg[1]) == RCon) {
            r = fi.*.arg[1];
            fi.*.arg[1] = fi.*.arg[0];
            fi.*.arg[0] = r;
        }
    } else {
        other = true;
    }
    if (other) {
        // since flags are not tracked in liveness,
        // the result of the flag-setting instruction
        // has to be marked as live
        if (t.*.nuse == 1)
            gencpy = true;
    }
    // generate conditional moves
    var isel1 = i;
    while (isel0 < isel1) : (isel1 -= 1) {
        isel1.*.op = @intCast(Oxsel + c);
        sel(isel1.*, tn, f);
    }
    assert(!gencmp or !gencpy);
    if (gencmp)
        selcmp(&cr, k, swap, f);
    if (gencpy)
        emit(Ocopy, Kw, R, r, R);
    isel0.* = INS0(Onop);
    return isel0;
}

fn seljmp(b: *Blk, f: *Fn) void {
    var k: i32 = undefined;
    var c: i32 = undefined;

    if (b.jmp.type == Jret0 or
        b.jmp.type == Jjmp or
        b.jmp.type == Jhlt)
        return;
    assert(b.jmp.type == Jjnz);
    var r = b.jmp.arg;
    const t = &f.tmp[r.val];
    b.jmp.arg = R;
    assert(rtype(r) == RTmp);
    if (b.s1 == b.s2) {
        chuse(r, -1, f);
        b.jmp.type = Jjmp;
        b.s2 = null;
        return;
    }
    const fi = flagi(b.ins, b.ins + b.nins);
    if (fi == null or !req(fi.*.to, r)) {
        var cr = [2]Ref{ r, CON_Z };
        selcmp(&cr, Kw, false, f);
        b.jmp.type = Jjf + Cine;
    } else if (iscmp(fi.*.op, &k, &c) and
        c != NCmpI + Cfeq and // see sel(), selsel()
        c != NCmpI + Cfne)
    {
        const swap = cmpswap(&fi.*.arg, c);
        if (swap)
            c = cmpop(c);
        if (t.*.nuse == 1) {
            selcmp(&fi.*.arg, k, swap, f);
            fi.* = INS0(Onop);
        }
        b.jmp.type = @intCast(Jjf + c);
    } else if (fi.*.op == Oand and t.*.nuse == 1 and
        (rtype(fi.*.arg[0]) == RTmp or
        rtype(fi.*.arg[1]) == RTmp))
    {
        fi.*.op = Oxtest;
        fi.*.to = R;
        b.jmp.type = Jjf + Cine;
        if (rtype(fi.*.arg[1]) == RCon) {
            r = fi.*.arg[1];
            fi.*.arg[1] = fi.*.arg[0];
            fi.*.arg[0] = r;
        }
    } else {
        // since flags are not tracked in liveness,
        // the result of the flag-setting instruction
        // has to be marked as live
        if (t.*.nuse == 1)
            emit(Ocopy, Kw, R, r, R);
        b.jmp.type = Jjf + Cine;
    }
}

const Pob = 0;
const Pbis = 1;
const Pois = 2;
const Pobis = 3;
const Pbi1 = 4;
const Pobi1 = 5;

// mgen generated code
//
// (with-vars (o b i s)
//   (patterns
//     (ob   (add (con o) (tmp b)))
//     (bis  (add (tmp b) (mul (tmp i) (con s 1 2 4 8))))
//     (ois  (add (con o) (mul (tmp i) (con s 1 2 4 8))))
//     (obis (add (con o) (tmp b) (mul (tmp i) (con s 1 2 4 8))))
//     (bi1  (add (tmp b) (tmp i)))
//     (obi1 (add (con o) (tmp b) (tmp i)))
// ))

const Oaddtbl = [91]uchar{
    2,
    2,  2,
    4,  4,  5,
    6,  6,  8,  8,
    4,  4,  9,  10, 9,
    7,  7,  5,  8,  9,  5,
    4,  4,  12, 10, 12, 12, 12,
    4,  4,  9,  10, 9,  9,  12, 9,
    11, 11, 5,  8,  9,  5,  12, 9,  5,
    7,  7,  5,  8,  9,  5,  12, 9,  5,  5,
    11, 11, 5,  8,  9,  5,  12, 9,  5,  5,  5,
    4,  4,  9,  10, 9,  9,  12, 9,  9,  9,  9,  9,
    7,  7,  5,  8,  9,  5,  12, 9,  5,  5,  5,  9,  5,
};

fn opn(op: i32, l_: i32, r_: i32) i32 {
    var l = l_;
    var r = r_;
    if (l < r) {
        const t = l;
        l = r;
        r = t;
    }
    switch (op) {
        Omul => {
            if (2 <= l)
                if (r == 0) {
                    return 3;
                };
            return 2;
        },
        Oadd => return Oaddtbl[@intCast(@divTrunc(l + l * l, 2) + r)],
        else => return 2,
    }
}

fn refn(r: Ref, tn: [*c]Num, con: [*c]Con) i32 {
    switch (rtype(r)) {
        RTmp => {
            if (tn[r.val].n == 0)
                tn[r.val].n = 2;
            return tn[r.val].n;
        },
        RCon => {
            if (con[r.val].type != CBits)
                return 1;
            const n = con[r.val].bits.i;
            if (n == 8 or n == 4 or n == 2 or n == 1)
                return 0;
            return 1;
        },
        else => return std.math.minInt(i32),
    }
}

const match = blk: {
    var m: [13]bits = @splat(0);
    m[4] = BIT(Pob);
    m[5] = BIT(Pbi1);
    m[6] = BIT(Pob) | BIT(Pois);
    m[7] = BIT(Pob) | BIT(Pobi1);
    m[8] = BIT(Pbi1) | BIT(Pbis);
    m[9] = BIT(Pbi1) | BIT(Pobi1);
    m[10] = BIT(Pbi1) | BIT(Pbis) | BIT(Pobi1) | BIT(Pobis);
    m[11] = BIT(Pob) | BIT(Pobi1) | BIT(Pobis);
    m[12] = BIT(Pbi1) | BIT(Pobi1) | BIT(Pobis);
    break :blk m;
};

const matcher = blk: {
    var m: [6][*c]const uchar = undefined;
    m[Pbi1] = &[_]uchar{
        1, 3, 1, 3, 2, 0,
    };
    m[Pbis] = &[_]uchar{
        5, 1, 8, 5, 27, 1, 5, 1, 2, 5, 13, 3, 1, 1, 3, 3, 3, 2, 0, 1,
        3, 3, 3, 2, 3,  1, 0, 1, 29,
    };
    m[Pob] = &[_]uchar{
        1, 3, 0, 3, 1, 0,
    };
    m[Pobi1] = &[_]uchar{
        5,  3, 9, 9, 10, 33, 12, 35, 45, 1, 5, 3, 11, 9, 7, 9, 4, 9,
        17, 1, 3, 0, 3,  1,  3,  2,  0,  3, 1, 1, 3,  0, 34, 1, 37, 1,
        5,  2, 5, 7, 2,  7,  8,  37, 29, 1, 3, 0, 1,  32,
    };
    m[Pobis] = &[_]uchar{
        5, 2, 10, 7, 11, 19, 49, 1, 1, 3, 3, 3, 2, 1, 3, 0, 3, 1, 0,
        1, 3, 0,  5, 1,  8,  5,  25, 1, 5, 1, 2, 5, 13, 3, 1, 1, 3, 3, 3,
        2, 0, 1,  3, 3,  3,  2,  26, 1, 51, 1, 5, 1, 6, 5, 9, 1, 3, 0, 51,
        3, 1, 1,  3, 0,  45,
    };
    m[Pois] = &[_]uchar{
        1, 3, 0, 1, 3, 3, 3, 2, 0,
    };
    break :blk m;
};

// end of generated code

fn anumber(tn: [*c]Num, b: *Blk, con: [*]Con) void {
    for (b.ins[0..b.nins]) |*i| {
        if (rtype(i.to) != RTmp)
            continue;
        const n = &tn[i.to.val];
        n.*.l = i.arg[0];
        n.*.r = i.arg[1];
        n.*.nl = @truncate(@as(u32, @bitCast(refn(n.*.l, tn, con))));
        n.*.nr = @truncate(@as(u32, @bitCast(refn(n.*.r, tn, con))));
        n.*.n = @truncate(@as(u32, @bitCast(opn(@intCast(i.op), n.*.nl, n.*.nr))));
    }
}

fn adisp(c: *Con, tn: [*c]Num, r_: Ref, f: *Fn, s: i32) Ref {
    var v: [2]Ref = undefined;
    var r = r_;

    while (!req(r, R)) {
        assert(rtype(r) == RTmp);
        const n = refn(r, tn, f.con);
        if ((match[@intCast(n)] & BIT(Pob)) == 0)
            break;
        runmatch(matcher[Pob], tn, r, &v);
        assert(rtype(v[0]) == RCon);
        _ = addcon(c, &f.con[v[0].val], s);
        r = v[1];
    }
    return r;
}

const pat = [_]i32{ Pobis, Pobi1, Pbis, Pois, Pbi1, -1 };

fn amatch(a: [*c]Addr, tn: [*c]Num, r: Ref, f: *Fn) bool {
    var v: [4]Ref = undefined;
    var co: Con = undefined;

    if (rtype(r) != RTmp)
        return false;

    const n = refn(r, tn, f.con);
    v = @splat(std.mem.zeroes(Ref));
    var p: usize = 0;
    while (pat[p] >= 0) : (p += 1) {
        if ((match[@intCast(n)] & BIT(pat[p])) != 0) {
            runmatch(matcher[@intCast(pat[p])], tn, r, &v);
            break;
        }
    }
    if (pat[p] < 0)
        v[1] = r;

    co = std.mem.zeroes(Con);
    const ro = v[0];
    const rb = adisp(&co, tn, v[1], f, 1);
    var ri = v[2];
    const rs = v[3];
    var s: i32 = 1;

    if (pat[p] < 0 and co.type != CUndef)
        if (amatch(a, tn, rb, f))
            return addcon(&a.*.offset, &co, 1);
    if (!req(ro, R)) {
        assert(rtype(ro) == RCon);
        const c = &f.con[ro.val];
        if (!addcon(&co, c, 1))
            return false;
    }
    if (!req(rs, R)) {
        assert(rtype(rs) == RCon);
        const c = &f.con[rs.val];
        assert(c.*.type == CBits);
        s = @truncate(c.*.bits.i);
    }
    ri = adisp(&co, tn, ri, f, s);
    a.* = .{ .offset = co, .base = rb, .index = ri, .scale = s };

    if (rtype(ri) == RTmp)
        if (f.tmp[ri.val].slot != -1) {
            if (a.*.scale != 1 or
                f.tmp[rb.val].slot != -1)
                return false;
            a.*.base = ri;
            a.*.index = rb;
        };
    if (!req(a.*.base, R)) {
        assert(rtype(a.*.base) == RTmp);
        s = f.tmp[a.*.base.val].slot;
        if (s != -1)
            a.*.base = SLOT(s);
    }
    return true;
}

/// instruction selection
/// requires use counts (as given by parsing)
pub fn amd64_isel(f: *Fn) void {
    // assign slots to fast allocs
    var b = f.start;
    // specific to NAlign == 3
    // or change n=4 and sz /= 4 below
    var al: i32 = Oalloc;
    var n: i32 = 4;
    while (al <= Oalloc1) : ({
        al += 1;
        n *= 2;
    }) {
        var i = b.*.ins;
        while (i < b.*.ins + b.*.nins) : (i += 1) {
            if (i.*.op == al) {
                if (rtype(i.*.arg[0]) != RCon)
                    break;
                var sz = f.con[i.*.arg[0].val].bits.i;
                if (sz < 0 or sz >= std.math.maxInt(i32) - 15)
                    err("invalid alloc size {d}", .{sz});
                sz = (sz + n - 1) & -@as(i64, n);
                sz = @divTrunc(sz, 4);
                if (sz > std.math.maxInt(i32) - f.slot)
                    die("alloc too large", .{});
                f.tmp[i.*.to.val].slot = f.slot;
                f.slot += @intCast(sz);
                f.salign = 2 + al - Oalloc;
                i.* = INS0(Onop);
            }
        }
    }

    // process basic blocks
    n = f.ntmp;
    const num: [*c]Num = ealloc(Num, n);
    b = f.start;
    while (b != null) : (b = b.*.link) {
        all.curi = all.insbEnd();
        const sb = [3][*c]Blk{ b.*.s1, b.*.s2, null };
        var si: usize = 0;
        while (sb[si] != null) : (si += 1) {
            var p = sb[si].*.phi;
            while (p != null) : (p = p.*.link) {
                var a: uint = 0;
                while (p.*.blk[a] != b) : (a += 1)
                    assert(a + 1 < p.*.narg);
                fixarg(&p.*.arg[a], p.*.cls, null, f);
            }
        }
        if (n != 0) @memset(num[0..@intCast(n)], std.mem.zeroes(Num));
        anumber(num, b, f.con);
        seljmp(b, f);
        var i = b.*.ins + b.*.nins;
        while (i != b.*.ins) {
            i -= 1;
            assert(i.*.op != Osel0);
            if (i.*.op == Osel1)
                i = selsel(f, b, i, num)
            else
                sel(i.*, num, f);
        }
        idup(b, all.curi, @intCast(ptrdiff(all.insbEnd(), all.curi)));
    }
    efree(@ptrCast(num));

    if (all.debug['I'] != 0) {
        dprint("\n> After instruction selection:\n", .{});
        printfn(f, all.dbg) catch {};
    }
}
