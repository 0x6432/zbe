//! One-to-one translation of rv64/emit.c
const std = @import("std");
const assert = std.debug.assert;
// -- imports --
const all = @import("../all.zig");
const tgt = @import("all.zig");
const A0 = tgt.A0;
const A7 = tgt.A7;
const BIT = all.BIT;
const Blk = all.Blk;
const CAddr = all.CAddr;
const CBits = all.CBits;
const Con = all.Con;
const FA0 = tgt.FA0;
const FP = tgt.FP;
const FS0 = tgt.FS0;
const FT0 = tgt.FT0;
const FT11 = tgt.FT11;
const Fn = all.Fn;
const GP = tgt.GP;
const Ins = all.Ins;
const Jhlt = all.Jhlt;
const Jjmp = all.Jjmp;
const Jjnz = all.Jjnz;
const Jret0 = all.Jret0;
const KBASE = all.KBASE;
const KWIDE = all.KWIDE;
const Kd = all.Kd;
const Kl = all.Kl;
const Ks = all.Ks;
const Kw = all.Kw;
const NOp = all.NOp;
const Oadd = all.ops.Oadd;
const Oaddr = all.ops.Oaddr;
const Oand = all.ops.Oand;
const Ocall = all.ops.Ocall;
const Ocast = all.ops.Ocast;
const Oceqd = all.ops.Oceqd;
const Oceqs = all.ops.Oceqs;
const Ocged = all.ops.Ocged;
const Ocges = all.ops.Ocges;
const Ocgtd = all.ops.Ocgtd;
const Ocgts = all.ops.Ocgts;
const Ocled = all.ops.Ocled;
const Ocles = all.ops.Ocles;
const Ocltd = all.ops.Ocltd;
const Oclts = all.ops.Oclts;
const Ocopy = all.ops.Ocopy;
const Ocsltl = all.ops.Ocsltl;
const Ocultl = all.ops.Ocultl;
const Odbgloc = all.ops.Odbgloc;
const Odiv = all.ops.Odiv;
const Odtosi = all.ops.Odtosi;
const Odtoui = all.ops.Odtoui;
const Oexts = all.ops.Oexts;
const Oextsb = all.ops.Oextsb;
const Oextsh = all.ops.Oextsh;
const Oextsw = all.ops.Oextsw;
const Oextub = all.ops.Oextub;
const Oextuh = all.ops.Oextuh;
const Oextuw = all.ops.Oextuw;
const Oload = all.ops.Oload;
const Oloadsb = all.ops.Oloadsb;
const Oloadsh = all.ops.Oloadsh;
const Oloadsw = all.ops.Oloadsw;
const Oloadub = all.ops.Oloadub;
const Oloaduh = all.ops.Oloaduh;
const Oloaduw = all.ops.Oloaduw;
const Omul = all.ops.Omul;
const Oneg = all.ops.Oneg;
const Onop = all.ops.Onop;
const Oor = all.ops.Oor;
const Orem = all.ops.Orem;
const Oreqz = all.ops.Oreqz;
const Ornez = all.ops.Ornez;
const Osalloc = all.ops.Osalloc;
const Osar = all.ops.Osar;
const Oshl = all.ops.Oshl;
const Oshr = all.ops.Oshr;
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
const Oswap = all.ops.Oswap;
const Oswtof = all.ops.Oswtof;
const Otruncd = all.ops.Otruncd;
const Oudiv = all.ops.Oudiv;
const Oultof = all.ops.Oultof;
const Ourem = all.ops.Ourem;
const Ouwtof = all.ops.Ouwtof;
const Oxor = all.ops.Oxor;
const R = all.R;
const RA = tgt.RA;
const RCon = all.RCon;
const RSlot = all.RSlot;
const RTmp = all.RTmp;
const Ref = all.Ref;
const S1 = tgt.S1;
const SExt = all.SExt;
const SExtThr = all.SExtThr;
const SGlo = all.SGlo;
const SP = tgt.SP;
const SThr = all.SThr;
const T0 = tgt.T0;
const T6 = tgt.T6;
const TMP = all.TMP;
const TP = tgt.TP;
const Writer = all.Writer;
const bufPrintZ = all.bufPrintZ;
const cs = all.cs;
const die = all.die;
const elf_emitfnfin = all.elf_emitfnfin;
const emitdbgloc = all.emitdbgloc;
const emitfnlnk = all.emitfnlnk;
const isload = all.isload;
const isreg = all.isreg;
const isstore = all.isstore;
const req = all.req;
const rsval = all.rsval;
const rtype = all.rtype;
const rv64_rclob = tgt.rv64_rclob;
const str = all.str;
// -- end imports --

