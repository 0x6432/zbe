//! One-to-one translation of amd64/isel.c
const std = @import("std");
const assert = std.debug.assert;
// -- imports --
const all = @import("../all.zig");
const Cls = all.Cls;
const J = all.J;
const Opc = all.Opc;
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
const KBASE = all.KBASE;
const KWIDE = all.KWIDE;
const MEM = all.MEM;
const NCmpI = all.NCmpI;
const Num = all.Num;
const Phi = all.Phi;
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

fn hascon(r: Ref, pc: **Con, f: *Fn) bool {
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

/// i is the instruction r belongs to (null for phi arguments)
fn fixarg(r: *Ref, k: i32, i: ?*Ins, f: *Fn) void {
    var buf: [32]u8 = undefined;
    var a: Addr = undefined;
    var cc: Con = undefined;
    var c: *Con = undefined;

    var r0 = r.*;
    var r1 = r0;
    const s = rslot(r0, f);
    const op: i32 = if (i) |ii| all.ops.num(ii.op) else all.ops.num(.copy);
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
        a.offset.sym.id = intern(@ptrCast(&buf));
        f.mem[@intCast(f.nmem - 1)] = a;
    } else if (op == Opc.call.int() and r == &i.?.arg[0] and
        rtype(r0) == RCon and f.con[r0.val].type != CAddr)
    {
        // use a temporary register so that we
        // produce an indirect call
        r1 = newtmp("isel", .l, f);
        emit(.copy, .l, r1, r0, R);
    } else if (op != Opc.copy.int() and k == Cls.l.int() and noimm(r0, f)) {
        // load constants that do not fit in
        // a 32bit signed integer into a
        // long temporary
        r1 = newtmp("isel", .l, f);
        emit(.copy, .l, r1, r0, R);
    } else if (s != -1) {
        // load fast locals' addresses into
        // temporaries right before the
        // instruction
        r1 = newtmp("isel", .l, f);
        emit(.addr, .l, r1, SLOT(s), R);
    } else if (op != Opc.call.int() and hascon(r0, &c, f) and
        c.type == CAddr and ((c.sym.type & SExt) != 0 or
        (all.T.apple != 0 and c.sym.type == SThr)))
    {
        r1 = newtmp("isel", .l, f);
        var r2: Ref = undefined;
        var r3: Ref = undefined;
        if (c.bits.i != 0) {
            r2 = newtmp("isel", .l, f);
            cc = std.mem.zeroes(Con);
            cc.type = CBits;
            cc.bits.i = c.bits.i;
            r3 = newcon(&cc, f);
            emit(.add, .l, r1, r2, r3);
        } else r2 = r1;
        if (all.T.apple != 0 and (c.sym.type & SThr) != 0) {
            emit(.copy, .l, r2, TMP(RAX), R);
            r2 = newtmp("isel", .l, f);
            r3 = newtmp("isel", .l, f);
            emit(.call, 0, R, r3, CALL(17));
            emit(.copy, .l, TMP(RDI), r2, R);
            emit(.load, .l, r3, r2, R);
        }
        cc = c.*;
        cc.bits.i = 0;
        r3 = newcon(&cc, f);
        emit(.addr, .l, r2, r3, R);
        if (rtype(r0) == RMem) {
            const m = &f.mem[r0.val];
            m.offset.type = CUndef;
            m.base = r1;
            r1 = r0;
        }
    } else if (!(isstore(op) and r == &i.?.arg[1]) and
        !isload(op) and op != Opc.call.int() and rtype(r0) == RCon and
        f.con[r0.val].type == CAddr)
    {
        // turn address operands into
        // lea/mov instructions
        r1 = newtmp("isel", .l, f);
        emit(.addr, .l, r1, r0, R);
    } else if (rtype(r0) == RMem) {
        // eliminate memory operands of
        // the form $foo(%rip, ...)
        const m = &f.mem[r0.val];
        if (req(m.base, R))
            if (m.offset.type == CAddr) {
                r0 = newtmp("isel", .l, f);
                emit(.addr, .l, r0, newcon(&m.offset, f), R);
                m.offset.type = CUndef;
                m.base = r0;
            };
    } else if (isxsel(op) and rtype(r.*) == RCon) {
        r1 = newtmp("isel", i.?.cls, f);
        emit(.copy, i.?.cls, r1, r.*, R);
    }
    r.* = r1;
}

