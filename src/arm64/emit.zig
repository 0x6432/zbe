//! One-to-one translation of arm64/emit.c
const std = @import("std");
const assert = std.debug.assert;
const C = @import("../libc.zig");
// -- imports --
const all = @import("../all.zig");
const tgt = @import("all.zig");
const BIT = all.BIT;
const CAddr = all.CAddr;
const CBits = all.CBits;
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
const FILE = all.FILE;
const Fn = all.Fn;
const INS = all.INS;
const IP1 = tgt.IP1;
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
const Kx = all.Kx;
const LR = tgt.LR;
const NCmp = all.NCmp;
const NCmpI = all.NCmpI;
const NOp = all.NOp;
const Oacmn = all.ops.Oacmn;
const Oacmp = all.ops.Oacmp;
const Oadd = all.ops.Oadd;
const Oaddr = all.ops.Oaddr;
const Oafcmp = all.ops.Oafcmp;
const Oand = all.ops.Oand;
const Ocall = all.ops.Ocall;
const Ocast = all.ops.Ocast;
const Ocopy = all.ops.Ocopy;
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
const Oflag = all.Oflag;
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
const R0 = tgt.R0;
const R18 = tgt.R18;
const RCon = all.RCon;
const RSlot = all.RSlot;
const RTmp = all.RTmp;
const Ref = all.Ref;
const SExt = all.SExt;
const SExtThr = all.SExtThr;
const SGlo = all.SGlo;
const SLOT = all.SLOT;
const SP = tgt.SP;
const SThr = all.SThr;
const TMP = all.TMP;
const V0 = tgt.V0;
const V30 = tgt.V30;
const arm64_logimm = tgt.arm64_logimm;
const arm64_rclob = tgt.arm64_rclob;
const die = all.die;
const elf_emitfnfin = all.elf_emitfnfin;
const emitdbgloc = all.emitdbgloc;
const emitfnlnk = all.emitfnlnk;
const isload = all.isload;
const isreg = all.isreg;
const isstore = all.isstore;
const loadsz = all.loadsz;
const req = all.req;
const rsval = all.rsval;
const rtype = all.rtype;
const storesz = all.storesz;
const str = all.str;
const uint = all.uint;
// -- end imports --

const E = struct {
    f: *FILE,
    @"fn": [*c]Fn,
    frame: u64,
    padding: uint,
};

const CmpX = struct { c: comptime_int, s0: []const u8, s1: []const u8 };
const CMP = [_]CmpX{
    .{ .c = Cieq, .s0 = "eq", .s1 = "ne" },
    .{ .c = Cine, .s0 = "ne", .s1 = "eq" },
    .{ .c = Cisge, .s0 = "ge", .s1 = "lt" },
    .{ .c = Cisgt, .s0 = "gt", .s1 = "le" },
    .{ .c = Cisle, .s0 = "le", .s1 = "gt" },
    .{ .c = Cislt, .s0 = "lt", .s1 = "ge" },
    .{ .c = Ciuge, .s0 = "cs", .s1 = "cc" },
    .{ .c = Ciugt, .s0 = "hi", .s1 = "ls" },
    .{ .c = Ciule, .s0 = "ls", .s1 = "hi" },
    .{ .c = Ciult, .s0 = "cc", .s1 = "cs" },
    .{ .c = NCmpI + Cfeq, .s0 = "eq", .s1 = "ne" },
    .{ .c = NCmpI + Cfge, .s0 = "ge", .s1 = "lt" },
    .{ .c = NCmpI + Cfgt, .s0 = "gt", .s1 = "le" },
    .{ .c = NCmpI + Cfle, .s0 = "ls", .s1 = "hi" },
    .{ .c = NCmpI + Cflt, .s0 = "mi", .s1 = "pl" },
    .{ .c = NCmpI + Cfne, .s0 = "ne", .s1 = "eq" },
    .{ .c = NCmpI + Cfo, .s0 = "vc", .s1 = "vs" },
    .{ .c = NCmpI + Cfuo, .s0 = "vs", .s1 = "vc" },
};