const Ki = -1; // matches Kw and Kl
const Ka = -2; // matches all classes

const OMap = struct {
    op: all.Opc,
    cls: i16,
    fmt: ?[*:0]const u8,
};
const omap = [_]OMap{
    .{ .op = Oadd, .cls = Ki, .fmt = "add%k %=, %0, %1" },
    .{ .op = Oadd, .cls = Ka, .fmt = "fadd.%k %=, %0, %1" },
    .{ .op = Osub, .cls = Ki, .fmt = "sub%k %=, %0, %1" },
    .{ .op = Osub, .cls = Ka, .fmt = "fsub.%k %=, %0, %1" },
    .{ .op = Oneg, .cls = Ki, .fmt = "neg%k %=, %0" },
    .{ .op = Oneg, .cls = Ka, .fmt = "fneg.%k %=, %0" },
    .{ .op = Odiv, .cls = Ki, .fmt = "div%k %=, %0, %1" },
    .{ .op = Odiv, .cls = Ka, .fmt = "fdiv.%k %=, %0, %1" },
    .{ .op = Orem, .cls = Ki, .fmt = "rem%k %=, %0, %1" },
    .{ .op = Orem, .cls = Kl, .fmt = "rem %=, %0, %1" },
    .{ .op = Oudiv, .cls = Ki, .fmt = "divu%k %=, %0, %1" },
    .{ .op = Ourem, .cls = Ki, .fmt = "remu%k %=, %0, %1" },
    .{ .op = Omul, .cls = Ki, .fmt = "mul%k %=, %0, %1" },
    .{ .op = Omul, .cls = Ka, .fmt = "fmul.%k %=, %0, %1" },
    .{ .op = Oand, .cls = Ki, .fmt = "and %=, %0, %1" },
    .{ .op = Oor, .cls = Ki, .fmt = "or %=, %0, %1" },
    .{ .op = Oxor, .cls = Ki, .fmt = "xor %=, %0, %1" },
    .{ .op = Osar, .cls = Ki, .fmt = "sra%k %=, %0, %1" },
    .{ .op = Oshr, .cls = Ki, .fmt = "srl%k %=, %0, %1" },
    .{ .op = Oshl, .cls = Ki, .fmt = "sll%k %=, %0, %1" },
    .{ .op = Ocsltl, .cls = Ki, .fmt = "slt %=, %0, %1" },
    .{ .op = Ocultl, .cls = Ki, .fmt = "sltu %=, %0, %1" },
    .{ .op = Oceqs, .cls = Ki, .fmt = "feq.s %=, %0, %1" },
    .{ .op = Ocges, .cls = Ki, .fmt = "fge.s %=, %0, %1" },
    .{ .op = Ocgts, .cls = Ki, .fmt = "fgt.s %=, %0, %1" },
    .{ .op = Ocles, .cls = Ki, .fmt = "fle.s %=, %0, %1" },
    .{ .op = Oclts, .cls = Ki, .fmt = "flt.s %=, %0, %1" },
    .{ .op = Oceqd, .cls = Ki, .fmt = "feq.d %=, %0, %1" },
    .{ .op = Ocged, .cls = Ki, .fmt = "fge.d %=, %0, %1" },
    .{ .op = Ocgtd, .cls = Ki, .fmt = "fgt.d %=, %0, %1" },
    .{ .op = Ocled, .cls = Ki, .fmt = "fle.d %=, %0, %1" },
    .{ .op = Ocltd, .cls = Ki, .fmt = "flt.d %=, %0, %1" },
    .{ .op = Ostoreb, .cls = Kw, .fmt = "sb %0, %M1" },
    .{ .op = Ostoreh, .cls = Kw, .fmt = "sh %0, %M1" },
    .{ .op = Ostorew, .cls = Kw, .fmt = "sw %0, %M1" },
    .{ .op = Ostorel, .cls = Ki, .fmt = "sd %0, %M1" },
    .{ .op = Ostores, .cls = Kw, .fmt = "fsw %0, %M1" },
    .{ .op = Ostored, .cls = Kw, .fmt = "fsd %0, %M1" },
    .{ .op = Oloadsb, .cls = Ki, .fmt = "lb %=, %M0" },
    .{ .op = Oloadub, .cls = Ki, .fmt = "lbu %=, %M0" },
    .{ .op = Oloadsh, .cls = Ki, .fmt = "lh %=, %M0" },
    .{ .op = Oloaduh, .cls = Ki, .fmt = "lhu %=, %M0" },
    .{ .op = Oloadsw, .cls = Ki, .fmt = "lw %=, %M0" },
    // riscv64 always sign-extends 32-bit
    // values stored in 64-bit registers
    .{ .op = Oloaduw, .cls = Kw, .fmt = "lw %=, %M0" },
    .{ .op = Oloaduw, .cls = Kl, .fmt = "lwu %=, %M0" },
    .{ .op = Oload, .cls = Kw, .fmt = "lw %=, %M0" },
    .{ .op = Oload, .cls = Kl, .fmt = "ld %=, %M0" },
    .{ .op = Oload, .cls = Ks, .fmt = "flw %=, %M0" },
    .{ .op = Oload, .cls = Kd, .fmt = "fld %=, %M0" },
    .{ .op = Oextsb, .cls = Ki, .fmt = "sext.b %=, %0" },
    .{ .op = Oextub, .cls = Ki, .fmt = "zext.b %=, %0" },
    .{ .op = Oextsh, .cls = Ki, .fmt = "sext.h %=, %0" },
    .{ .op = Oextuh, .cls = Ki, .fmt = "zext.h %=, %0" },
    .{ .op = Oextsw, .cls = Kl, .fmt = "sext.w %=, %0" },
    .{ .op = Oextuw, .cls = Kl, .fmt = "zext.w %=, %0" },
    .{ .op = Otruncd, .cls = Ks, .fmt = "fcvt.s.d %=, %0" },
    .{ .op = Oexts, .cls = Kd, .fmt = "fcvt.d.s %=, %0" },
    .{ .op = Ostosi, .cls = Kw, .fmt = "fcvt.w.s %=, %0, rtz" },
    .{ .op = Ostosi, .cls = Kl, .fmt = "fcvt.l.s %=, %0, rtz" },
    .{ .op = Ostoui, .cls = Kw, .fmt = "fcvt.wu.s %=, %0, rtz" },
    .{ .op = Ostoui, .cls = Kl, .fmt = "fcvt.lu.s %=, %0, rtz" },
    .{ .op = Odtosi, .cls = Kw, .fmt = "fcvt.w.d %=, %0, rtz" },
    .{ .op = Odtosi, .cls = Kl, .fmt = "fcvt.l.d %=, %0, rtz" },
    .{ .op = Odtoui, .cls = Kw, .fmt = "fcvt.wu.d %=, %0, rtz" },
    .{ .op = Odtoui, .cls = Kl, .fmt = "fcvt.lu.d %=, %0, rtz" },
    .{ .op = Oswtof, .cls = Ka, .fmt = "fcvt.%k.w %=, %0" },
    .{ .op = Ouwtof, .cls = Ka, .fmt = "fcvt.%k.wu %=, %0" },
    .{ .op = Osltof, .cls = Ka, .fmt = "fcvt.%k.l %=, %0" },
    .{ .op = Oultof, .cls = Ka, .fmt = "fcvt.%k.lu %=, %0" },
    .{ .op = Ocast, .cls = Kw, .fmt = "fmv.x.w %=, %0" },
    .{ .op = Ocast, .cls = Kl, .fmt = "fmv.x.d %=, %0" },
    .{ .op = Ocast, .cls = Ks, .fmt = "fmv.w.x %=, %0" },
    .{ .op = Ocast, .cls = Kd, .fmt = "fmv.d.x %=, %0" },
    .{ .op = Ocopy, .cls = Ki, .fmt = "mv %=, %0" },
    .{ .op = Ocopy, .cls = Ka, .fmt = "fmv.%k %=, %0" },
    .{ .op = Oswap, .cls = Ki, .fmt = "mv %?, %0\n\tmv %0, %1\n\tmv %1, %?" },
    .{ .op = Oswap, .cls = Ka, .fmt = "fmv.%k %?, %0\n\tfmv.%k %0, %1\n\tfmv.%k %1, %?" },
    .{ .op = Oreqz, .cls = Ki, .fmt = "seqz %=, %0" },
    .{ .op = Ornez, .cls = Ki, .fmt = "snez %=, %0" },
    .{ .op = Ocall, .cls = Kw, .fmt = "jalr %0" },
    .{ .op = .xxx, .cls = 0, .fmt = null }, // sentinel
};

