//! One-to-one translation of rv64/isel.c
const std = @import("std");
const assert = std.debug.assert;
// -- imports --
const all = @import("../all.zig");
const tgt = @import("all.zig");
const Blk = all.Blk;
const CAddr = all.CAddr;
const CBits = all.CBits;
const CON = all.CON;
const Cfeq = all.Cfeq;
const Cfge = all.Cfge;
const Cfgt = all.Cfgt;
const Cfle = all.Cfle;
const Cflt = all.Cflt;
const Cfne = all.Cfne;
const Cfo = all.Cfo;
const Cfuo = all.Cfuo;
const Cieq = all.Cieq;
const Cine = all.Cine;
const Cisge = all.Cisge;
const Cisgt = all.Cisgt;
const Cisle = all.Cisle;
const Cislt = all.Cislt;
const Ciuge = all.Ciuge;
const Ciugt = all.Ciugt;
const Ciule = all.Ciule;
const Ciult = all.Ciult;
const Con = all.Con;
const Fn = all.Fn;
const INRANGE = all.INRANGE;
const INS0 = all.INS0;
const Ins = all.Ins;
const Jjnz = all.Jjnz;
const KBASE = all.KBASE;
const KWIDE = all.KWIDE;
const Kl = all.Kl;
const Kw = all.Kw;
const NCmpI = all.NCmpI;
const Oaddr = all.ops.Oaddr;
const Oalloc = all.Oalloc;
const Oalloc1 = all.Oalloc1;
const Oand = all.ops.Oand;
const Ocall = all.ops.Ocall;
const Oceqd = all.ops.Oceqd;
const Oceqs = all.ops.Oceqs;
const Ocopy = all.ops.Ocopy;
const Ocsltl = all.ops.Ocsltl;
const Ocultl = all.ops.Ocultl;
const Oextsw = all.ops.Oextsw;
const Oload = all.ops.Oload;
const Onop = all.ops.Onop;
const Oreqz = all.ops.Oreqz;
const Ornez = all.ops.Ornez;
const Oxor = all.ops.Oxor;
const R = all.R;
const RCon = all.RCon;
const RTmp = all.RTmp;
const Ref = all.Ref;
const SLOT = all.SLOT;
const argcls = all.argcls;
const bufPrintZ = all.bufPrintZ;
const cs = all.cs;
const die = all.die;
const dprint = all.dprint;
const emit = all.emit;
const emiti = all.emiti;
const err = all.err;
const getcon = all.getcon;
const idup = all.idup;
const intern = all.intern;
const iscmp = all.iscmp;
const isload = all.isload;
const isreg = all.isreg;
const isstore = all.isstore;
const newtmp = all.newtmp;
const printfn = all.printfn;
const ptrdiff = all.ptrdiff;
const rtype = all.rtype;
const rv64_op = tgt.rv64_op;
const salloc = all.salloc;
const stashbits = all.stashbits;
const uint = all.uint;
const vgrow = all.vgrow;
// -- end imports --

fn memarg(r: [*c]Ref, op: i32, i: [*c]Ins) bool {
    if (isload(op) or op == Ocall)
        return i != null and r == &i.*.arg[0];
    if (isstore(op))
        return i != null and r == &i.*.arg[1];
    return false;
}

fn immarg(r: [*c]Ref, op: i32, i: [*c]Ins) bool {
    return rv64_op[@intCast(op)].imm != 0 and i != null and r == &i.*.arg[1];
}

fn fixarg(r: [*c]Ref, k: i32, i: [*c]Ins, f: [*c]Fn) void {
    var buf: [32]u8 = undefined;

    const r0 = r.*;
    var r1 = r0;
    const op: i32 = if (i != null) @intCast(i.*.op) else Ocopy;
    switch (rtype(r0)) {
        RCon => blk: {
            var c: [*c]Con = &f.*.con[r0.val];
            if (c.*.type == CAddr and memarg(r, op, i))
                break :blk;
            if (KBASE(k) == 0 and c.*.type == CBits and immarg(r, op, i) and
                -2048 <= c.*.bits.i and c.*.bits.i < 2048)
                break :blk;
            r1 = newtmp("isel", k, f);
            if (KBASE(k) == 1) {
                // load floating points from memory
                // slots, they can't be used as
                // immediates
                assert(c.*.type == CBits);
                const n = stashbits(@bitCast(c.*.bits.i), if (KWIDE(k) != 0) 8 else 4);
                f.*.ncon += 1;
                vgrow(&f.*.con, f.*.ncon);
                c = &f.*.con[@intCast(f.*.ncon - 1)];
                bufPrintZ(&buf, "\"{s}fp{d}\"", .{cs(&all.T.asloc), n});
                c.* = std.mem.zeroes(Con);
                c.*.type = CAddr;
                c.*.sym.id = intern(&buf);
                emit(Oload, k, r1, CON(ptrdiff(c, f.*.con)), R);
                break :blk;
            }
            emit(Ocopy, k, r1, r0, R);
        },
        RTmp => blk: {
            if (isreg(r0))
                break :blk;
            const s = f.*.tmp[r0.val].slot;
            if (s != -1) {
                // aggregate passed by value on
                // stack, or fast local address,
                // replace with slot if we can
                if (memarg(r, op, i)) {
                    r1 = SLOT(s);
                    break :blk;
                }
                r1 = newtmp("isel", k, f);
                emit(Oaddr, k, r1, SLOT(s), R);
                break :blk;
            }
            if (k == Kw and f.*.tmp[r0.val].cls == Kl) {
                // TODO: this sign extension isn't needed
                // for 32-bit arithmetic instructions
                r1 = newtmp("isel", k, f);
                emit(Oextsw, Kl, r1, r0, R);
            } else {
                assert(k == f.*.tmp[r0.val].cls);
            }
        },
        else => {},
    }
    r.* = r1;
}