const Ki = -1; // matches Kw and Kl
const Ka = -2; // matches all classes

const OMap = struct {
    op: i16,
    cls: i16,
    fmt: [*c]const u8,
};
const omap = blk: {
    const base = [_]OMap{
        .{ .op = Oadd, .cls = Ki, .fmt = "add %=, %0, %1" },
        .{ .op = Oadd, .cls = Ka, .fmt = "fadd %=, %0, %1" },
        .{ .op = Osub, .cls = Ki, .fmt = "sub %=, %0, %1" },
        .{ .op = Osub, .cls = Ka, .fmt = "fsub %=, %0, %1" },
        .{ .op = Oneg, .cls = Ki, .fmt = "neg %=, %0" },
        .{ .op = Oneg, .cls = Ka, .fmt = "fneg %=, %0" },
        .{ .op = Oand, .cls = Ki, .fmt = "and %=, %0, %1" },
        .{ .op = Oor, .cls = Ki, .fmt = "orr %=, %0, %1" },
        .{ .op = Oxor, .cls = Ki, .fmt = "eor %=, %0, %1" },
        .{ .op = Osar, .cls = Ki, .fmt = "asr %=, %0, %1" },
        .{ .op = Oshr, .cls = Ki, .fmt = "lsr %=, %0, %1" },
        .{ .op = Oshl, .cls = Ki, .fmt = "lsl %=, %0, %1" },
        .{ .op = Omul, .cls = Ki, .fmt = "mul %=, %0, %1" },
        .{ .op = Omul, .cls = Ka, .fmt = "fmul %=, %0, %1" },
        .{ .op = Odiv, .cls = Ki, .fmt = "sdiv %=, %0, %1" },
        .{ .op = Odiv, .cls = Ka, .fmt = "fdiv %=, %0, %1" },
        .{ .op = Oudiv, .cls = Ki, .fmt = "udiv %=, %0, %1" },
        .{ .op = Orem, .cls = Ki, .fmt = "sdiv %?, %0, %1\n\tmsub\t%=, %?, %1, %0" },
        .{ .op = Ourem, .cls = Ki, .fmt = "udiv %?, %0, %1\n\tmsub\t%=, %?, %1, %0" },
        .{ .op = Ocopy, .cls = Ki, .fmt = "mov %=, %0" },
        .{ .op = Ocopy, .cls = Ka, .fmt = "fmov %=, %0" },
        .{ .op = Oswap, .cls = Ki, .fmt = "mov %?, %0\n\tmov\t%0, %1\n\tmov\t%1, %?" },
        .{ .op = Oswap, .cls = Ka, .fmt = "fmov %?, %0\n\tfmov\t%0, %1\n\tfmov\t%1, %?" },
        .{ .op = Ostoreb, .cls = Kw, .fmt = "strb %W0, %M1" },
        .{ .op = Ostoreh, .cls = Kw, .fmt = "strh %W0, %M1" },
        .{ .op = Ostorew, .cls = Kw, .fmt = "str %W0, %M1" },
        .{ .op = Ostorel, .cls = Kw, .fmt = "str %L0, %M1" },
        .{ .op = Ostores, .cls = Kw, .fmt = "str %S0, %M1" },
        .{ .op = Ostored, .cls = Kw, .fmt = "str %D0, %M1" },
        .{ .op = Oloadsb, .cls = Ki, .fmt = "ldrsb %=, %M0" },
        .{ .op = Oloadub, .cls = Ki, .fmt = "ldrb %W=, %M0" },
        .{ .op = Oloadsh, .cls = Ki, .fmt = "ldrsh %=, %M0" },
        .{ .op = Oloaduh, .cls = Ki, .fmt = "ldrh %W=, %M0" },
        .{ .op = Oloadsw, .cls = Kw, .fmt = "ldr %=, %M0" },
        .{ .op = Oloadsw, .cls = Kl, .fmt = "ldrsw %=, %M0" },
        .{ .op = Oloaduw, .cls = Ki, .fmt = "ldr %W=, %M0" },
        .{ .op = Oload, .cls = Ka, .fmt = "ldr %=, %M0" },
        .{ .op = Oextsb, .cls = Ki, .fmt = "sxtb %=, %W0" },
        .{ .op = Oextub, .cls = Ki, .fmt = "uxtb %W=, %W0" },
        .{ .op = Oextsh, .cls = Ki, .fmt = "sxth %=, %W0" },
        .{ .op = Oextuh, .cls = Ki, .fmt = "uxth %W=, %W0" },
        .{ .op = Oextsw, .cls = Ki, .fmt = "sxtw %L=, %W0" },
        .{ .op = Oextuw, .cls = Ki, .fmt = "mov %W=, %W0" },
        .{ .op = Oexts, .cls = Kd, .fmt = "fcvt %=, %S0" },
        .{ .op = Otruncd, .cls = Ks, .fmt = "fcvt %=, %D0" },
        .{ .op = Ocast, .cls = Kw, .fmt = "fmov %=, %S0" },
        .{ .op = Ocast, .cls = Kl, .fmt = "fmov %=, %D0" },
        .{ .op = Ocast, .cls = Ks, .fmt = "fmov %=, %W0" },
        .{ .op = Ocast, .cls = Kd, .fmt = "fmov %=, %L0" },
        .{ .op = Ostosi, .cls = Ka, .fmt = "fcvtzs %=, %S0" },
        .{ .op = Ostoui, .cls = Ka, .fmt = "fcvtzu %=, %S0" },
        .{ .op = Odtosi, .cls = Ka, .fmt = "fcvtzs %=, %D0" },
        .{ .op = Odtoui, .cls = Ka, .fmt = "fcvtzu %=, %D0" },
        .{ .op = Oswtof, .cls = Ka, .fmt = "scvtf %=, %W0" },
        .{ .op = Ouwtof, .cls = Ka, .fmt = "ucvtf %=, %W0" },
        .{ .op = Osltof, .cls = Ka, .fmt = "scvtf %=, %L0" },
        .{ .op = Oultof, .cls = Ka, .fmt = "ucvtf %=, %L0" },
        .{ .op = Ocall, .cls = Kw, .fmt = "blr %L0" },

        .{ .op = Oacmp, .cls = Ki, .fmt = "cmp %0, %1" },
        .{ .op = Oacmn, .cls = Ki, .fmt = "cmn %0, %1" },
        .{ .op = Oafcmp, .cls = Ka, .fmt = "fcmpe %0, %1" },
    };
    var flags: [CMP.len]OMap = undefined;
    for (CMP, 0..) |x, n|
        flags[n] = .{ .op = Oflag + x.c, .cls = Ki, .fmt = "cset %=, " ++ x.s0 };
    const tail = [_]OMap{
        .{ .op = NOp, .cls = 0, .fmt = null },
    };
    break :blk base ++ flags ++ tail;
};