const rname = blk: {
    var t: [FT11 + 1]?[*:0]const u8 = @splat(null);
    t[FP] = "fp";
    t[SP] = "sp";
    t[GP] = "gp";
    t[TP] = "tp";
    t[RA] = "ra";
    for (.{ "t0", "t1", "t2", "t3", "t4", "t5" }, 0..) |s, n| t[T0 + n] = s;
    for (.{ "a0", "a1", "a2", "a3", "a4", "a5", "a6", "a7" }, 0..) |s, n| t[A0 + n] = s;
    for (.{ "s1", "s2", "s3", "s4", "s5", "s6", "s7", "s8", "s9", "s10", "s11" }, 0..) |s, n| t[S1 + n] = s;
    for (.{ "ft0", "ft1", "ft2", "ft3", "ft4", "ft5", "ft6", "ft7", "ft8", "ft9", "ft10" }, 0..) |s, n| t[FT0 + n] = s;
    for (.{ "fa0", "fa1", "fa2", "fa3", "fa4", "fa5", "fa6", "fa7" }, 0..) |s, n| t[FA0 + n] = s;
    for (.{ "fs0", "fs1", "fs2", "fs3", "fs4", "fs5", "fs6", "fs7", "fs8", "fs9", "fs10", "fs11" }, 0..) |s, n| t[FS0 + n] = s;
    t[T6] = "t6";
    t[FT11] = "ft11";
    break :blk t;
};

