//! One-to-one translation of amd64/emit.c
const std = @import("std");
const assert = std.debug.assert;
// -- imports --
const all = @import("../all.zig");
const tgt = @import("all.zig");
const BIT = all.BIT;
const Blk = all.Blk;
const CAddr = all.CAddr;
const CBits = all.CBits;
const CUndef = all.CUndef;
const Cfge = all.Cfge;
const Cfgt = all.Cfgt;
const Cfle = all.Cfle;
const Cflt = all.Cflt;
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
const INS = all.INS;
const Ins = all.Ins;
const Jhlt = all.Jhlt;
const Jjf = all.Jjf;
const Jjmp = all.Jjmp;
const Jret0 = all.Jret0;
const KBASE = all.KBASE;
const KWIDE = all.KWIDE;
const Kd = all.Kd;
const Kl = all.Kl;
const Ks = all.Ks;
const Kw = all.Kw;
const NCLR_SYSV = tgt.NCLR_SYSV;
const NCLR_WIN = tgt.NCLR_WIN;
const NCmp = all.NCmp;
const NCmpI = all.NCmpI;
const NOp = all.NOp;
const Oadd = all.ops.Oadd;
const Oaddr = all.ops.Oaddr;
const Oand = all.ops.Oand;
const Ocall = all.ops.Ocall;
const Ocast = all.ops.Ocast;
const Ocopy = all.ops.Ocopy;
const Odbgloc = all.ops.Odbgloc;
const Odiv = all.ops.Odiv;
const Odtosi = all.ops.Odtosi;
const Oexts = all.ops.Oexts;
const Oextsb = all.ops.Oextsb;
const Oextsh = all.ops.Oextsh;
const Oextsw = all.ops.Oextsw;
const Oextub = all.ops.Oextub;
const Oextuh = all.ops.Oextuh;
const Oextuw = all.ops.Oextuw;
const Oflag = all.Oflag;
const Oflagfeq = all.ops.Oflagfeq;
const Oflagfne = all.ops.Oflagfne;
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
const Osalloc = all.ops.Osalloc;
const Osar = all.ops.Osar;
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
const Osub = all.ops.Osub;
const Oswap = all.ops.Oswap;
const Oswtof = all.ops.Oswtof;
const Otruncd = all.ops.Otruncd;
const Oxcmp = all.ops.Oxcmp;
const Oxdiv = all.ops.Oxdiv;
const Oxidiv = all.ops.Oxidiv;
const Oxor = all.ops.Oxor;
const Oxsel = all.Oxsel;
const Oxtest = all.ops.Oxtest;
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
const RCon = all.RCon;
const RDI = tgt.RDI;
const RDX = tgt.RDX;
const RMem = all.RMem;
const RSI = tgt.RSI;
const RSP = tgt.RSP;
const RSlot = all.RSlot;
const RTmp = all.RTmp;
const Ref = all.Ref;
const SExt = all.SExt;
const SExtThr = all.SExtThr;
const SGlo = all.SGlo;
const SThr = all.SThr;
const TMP = all.TMP;
const Writer = all.Writer;
const XMM0 = tgt.XMM0;
const XMM15 = tgt.XMM15;
const addcon = all.addcon;
const bits = all.bits;
const bufPrintZ = all.bufPrintZ;
const cs = all.cs;
const die = all.die;
const elf_emitfnfin = all.elf_emitfnfin;
const emitdbgloc = all.emitdbgloc;
const emitfnlnk = all.emitfnlnk;
const isreg = all.isreg;
const isxsel = all.isxsel;
const req = all.req;
const rsval = all.rsval;
const rtype = all.rtype;
const stashbits = all.stashbits;
const str = all.str;
const uint = all.uint;
// -- end imports --

const E = extern struct {
    f: *Writer,
    @"fn": *Fn,
    fp: i32,
    fsz: u64,
    nclob: i32,
};

const CmpX = struct { c: comptime_int, s0: []const u8, s1: []const u8 };
const CMP = [_]CmpX{
    .{ .c = Ciule, .s0 = "be", .s1 = "a" },
    .{ .c = Ciult, .s0 = "b", .s1 = "ae" },
    .{ .c = Cisle, .s0 = "le", .s1 = "g" },
    .{ .c = Cislt, .s0 = "l", .s1 = "ge" },
    .{ .c = Cisgt, .s0 = "g", .s1 = "le" },
    .{ .c = Cisge, .s0 = "ge", .s1 = "l" },
    .{ .c = Ciugt, .s0 = "a", .s1 = "be" },
    .{ .c = Ciuge, .s0 = "ae", .s1 = "b" },
    .{ .c = Cieq, .s0 = "z", .s1 = "nz" },
    .{ .c = Cine, .s0 = "nz", .s1 = "z" },
    .{ .c = NCmpI + Cfle, .s0 = "?", .s1 = "?" },
    .{ .c = NCmpI + Cflt, .s0 = "?", .s1 = "?" },
    .{ .c = NCmpI + Cfgt, .s0 = "a", .s1 = "be" },
    .{ .c = NCmpI + Cfge, .s0 = "ae", .s1 = "b" },
    .{ .c = NCmpI + Cfo, .s0 = "np", .s1 = "p" },
    .{ .c = NCmpI + Cfuo, .s0 = "p", .s1 = "np" },
};

