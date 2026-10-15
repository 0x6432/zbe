//! One-to-one translation of rv64/isel.c
const std = @import("std");
const assert = std.debug.assert;
// -- imports --
const all = @import("../all.zig");
const Cls = all.Cls;
const J = all.J;
const Opc = all.Opc;
const tgt = @import("all.zig");
const Blk = all.Blk;
const CAddr = all.CAddr;
const CBits = all.CBits;
const conRef = all.conRef;
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
const inRange = all.inRange;
const insOp = all.insOp;
const Ins = all.Ins;
const clsBase = all.clsBase;
const clsWide = all.clsWide;
const NCmpI = all.NCmpI;
const Phi = all.Phi;
const R = all.R;
const RCon = all.RCon;
const RTmp = all.RTmp;
const Ref = all.Ref;
const slotRef = all.slotRef;
const argcls = all.argcls;
const bufPrintZ = all.bufPrintZ;
const cs = all.cs;
const die = all.die;
const dprint = all.dprint;
const emit = all.emit;
const emiti = all.emiti;
const fail = all.fail;
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

fn memarg(r: *Ref, op: Opc, i: ?*Ins) bool {
    const ii = i orelse return false;
    if (isload(op) or op == .call)
        return r == &ii.arg[0];
    if (isstore(op))
        return r == &ii.arg[1];
    return false;
}

fn immarg(r: *Ref, op: Opc, i: ?*Ins) bool {
    const ii = i orelse return false;
    return rv64_op[op.int()].imm != 0 and r == &ii.arg[1];
}

fn fixarg(r: *Ref, k: Cls, i: ?*Ins, f: *Fn) void {
    var buf: [32]u8 = undefined;

    const r0 = r.*;
    var r1 = r0;
    const op: Opc = if (i) |ii| ii.op else .copy;
    switch (rtype(r0)) {
        RCon => blk: {
            var c: *Con = &f.cons()[r0.val];
            if (c.type == CAddr and memarg(r, op, i))
                break :blk;
            if (clsBase(k) == 0 and c.type == CBits and immarg(r, op, i) and
                -2048 <= c.bits.i and c.bits.i < 2048)
                break :blk;
            r1 = newtmp("isel", k, f);
            if (clsBase(k) == 1) {
                // load floating points from memory
                // slots, they can't be used as
                // immediates
                assert(c.type == CBits);
                const n = stashbits(@bitCast(c.bits.i), if (clsWide(k) != 0) 8 else 4);
                f.ncon += 1;
                vgrow(&f.con, f.ncon);
                const ci: usize = @intCast(f.ncon - 1);
                c = &f.cons()[ci];
                bufPrintZ(&buf, "\"{s}fp{d}\"", .{cs(&all.T.asloc), n});
                c.* = std.mem.zeroes(Con);
                c.type = CAddr;
                c.sym.id = intern(@ptrCast(&buf));
                emit(.load, k, r1, conRef(ci), R);
                break :blk;
            }
            emit(.copy, k, r1, r0, R);
        },
        RTmp => blk: {
            if (isreg(r0))
                break :blk;
            const s = f.tmps()[r0.val].slot;
            if (s != -1) {
                // aggregate passed by value on
                // stack, or fast local address,
                // replace with slot if we can
                if (memarg(r, op, i)) {
                    r1 = slotRef(s);
                    break :blk;
                }
                r1 = newtmp("isel", k, f);
                emit(.addr, k, r1, slotRef(s), R);
                break :blk;
            }
            if (k == .w and f.tmps()[r0.val].cls == .l) {
                // TODO: this sign extension isn't needed
                // for 32-bit arithmetic instructions
                r1 = newtmp("isel", k, f);
                emit(.extsw, .l, r1, r0, R);
            } else {
                assert(k == f.tmps()[r0.val].cls);
            }
        },
        else => {},
    }
    r.* = r1;
}

fn negate(pr: *Ref, f: *Fn) void {
    const r = newtmp("isel", .w, f);
    emit(.xor, .w, pr.*, r, getcon(1, f));
    pr.* = r;
}

fn fixcmp(k: Cls, f: *Fn) void {
    const icmp = &all.curi[0];
    fixarg(&icmp.arg[0], k, icmp, f);
    fixarg(&icmp.arg[1], k, icmp, f);
}