const V31 = 0x1fffffff; // local name for V31

var rname_buf: [4]u8 = undefined;

fn rname(r: i32, k: i32) [*c]u8 {
    const buf: [*c]u8 = &rname_buf;
    if (r == SP) {
        assert(k == Kl);
        _ = C.sprintf(buf, "sp");
    } else if (R0 <= r and r <= LR) {
        switch (k) {
            else => die("invalid class", .{}),
            Kw => _ = C.sprintf(buf, "w%d", @as(c_int, r - R0)),
            Kx, Kl => _ = C.sprintf(buf, "x%d", @as(c_int, r - R0)),
        }
    } else if (V0 <= r and r <= V30) {
        switch (k) {
            else => die("invalid class", .{}),
            Ks => _ = C.sprintf(buf, "s%d", @as(c_int, r - V0)),
            Kx, Kd => _ = C.sprintf(buf, "d%d", @as(c_int, r - V0)),
        }
    } else if (r == V31) {
        switch (k) {
            else => die("invalid class", .{}),
            Ks => _ = C.sprintf(buf, "s31"),
            Kd => _ = C.sprintf(buf, "d31"),
        }
    } else die("invalid register", .{});
    return buf;
}

fn slot(r: Ref, e: *E) u64 {
    const s = rsval(r);
    if (s == -1)
        return 16 + e.frame;
    if (s < 0) {
        const s2: u64 = @bitCast(@as(i64, s + 2));
        if (e.@"fn".*.vararg != 0 and all.T.apple == 0)
            return (16 + e.frame + 192) -% s2
        else
            return (16 + e.frame) -% s2;
    } else return 16 + @as(u64, e.padding +% 4 *% @as(u32, @bitCast(s)));
}