const SLong = 0;
const SWord = 1;
const SShort = 2;
const SByte = 3;

/// omap class pattern: a concrete class, `i` (Kw or Kl) or `a` (any class)
const KPat = enum(i16) { a = -2, i = -1, w, l, s, d };

// Instruction format strings:
//
// if the format string starts with -, the instruction
// is assumed to be 3-address and is put in 2-address
// mode using an extra mov if necessary
//
// if the format string starts with +, the same as the
// above applies, but commutativity is also assumed
//
// %k  is used to set the class of the instruction,
//     it'll expand to "l", "q", "ss", "sd", depending
//     on the instruction class
// %0  designates the first argument
// %1  designates the second argument
// %=  designates the result
//
// if %k is not used, a prefix to 0, 1, or = must be
// added, it can be:
//   M - memory reference
//   L - long  (64 bits)
//   W - word  (32 bits)
//   H - short (16 bits)
//   B - byte  (8 bits)
//   S - single precision float
//   D - double precision float
const OMap = struct {
    op: all.Opc,
    cls: KPat,
    fmt: ?[*:0]const u8,
};
const omap = blk: {
    const base = [_]OMap{
        .{ .op = Oadd, .cls = .a, .fmt = "+add%k %1, %=" },
        .{ .op = Osub, .cls = .a, .fmt = "-sub%k %1, %=" },
        .{ .op = Oand, .cls = .i, .fmt = "+and%k %1, %=" },
        .{ .op = Oor, .cls = .i, .fmt = "+or%k %1, %=" },
        .{ .op = Oxor, .cls = .i, .fmt = "+xor%k %1, %=" },
        .{ .op = Osar, .cls = .i, .fmt = "-sar%k %B1, %=" },
        .{ .op = Oshr, .cls = .i, .fmt = "-shr%k %B1, %=" },
        .{ .op = Oshl, .cls = .i, .fmt = "-shl%k %B1, %=" },
        .{ .op = Omul, .cls = .i, .fmt = "+imul%k %1, %=" },
        .{ .op = Omul, .cls = .s, .fmt = "+mulss %1, %=" },
        .{ .op = Omul, .cls = .d, .fmt = "+mulsd %1, %=" },
        .{ .op = Odiv, .cls = .a, .fmt = "-div%k %1, %=" },
        .{ .op = Ostorel, .cls = .a, .fmt = "movq %L0, %M1" },
        .{ .op = Ostorew, .cls = .a, .fmt = "movl %W0, %M1" },
        .{ .op = Ostoreh, .cls = .a, .fmt = "movw %H0, %M1" },
        .{ .op = Ostoreb, .cls = .a, .fmt = "movb %B0, %M1" },
        .{ .op = Ostores, .cls = .a, .fmt = "movss %S0, %M1" },
        .{ .op = Ostored, .cls = .a, .fmt = "movsd %D0, %M1" },
        .{ .op = Oload, .cls = .a, .fmt = "mov%k %M0, %=" },
        .{ .op = Oloadsw, .cls = .l, .fmt = "movslq %M0, %L=" },
        .{ .op = Oloadsw, .cls = .w, .fmt = "movl %M0, %W=" },
        .{ .op = Oloaduw, .cls = .i, .fmt = "movl %M0, %W=" },
        .{ .op = Oloadsh, .cls = .i, .fmt = "movsw%k %M0, %=" },
        .{ .op = Oloaduh, .cls = .i, .fmt = "movzw%k %M0, %=" },
        .{ .op = Oloadsb, .cls = .i, .fmt = "movsb%k %M0, %=" },
        .{ .op = Oloadub, .cls = .i, .fmt = "movzb%k %M0, %=" },
        .{ .op = Oextsw, .cls = .l, .fmt = "movslq %W0, %L=" },
        .{ .op = Oextuw, .cls = .l, .fmt = "movl %W0, %W=" },
        .{ .op = Oextsh, .cls = .i, .fmt = "movsw%k %H0, %=" },
        .{ .op = Oextuh, .cls = .i, .fmt = "movzw%k %H0, %=" },
        .{ .op = Oextsb, .cls = .i, .fmt = "movsb%k %B0, %=" },
        .{ .op = Oextub, .cls = .i, .fmt = "movzb%k %B0, %=" },

        .{ .op = Oexts, .cls = .d, .fmt = "cvtss2sd %0, %=" },
        .{ .op = Otruncd, .cls = .s, .fmt = "cvtsd2ss %0, %=" },
        .{ .op = Ostosi, .cls = .i, .fmt = "cvttss2si%k %0, %=" },
        .{ .op = Odtosi, .cls = .i, .fmt = "cvttsd2si%k %0, %=" },
        .{ .op = Oswtof, .cls = .a, .fmt = "cvtsi2%k %W0, %=" },
        .{ .op = Osltof, .cls = .a, .fmt = "cvtsi2%k %L0, %=" },
        .{ .op = Ocast, .cls = .i, .fmt = "movq %D0, %L=" },
        .{ .op = Ocast, .cls = .a, .fmt = "movq %L0, %D=" },

        .{ .op = Oaddr, .cls = .i, .fmt = "lea%k %M0, %=" },
        .{ .op = Oswap, .cls = .i, .fmt = "xchg%k %0, %1" },
        .{ .op = Osign, .cls = .l, .fmt = "cqto" },
        .{ .op = Osign, .cls = .w, .fmt = "cltd" },
        .{ .op = Oxdiv, .cls = .i, .fmt = "div%k %0" },
        .{ .op = Oxidiv, .cls = .i, .fmt = "idiv%k %0" },
        .{ .op = Oxcmp, .cls = .s, .fmt = "ucomiss %S0, %S1" },
        .{ .op = Oxcmp, .cls = .d, .fmt = "ucomisd %D0, %D1" },
        .{ .op = Oxcmp, .cls = .i, .fmt = "cmp%k %0, %1" },
        .{ .op = Oxtest, .cls = .i, .fmt = "test%k %0, %1" },
    };
    var flags: [CMP.len]OMap = undefined;
    for (CMP, 0..) |x, n|
        flags[n] = .{ .op = Oflag.offset(x.c), .cls = .i, .fmt = "set" ++ x.s0 ++ " %B=\n\tmovzb%k %B=, %=" };
    const tail = [_]OMap{
        .{ .op = Oflagfeq, .cls = .i, .fmt = "setz %B=\n\tmovzb%k %B=, %=" },
        .{ .op = Oflagfne, .cls = .i, .fmt = "setnz %B=\n\tmovzb%k %B=, %=" },
        .{ .op = .xxx, .cls = .w, .fmt = null }, // sentinel
    };
    break :blk base ++ flags ++ tail;
};

