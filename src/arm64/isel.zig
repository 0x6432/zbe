//! One-to-one translation of arm64/isel.c
const std = @import("std");
const assert = std.debug.assert;
const C = @import("../libc.zig");
// -- imports --
const all = @import("../all.zig");
const tgt = @import("all.zig");
const Blk = all.Blk;
const CALL = all.CALL;
const CAddr = all.CAddr;
const CBits = all.CBits;
const CON = all.CON;
const CON_Z = all.CON_Z;
const Con = all.Con;
const Fn = all.Fn;
const INRANGE = all.INRANGE;
const INS0 = all.INS0;
const Ins = all.Ins;
const Jhlt = all.Jhlt;
const Jjf = all.Jjf;
const Jjfine = all.Jjfine;
const Jjmp = all.Jjmp;
const Jjnz = all.Jjnz;
const Jret0 = all.Jret0;
const KBASE = all.KBASE;
const KWIDE = all.KWIDE;
const Kl = all.Kl;
const Kw = all.Kw;
const Oacmn = all.ops.Oacmn;
const Oacmp = all.ops.Oacmp;
const Oadd = all.ops.Oadd;
const Oaddr = all.ops.Oaddr;
const Oafcmp = all.ops.Oafcmp;
const Oalloc = all.Oalloc;
const Oalloc1 = all.Oalloc1;
const Ocall = all.ops.Ocall;
const Ocopy = all.ops.Ocopy;
const Oflag = all.Oflag;
const Oload = all.ops.Oload;
const Onop = all.ops.Onop;
const R = all.R;
const R0 = tgt.R0;
const RCon = all.RCon;
const RTmp = all.RTmp;
const Ref = all.Ref;
const SExt = all.SExt;
const SLOT = all.SLOT;
const SThr = all.SThr;
const TMP = all.TMP;
const argcls = all.argcls;
const cmpop = all.cmpop;
const emit = all.emit;
const emiti = all.emiti;
const err = all.err;
const getcon = all.getcon;
const idup = all.idup;
const intern = all.intern;
const iscmp = all.iscmp;
const newcon = all.newcon;
const newtmp = all.newtmp;
const printfn = all.printfn;
const ptrdiff = all.ptrdiff;
const req = all.req;
const rtype = all.rtype;
const salloc = all.salloc;
const stashbits = all.stashbits;
const uint = all.uint;
const vgrow = all.vgrow;
// -- end imports --

const Iother = 0;
const Iplo12 = 1;
const Iphi12 = 2;
const Iplo24 = 3;
const Inlo12 = 4;
const Inhi12 = 5;
const Inlo24 = 6;

fn imm(c: [*c]Con, k: i32, pn: *i64) i32 {
    if (c.*.type != CBits)
        return Iother;
    var n = c.*.bits.i;
    if (k == Kw)
        n = @as(i32, @truncate(n));
    var i: i32 = Iplo12;
    if (n < 0) {
        i = Inlo12;
        n = @bitCast(0 -% @as(u64, @bitCast(n)));
    }
    pn.* = n;
    if ((n & 0x000fff) == n)
        return i;
    if ((n & 0xfff000) == n)
        return i + 1;
    if ((n & 0xffffff) == n)
        return i + 2;
    return Iother;
}

pub fn arm64_logimm(x_: u64, k: i32) bool {
    var x = x_;
    if (k == Kw)
        x = (x & 0xffffffff) | x << 32;
    if ((x & 1) != 0)
        x = ~x;
    if (x == 0)
        return false;
    if (x == 0xaaaaaaaaaaaaaaaa)
        return true;
    const n: u64 = blk: {
        var n = x & 0xf;
        if (0x1111111111111111 *% n == x)
            break :blk n;
        n = x & 0xff;
        if (0x0101010101010101 *% n == x)
            break :blk n;
        n = x & 0xffff;
        if (0x0001000100010001 *% n == x)
            break :blk n;
        n = x & 0xffffffff;
        if (0x0000000100000001 *% n == x)
            break :blk n;
        break :blk x;
    };
    // Check:
    return (n & (n +% (n & (0 -% n)))) == 0;
}