fn emitf(s_: [*c]const u8, i: [*c]Ins, e: *E) void {
    var s = s_;
    var r: Ref = undefined;
    var c: u8 = undefined;

    _ = C.fputc('\t', e.f);

    var sp = false;
    while (true) {
        var k: i32 = @intCast(i.*.cls);
        while (true) {
            c = s.*;
            s += 1;
            if (c == '%') break;
            if (c == ' ' and !sp) {
                _ = C.fputc('\t', e.f);
                sp = true;
            } else if (c == 0) {
                _ = C.fputc('\n', e.f);
                return;
            } else _ = C.fputc(c, e.f);
        }
        sw: while (true) { // Switch:
            c = s.*;
            s += 1;
            switch (c) {
                else => die("invalid escape", .{}),
                'W' => {
                    k = Kw;
                    continue :sw;
                },
                'L' => {
                    k = Kl;
                    continue :sw;
                },
                'S' => {
                    k = Ks;
                    continue :sw;
                },
                'D' => {
                    k = Kd;
                    continue :sw;
                },
                '?' => {
                    if (KBASE(k) == 0)
                        _ = C.fputs(rname(IP1, k), e.f)
                    else
                        _ = C.fputs(rname(V31, k), e.f);
                },
                '=', '0' => {
                    r = if (c == '=') i.*.to else i.*.arg[0];
                    assert(isreg(r) or req(r, TMP(V31)));
                    _ = C.fputs(rname(@intCast(r.val), k), e.f);
                },
                '1' => {
                    r = i.*.arg[1];
                    switch (rtype(r)) {
                        else => die("invalid second argument", .{}),
                        RTmp => {
                            assert(isreg(r));
                            _ = C.fputs(rname(@intCast(r.val), k), e.f);
                        },
                        RCon => {
                            const pc = &e.@"fn".*.con[r.val];
                            const n: u64 = @bitCast(pc.*.bits.i);
                            assert(pc.*.type == CBits);
                            if ((n >> 24) != 0) {
                                assert(arm64_logimm(n, k));
                                _ = C.fprintf(e.f, "#%lu", @as(c_ulong, n));
                            } else if ((n & 0xfff000) != 0) {
                                assert((n & ~@as(u64, 0xfff000)) == 0);
                                _ = C.fprintf(e.f, "#%lu, lsl #12", @as(c_ulong, n >> 12));
                            } else {
                                assert((n & ~@as(u64, 0xfff)) == 0);
                                _ = C.fprintf(e.f, "#%lu", @as(c_ulong, n));
                            }
                        },
                    }
                },
                'M' => {
                    c = s.*;
                    s += 1;
                    assert(c == '0' or c == '1' or c == '=');
                    r = if (c == '=') i.*.to else i.*.arg[c - '0'];
                    switch (rtype(r)) {
                        else => die("todo (arm emit): unhandled ref", .{}),
                        RTmp => {
                            assert(isreg(r));
                            _ = C.fprintf(e.f, "[%s]", rname(@intCast(r.val), Kl));
                        },
                        RSlot => _ = C.fprintf(e.f, "[x29, %lu]", @as(c_ulong, slot(r, e))),
                    }
                },
            }
            break;
        }
    }
}