const cmov = blk: {
    var t: [NCmp][2][*:0]const u8 = @splat(.{ "", "" });
    for (CMP) |x|
        t[x.c] = .{ "cmov" ++ x.s0 ++ " %0, %=", "cmov" ++ x.s1 ++ " %1, %=" };
    break :blk t;
};

const ctoa = blk: {
    var t: [NCmp][2]?[*:0]const u8 = @splat(.{ null, null });
    for (CMP) |x|
        t[x.c] = .{ x.s0 ++ "", x.s1 ++ "" };
    break :blk t;
};

const rname = blk: {
    var t: [XMM0][4]?[*:0]const u8 = @splat(.{ null, null, null, null });
    t[RAX] = .{ "rax", "eax", "ax", "al" };
    t[RBX] = .{ "rbx", "ebx", "bx", "bl" };
    t[RCX] = .{ "rcx", "ecx", "cx", "cl" };
    t[RDX] = .{ "rdx", "edx", "dx", "dl" };
    t[RSI] = .{ "rsi", "esi", "si", "sil" };
    t[RDI] = .{ "rdi", "edi", "di", "dil" };
    t[RBP] = .{ "rbp", "ebp", "bp", "bpl" };
    t[RSP] = .{ "rsp", "esp", "sp", "spl" };
    t[R8] = .{ "r8", "r8d", "r8w", "r8b" };
    t[R9] = .{ "r9", "r9d", "r9w", "r9b" };
    t[R10] = .{ "r10", "r10d", "r10w", "r10b" };
    t[R11] = .{ "r11", "r11d", "r11w", "r11b" };
    t[R12] = .{ "r12", "r12d", "r12w", "r12b" };
    t[R13] = .{ "r13", "r13d", "r13w", "r13b" };
    t[R14] = .{ "r14", "r14d", "r14w", "r14b" };
    t[R15] = .{ "r15", "r15d", "r15w", "r15b" };
    break :blk t;
};

fn slot(r: Ref, e: *E) i32 {
    const s = rsval(r);
    assert(s <= e.@"fn".slot);
    // specific to NAlign == 3
    if (s < 0) {
        if (e.fp == RSP)
            return @truncate(@as(i64, 4 * -s - 8) + @as(i64, @bitCast(e.fsz)) + e.nclob * 8)
        else
            return 4 * -s;
    } else if (e.fp == RSP) {
        return 4 * s + e.nclob * 8;
    } else if (e.@"fn".vararg != 0) {
        if (all.T.windows != 0)
            return -4 * (e.@"fn".slot - s)
        else
            return -176 + -4 * (e.@"fn".slot - s);
    } else return -4 * (e.@"fn".slot - s);
}