fn fixarg(pr: [*c]Ref, k: i32, phi: bool, f: [*c]Fn) void {
    var buf: [32]u8 = undefined;
    var cc: Con = undefined;
    var r1: Ref = undefined;
    var r2: Ref = undefined;
    var r3: Ref = undefined;

    const r0 = pr.*;
    switch (rtype(r0)) {
        RCon => {
            var c: [*c]Con = &f.*.con[r0.val];
            if (c.*.type == CAddr and ((c.*.sym.type & SExt) != 0 or
                (all.T.apple != 0 and (c.*.sym.type & SThr) != 0)))
            {
                r1 = newtmp("isel", Kl, f);
                pr.* = r1;
                if (c.*.bits.i != 0) {
                    r2 = newtmp("isel", Kl, f);
                    cc = std.mem.zeroes(Con);
                    cc.type = CBits;
                    cc.bits.i = c.*.bits.i;
                    r3 = newcon(&cc, f);
                    emit(Oadd, Kl, r1, r2, r3);
                    r1 = r2;
                }
                if (all.T.apple != 0 and (c.*.sym.type & SThr) != 0) {
                    emit(Ocopy, Kl, r1, TMP(R0), R);
                    r1 = newtmp("isel", Kl, f);
                    r2 = newtmp("isel", Kl, f);
                    emit(Ocall, 0, R, r1, CALL(33));
                    emit(Ocopy, Kl, TMP(R0), r2, R);
                    emit(Oload, Kl, r1, r2, R);
                    r1 = r2;
                }
                cc = c.*;
                cc.bits.i = 0;
                r3 = newcon(&cc, f);
                emit(Ocopy, Kl, r1, r3, R);
                return;
            }
            if (KBASE(k) == 0 and phi)
                return;
            r1 = newtmp("isel", k, f);
            if (KBASE(k) == 0) {
                emit(Ocopy, k, r1, r0, R);
            } else {
                const n = stashbits(@bitCast(c.*.bits.i), if (KWIDE(k) != 0) 8 else 4);
                f.*.ncon += 1;
                vgrow(&f.*.con, f.*.ncon);
                c = &f.*.con[@intCast(f.*.ncon - 1)];
                _ = C.sprintf(&buf, "\"%sfp%d\"", &all.T.asloc, @as(c_int, n));
                c.* = std.mem.zeroes(Con);
                c.*.type = CAddr;
                c.*.sym.id = intern(&buf);
                r2 = newtmp("isel", Kl, f);
                emit(Oload, k, r1, r2, R);
                emit(Ocopy, Kl, r2, CON(ptrdiff(c, f.*.con)), R);
            }
            pr.* = r1;
        },
        RTmp => {
            const s = f.*.tmp[r0.val].slot;
            if (s == -1)
                return;
            r1 = newtmp("isel", Kl, f);
            emit(Oaddr, Kl, r1, SLOT(s), R);
            pr.* = r1;
        },
        else => {},
    }
}

fn selcmp(arg: [*c]Ref, k: i32, f: [*c]Fn) bool {
    var n: i64 = undefined;

    if (KBASE(k) == 1) {
        emit(Oafcmp, k, R, arg[0], arg[1]);
        const iarg: [*c]Ref = &all.curi.*.arg;
        fixarg(&iarg[0], k, false, f);
        fixarg(&iarg[1], k, false, f);
        return false;
    }
    const swap = rtype(arg[0]) == RCon;
    if (swap) {
        const r = arg[1];
        arg[1] = arg[0];
        arg[0] = r;
    }
    var fix = true;
    var cmp: i32 = Oacmp;
    var r = arg[1];
    if (rtype(r) == RCon) {
        const c = &f.*.con[r.val];
        switch (imm(c, k, &n)) {
            else => {},
            Iplo12, Iphi12 => fix = false,
            Inlo12, Inhi12 => {
                cmp = Oacmn;
                r = getcon(n, f);
                fix = false;
            },
        }
    }
    emit(cmp, k, R, arg[0], r);
    const iarg: [*c]Ref = &all.curi.*.arg;
    fixarg(&iarg[0], k, false, f);
    if (fix)
        fixarg(&iarg[1], k, false, f);
    return swap;
}