fn slot(r: Ref, f: *Fn) i64 {
    const s = rsval(r);
    assert(s <= f.slot);
    if (s < 0)
        return 8 * -@as(i64, s)
    else
        return -4 * @as(i64, f.slot - s);
}

fn emitaddr(c: *Con, f: *Writer) Writer.Error!void {
    assert((c.sym.type & ~@as(i32, SExt)) == SGlo);
    try f.writeAll(cs(str(c.sym.id)));
    if (c.bits.i != 0) {
        // TODO: fix isel to ensure no offset for SGlo
        if ((c.sym.type & SExt) != 0)
            die("extern with offset is not supported", .{});
        try f.print("+{d}", .{c.bits.i});
    }
}

const clschr = [_]u8{ 'w', 'l', 's', 'd' };

fn emitf(s_: [*:0]const u8, i: *Ins, fn_: *Fn, f: *Writer) Writer.Error!void {
    var s = s_;
    var r: Ref = undefined;
    var c: u8 = undefined;

    try f.writeByte('\t');
    while (true) {
        const k: i32 = i.cls;
        while (true) {
            c = s[0];
            s += 1;
            if (c == '%') break;
            if (c == 0) {
                try f.writeByte('\n');
                return;
            } else try f.writeByte(c);
        }
        c = s[0];
        s += 1;
        switch (c) {
            else => die("invalid escape", .{}),
            '?' => {
                if (KBASE(k) == 0)
                    try f.writeAll("t6")
                else
                    try f.writeAll("ft11");
            },
            'k' => {
                if (i.cls != Kl)
                    try f.writeByte(clschr[@as(usize, @intCast(i.cls))]);
            },
            '=', '0' => {
                r = if (c == '=') i.to else i.arg[0];
                assert(isreg(r));
                try f.writeAll(cs(rname[r.val]));
            },
            '1' => {
                r = i.arg[1];
                switch (rtype(r)) {
                    else => die("invalid second argument", .{}),
                    RTmp => {
                        assert(isreg(r));
                        try f.writeAll(cs(rname[r.val]));
                    },
                    RCon => {
                        const pc = &fn_.con[r.val];
                        assert(pc.type == CBits);
                        assert(pc.bits.i >= -2048 and pc.bits.i < 2048);
                        try f.print("{d}", .{pc.bits.i});
                    },
                }
            },
            'M' => {
                c = s[0];
                s += 1;
                assert(c == '0' or c == '1');
                r = i.arg[c - '0'];
                switch (rtype(r)) {
                    else => die("invalid address argument", .{}),
                    RTmp => try f.print("0({s})", .{cs(rname[r.val])}),
                    RCon => {
                        const pc = &fn_.con[r.val];
                        assert(pc.type == CAddr);
                        try emitaddr(pc, f);
                        if (isstore(i.op) or
                            (isload(i.op) and KBASE(i.cls) == 1))
                        {
                            // store (and float load)
                            // pseudo-instructions need a
                            // temporary register in which to
                            // load the address
                            try f.print(", t6", .{});
                        }
                    },
                    RSlot => {
                        const offset = slot(r, fn_);
                        assert(offset >= -2048 and offset <= 2047);
                        try f.print("{d}(fp)", .{offset});
                    },
                }
            },
        }
    }
}