fn emitcon(con: *Con, e: *E) Writer.Error!void {
    switch (con.type) {
        CAddr => {
            const l = str(con.sym.id);
            const p: [*:0]const u8 = if (l[0] == '"') "" else @ptrCast(&all.T.assym);
            if (con.sym.type == SThr) {
                assert(all.T.apple == 0);
                try e.f.print("%fs:{s}{s}@tpoff", .{cs(p), cs(l)});
            } else {
                assert((con.sym.type & ~@as(i32, SExt)) == SGlo);
                try e.f.print("{s}{s}", .{cs(p), cs(l)});
            }
            if (con.bits.i != 0)
                try e.f.print("{d:1}", .{con.bits.i});
        },
        CBits => try e.f.print("{d}", .{con.bits.i}),
        else => die("unreachable", .{}),
    }
}

var regtoa_buf: [6]u8 = undefined;

fn regtoa(reg: i32, sz: i32) ?[*:0]const u8 {
    assert(reg <= XMM15);
    if (reg >= XMM0) {
        bufPrintZ(&regtoa_buf, "xmm{d}", .{reg - XMM0});
        return @ptrCast(&regtoa_buf);
    } else return rname[@intCast(reg)][@intCast(sz)];
}

fn getarg(c: u8, i: *Ins) Ref {
    switch (c) {
        '0' => return i.arg[0],
        '1' => return i.arg[1],
        '=' => return i.to,
        else => die("invalid arg letter {c}", .{c}),
    }
}

fn emitcopy(r1: Ref, r2: Ref, k: i32, e: *E) Writer.Error!void {
    var icp: Ins = undefined;

    icp.op = Ocopy;
    icp.arg[0] = r2;
    icp.to = r1;
    icp.cls = all.kof(k);
    try emitins(icp, e);
}

const clstoa = [_][*:0]const u8{ "l", "q", "ss", "sd" };

fn emitmem(ref: Ref, e: *E) Writer.Error!void {
    var off: Con = undefined;
    const m = &e.@"fn".mem[ref.val];
    if (rtype(m.base) == RSlot) {
        off.type = CBits;
        off.bits.i = slot(m.base, e);
        _ = addcon(&m.offset, &off, 1);
        m.base = TMP(e.fp);
    }
    if (m.offset.type != CUndef)
        try emitcon(&m.offset, e);
    try e.f.writeByte('(');
    if (!req(m.base, R))
        try e.f.print("%{s}", .{cs(regtoa((m.base.val), SLong))})
    else if (m.offset.type == CAddr)
        try e.f.print("%rip", .{});
    if (!req(m.index, R))
        try e.f.print(", %{s}, {d}", .{cs(regtoa((m.index.val), SLong)), m.scale});
    try e.f.writeByte(')');
}

fn emitf(s_: [*:0]const u8, i: *Ins, e: *E) Writer.Error!void {
    var s = s_;
    var c: u8 = undefined;
    var sz: i32 = undefined;

    switch (s[0]) {
        '+', '-' => {
            if (s[0] == '+') {
                if (req(i.arg[1], i.to)) {
                    const ref = i.arg[0];
                    i.arg[0] = i.arg[1];
                    i.arg[1] = ref;
                }
                // fall through
            }
            assert(!req(i.arg[1], i.to) or req(i.arg[0], i.to)); // cannot convert to 2-address
            try emitcopy(i.to, i.arg[0], all.knum(i.cls), e);
            s += 1;
        },
        else => {},
    }

    try e.f.writeByte('\t');
    while (true) { // Next:
        while (true) {
            c = s[0];
            s += 1;
            if (c == '%') break;
            if (c == 0) {
                try e.f.writeByte('\n');
                return;
            } else try e.f.writeByte(c);
        }
        c = s[0];
        s += 1;
        var doref = false;
        switch (c) {
            '%' => try e.f.writeByte('%'),
            'k' => try e.f.writeAll(cs(clstoa[i.cls.idx()])),
            '0', '1', '=' => {
                sz = if (KWIDE(i.cls) != 0) SLong else SWord;
                s -= 1;
                doref = true;
            },
            'D', 'S' => {
                sz = SLong; // does not matter for floats
                doref = true;
            },
            'L' => {
                sz = SLong;
                doref = true;
            },
            'W' => {
                sz = SWord;
                doref = true;
            },
            'H' => {
                sz = SShort;
                doref = true;
            },
            'B' => {
                sz = SByte;
                doref = true;
            },
            'M' => {
                c = s[0];
                s += 1;
                const ref = getarg(c, i);
                switch (rtype(ref)) {
                    RMem => try emitmem(ref, e),
                    RSlot => try e.f.print("{d}(%{s})", .{slot(ref, e), cs(regtoa(e.fp, SLong))}),
                    RCon => {
                        var off = e.@"fn".con[ref.val];
                        try emitcon(&off, e);
                        if (off.type == CAddr and off.sym.type != SThr)
                            try e.f.print("(%rip)", .{});
                    },
                    RTmp => {
                        assert(isreg(ref));
                        try e.f.print("(%{s})", .{cs(regtoa((ref.val), SLong))});
                    },
                    else => die("unreachable", .{}),
                }
            },
            else => die("invalid format specifier %{c}", .{c}),
        }
        if (doref) { // Ref:
            c = s[0];
            s += 1;
            const ref = getarg(c, i);
            switch (rtype(ref)) {
                RTmp => {
                    assert(isreg(ref));
                    try e.f.print("%{s}", .{cs(regtoa((ref.val), sz))});
                },
                RSlot => try e.f.print("{d}(%{s})", .{slot(ref, e), cs(regtoa(e.fp, SLong))}),
                RMem => try emitmem(ref, e),
                RCon => {
                    try e.f.writeByte('$');
                    try emitcon(&e.@"fn".con[ref.val], e);
                },
                else => die("unreachable", .{}),
            }
        }
    }
}