fn negate(pr: *Ref, f: [*c]Fn) void {
    const r = newtmp("isel", Kw, f);
    emit(Oxor, Kw, pr.*, r, getcon(1, f));
    pr.* = r;
}

fn fixcmp(k: i32, f: [*c]Fn) void {
    const icmp = all.curi;
    fixarg(&icmp.*.arg[0], k, icmp, f);
    fixarg(&icmp.*.arg[1], k, icmp, f);
}

fn selcmp(i_: Ins, k: i32, op_: i32, f: [*c]Fn) void {
    var i = i_;
    var op = op_;
    var sign = false;
    var swap = false;
    var neg = false;

    switch (op) {
        Cieq => {
            const r = newtmp("isel", k, f);
            emit(Oreqz, i.cls, i.to, r, R);
            emit(Oxor, k, r, i.arg[0], i.arg[1]);
            fixcmp(k, f);
            return;
        },
        Cine => {
            const r = newtmp("isel", k, f);
            emit(Ornez, i.cls, i.to, r, R);
            emit(Oxor, k, r, i.arg[0], i.arg[1]);
            fixcmp(k, f);
            return;
        },
        Cisge => { sign = true; swap = false; neg = true; },
        Cisgt => { sign = true; swap = true; neg = false; },
        Cisle => { sign = true; swap = true; neg = true; },
        Cislt => { sign = true; swap = false; neg = false; },
        Ciuge => { sign = false; swap = false; neg = true; },
        Ciugt => { sign = false; swap = true; neg = false; },
        Ciule => { sign = false; swap = true; neg = true; },
        Ciult => { sign = false; swap = false; neg = false; },
        NCmpI + Cfeq, NCmpI + Cfge, NCmpI + Cfgt, NCmpI + Cfle, NCmpI + Cflt => {
            swap = false;
            neg = false;
        },
        NCmpI + Cfuo, NCmpI + Cfo => {
            if (op == NCmpI + Cfuo)
                negate(&i.to, f);
            const r0 = newtmp("isel", i.cls, f);
            const r1 = newtmp("isel", i.cls, f);
            emit(Oand, i.cls, i.to, r0, r1);
            op = if (KWIDE(k) != 0) Oceqd else Oceqs;
            emit(op, i.cls, r0, i.arg[0], i.arg[0]);
            fixcmp(k, f);
            emit(op, i.cls, r1, i.arg[1], i.arg[1]);
            fixcmp(k, f);
            return;
        },
        NCmpI + Cfne => {
            swap = false;
            neg = true;
            i.op = if (KWIDE(k) != 0) Oceqd else Oceqs;
        },
        else => unreachable, // unknown comparison
    }
    if (op < NCmpI)
        i.op = if (sign) Ocsltl else Ocultl;
    if (swap) {
        const r = i.arg[0];
        i.arg[0] = i.arg[1];
        i.arg[1] = r;
    }
    if (neg)
        negate(&i.to, f);
    emiti(i);
    fixcmp(k, f);
}

fn sel(i_: Ins, f: [*c]Fn) void {
    var i = i_;
    var ck: i32 = undefined;
    var cc: i32 = undefined;

    if (INRANGE(i.op, Oalloc, Oalloc1)) {
        const i_0 = all.curi - 1;
        salloc(i.to, i.arg[0], f);
        fixarg(&i_0.*.arg[0], Kl, i_0, f);
        return;
    }
    if (iscmp(i.op, &ck, &cc)) {
        selcmp(i, ck, cc, f);
        return;
    }
    if (i.op != Onop) {
        emiti(i);
        const i_0 = all.curi; // fixarg() can change curi
        fixarg(&i_0.*.arg[0], argcls(&i, 0), i_0, f);
        fixarg(&i_0.*.arg[1], argcls(&i, 1), i_0, f);
    }
}

fn seljmp(b: [*c]Blk, f: [*c]Fn) void {
    // TODO: replace cmp+jnz with beq/bne/blt[u]/bge[u]
    if (b.*.jmp.type == Jjnz)
        fixarg(&b.*.jmp.arg, Kw, null, f);
}

pub fn rv64_isel(f: [*c]Fn) void {
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
                    err("invalid alloc size {d}", .{sz});
                sz = (sz + n - 1) & -@as(i64, n);
                sz = @divTrunc(sz, 4);
                if (sz > std.math.maxInt(i32) - f.*.slot)
                    die("alloc too large", .{});
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
                fixarg(&p.*.arg[a], p.*.cls, null, f);
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
        dprint("\n> After instruction selection:\n", .{});
        printfn(f, all.dbg) catch {};
    }
}