fn callable(r: Ref, f: [*c]Fn) bool {
    if (rtype(r) == RTmp)
        return true;
    if (rtype(r) == RCon) {
        const c = &f.*.con[r.val];
        if (c.*.type == CAddr and c.*.bits.i == 0)
            return true;
    }
    return false;
}

fn sel(i_: Ins, f: [*c]Fn) void {
    var i = i_;
    var ck: i32 = undefined;
    var cc: i32 = undefined;

    if (INRANGE(i.op, Oalloc, Oalloc1)) {
        const i_0 = all.curi - 1;
        salloc(i.to, i.arg[0], f);
        fixarg(&i_0.*.arg[0], Kl, false, f);
        return;
    }
    if (iscmp(i.op, &ck, &cc)) {
        emit(Oflag, i.cls, i.to, R, R);
        const i_0 = all.curi;
        if (selcmp(&i.arg, ck, f))
            i_0.*.op += @intCast(cmpop(cc))
        else
            i_0.*.op += @intCast(cc);
        return;
    }
    if (i.op == Ocall and callable(i.arg[0], f)) {
        emiti(i);
        return;
    }
    if (i.op != Onop) {
        emiti(i);
        const iarg: [*c]Ref = &all.curi.*.arg; // fixarg() can change curi
        fixarg(&iarg[0], argcls(&i, 0), false, f);
        fixarg(&iarg[1], argcls(&i, 1), false, f);
    }
}

fn seljmp(b: [*c]Blk, f: [*c]Fn) void {
    var ck: i32 = undefined;
    var cc: i32 = undefined;

    if (b.*.jmp.type == Jret0 or
        b.*.jmp.type == Jjmp or
        b.*.jmp.type == Jhlt)
        return;
    assert(b.*.jmp.type == Jjnz);
    const r = b.*.jmp.arg;
    var use: i32 = -1;
    b.*.jmp.arg = R;
    var ir: [*c]Ins = null;
    var i = b.*.ins + b.*.nins;
    while (i > b.*.ins) {
        i -= 1;
        if (req(i.*.to, r)) {
            use = @intCast(f.*.tmp[r.val].nuse);
            ir = i;
            break;
        }
    }
    if (ir != null and use == 1 and iscmp(ir.*.op, &ck, &cc)) {
        if (selcmp(&ir.*.arg, ck, f))
            cc = cmpop(cc);
        b.*.jmp.type = @intCast(Jjf + cc);
        ir.* = INS0(Onop);
    } else {
        var a = [2]Ref{ r, CON_Z };
        _ = selcmp(&a, Kw, f);
        b.*.jmp.type = Jjfine;
    }
}

pub fn arm64_isel(f: [*c]Fn) void {
    // assign slots to fast allocs
    var b = f.*.start;
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
                var sz = f.*.con[i.*.arg[0].val].bits.i;
                if (sz < 0 or sz >= std.math.maxInt(i32) - 15)
                    err("invalid alloc size %ld", .{@as(c_long, sz)});
                sz = (sz + n - 1) & -@as(i64, n);
                sz = @divTrunc(sz, 4);
                f.*.tmp[i.*.to.val].slot = f.*.slot;
                f.*.slot += @intCast(sz);
                i.* = INS0(Onop);
            }
        }
    }

    b = f.*.start;
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
                fixarg(&p.*.arg[a], p.*.cls, true, f);
            }
        }
        seljmp(b, f);
        var i = b.*.ins + b.*.nins;
        while (i != b.*.ins) {
            i -= 1;
            sel(i.*, f);
        }
        idup(b, all.curi, @intCast(ptrdiff(all.insbEnd(), all.curi)));
    }

    if (all.debug['I'] != 0) {
        _ = C.fprintf(C.stderr, "\n> After instruction selection:\n");
        printfn(f, C.stderr);
    }
}