const negmask = blk: {
    var t: [4]bits = @splat(0);
    t[Ks.idx()] = 0x80000000;
    t[Kd.idx()] = 0x8000000000000000;
    break :blk t;
};

/// Table: most instructions are just pulled out of
/// the table omap[], some special cases are
/// detailed in emitins()
fn emittable(i: *Ins, e: *E) Writer.Error!void {
    var o: usize = 0;
    while (true) : (o += 1) {
        // this linear search should really be a binary
        // search
        if (omap[o].op == .xxx)
            die("no match for {s}({c})", .{cs(all.optab[i.op.int()].name), "wlsd"[i.cls.idx()]});
        if (omap[o].op == i.op)
            if (@intFromEnum(omap[o].cls) == @intFromEnum(i.cls) or
                (omap[o].cls == .i and KBASE(i.cls) == 0) or
                (omap[o].cls == .a))
                break;
    }
    try emitf(omap[o].fmt.?, i, e);
}

fn emitins(i_: Ins, e: *E) Writer.Error!void {
    var i = i_;

    switch (i.op) {
        else => {
            if (isxsel(i.op)) {
                // case_Oxsel:
                if (req(i.to, i.arg[1])) {
                    try emitf(cmov[@intCast(i.op.diff(Oxsel))][0], &i, e);
                } else {
                    if (!req(i.to, i.arg[0]))
                        try emitf("mov %0, %=", &i, e);
                    try emitf(cmov[@intCast(i.op.diff(Oxsel))][1], &i, e);
                }
                return;
            }
            try emittable(&i, e);
        },
        Onop => {
            // just do nothing for nops, they are inserted
            // by some passes
        },
        Omul => {
            // here, we try to use the 3-addresss form
            // of multiplication when possible
            if (rtype(i.arg[1]) == RCon) {
                const r = i.arg[0];
                i.arg[0] = i.arg[1];
                i.arg[1] = r;
            }
            if (KBASE(i.cls) == 0 and // only available for ints
                rtype(i.arg[0]) == RCon and
                rtype(i.arg[1]) == RTmp)
            {
                try emitf("imul%k %0, %1, %=", &i, e);
                return;
            }
            try emittable(&i, e);
        },
        Osub => {
            // we have to use the negation trick to handle
            // some 3-address subtractions
            if (req(i.to, i.arg[1]) and !req(i.arg[0], i.to)) {
                const ineg = INS(Oneg, i.cls, i.to, i.to, R);
                try emitins(ineg, e);
                try emitf("add%k %0, %=", &i, e);
                return;
            }
            try emittable(&i, e);
        },
        Oneg => {
            if (!req(i.to, i.arg[0]))
                try emitf("mov%k %0, %=", &i, e);
            if (KBASE(i.cls) == 0)
                try emitf("neg%k %=", &i, e)
            else
                try e.f.print("\txorp{c} {s}fp{d}(%rip), %{s}\n", .{"xxsd"[i.cls.idx()], cs(&all.T.asloc), stashbits(negmask[i.cls.idx()], 16), cs(regtoa((i.to.val), SLong))});
        },
        Odiv => {
            // use xmm15 to adjust the instruction when the
            // conversion to 2-address in emitf() would fail
            if (req(i.to, i.arg[1])) {
                i.arg[1] = TMP(XMM0 + 15);
                try emitf("mov%k %=, %1", &i, e);
                try emitf("mov%k %0, %=", &i, e);
                i.arg[0] = i.to;
            }
            try emittable(&i, e);
        },
        Ocopy => {
            // copies are used for many things; see my note
            // to understand how to load big constants:
            // https://c9x.me/notes/2015-09-19.html
            assert(rtype(i.to) != RMem);
            if (req(i.to, R) or req(i.arg[0], R))
                return;
            if (req(i.to, i.arg[0]))
                return;
            const t0 = rtype(i.arg[0]);
            if (i.cls == Kl and
                t0 == RCon and
                e.@"fn".con[i.arg[0].val].type == CBits)
            {
                const val = e.@"fn".con[i.arg[0].val].bits.i;
                if (isreg(i.to))
                    if (val >= 0 and val <= std.math.maxInt(u32)) {
                        try emitf("movl %W0, %W=", &i, e);
                        return;
                    };
                if (rtype(i.to) == RSlot)
                    if (val < std.math.minInt(i32) or val > std.math.maxInt(i32)) {
                        try emitf("movl %0, %=", &i, e);
                        try emitf("movl %0>>32, 4+%=", &i, e);
                        return;
                    };
            }
            if (isreg(i.to) and
                t0 == RCon and
                e.@"fn".con[i.arg[0].val].type == CAddr)
            {
                try emitf("lea%k %M0, %=", &i, e);
                return;
            }
            if (rtype(i.to) == RSlot and
                (t0 == RSlot or t0 == RMem))
            {
                i.cls = if (KWIDE(i.cls) != 0) Kd else Ks;
                i.arg[1] = TMP(XMM0 + 15);
                try emitf("mov%k %0, %1", &i, e);
                try emitf("mov%k %1, %=", &i, e);
                return;
            }
            // conveniently, the assembler knows if it
            // should use movabsq when reading movq
            try emitf("mov%k %0, %=", &i, e);
        },
        Oaddr => {
            if (rtype(i.arg[0]) != RCon) {
                try emittable(&i, e);
                return;
            }
            const con = &e.@"fn".con[i.arg[0].val];
            assert(isreg(i.to) and con.type == CAddr);
            const sym = str(con.sym.id);
            const pfx: [*:0]const u8 = if (sym[0] == '"') "" else @ptrCast(&all.T.assym);
            if (all.T.apple != 0 and (con.sym.type & SThr) != 0) {
                try e.f.print("\tmovq {s}{s}@tlvp(%rip), %{s}\n", .{cs(pfx), cs(sym), cs(regtoa((i.to.val), SLong))});
                return;
            }
            if (all.T.windows != 0 and con.sym.type != SGlo)
                die("extern/thread unsupported on amd64_win", .{});
            switch (con.sym.type) {
                SThr => {
                    // derive the symbol address from the TCB
                    // address at offset 0 of %fs
                    try emitf("movq %%fs:0, %L=", &i, e);
                    try e.f.print("\tleaq {s}{s}@tpoff", .{cs(pfx), cs(sym)});
                    if (con.bits.i != 0)
                        try e.f.print("{d:1}", .{con.bits.i});
                    try e.f.print("(%{s}), %{s}\n", .{cs(regtoa((i.to.val), SLong)), cs(regtoa((i.to.val), SLong))});
                },
                SExtThr => {
                    // initial-exec TLS: load offset from
                    // GOT, add to thread-base register
                    assert(con.bits.i == 0);
                    try emitf("movq %%fs:0, %L=", &i, e);
                    try e.f.print("\taddq {s}{s}@gottpoff(%rip), %{s}\n", .{cs(pfx), cs(sym), cs(regtoa((i.to.val), SLong))});
                },
                SExt => {
                    // load address from the GOT
                    assert(con.bits.i == 0);
                    try e.f.print("\tmovq {s}{s}@gotpcrel(%rip), %{s}\n", .{cs(pfx), cs(sym), cs(regtoa((i.to.val), SLong))});
                },
                else => try emittable(&i, e),
            }
        },
        Ocall => {
            // calls simply have a weird syntax in AT&T
            // assembly...
            switch (rtype(i.arg[0])) {
                RCon => {
                    const con = &e.@"fn".con[i.arg[0].val];
                    try e.f.print("\tcallq ", .{});
                    try emitcon(con, e);
                    if (con.type == CAddr and
                        (con.sym.type & SExt) != 0 and
                        all.T.apple == 0)
                        try e.f.print("@plt", .{});
                    try e.f.print("\n", .{});
                },
                RTmp => try emitf("callq *%L0", &i, e),
                else => die("invalid call argument", .{}),
            }
        },
        Osalloc => {
            // there is no good reason why this is here
            // maybe we should split Osalloc in 2 different
            // instructions depending on the result
            assert(e.fp == RBP);
            try emitf("subq %L0, %%rsp", &i, e);
            if (!req(i.to, R))
                try emitcopy(i.to, TMP(RSP), all.knum(Kl), e);
        },
        Oswap => {
            if (KBASE(i.cls) == 0) {
                try emittable(&i, e);
                return;
            }
            // for floats, there is no swap instruction
            // so we use xmm15 as a temporary
            try emitcopy(TMP(XMM0 + 15), i.arg[0], all.knum(i.cls), e);
            try emitcopy(i.arg[0], i.arg[1], all.knum(i.cls), e);
            try emitcopy(i.arg[1], TMP(XMM0 + 15), all.knum(i.cls), e);
        },
        Odbgloc => try emitdbgloc(i.arg[0].val, i.arg[1].val, e.f),
    }
}