fn loadaddr(c: [*c]Con, rn: [*c]u8, e: *E) void {
    var s: [*c]const u8 = undefined;

    switch (c.*.sym.type) {
        else => die("unreachable", .{}),
        SGlo => {
            if (all.T.apple != 0)
                s = "\tadrp\tR, S@pageO\n" ++
                    "\tadd\tR, R, S@pageoffO\n"
            else
                s = "\tadrp\tR, SO\n" ++
                    "\tadd\tR, R, #:lo12:SO\n";
        },
        SExtThr, SThr => {
            if (c.*.sym.type == SExtThr and all.T.apple == 0)
                die("extern thread unavailable on arm64", .{});
            if (all.T.apple != 0)
                s = "\tadrp\tR, S@tlvppage\n" ++
                    "\tldr\tR, [R, S@tlvppageoff]\n"
            else
                s = "\tmrs\tR, tpidr_el0\n" ++
                    "\tadd\tR, R, #:tprel_hi12:SO, lsl #12\n" ++
                    "\tadd\tR, R, #:tprel_lo12_nc:SO\n";
        },
        SExt => {
            assert(c.*.bits.i == 0);
            if (all.T.apple != 0)
                s = "\tadrp\tR, S@gotpage\n" ++
                    "\tldr\tR, [R, S@gotpageoff]\n"
            else
                s = "\tadrp\tR, :got:S\n" ++
                    "\tldr\tR, [R, #:got_lo12:S]\n";
        },
    }

    const l = str(c.*.sym.id);
    const p: [*c]const u8 = if (l[0] == '"') "" else &all.T.assym;
    while (s.* != 0) : (s += 1) {
        switch (s.*) {
            else => _ = C.fputc(s.*, e.f),
            'R' => _ = C.fputs(rn, e.f),
            'S' => {
                _ = C.fputs(p, e.f);
                _ = C.fputs(l, e.f);
            },
            'O' => {
                if (c.*.bits.i != 0)
                    // todo, handle large offsets
                    _ = C.fprintf(e.f, "+%ld", @as(c_long, c.*.bits.i));
            },
        }
    }
}

fn loadcon(c: [*c]Con, r: i32, k: i32, e: *E) void {
    const w = KWIDE(k);
    var rn = rname(r, k);
    var n = c.*.bits.i;
    if (c.*.type == CAddr) {
        rn = rname(r, Kl);
        loadaddr(c, rn, e);
        return;
    }
    assert(c.*.type == CBits);
    if (w == 0)
        n = @as(i32, @truncate(n));
    if ((n | 0xffff) == -1 or arm64_logimm(@bitCast(n), k)) {
        _ = C.fprintf(e.f, "\tmov\t%s, #%ld\n", rn, @as(c_long, n));
    } else {
        _ = C.fprintf(e.f, "\tmov\t%s, #%d\n", rn, @as(c_int, @intCast(n & 0xffff)));
        var sh: i32 = 16;
        while (true) : (sh += 16) {
            n >>= 16;
            if (n == 0) break;
            if ((w == 0 and sh == 32) or sh == 64)
                break;
            _ = C.fprintf(e.f, "\tmovk\t%s, #0x%x, lsl #%d\n", rn, @as(c_uint, @intCast(n & 0xffff)), @as(c_int, sh));
        }
    }
}

fn fixarg(pr: [*c]Ref, sz: i32, t: i32, e: *E) bool {
    const r = pr.*;
    if (rtype(r) == RSlot) {
        const s = slot(r, e);
        if (s > @as(u32, @bitCast(sz)) *% 4095) {
            if (t < 0)
                return true;
            var i = INS(Oaddr, Kl, TMP(t), r, R);
            emitins(&i, e);
            pr.* = TMP(t);
        }
    }
    return false;
}