fn selcmp(i_: Ins, k: Cls, op_: i32, f: *Fn) void {
    var i = i_;
    const op = op_;
    var sign = false;
    var swap = false;
    var neg = false;

    switch (op) {
        Cieq => {
            const r = newtmp("isel", k, f);
            emit(.reqz, i.cls, i.to, r, R);
            emit(.xor, k, r, i.arg[0], i.arg[1]);
            fixcmp(k, f);
            return;
        },
        Cine => {
            const r = newtmp("isel", k, f);
            emit(.rnez, i.cls, i.to, r, R);
            emit(.xor, k, r, i.arg[0], i.arg[1]);
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
            emit(.@"and", i.cls, i.to, r0, r1);
            const cop: Opc = if (clsWide(k) != 0) .ceqd else .ceqs;
            emit(cop, i.cls, r0, i.arg[0], i.arg[0]);
            fixcmp(k, f);
            emit(cop, i.cls, r1, i.arg[1], i.arg[1]);
            fixcmp(k, f);
            return;
        },
        NCmpI + Cfne => {
            swap = false;
            neg = true;
            i.op = if (clsWide(k) != 0) .ceqd else .ceqs;
        },
        else => unreachable, // unknown comparison
    }
    if (op < NCmpI)
        i.op = if (sign) .csltl else .cultl;
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

fn sel(i_: Ins, f: *Fn) all.Error!void {
    var i = i_;
    var ck: Cls = undefined;
    var cc: i32 = undefined;

    if (inRange(i.op, Opc.alloc_first, Opc.alloc_last)) {
        const i_0 = &(all.curi - 1)[0];
        try salloc(i.to, i.arg[0], f);
        fixarg(&i_0.arg[0], .l, i_0, f);
        return;
    }
    if (iscmp(i.op, &ck, &cc)) {
        selcmp(i, ck, cc, f);
        return;
    }
    if ((i.op == .sar or i.op == .shr or i.op == .shl) and rtype(i.arg[1]) == RCon) {
        // rv64 masks register shift counts to 5 (w) / 6 (l) bits, but an
        // immediate shamt >= width does not assemble: mask it the same way
        const c = &f.cons()[i.arg[1].val];
        if (c.type == CBits) {
            const m: i64 = if (i.cls == .w) 31 else 63;
            if (c.bits.i & m != c.bits.i)
                i.arg[1] = getcon(c.bits.i & m, f);
        }
    }
    if (i.op != .nop) {
        emiti(i);
        const i_0 = &all.curi[0]; // fixarg() can change curi
        fixarg(&i_0.arg[0], argcls(&i, 0), i_0, f);
        fixarg(&i_0.arg[1], argcls(&i, 1), i_0, f);
    }
}

fn seljmp(b: *Blk, f: *Fn) void {
    // TODO: replace cmp+jnz with beq/bne/blt[u]/bge[u]
    if (b.jmp.type == .jnz)
        fixarg(&b.jmp.arg, .w, null, f);
}

pub fn rv64_isel(f: *Fn) all.Error!void {
    // assign slots to fast allocs
    const start = f.start.?;
    // specific to NAlign == 3
    // or change n=4 and sz /= 4 below
    var al: i32 = 0; // alloc4, alloc8, alloc16
    var n: i32 = 4;
    while (al <= Opc.alloc_last.diff(Opc.alloc_first)) : ({
        al += 1;
        n *= 2;
    }) {
        for (start.insns()) |*i| {
            if (i.op.diff(Opc.alloc_first) == al) {
                if (rtype(i.arg[0]) != RCon)
                    break;
                var sz = f.cons()[i.arg[0].val].bits.i;
                if (sz < 0 or sz >= std.math.maxInt(i32) - 15)
                    return fail("invalid alloc size {d}", .{sz});
                sz = (sz + n - 1) & -@as(i64, n);
                sz = @divTrunc(sz, 4);
                if (sz > std.math.maxInt(i32) - f.slot)
                    return all.failInput("alloc too large", .{});
                f.tmps()[i.to.val].slot = f.slot;
                f.slot += @intCast(sz);
                i.* = insOp(.nop);
            }
        }
    }

    var b_it = f.start;
    while (b_it) |b| : (b_it = b.link) {
        all.curi = all.insbEnd();
        for ([2]?*Blk{ b.s1, b.s2 }) |sb_| {
            const sb = sb_ orelse break;
            var p_it = sb.phi;
            while (p_it) |p| : (p_it = p.link) {
                var a: uint = 0;
                while (p.blks()[a] != b) : (a += 1)
                    assert(a + 1 < p.narg);
                fixarg(&p.args()[a], p.cls, null, f);
            }
        }
        seljmp(b, f);
        var i_n = b.nins;
        while (i_n > 0) {
            i_n -= 1;
            try sel(b.insns()[i_n], f);
        }
        idup(b, all.insbTailSlice());
    }

    if (all.debug['I'] != 0) {
        dprint("\n> After instruction selection:\n", .{});
        printfn(f, all.dbg) catch {};
    }
}