fn seladdr(r: *Ref, tn: [*]Num, f: *Fn) void {
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

fn cmpswap(arg: *const [2]Ref, op: i32) bool {
    switch (op) {
        NCmpI + Cflt, NCmpI + Cfle => return true,
        NCmpI + Cfgt, NCmpI + Cfge => return false,
        else => {},
    }
    return rtype(arg[0]) == RCon;
}

fn selcmp(arg: *[2]Ref, k: i32, swap: bool, f: *Fn) void {
    if (swap) {
        const r = arg[1];
        arg[1] = arg[0];
        arg[0] = r;
    }
    emit(.xcmp, k, R, arg[1], arg[0]);
    const icmp = &all.curi[0];
    if (rtype(arg[0]) == RCon) {
        assert(k != Cls.w.int());
        icmp.arg[1] = newtmp("isel", k, f);
        emit(.copy, k, icmp.arg[1], arg[0], R);
        fixarg(&all.curi[0].arg[0], k, &all.curi[0], f);
    }
    fixarg(&icmp.arg[0], k, icmp, f);
    fixarg(&icmp.arg[1], k, icmp, f);
}

fn sel(i_: Ins, tn: ?[*]Num, f: *Fn) void {
    var i = i_;
    var r0: Ref = undefined;
    var r1: Ref = undefined;
    var tmp: [7]Ref = undefined;
    var x: i32 = undefined;
    var kc: i32 = undefined;
    var i_1: *Ins = undefined;

    if (rtype(i.to) == RTmp)
        if (!isreg(i.to) and !isreg(i.arg[0]) and !isreg(i.arg[1]))
            if (f.tmp[i.to.val].nuse == 0) {
                chuse(i.arg[0], -1, f);
                chuse(i.arg[1], -1, f);
                return;
            };
    const i_0 = all.curi;
    const k: i32 = all.knum(i.cls);
    sw: switch (i.op) {
        .div, .rem, .udiv, .urem => {
            if (KBASE(k) == 1)
                continue :sw .copy; // goto Emit
            if (i.op == .div or i.op == .udiv) {
                r0 = TMP(RAX);
                r1 = TMP(RDX);
            } else {
                r0 = TMP(RDX);
                r1 = TMP(RAX);
            }
            emit(.copy, k, i.to, r0, R);
            emit(.copy, k, R, r1, R);
            if (rtype(i.arg[1]) == RCon) {
                // immediates not allowed for
                // divisions in x86
                r0 = newtmp("isel", k, f);
            } else r0 = i.arg[1];
            if (f.tmp[r0.val].slot != -1)
                err("unlikely argument %{s} in {s}", .{cs(f.tmp[r0.val].name), cs(all.optab[i.op.int()].name)});
            if (i.op == .div or i.op == .rem) {
                emit(.xidiv, k, R, r0, R);
                emit(.sign, k, TMP(RDX), TMP(RAX), R);
            } else {
                emit(.xdiv, k, R, r0, R);
                emit(.copy, k, TMP(RDX), CON_Z, R);
            }
            emit(.copy, k, TMP(RAX), i.arg[0], R);
            fixarg(&all.curi[0].arg[0], k, &all.curi[0], f);
            if (rtype(i.arg[1]) == RCon)
                emit(.copy, k, r0, i.arg[1], R);
        },
        .sar, .shr, .shl => {
            r0 = i.arg[1];
            if (rtype(r0) == RCon) {
                // x86 masks the count; an immediate >= width does not assemble
                const c = &f.con[r0.val];
                if (c.type == CBits) {
                    const m: i64 = if (k == Cls.w.int()) 31 else 63;
                    if (c.bits.i & m != c.bits.i)
                        i.arg[1] = getcon(c.bits.i & m, f);
                }
                continue :sw .copy; // goto Emit
            }
            if (f.tmp[r0.val].slot != -1)
                err("unlikely argument %{s} in {s}", .{cs(f.tmp[r0.val].name), cs(all.optab[i.op.int()].name)});
            i.arg[1] = TMP(RCX);
            emit(.copy, .w, R, TMP(RCX), R);
            emiti(i);
            i_1 = &all.curi[0];
            emit(.copy, .w, TMP(RCX), r0, R);
            fixarg(&i_1.arg[0], argcls(&i, 0), i_1, f);
        },
        .uwtof => {
            r0 = newtmp("utof", .l, f);
            emit(.sltof, k, i.to, r0, R);
            emit(.extuw, .l, r0, i.arg[0], R);
            fixarg(&all.curi[0].arg[0], k, &all.curi[0], f);
        },
        .ultof => {
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
            if (k == Cls.s.int()) {
                kc = all.knum(.w);
                sh = 23;
            } else {
                kc = all.knum(.l);
                sh = 52;
            }
            var j: usize = 0;
            while (j < 4) : (j += 1)
                tmp[j] = newtmp("utof", .l, f);
            while (j < 7) : (j += 1)
                tmp[j] = newtmp("utof", kc, f);
            emit(.cast, k, i.to, tmp[6], R);
            emit(.add, kc, tmp[6], tmp[4], tmp[5]);
            emit(.shl, kc, tmp[5], tmp[1], getcon(sh, f));
            emit(.cast, kc, tmp[4], r0, R);
            emit(.sltof, k, r0, tmp[3], R);
            emit(.@"or", .l, tmp[3], tmp[0], tmp[2]);
            emit(.shr, .l, tmp[2], i.arg[0], tmp[1]);
            const ci = &all.curi[0];
            all.curi += 1;
            sel(ci.*, null, f);
            emit(.shr, .l, tmp[1], i.arg[0], getcon(63, f));
            fixarg(&all.curi[0].arg[0], all.knum(.l), &all.curi[0], f);
            emit(.@"and", .l, tmp[0], i.arg[0], getcon(1, f));
            fixarg(&all.curi[0].arg[0], all.knum(.l), &all.curi[0], f);
        },
        .stoui, .dtoui => {
            if (i.op == .stoui) {
                i.op = .stosi;
                kc = all.knum(.s);
                tmp[4] = getcon(0xdf000000, f);
            } else {
                i.op = .dtosi;
                kc = all.knum(.d);
                tmp[4] = getcon(@bitCast(@as(u64, 0xc3e0000000000000)), f);
            }
            // Oftoui:
            if (k == Cls.w.int()) {
                r0 = newtmp("ftou", .l, f);
                emit(.copy, .w, i.to, r0, R);
                i.cls = .l;
                i.to = r0;
                continue :sw .copy; // goto Emit
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
                tmp[j] = newtmp("ftou", .l, f);
            emit(.@"or", .l, i.to, tmp[0], tmp[3]);
            emit(.@"and", .l, tmp[3], tmp[2], tmp[1]);
            emit(i.op, .l, tmp[2], r0, R);
            emit(.add, kc, r0, tmp[4], i.arg[0]);
            i_1 = &all.curi[0]; // fixarg() can change curi
            fixarg(&i_1.arg[0], kc, i_1, f);
            fixarg(&i_1.arg[1], kc, i_1, f);
            emit(.sar, .l, tmp[1], tmp[0], getcon(63, f));
            emit(i.op, .l, tmp[0], i.arg[0], R);
            fixarg(&all.curi[0].arg[0], all.knum(.l), &all.curi[0], f);
        },
        .nop => {},
        .stored, .stores, .storel, .storew, .storeh, .storeb => {
            if (rtype(i.arg[0]) == RCon) {
                if (i.op == .stored)
                    i.op = .storel;
                if (i.op == .stores)
                    i.op = .storew;
            }
            seladdr(&i.arg[1], tn.?, f);
            continue :sw .copy; // goto Emit
        },
        .dbgloc, .call, .salloc, .copy, .add, .sub, .neg, .mul, .@"and", .@"or", .xor, .xtest, .stosi, .dtosi, .swtof, .sltof, .exts, .truncd, .cast => {
            // Emit:
            emiti(i);
            i_1 = &all.curi[0]; // fixarg() can change curi
            fixarg(&i_1.arg[0], argcls(&i, 0), i_1, f);
            fixarg(&i_1.arg[1], argcls(&i, 1), i_1, f);
        },
        .alloc4, .alloc8, .alloc16 => salloc(i.to, i.arg[0], f),
        else => {
            if (isext(i.op))
                continue :sw .copy; // goto case_Oext
            if (isxsel(i.op))
                continue :sw .copy; // goto case_Oxsel
            if (isload(i.op)) {
                // case_Oload:
                seladdr(&i.arg[0], tn.?, f);
                continue :sw .copy; // goto Emit
            }
            if (iscmp(i.op, &kc, &x)) {
                switch (x) {
                    NCmpI + Cfeq => {
                        // zf is set when operands are
                        // unordered, so we may have to
                        // check pf
                        r0 = newtmp("isel", .w, f);
                        r1 = newtmp("isel", .w, f);
                        emit(.@"and", .w, i.to, r0, r1);
                        emit(.flagfo, k, r1, R, R);
                        i.to = r0;
                    },
                    NCmpI + Cfne => {
                        r0 = newtmp("isel", .w, f);
                        r1 = newtmp("isel", .w, f);
                        emit(.@"or", .w, i.to, r0, r1);
                        emit(.flagfuo, k, r1, R, R);
                        i.to = r0;
                    },
                    else => {},
                }
                const swap = cmpswap(&i.arg, x);
                if (swap)
                    x = cmpop(x);
                emit(Opc.flag_first.offset(x), k, i.to, R, R);
                selcmp(&i.arg, kc, swap, f);
                break :sw;
            }
            die("unknown instruction {s}", .{cs(all.optab[i.op.int()].name)});
        },
    }

    for (all.curi[0 .. i_0 - all.curi]) |*ii| {
        assert(rslot(ii.arg[0], f) == -1);
        assert(rslot(ii.arg[1], f) == -1);
    }
}

/// finds the instruction setting the flags used at
/// the end of ins, if any
fn flagi(ins: []Ins) ?*Ins {
    var n = ins.len;
    while (n > 0) {
        n -= 1;
        const i = &ins[n];
        if (amd64_op[i.op.int()].zflag != 0)
            return i;
        if (amd64_op[i.op.int()].lflag != 0)
            continue;
        return null;
    }
    return null;
}

/// selects the sel0/sel1 group ending at b.ins[n1];
/// returns the index of its sel0
fn selsel(f: *Fn, b: *Blk, n1: uint, tn: [*]Num) uint {
    var cr: [2]Ref = undefined;

    assert(b.ins[n1].op == .sel1);
    var n0 = n1;
    while (0 < n0) : (n0 -= 1) {
        if (b.ins[n0].op == .sel0)
            break;
        assert(b.ins[n0].op == .sel1);
    }
    const isel0 = &b.ins[n0];
    assert(isel0.op == .sel0);
    var r = isel0.arg[0];
    assert(rtype(r) == RTmp);
    const t = &f.tmp[r.val];
    const fi_ = flagi(b.ins[0..n0]);
    cr[0] = R;
    cr[1] = R;
    var gencmp = false;
    var gencpy = false;
    var swap = false;
    var k: i32 = all.knum(.w);
    var c: i32 = Cine;
    var other = false;
    if (fi_ == null or !req(fi_.?.to, r)) {
        gencmp = true;
        cr[0] = r;
        cr[1] = CON_Z;
    } else {
        const fi = fi_.?;
        if (iscmp(fi.op, &k, &c)) {
            if (c == NCmpI + Cfeq or
                c == NCmpI + Cfne)
            {
                // these are selected as 'and'
                // or 'or', so we check their
                // result with Cine
                c = Cine;
                other = true;
            } else {
                swap = cmpswap(&fi.arg, c);
                if (swap)
                    c = cmpop(c);
                if (t.nuse == 1) {
                    gencmp = true;
                    cr[0] = fi.arg[0];
                    cr[1] = fi.arg[1];
                    fi.* = INS0(.nop);
                }
            }
        } else if (fi.op == .@"and" and t.nuse == 1 and
            (rtype(fi.arg[0]) == RTmp or
            rtype(fi.arg[1]) == RTmp))
        {
            fi.op = .xtest;
            fi.to = R;
            if (rtype(fi.arg[1]) == RCon) {
                r = fi.arg[1];
                fi.arg[1] = fi.arg[0];
                fi.arg[0] = r;
            }
        } else {
            other = true;
        }
    }
    if (other) {
        // since flags are not tracked in liveness,
        // the result of the flag-setting instruction
        // has to be marked as live
        if (t.nuse == 1)
            gencpy = true;
    }
    // generate conditional moves
    var k1 = n1;
    while (n0 < k1) : (k1 -= 1) {
        const isel1 = &b.ins[k1];
        isel1.op = Opc.xsel_first.offset(c);
        sel(isel1.*, tn, f);
    }
    assert(!gencmp or !gencpy);
    if (gencmp)
        selcmp(&cr, k, swap, f);
    if (gencpy)
        emit(.copy, .w, R, r, R);
    isel0.* = INS0(.nop);
    return n0;
}

fn seljmp(b: *Blk, f: *Fn) void {
    var k: i32 = undefined;
    var c: i32 = undefined;

    if (b.jmp.type == .ret0 or
        b.jmp.type == .jmp or
        b.jmp.type == .hlt)
        return;
    assert(b.jmp.type == .jnz);
    var r = b.jmp.arg;
    const t = &f.tmp[r.val];
    b.jmp.arg = R;
    assert(rtype(r) == RTmp);
    if (b.s1 == b.s2) {
        chuse(r, -1, f);
        b.jmp.type = .jmp;
        b.s2 = null;
        return;
    }
    const fi_ = flagi(b.ins[0..b.nins]);
    if (fi_ == null or !req(fi_.?.to, r)) {
        var cr = [2]Ref{ r, CON_Z };
        selcmp(&cr, all.knum(.w), false, f);
        b.jmp.type = J.jf_first.add(Cine);
        return;
    }
    const fi = fi_.?;
    if (iscmp(fi.op, &k, &c) and
        c != NCmpI + Cfeq and // see sel(), selsel()
        c != NCmpI + Cfne)
    {
        const swap = cmpswap(&fi.arg, c);
        if (swap)
            c = cmpop(c);
        if (t.nuse == 1) {
            selcmp(&fi.arg, k, swap, f);
            fi.* = INS0(.nop);
        }
        b.jmp.type = J.jf_first.add(c);
    } else if (fi.op == .@"and" and t.nuse == 1 and
        (rtype(fi.arg[0]) == RTmp or
        rtype(fi.arg[1]) == RTmp))
    {
        fi.op = .xtest;
        fi.to = R;
        b.jmp.type = J.jf_first.add(Cine);
        if (rtype(fi.arg[1]) == RCon) {
            r = fi.arg[1];
            fi.arg[1] = fi.arg[0];
            fi.arg[0] = r;
        }
    } else {
        // since flags are not tracked in liveness,
        // the result of the flag-setting instruction
        // has to be marked as live
        if (t.nuse == 1)
            emit(.copy, .w, R, r, R);
        b.jmp.type = J.jf_first.add(Cine);
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
        all.ops.num(.mul) => {
            if (2 <= l)
                if (r == 0) {
                    return 3;
                };
            return 2;
        },
        all.ops.num(.add) => return Oaddtbl[@intCast(@divTrunc(l + l * l, 2) + r)],
        else => return 2,
    }
}

fn refn(r: Ref, tn: [*]Num, con: [*]const Con) i32 {
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
    var m: [6][]const uchar = undefined;
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

fn anumber(tn: [*]Num, b: *Blk, con: [*]Con) void {
    for (b.ins[0..b.nins]) |*i| {
        if (rtype(i.to) != RTmp)
            continue;
        const n = &tn[i.to.val];
        n.l = i.arg[0];
        n.r = i.arg[1];
        n.nl = @truncate(@as(u32, @bitCast(refn(n.l, tn, con))));
        n.nr = @truncate(@as(u32, @bitCast(refn(n.r, tn, con))));
        n.n = @truncate(@as(u32, @bitCast(opn(all.ops.num(i.op), n.nl, n.nr))));
    }
}

fn adisp(c: *Con, tn: [*]Num, r_: Ref, f: *Fn, s: i32) Ref {
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

fn amatch(a: ?*Addr, tn: [*]Num, r: Ref, f: *Fn) bool {
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
            return addcon(&a.?.offset, &co, 1);
    if (!req(ro, R)) {
        assert(rtype(ro) == RCon);
        const c = &f.con[ro.val];
        if (!addcon(&co, c, 1))
            return false;
    }
    if (!req(rs, R)) {
        assert(rtype(rs) == RCon);
        const c = &f.con[rs.val];
        assert(c.type == CBits);
        s = @truncate(c.bits.i);
    }
    ri = adisp(&co, tn, ri, f, s);
    a.?.* = .{ .offset = co, .base = rb, .index = ri, .scale = s };

    if (rtype(ri) == RTmp)
        if (f.tmp[ri.val].slot != -1) {
            if (a.?.scale != 1 or
                f.tmp[rb.val].slot != -1)
                return false;
            a.?.base = ri;
            a.?.index = rb;
        };
    if (!req(a.?.base, R)) {
        assert(rtype(a.?.base) == RTmp);
        s = f.tmp[a.?.base.val].slot;
        if (s != -1)
            a.?.base = SLOT(s);
    }
    return true;
}

/// instruction selection
/// requires use counts (as given by parsing)
pub fn amd64_isel(f: *Fn) void {
    // assign slots to fast allocs
    const start = f.start.?;
    // specific to NAlign == 3
    // or change n=4 and sz /= 4 below
    var al: i32 = all.ops.num(Opc.alloc_first);
    var n: i32 = 4;
    while (al <= Opc.alloc_last.int()) : ({
        al += 1;
        n *= 2;
    }) {
        for (start.ins[0..start.nins]) |*i| {
            if (all.ops.num(i.op) == al) {
                if (rtype(i.arg[0]) != RCon)
                    break;
                var sz = f.con[i.arg[0].val].bits.i;
                if (sz < 0 or sz >= std.math.maxInt(i32) - 15)
                    err("invalid alloc size {d}", .{sz});
                sz = (sz + n - 1) & -@as(i64, n);
                sz = @divTrunc(sz, 4);
                if (sz > std.math.maxInt(i32) - f.slot)
                    die("alloc too large", .{});
                f.tmp[i.to.val].slot = f.slot;
                f.slot += @intCast(sz);
                f.salign = 2 + al - all.ops.num(Opc.alloc_first);
                i.* = INS0(.nop);
            }
        }
    }

    // process basic blocks
    n = f.ntmp;
    const num = ealloc(Num, n);
    var b_it = f.start;
    while (b_it) |b| : (b_it = b.link) {
        all.curi = all.insbEnd();
        for ([2]?*Blk{ b.s1, b.s2 }) |sb_| {
            const sb = sb_ orelse break;
            var p_it = sb.phi;
            while (p_it) |p| : (p_it = p.link) {
                var a: uint = 0;
                while (p.blk[a] != b) : (a += 1)
                    assert(a + 1 < p.narg);
                fixarg(&p.arg[a], all.knum(p.cls), null, f);
            }
        }
        if (n != 0) @memset(num[0..@intCast(n)], std.mem.zeroes(Num));
        anumber(num, b, f.con);
        seljmp(b, f);
        var k = b.nins;
        while (k != 0) {
            k -= 1;
            assert(b.ins[k].op != .sel0);
            if (b.ins[k].op == .sel1)
                k = selsel(f, b, k, num)
            else
                sel(b.ins[k], num, f);
        }
        idup(b, all.curi, (all.insbTail()));
    }
    efree((num));

    if (all.debug['I'] != 0) {
        dprint("\n> After instruction selection:\n", .{});
        printfn(f, all.dbg) catch {};
    }
}