fn emitins(i: [*c]Ins, e: *E) void {
    switch (i.*.op) {
        else => {
            if (isload(i.*.op))
                _ = fixarg(&i.*.arg[0], loadsz(i), IP1, e);
            if (isstore(i.*.op)) {
                const t: i32 = if (all.T.apple != 0) -1 else R18;
                if (fixarg(&i.*.arg[1], storesz(i), t, e)) {
                    if (req(i.*.arg[0], TMP(IP1))) {
                        _ = C.fprintf(e.f, "\tfmov\t%c31, %c17\n", @as(c_int, "ds"[@intFromBool(i.*.cls == Kw)]), @as(c_int, "xw"[@intFromBool(i.*.cls == Kw)]));
                        i.*.arg[0] = TMP(V31);
                        i.*.op = Ostores + (i.*.cls - Kw);
                    }
                    _ = fixarg(&i.*.arg[1], storesz(i), IP1, e);
                }
            }
            table(i, e);
        },
        Onop => {},
        Ocopy => {
            if (req(i.*.to, i.*.arg[0]))
                return;
            if (rtype(i.*.to) == RSlot) {
                const r = i.*.to;
                if (!isreg(i.*.arg[0])) {
                    i.*.to = TMP(IP1);
                    emitins(i, e);
                    i.*.arg[0] = i.*.to;
                }
                i.*.op = Ostorew + i.*.cls;
                i.*.cls = Kw;
                i.*.arg[1] = r;
                emitins(i, e);
                return;
            }
            assert(isreg(i.*.to));
            switch (rtype(i.*.arg[0])) {
                RCon => {
                    const c = &e.@"fn".*.con[i.*.arg[0].val];
                    loadcon(c, @intCast(i.*.to.val), @intCast(i.*.cls), e);
                },
                RSlot => {
                    i.*.op = Oload;
                    emitins(i, e);
                },
                else => {
                    assert(i.*.to.val != IP1);
                    table(i, e);
                },
            }
        },
        Oaddr => {
            assert(rtype(i.*.arg[0]) == RSlot);
            const rn = rname(@intCast(i.*.to.val), Kl);
            const s = slot(i.*.arg[0], e);
            if (s <= 4095)
                _ = C.fprintf(e.f, "\tadd\t%s, x29, #%lu\n", rn, @as(c_ulong, s))
            else if (s <= 65535)
                _ = C.fprintf(e.f, "\tmov\t%s, #%lu\n" ++
                    "\tadd\t%s, x29, %s\n", rn, @as(c_ulong, s), rn, rn)
            else
                _ = C.fprintf(e.f, "\tmov\t%s, #%lu\n" ++
                    "\tmovk\t%s, #%lu, lsl #16\n" ++
                    "\tadd\t%s, x29, %s\n", rn, @as(c_ulong, s & 0xFFFF), rn, @as(c_ulong, s >> 16), rn, rn);
        },
        Ocall => {
            if (rtype(i.*.arg[0]) != RCon) {
                table(i, e);
                return;
            }
            const c = &e.@"fn".*.con[i.*.arg[0].val];
            if (c.*.type != CAddr or
                (c.*.sym.type & SThr) != 0 or
                c.*.bits.i != 0)
                die("invalid call argument", .{});
            const l = str(c.*.sym.id);
            const p: [*c]const u8 = if (l[0] == '"') "" else &all.T.assym;
            _ = C.fprintf(e.f, "\tbl\t%s%s\n", p, l);
        },
        Osalloc => {
            emitf("sub sp, sp, %0", i, e);
            if (!req(i.*.to, R))
                emitf("mov %=, sp", i, e);
        },
        Odbgloc => emitdbgloc(i.*.arg[0].val, i.*.arg[1].val, e.f),
    }
}

/// Table: most instructions are just pulled out of
/// the table omap[], some special cases are
/// detailed in emitins
fn table(i: [*c]Ins, e: *E) void {
    var o: usize = 0;
    while (true) : (o += 1) {
        // this linear search should really be a binary
        // search
        if (omap[o].op == NOp)
            die("no match for %s(%c)", .{ all.optab[i.*.op].name, @as(c_int, "wlsd"[i.*.cls]) });
        if (omap[o].op == i.*.op and
            (omap[o].cls == i.*.cls or omap[o].cls == Ka or
            (omap[o].cls == Ki and KBASE(i.*.cls) == 0)))
            break;
    }
    emitf(omap[o].fmt, i, e);
}