fn sysv_framesz(e: *E) void {
    // specific to NAlign == 3
    var o: u64 = 0;
    if (e.@"fn".leaf == 0) {
        var i: usize = 0;
        o = 0;
        while (i < NCLR_SYSV) : (i += 1)
            o ^= e.@"fn".reg >> @intCast(tgt.sysv.amd64_sysv_rclob[i]);
        o &= 1;
    }
    var f: u64 = @intCast(e.@"fn".slot);
    f = (f + 3) & ~@as(u64, 3);
    if (f > 0 and
        e.fp == RSP and
        e.@"fn".salign == 4)
        f += 2;
    e.fsz = 4 * f + 8 * o + 176 * @as(u64, @intCast(e.@"fn".vararg));
}

var sysv_id0: i32 = 0;

pub fn amd64_sysv_emitfn(f: *Fn, fp: *Writer) Writer.Error!void {
    var itmp: Ins = undefined;
    var e_ = E{ .f = fp, .@"fn" = f, .fp = 0, .fsz = 0, .nclob = 0 };
    const e = &e_;
    const rclob = tgt.sysv.amd64_sysv_rclob[0..NCLR_SYSV];
    const rsave = tgt.sysv.amd64_sysv_rsave[0..6];

    try emitfnlnk(f.name.?, &f.lnk, fp);
    try fp.writeAll("\tendbr64\n");
    if (f.leaf == 0 or f.vararg != 0 or f.dynalloc != 0) {
        e.fp = RBP;
        try fp.writeAll("\tpushq %rbp\n\tmovq %rsp, %rbp\n");
    } else e.fp = RSP;
    sysv_framesz(e);
    if (e.fsz != 0)
        try fp.print("\tsubq ${d}, %rsp\n", .{e.fsz});
    if (f.vararg != 0) {
        var o: i32 = -176;
        for (rsave) |r| {
            try fp.print("\tmovq %{s}, {d}(%rbp)\n", .{cs(rname[@intCast(r)][0]), o});
            o += 8;
        }
        var n: i32 = 0;
        while (n < 8) : ({
            n += 1;
            o += 16;
        })
            try fp.print("\tmovaps %xmm{d}, {d}(%rbp)\n", .{n, o});
    }
    for (rclob) |r| {
        if ((f.reg & BIT(r)) != 0) {
            itmp.arg[0] = TMP(r);
            try emitf("pushq %L0", &itmp, e);
            e.nclob += 1;
        }
    }

    var lbl = false;
    var b_it: ?*Blk = f.start;
    while (b_it) |b| : (b_it = b.link) {
        if (lbl or b.npred > 1) {
            var p: uint = 0;
            while (p < b.npred) : (p += 1) {
                if (b.pred[p].id >= b.id)
                    break;
            }
            if (p != b.npred)
                try fp.print(".p2align 4\n", .{});
            try fp.print("{s}bb{d}:\n", .{cs(&all.T.asloc), sysv_id0 + @as(i32, @intCast(b.id))});
        }
        for (b.ins[0..b.nins]) |*i|
            try emitins(i.*, e);
        lbl = true;
        sw: switch (b.jmp.type) {
            Jhlt => try fp.print("\tud2\n", .{}),
            Jret0 => {
                if (f.dynalloc != 0)
                    try fp.print("\tmovq %rbp, %rsp\n" ++ "\tsubq ${d}, %rsp\n", .{e.fsz + @as(u64, @intCast(e.nclob)) * 8});
                var k = rclob.len;
                while (k > 0) {
                    k -= 1;
                    const r = rclob[k];
                    if ((f.reg & BIT(r)) != 0) {
                        itmp.arg[0] = TMP(r);
                        try emitf("popq %L0", &itmp, e);
                    }
                }
                if (e.fp == RBP)
                    try fp.writeAll("\tleave\n")
                else if (e.fsz != 0)
                    try fp.print("\taddq ${d}, %rsp\n", .{e.fsz});
                try fp.writeAll("\tret\n");
            },
            Jjmp => {
                // Jmp:
                if (b.s1 != b.link)
                    try fp.print("\tjmp {s}bb{d}\n", .{cs(&all.T.asloc), sysv_id0 + @as(i32, @intCast(b.s1.?.id))})
                else
                    lbl = false;
            },
            else => {
                const c: i32 = b.jmp.type.int() - Jjf.int();
                if (0 <= c and c <= NCmp) {
                    var n: usize = undefined;
                    if (b.link == b.s2) {
                        const s = b.s1;
                        b.s1 = b.s2;
                        b.s2 = s;
                        n = 0;
                    } else n = 1;
                    try fp.print("\tj{s} {s}bb{d}\n", .{cs(ctoa[@intCast(c)][n]), cs(&all.T.asloc), sysv_id0 + @as(i32, @intCast(b.s2.?.id))});
                    continue :sw Jjmp;
                }
                die("unhandled jump {d}", .{b.jmp.type});
            },
        }
    }
    sysv_id0 += @intCast(f.nblk);
    if (all.T.apple == 0)
        try elf_emitfnfin(f.name.?, fp);
}