fn loadaddr(c: *Con, rn: ?[*:0]const u8, f: *Writer) Writer.Error!void {
    var off: [32]u8 = undefined;

    switch (c.sym.type) {
        SGlo, SExt => {
            try f.print("\t{s} {s}, ", .{if (c.sym.type == SExt) "lga" else "lla", cs(rn)});
            try emitaddr(c, f);
            try f.writeByte('\n');
        },
        SThr => {
            if (c.bits.i != 0)
                bufPrintZ(&off, "+{d}", .{c.bits.i})
            else
                off[0] = 0;
            try f.print("\tlui {s}, %tprel_hi({s}){s}\n", .{cs(rn), cs(str(c.sym.id)), cs(&off)});
            try f.print("\tadd {s}, {s}, tp, %tprel_add({s}){s}\n", .{cs(rn), cs(rn), cs(str(c.sym.id)), cs(&off)});
            try f.print("\taddi {s}, {s}, %tprel_lo({s}){s}\n", .{cs(rn), cs(rn), cs(str(c.sym.id)), cs(&off)});
        },
        SExtThr => die("extern thread unavailable on rv64", .{}),
        else => {},
    }
}

fn loadcon(c: *Con, r: i32, k: i32, f: *Writer) Writer.Error!void {
    const rn = rname[@intCast(r)];
    switch (c.type) {
        CAddr => try loadaddr(c, rn, f),
        CBits => {
            var n = c.bits.i;
            if (KWIDE(k) == 0)
                n = @as(i32, @truncate(n));
            try f.print("\tli {s}, {d}\n", .{cs(rn), n});
        },
        else => die("invalid constant", .{}),
    }
}

fn fixmem(pr: *Ref, fn_: *Fn, f: *Writer) Writer.Error!void {
    const r = pr.*;
    if (rtype(r) == RCon) {
        const c = &fn_.con[r.val];
        if (c.type == CAddr and c.sym.type != SGlo) {
            try loadcon(c, T6, Kl, f);
            pr.* = TMP(T6);
        }
    }
    if (rtype(r) == RSlot) {
        const s = slot(r, fn_);
        if (s < -2048 or s > 2047) {
            try f.print("\tli t6, {d}\n", .{s});
            try f.print("\tadd t6, fp, t6\n", .{});
            pr.* = TMP(T6);
        }
    }
}