fn framelayout(e: *E) void {
    var o: uint = 0;
    var r: [*c]i32 = arm64_rclob;
    while (r.* >= 0) : (r += 1)
        o += @intCast(1 & (e.@"fn".*.reg >> @intCast(r.*)));
    var f: u64 = @intCast(e.@"fn".*.slot);
    f = (f + 3) & ~@as(u64, 3);
    o += o & 1;
    e.padding = @truncate(4 * (f - @as(u64, @intCast(e.@"fn".*.slot))));
    e.frame = 4 * f + 8 * @as(u64, o);
}

// Stack-frame layout:
//
// +=============+
// | varargs     |
// |  save area  |
// +-------------+
// | callee-save |  ^
// |  registers  |  |
// +-------------+  |
// |    ...      |  |
// | spill slots |  |
// |    ...      |  | e->frame
// +-------------+  |
// |    ...      |  |
// |   locals    |  |
// |    ...      |  |
// +-------------+  |
// | e->padding  |  v
// +-------------+
// |  saved x29  |
// |  saved x30  |
// +=============+ <- x29

const ctoa = blk: {
    var t: [NCmp][2][*c]const u8 = @splat(.{ null, null });
    for (CMP) |x|
        t[x.c] = .{ x.s0 ++ "", x.s1 ++ "" };
    break :blk t;
};

var id0: i32 = 0;