fn winabi_framesz(e: *E) void {
    // specific to NAlign == 3
    var o: u64 = 0;
    if (e.@"fn".leaf == 0) {
        var i: usize = 0;
        o = 0;
        while (i < NCLR_WIN) : (i += 1)
            o ^= e.@"fn".reg >> @intCast(tgt.winabi.amd64_winabi_rclob[i]);
        o &= 1;
    }
    var f: u64 = @intCast(e.@"fn".slot);
    f = (f + 3) & ~@as(u64, 3);
    if (f > 0 and
        e.fp == RSP and
        e.@"fn".salign == 4)
        f += 2;
    e.fsz = 4 * f + 8 * o;
}

var winabi_id0: i32 = 0;

pub fn amd64_winabi_emitfn(f: *Fn, fp: *Writer) Writer.Error!void {
    var itmp: Ins = undefined;
    var e_ = E{ .f = fp, .@"fn" = f, .fp = 0, .fsz = 0, .nclob = 0 };
    const e = &e_;
    const rclob = tgt.winabi.amd64_winabi_rclob[0..NCLR_WIN];

    try emitfnlnk(f.name.?, &f.lnk, fp);
    try fp.writeAll("\tendbr64\n");
    if (f.vararg != 0) {
        try fp.print("\tmovq %rcx, 0x8(%rsp)\n", .{});
        try fp.print("\tmovq %rdx, 0x10(%rsp)\n", .{});
        try fp.print("\tmovq %r8, 0x18(%rsp)\n", .{});
        try fp.print("\tmovq %r9, 0x20(%rsp)\n", .{});
    }
    if (f.leaf == 0 or f.vararg != 0 or f.dynalloc != 0) {
        e.fp = RBP;
        try fp.writeAll("\tpushq %rbp\n\tmovq %rsp, %rbp\n");
    } else e.fp = RSP;
    winabi_framesz(e);
    if (e.fsz != 0)
        try fp.print("\tsubq ${d}, %rsp\n", .{e.fsz});
    for (rclob) |r| {
        if ((f.reg & BIT(r)) != 0) {
            itmp.arg[0] = TMP(r);
            try emitf("pushq %L0", &itmp, e);
            e.nclob += 1;
        }
    }

    var lbl = false;
    var b_it: ?*Blk = f.start;
    while (b_it) |b| : (b_it = b.link) {
        if (lbl or b.npred > 1)
            try fp.print("{s}bb{d}:\n", .{cs(&all.T.asloc), winabi_id0 + @as(i32, @intCast(b.id))});
        for (b.ins[0..b.nins]) |*i|
            try emitins(i.*, e);
        lbl = true;
        sw: switch (b.jmp.type) {
            Jhlt => try fp.print("\tud2\n", .{}),
            Jret0 => {
                if (f.dynalloc != 0)
                    try fp.print("\tmovq %rbp, %rsp\n" ++ "\tsubq ${d}, %rsp\n", .{e.fsz + @as(u64, @intCast(e.nclob)) * 8});
                var k = rclob.len;
                while (k > 0) {
                    k -= 1;
                    const r = rclob[k];
                    if ((f.reg & BIT(r)) != 0) {
                        itmp.arg[0] = TMP(r);
                        try emitf("popq %L0", &itmp, e);
                    }
                }
                if (e.fp == RBP)
                    try fp.writeAll("\tleave\n")
                else if (e.fsz != 0)
                    try fp.print("\taddq ${d}, %rsp\n", .{e.fsz});
                try fp.writeAll("\tret\n");
            },
            Jjmp => {
                // Jmp:
                if (b.s1 != b.link)
                    try fp.print("\tjmp {s}bb{d}\n", .{cs(&all.T.asloc), winabi_id0 + @as(i32, @intCast(b.s1.?.id))})
                else
                    lbl = false;
            },
            else => {
                const c: i32 = b.jmp.type.int() - Jjf.int();
                if (0 <= c and c <= NCmp) {
                    var n: usize = undefined;
                    if (b.link == b.s2 or c >= NCmpI) {
                        const s = b.s1;
                        b.s1 = b.s2;
                        b.s2 = s;
                        n = 0;
                    } else n = 1;
                    try fp.print("\tj{s} {s}bb{d}\n", .{cs(ctoa[@intCast(c)][n]), cs(&all.T.asloc), winabi_id0 + @as(i32, @intCast(b.s2.?.id))});
                    continue :sw Jjmp;
                }
                die("unhandled jump {d}", .{b.jmp.type});
            },
        }
    }
    winabi_id0 += @intCast(f.nblk);
}