/// Table: most instructions are just pulled out of
/// the table omap[], some special cases are
/// detailed in emitins
fn table(i: *Ins, fn_: *Fn, f: *Writer) Writer.Error!void {
    var o: usize = 0;
    while (true) : (o += 1) {
        // this linear search should really be a binary
        // search
        if (omap[o].op == .xxx)
            die("no match for {s}({c})", .{cs(all.optab[i.op.int()].name), "wlsd"[@as(usize, @intCast(i.cls))]});
        if (omap[o].op == i.op and
            (omap[o].cls == i.cls or omap[o].cls == Ka or
            (omap[o].cls == Ki and KBASE(i.cls) == 0)))
            break;
    }
    try emitf(omap[o].fmt.?, i, fn_, f);
}

fn emitins(i: *Ins, fn_: *Fn, f: *Writer) Writer.Error!void {
    switch (i.op) {
        else => {
            if (isload(i.op))
                try fixmem(&i.arg[0], fn_, f)
            else if (isstore(i.op))
                try fixmem(&i.arg[1], fn_, f);
            try table(i, fn_, f);
        },
        Ocopy => {
            if (req(i.to, i.arg[0]))
                return;
            if (rtype(i.to) == RSlot) {
                switch (rtype(i.arg[0])) {
                    RSlot, RCon => die("unimplemented", .{}),
                    else => {
                        assert(isreg(i.arg[0]));
                        i.arg[1] = i.to;
                        i.to = R;
                        switch (i.cls) {
                            Kw => i.op = Ostorew,
                            Kl => i.op = Ostorel,
                            Ks => i.op = Ostores,
                            Kd => i.op = Ostored,
                            else => {},
                        }
                        try fixmem(&i.arg[1], fn_, f);
                        try table(i, fn_, f);
                    },
                }
                return;
            }
            assert(isreg(i.to));
            switch (rtype(i.arg[0])) {
                RCon => try loadcon(&fn_.con[i.arg[0].val], @intCast(i.to.val), i.cls, f),
                RSlot => {
                    i.op = Oload;
                    try fixmem(&i.arg[0], fn_, f);
                    try table(i, fn_, f);
                },
                else => {
                    assert(isreg(i.arg[0]));
                    try table(i, fn_, f);
                },
            }
        },
        Onop => {},
        Oaddr => {
            assert(rtype(i.arg[0]) == RSlot);
            const rn = rname[i.to.val];
            const s = slot(i.arg[0], fn_);
            if (-s < 2048) {
                try f.print("\tadd {s}, fp, {d}\n", .{cs(rn), s});
            } else {
                try f.print("\tli {s}, {d}\n" ++ "\tadd {s}, fp, {s}\n", .{cs(rn), s, cs(rn), cs(rn)});
            }
        },
        Ocall => {
            switch (rtype(i.arg[0])) {
                RCon => {
                    const con = &fn_.con[i.arg[0].val];
                    if (con.type != CAddr or
                        (con.sym.type & SThr) != 0 or
                        con.bits.i != 0)
                        die("invalid call argument", .{});
                    try f.print("\tcall {s}\n", .{cs(str(con.sym.id))});
                },
                RTmp => try emitf("jalr %0", i, fn_, f),
                else => die("invalid call argument", .{}),
            }
        },
        Osalloc => {
            try emitf("sub sp, sp, %0", i, fn_, f);
            if (!req(i.to, R))
                try emitf("mv %=, sp", i, fn_, f);
        },
        Odbgloc => try emitdbgloc(i.arg[0].val, i.arg[1].val, f),
    }
}

// Stack-frame layout:
//
// +=============+
// | varargs     |
// |  save area  |
// +-------------+
// |  saved ra   |
// |  saved fp   |
// +-------------+ <- fp
// |    ...      |
// | spill slots |
// |    ...      |
// +-------------+
// |    ...      |
// |   locals    |
// |    ...      |
// +-------------+
// |   padding   |
// +-------------+
// | callee-save |
// |  registers  |
// +=============+

var id0: i32 = 0;