pub fn arm64_emitfn(f: [*c]Fn, out: *FILE) void {
    var e_ = E{ .f = out, .@"fn" = f, .frame = 0, .padding = 0 };
    const e = &e_;
    if (all.T.apple != 0)
        e.@"fn".*.lnk.@"align" = 4;
    emitfnlnk(e.@"fn".*.name, &e.@"fn".*.lnk, e.f);
    _ = C.fputs("\thint\t#34\n", e.f);
    framelayout(e);

    if (e.@"fn".*.vararg != 0 and all.T.apple == 0) {
        var n: i32 = 7;
        while (n >= 0) : (n -= 1)
            _ = C.fprintf(e.f, "\tstr\tq%d, [sp, -16]!\n", @as(c_int, n));
        n = 7;
        while (n >= 0) : (n -= 2)
            _ = C.fprintf(e.f, "\tstp\tx%d, x%d, [sp, -16]!\n", @as(c_int, n - 1), @as(c_int, n));
    }

    if (e.frame + 16 <= 512)
        _ = C.fprintf(e.f, "\tstp\tx29, x30, [sp, -%lu]!\n", @as(c_ulong, e.frame + 16))
    else if (e.frame <= 4095)
        _ = C.fprintf(e.f, "\tsub\tsp, sp, #%lu\n" ++
            "\tstp\tx29, x30, [sp, -16]!\n", @as(c_ulong, e.frame))
    else if (e.frame <= 65535)
        _ = C.fprintf(e.f, "\tmov\tx16, #%lu\n" ++
            "\tsub\tsp, sp, x16\n" ++
            "\tstp\tx29, x30, [sp, -16]!\n", @as(c_ulong, e.frame))
    else
        _ = C.fprintf(e.f, "\tmov\tx16, #%lu\n" ++
            "\tmovk\tx16, #%lu, lsl #16\n" ++
            "\tsub\tsp, sp, x16\n" ++
            "\tstp\tx29, x30, [sp, -16]!\n", @as(c_ulong, e.frame & 0xFFFF), @as(c_ulong, e.frame >> 16));
    _ = C.fputs("\tmov\tx29, sp\n", e.f);
    var s: i32 = @intCast((e.frame - e.padding) / 4);
    var r: [*c]i32 = arm64_rclob;
    while (r.* >= 0) : (r += 1) {
        if ((e.@"fn".*.reg & BIT(r.*)) != 0) {
            s -= 2;
            var i = INS(@as(i32, if (r.* >= V0) Ostored else Ostorel), 0, R, TMP(r.*), SLOT(s));
            emitins(&i, e);
        }
    }

    var lbl = false;
    var b = e.@"fn".*.start;
    while (b != null) : (b = b.*.link) {
        if (lbl or b.*.npred > 1)
            _ = C.fprintf(e.f, "%s%d:\n", &all.T.asloc, @as(c_int, id0 + @as(i32, @intCast(b.*.id))));
        var i = b.*.ins;
        while (i != b.*.ins + b.*.nins) : (i += 1)
            emitins(i, e);
        lbl = true;
        var jmp = false;
        switch (b.*.jmp.type) {
            Jhlt => _ = C.fprintf(e.f, "\tbrk\t#1000\n"),
            Jret0 => {
                s = @intCast((e.frame - e.padding) / 4);
                r = arm64_rclob;
                while (r.* >= 0) : (r += 1) {
                    if ((e.@"fn".*.reg & BIT(r.*)) != 0) {
                        s -= 2;
                        var in = INS(Oload, @as(i32, if (r.* >= V0) Kd else Kl), TMP(r.*), SLOT(s), R);
                        emitins(&in, e);
                    }
                }
                if (e.@"fn".*.dynalloc != 0)
                    _ = C.fputs("\tmov sp, x29\n", e.f);
                var o = e.frame + 16;
                if (e.@"fn".*.vararg != 0 and all.T.apple == 0)
                    o += 192;
                if (o <= 504)
                    _ = C.fprintf(e.f, "\tldp\tx29, x30, [sp], %lu\n", @as(c_ulong, o))
                else if (o - 16 <= 4095)
                    _ = C.fprintf(e.f, "\tldp\tx29, x30, [sp], 16\n" ++
                        "\tadd\tsp, sp, #%lu\n", @as(c_ulong, o - 16))
                else if (o - 16 <= 65535)
                    _ = C.fprintf(e.f, "\tldp\tx29, x30, [sp], 16\n" ++
                        "\tmov\tx16, #%lu\n" ++
                        "\tadd\tsp, sp, x16\n", @as(c_ulong, o - 16))
                else
                    _ = C.fprintf(e.f, "\tldp\tx29, x30, [sp], 16\n" ++
                        "\tmov\tx16, #%lu\n" ++
                        "\tmovk\tx16, #%lu, lsl #16\n" ++
                        "\tadd\tsp, sp, x16\n", @as(c_ulong, (o - 16) & 0xFFFF), @as(c_ulong, (o - 16) >> 16));
                _ = C.fprintf(e.f, "\tret\n");
            },
            Jjmp => jmp = true,
            else => {
                const c: i32 = @as(i32, @intCast(b.*.jmp.type)) - Jjf;
                if (c < 0 or c > NCmp)
                    die("unhandled jump %d", .{@as(c_int, @intCast(b.*.jmp.type))});
                var n: usize = undefined;
                if (b.*.link == b.*.s2) {
                    const t = b.*.s1;
                    b.*.s1 = b.*.s2;
                    b.*.s2 = t;
                    n = 0;
                } else n = 1;
                _ = C.fprintf(e.f, "\tb%s\t%s%d\n", ctoa[@intCast(c)][n], &all.T.asloc, @as(c_int, id0 + @as(i32, @intCast(b.*.s2.*.id))));
                jmp = true;
            },
        }
        if (jmp) { // Jmp:
            if (b.*.s1 != b.*.link)
                _ = C.fprintf(e.f, "\tb\t%s%d\n", &all.T.asloc, @as(c_int, id0 + @as(i32, @intCast(b.*.s1.*.id))))
            else
                lbl = false;
        }
    }
    id0 += @intCast(e.@"fn".*.nblk);
    if (all.T.apple == 0)
        elf_emitfnfin(f.*.name, out);
}