pub fn rv64_emitfn(fn_: *Fn, f: *Writer) Writer.Error!void {
    try emitfnlnk(fn_.name.?, &fn_.lnk, f);

    if (fn_.vararg != 0) {
        // TODO: only need space for registers
        // unused by named arguments
        try f.print("\tadd sp, sp, -64\n", .{});
        var r: i32 = A0;
        while (r <= A7) : (r += 1)
            try f.print("\tsd {s}, {d}(sp)\n", .{cs(rname[@intCast(r)]), 8 * (r - A0)});
    }
    try f.print("\tsd fp, -16(sp)\n", .{});
    try f.print("\tsd ra, -8(sp)\n", .{});
    try f.print("\tadd fp, sp, -16\n", .{});

    var frame: i32 = (16 + 4 * fn_.slot + 15) & ~@as(i32, 15);
    for (rv64_rclob) |r| {
        if (r < 0) break;
        if ((fn_.reg & BIT(r)) != 0)
            frame += 8;
    }
    frame = (frame + 15) & ~@as(i32, 15);

    if (frame <= 2048)
        try f.print("\tadd sp, sp, -{d}\n", .{frame})
    else
        try f.print("\tli t6, {d}\n" ++ "\tsub sp, sp, t6\n", .{frame});
    var off: i32 = 0;
    for (rv64_rclob) |r| {
        if (r < 0) break;
        if ((fn_.reg & BIT(r)) != 0) {
            try f.print("\t{s} {s}, {d}(sp)\n", .{ if (r < FT0) "sd" else "fsd", cs(rname[@intCast(r)]), off });
            off += 8;
        }
    }

    var lbl = false;
    var b_it: ?*Blk = fn_.start;
    while (b_it) |b| : (b_it = b.link) {
        if (lbl or b.npred > 1)
            try f.print(".L{d}:\n", .{id0 + @as(i32, @intCast(b.id))});
        for (b.ins[0..b.nins]) |*i|
            try emitins(i, fn_, f);
        lbl = true;
        var jmp = false;
        switch (b.jmp.type) {
            Jhlt => try f.print("\tebreak\n", .{}),
            Jret0 => {
                if (fn_.dynalloc != 0) {
                    if (frame - 16 <= 2048)
                        try f.print("\tadd sp, fp, -{d}\n", .{frame - 16})
                    else
                        try f.print("\tli t6, {d}\n" ++ "\tsub sp, fp, t6\n", .{frame - 16});
                }
                off = 0;
                for (rv64_rclob) |r| {
                    if (r < 0) break;
                    if ((fn_.reg & BIT(r)) != 0) {
                        try f.print("\t{s} {s}, {d}(sp)\n", .{ if (r < FT0) "ld" else "fld", cs(rname[@intCast(r)]), off });
                        off += 8;
                    }
                }
                try f.print("\tadd sp, fp, {d}\n" ++ "\tld ra, 8(fp)\n" ++ "\tld fp, 0(fp)\n" ++ "\tret\n", .{16 + @as(i32, fn_.vararg) * 64});
            },
            Jjmp => jmp = true,
            Jjnz => {
                var neg = false;
                if (b.link == b.s2) {
                    const s = b.s1;
                    b.s1 = b.s2;
                    b.s2 = s;
                    neg = true;
                }
                if (rtype(b.jmp.arg) == RSlot) {
                    var ii = std.mem.zeroes(Ins);
                    ii.arg[0] = b.jmp.arg;
                    try emitf("lw t6, %M0", &ii, fn_, f);
                    b.jmp.arg = TMP(T6);
                }
                assert(isreg(b.jmp.arg));
                try f.print("\tb{s}z {s}, .L{d}\n", .{if (neg) "ne" else "eq", cs(rname[b.jmp.arg.val]), id0 + @as(i32, @intCast(b.s2.?.id))});
                jmp = true;
            },
            else => {},
        }
        if (jmp) { // Jmp:
            if (b.s1 != b.link)
                try f.print("\tj .L{d}\n", .{id0 + @as(i32, @intCast(b.s1.?.id))})
            else
                lbl = false;
        }
    }
    id0 += @intCast(fn_.nblk);
    try elf_emitfnfin(fn_.name.?, f);
}
