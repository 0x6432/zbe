//! One-to-one translation of parse.c
const std = @import("std");
const assert = std.debug.assert;
// -- imports --
const all = @import("all.zig");
const BSet = all.BSet;
const Blk = all.Blk;
const CAddr = all.CAddr;
const CBits = all.CBits;
const CUndef = all.CUndef;
const Con = all.Con;
const DB = all.DB;
const DEnd = all.DEnd;
const DH = all.DH;
const DL = all.DL;
const DStart = all.DStart;
const DW = all.DW;
const DZ = all.DZ;
const Dat = all.Dat;
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
const INT = all.INT;
const Ins = all.Ins;
const Jhlt = all.Jhlt;
const Jjmp = all.Jjmp;
const Jjnz = all.Jjnz;
const Jret0 = all.Jret0;
const Jretc = all.Jretc;
const Jretd = all.Jretd;
const Jretl = all.Jretl;
const Jrets = all.Jrets;
const Jretsb = all.Jretsb;
const Jretsh = all.Jretsh;
const Jretub = all.Jretub;
const Jretuh = all.Jretuh;
const Jretw = all.Jretw;
const Jxxx = all.Jxxx;
const Kd = all.Kd;
const Kl = all.Kl;
const Ks = all.Ks;
const Kw = all.Kw;
const Kx = all.Kx;
const Lnk = all.Lnk;
const Mem = all.Mem;
const NField = all.NField;
const NIns = all.NIns;
const NOp = all.NOp;
const NPubOp = all.NPubOp;
const Oacmn = all.ops.Oacmn;
const Oacmp = all.ops.Oacmp;
const Oafcmp = all.ops.Oafcmp;
const Oalloc = all.Oalloc;
const Oarg = all.ops.Oarg;
const Oargc = all.ops.Oargc;
const Oarge = all.ops.Oarge;
const Oargsb = all.ops.Oargsb;
const Oargv = all.ops.Oargv;
const Oblit0 = all.ops.Oblit0;
const Oblit1 = all.ops.Oblit1;
const Ocall = all.ops.Ocall;
const Odbgloc = all.ops.Odbgloc;
const Oload = all.ops.Oload;
const Oloadsw = all.ops.Oloadsw;
const Op = all.Op;
const Opar = all.ops.Opar;
const Oparc = all.ops.Oparc;
const Opare = all.ops.Opare;
const Oparsb = all.ops.Oparsb;
const Oswap = all.ops.Oswap;
const Ovastart = all.ops.Ovastart;
const Oxcmp = all.ops.Oxcmp;
const Oxdiv = all.ops.Oxdiv;
const Oxidiv = all.ops.Oxidiv;
const Oxtest = all.ops.Oxtest;
const PFn = all.PFn;
const PHeap = all.PHeap;
const Phi = all.Phi;
const R = all.R;
const RCall = all.RCall;
const RCon = all.RCon;
const RInt = all.RInt;
const RMem = all.RMem;
const RSlot = all.RSlot;
const RTmp = all.RTmp;
const RType = all.RType;
const Ref = all.Ref;
const SExt = all.SExt;
const SThr = all.SThr;
const TMP = all.TMP;
const TYPE = all.TYPE;
const Tmp = all.Tmp;
const Tmp0 = all.Tmp0;
const Typ = all.Typ;
const UNDEF = all.UNDEF;
const Writer = all.Writer;
const bsequal = all.bsequal;
const bshas = all.bshas;
const bsinit = all.bsinit;
const bsset = all.bsset;
const bszero = all.bszero;
const cfloat = all.cfloat;
const clsmerge = all.clsmerge;
const cs = all.cs;
const dprint = all.dprint;
const ealloc = all.ealloc;
const efree = all.efree;
const fillpreds = all.fillpreds;
const hash = all.hash;
const idup = all.idup;
const intern = all.intern;
const isret = all.isret;
const isstore = all.isstore;
const newblk = all.newblk;
const newcon = all.newcon;
const newtmp = all.newtmp;
const palloc = all.palloc;
const ptrdiff = all.ptrdiff;
const req = all.req;
const rsval = all.rsval;
const rtype = all.rtype;
const str = all.str;
const streq = all.streq;
const strf = all.strf;
const uchar = all.uchar;
const uint = all.uint;
const vfree = all.vfree;
const vgrow = all.vgrow;
const vnewT = all.vnewT;
// -- end imports --

const Ksb = 4; // matches Oarg/Opar/Jret
const Kub = 5;
const Ksh = 6;
const Kuh = 7;
const Kc = 8;
const K0 = 9;
const Ke = -2; // erroneous mode
const Km = Kl; // memory pointer

fn kcls(ch: u8) i16 {
    return switch (ch) {
        'w' => Kw,
        'l' => Kl,
        's' => Ks,
        'd' => Kd,
        'm' => Km,
        'x' => Kx,
        'e' => Ke,
        else => unreachable,
    };
}

/// optab[NOp], built at compile time from the ops.h table
pub const optab_init: [NOp]Op = blk: {
    @setEvalBranchQuota(100000);
    var t: [NOp]Op = undefined;
    t[0] = std.mem.zeroes(Op);
    for (all.ops.defs, 1..) |d, i| {
        var o: Op = undefined;
        o.name = d.name.ptr;
        for (0..2) |a| for (0..4) |k| {
            o.argcls[a][k] = kcls(d.t[a][k]);
        };
        o.canfold = d.f[0];
        o.hasid = d.f[1];
        o.idval = d.f[2];
        o.commutes = d.f[3];
        o.assoc = d.f[4];
        o.idemp = d.f[5];
        o.cmpeqwl = d.f[6];
        o.cmplgtewl = d.f[7];
        o.eqval = d.f[8];
        o.pinned = d.f[9];
        t[i] = o;
    }
    break :blk t;
};

const PState = i32;
const PXXX = 0;
const PLbl = 1;
const PPhi = 2;
const PIns = 3;
const PEnd = 4;

// enum Token
const Txxx = 0;
const Tloadw = NPubOp + 0;
const Tloadl = NPubOp + 1;
const Tloads = NPubOp + 2;
const Tloadd = NPubOp + 3;
const Talloc1 = NPubOp + 4;
const Talloc2 = NPubOp + 5;
const Tblit = NPubOp + 6;
const Tcall = NPubOp + 7;
const Tenv = NPubOp + 8;
const Tphi = NPubOp + 9;
const Tjmp = NPubOp + 10;
const Tjnz = NPubOp + 11;
const Tret = NPubOp + 12;
const Thlt = NPubOp + 13;
const Texport = NPubOp + 14;
const Tthread = NPubOp + 15;
const Textern = NPubOp + 16;
const Tcommon = NPubOp + 17;
const Tfunc = NPubOp + 18;
const Ttype = NPubOp + 19;
const Tdata = NPubOp + 20;
const Tsection = NPubOp + 21;
const Talign = NPubOp + 22;
const Tdbgfile = NPubOp + 23;
const Tl = NPubOp + 24;
const Tw = NPubOp + 25;
const Tsh = NPubOp + 26;
const Tuh = NPubOp + 27;
const Th = NPubOp + 28;
const Tsb = NPubOp + 29;
const Tub = NPubOp + 30;
const Tb = NPubOp + 31;
const Td = NPubOp + 32;
const Ts = NPubOp + 33;
const Tz = NPubOp + 34;
const Tint = NPubOp + 35;
const Tflts = NPubOp + 36;
const Tfltd = NPubOp + 37;
const Ttmp = NPubOp + 38;
const Tlbl = NPubOp + 39;
const Tglo = NPubOp + 40;
const Ttyp = NPubOp + 41;
const Tstr = NPubOp + 42;
const Tplus = NPubOp + 43;
const Teq = NPubOp + 44;
const Tcomma = NPubOp + 45;
const Tlparen = NPubOp + 46;
const Trparen = NPubOp + 47;
const Tlbrace = NPubOp + 48;
const Trbrace = NPubOp + 49;
const Tnl = NPubOp + 50;
const Tdots = NPubOp + 51;
const Teof = NPubOp + 52;
const Ntok = NPubOp + 53;

var kwmap: [Ntok][*c]const u8 = blk: {
    var m: [Ntok][*c]const u8 = @splat(null);
    m[Tloadw] = "loadw";
    m[Tloadl] = "loadl";
    m[Tloads] = "loads";
    m[Tloadd] = "loadd";
    m[Talloc1] = "alloc1";
    m[Talloc2] = "alloc2";
    m[Tblit] = "blit";
    m[Tcall] = "call";
    m[Tenv] = "env";
    m[Tphi] = "phi";
    m[Tjmp] = "jmp";
    m[Tjnz] = "jnz";
    m[Tret] = "ret";
    m[Thlt] = "hlt";
    m[Texport] = "export";
    m[Tthread] = "thread";
    m[Textern] = "extern";
    m[Tcommon] = "common";
    m[Tfunc] = "function";
    m[Ttype] = "type";
    m[Tdata] = "data";
    m[Tsection] = "section";
    m[Talign] = "align";
    m[Tdbgfile] = "dbgfile";
    m[Tsb] = "sb";
    m[Tub] = "ub";
    m[Tsh] = "sh";
    m[Tuh] = "uh";
    m[Tb] = "b";
    m[Th] = "h";
    m[Tw] = "w";
    m[Tl] = "l";
    m[Ts] = "s";
    m[Td] = "d";
    m[Tz] = "z";
    m[Tdots] = "...";
    break :blk m;
};

const NPred = 63;
const TMask = 16383; // for temps hash
const BMask = 8191; // for blocks hash
const K: u32 = 11183273; // found using tools/lexh.c
const M = 23;

var lexh: [1 << (32 - M)]uchar = @splat(0);
/// input text and read position (replaces FILE* + fgetc/ungetc)
var in: []const u8 = "";
var ipos: usize = 0;
const EOF: i32 = -1;

fn getc() i32 {
    if (ipos >= in.len) return EOF;
    const c = in[ipos];
    ipos += 1;
    return c;
}

fn ungetc(c: i32) void {
    if (c != EOF) ipos -= 1;
}

fn isdigit(c: i32) bool {
    return c >= '0' and c <= '9';
}

fn isalpha(c: i32) bool {
    return (c >= 'a' and c <= 'z') or (c >= 'A' and c <= 'Z');
}

fn isblank(c: i32) bool {
    return c == ' ' or c == '\t';
}

fn isspace(c: i32) bool {
    return c == ' ' or (c >= '\t' and c <= '\r');
}

fn isxdigit(c: i32) bool {
    return isdigit(c) or (c >= 'a' and c <= 'f') or (c >= 'A' and c <= 'F');
}

/// scanf("_%f")-like: match '_', then the longest prefix of a
/// floating-point number (strtod syntax); like scanf, a failed match
/// leaves consumed characters consumed except the last lookahead
fn scanflt(comptime F: type, out: *F) bool {
    var c = getc();
    if (c != '_') {
        ungetc(c);
        return false;
    }
    c = getc();
    while (isspace(c)) c = getc();
    const start = ipos - @intFromBool(c != EOF);
    if (c == '+' or c == '-') c = getc();
    const ok = blk: {
        if (c == 'i' or c == 'I' or c == 'n' or c == 'N') {
            const word: []const u8 = if (c == 'i' or c == 'I') "infinity" else "nan";
            var n: usize = 0;
            while (n < word.len and c != EOF and std.ascii.toLower(@intCast(c)) == word[n]) : (n += 1)
                c = getc();
            if (word.len == 3 and n == 3) {
                if (c == '(') {
                    c = getc();
                    while (isalpha(c) or isdigit(c) or c == '_') c = getc();
                    if (c != ')') break :blk false;
                    c = getc();
                }
                break :blk true;
            }
            break :blk n == 3 or n == 8;
        }
        var hex = false;
        var digits = false;
        if (c == '0') {
            digits = true;
            c = getc();
            if (c == 'x' or c == 'X') {
                hex = true;
                digits = false;
                c = getc();
            }
        }
        const isd = if (hex) &isxdigit else &isdigit;
        while (isd(c)) : (c = getc()) digits = true;
        if (c == '.') {
            c = getc();
            while (isd(c)) : (c = getc()) digits = true;
        }
        if (!digits) break :blk false;
        if ((!hex and (c == 'e' or c == 'E')) or (hex and (c == 'p' or c == 'P'))) {
            c = getc();
            if (c == '+' or c == '-') c = getc();
            if (!isdigit(c)) break :blk false;
            while (isdigit(c)) c = getc();
        }
        break :blk true;
    };
    ungetc(c);
    if (!ok) return false;
    var txt = in[start..ipos];
    const neg = txt[0] == '-';
    if (txt[0] == '-' or txt[0] == '+') txt = txt[1..];
    const v = std.fmt.parseFloat(F, txt) catch return false;
    out.* = if (neg) -v else v;
    return true;
}

var inpath: []const u8 = "";
var thead: i32 = 0;
var tokval: struct {
    chr: u8,
    fltd: f64,
    flts: f32,
    num: i64,
    str: [*c]u8,
} = .{ .chr = 0, .fltd = 0, .flts = 0, .num = 0, .str = null };
var lnum: i32 = 0;

var curf: [*c]Fn = null;
var tmph: [*c]i32 = null;
var tmphcap: i32 = 0;
var plink: [*c][*c]Phi = null;
var curb: [*c]Blk = null;
var blink: [*c][*c]Blk = null;
var blkh: [BMask + 1][*c]Blk = @splat(null);
var nblk: i32 = 0;
var rcls: i32 = 0;
var ntyp: uint = 0;

pub fn err(comptime fmt: []const u8, args: anytype) noreturn {
    dprint("qbe:{s}:{d}: " ++ fmt ++ "\n", .{ inpath, lnum } ++ args);
    all.dbg.flush() catch {};
    if (all.outw) |w| w.flush() catch {};
    std.process.exit(1);
}

var lexinit_done = false;
fn lexinit() void {
    if (lexinit_done)
        return;
    var i: usize = 0;
    while (i < NPubOp) : (i += 1)
        if (all.optab[i].name != null) {
            kwmap[i] = all.optab[i].name;
        };
    comptime assert(Ntok <= 255);
    i = 0;
    while (i < Ntok) : (i += 1)
        if (kwmap[i] != null) {
            const h = (hash(kwmap[i]) *% K) >> M;
            assert(lexh[h] == Txxx);
            lexh[h] = @intCast(i);
        };
    lexinit_done = true;
}

fn getint() i64 {
    var n: u64 = 0;
    var c = getc();
    const m = (c == '-');
    if (m) {
        c = getc();
        if (!isdigit(c))
            err("integer expected", .{});
    }
    while (true) {
        n = 10 *% n +% @as(u64, @bitCast(@as(i64, c - '0')));
        c = getc();
        if (!isdigit(c)) break;
    }
    ungetc(c);
    if (m)
        n = 1 +% ~n;
    return @bitCast(n);
}

fn lex() i32 {
    var c: i32 = undefined;
    var i: usize = undefined;
    var esc: bool = undefined;
    var t: i32 = undefined;

    while (true) {
        c = getc();
        if (!isblank(c)) break;
    }
    t = Txxx;
    tokval.chr = @truncate(@as(c_uint, @bitCast(c)));
    const L = enum { none, alpha, quoted };
    var go: L = .none;
    switch (c) {
        EOF => return Teof,
        ',' => return Tcomma,
        '(' => return Tlparen,
        ')' => return Trparen,
        '{' => return Tlbrace,
        '}' => return Trbrace,
        '=' => return Teq,
        '+' => return Tplus,
        's' => {
            if (scanflt(f32, &tokval.flts))
                return Tflts;
        },
        'd' => {
            if (scanflt(f64, &tokval.fltd))
                return Tfltd;
        },
        '%' => {
            t = Ttmp;
            c = getc();
            go = .alpha;
        },
        '@' => {
            t = Tlbl;
            c = getc();
            go = .alpha;
        },
        '$' => {
            t = Tglo;
            c = getc();
            go = if (c == '"') .quoted else .alpha;
        },
        ':' => {
            t = Ttyp;
            c = getc();
            go = .alpha;
        },
        '#', '\n' => {
            if (c == '#') {
                while (true) {
                    c = getc();
                    if (c == '\n' or c == EOF) break;
                }
            }
            lnum += 1;
            return Tnl;
        },
        else => {},
    }
    if (go == .none) {
        if (isdigit(c) or c == '-') {
            ungetc(c);
            tokval.num = getint();
            return Tint;
        }
        if (c == '"') {
            t = Tstr;
            go = .quoted;
        }
    }
    if (go == .quoted) {
        tokval.str[0] = @truncate(@as(c_uint, @bitCast(c)));
        esc = false;
        i = 1;
        while (true) : (i += 1) {
            c = getc();
            if (c == EOF)
                err("unterminated string", .{});
            vgrow(&tokval.str, i + 2);
            tokval.str[i] = @truncate(@as(c_uint, @bitCast(c)));
            if (c == '"' and !esc) {
                tokval.str[i + 1] = 0;
                return t;
            }
            esc = (c == '\\' and !esc);
        }
    }
    // Alpha:
    if (!isalpha(c) and c != '.' and c != '_')
        err("invalid character {c} ({d})", .{ @as(u8, @truncate(@as(c_uint, @bitCast(c)))), c });
    i = 0;
    while (true) {
        vgrow(&tokval.str, i + 2);
        tokval.str[i] = @truncate(@as(c_uint, @bitCast(c)));
        i += 1;
        c = getc();
        if (!(isalpha(c) or c == '$' or c == '.' or c == '_' or isdigit(c))) break;
    }
    tokval.str[i] = 0;
    ungetc(c);
    if (t != Txxx) {
        return t;
    }
    t = lexh[(hash(tokval.str) *% K) >> M];
    if (t == Txxx or !streq(kwmap[@intCast(t)], tokval.str)) {
        err("unknown keyword {s}", .{cs(tokval.str)});
    }
    return t;
}

fn peek() i32 {
    if (thead == Txxx)
        thead = lex();
    return thead;
}

fn next() i32 {
    const t = peek();
    thead = Txxx;
    return t;
}

fn nextnl() i32 {
    var t: i32 = undefined;
    while (true) {
        t = next();
        if (t != Tnl) break;
    }
    return t;
}

const ttoa: [Ntok][*c]const u8 = blk: {
    var m: [Ntok][*c]const u8 = @splat(null);
    m[Tlbl] = "label";
    m[Tcomma] = ",";
    m[Teq] = "=";
    m[Tnl] = "newline";
    m[Tlparen] = "(";
    m[Trparen] = ")";
    m[Tlbrace] = "{";
    m[Trbrace] = "}";
    m[Teof] = null;
    break :blk m;
};

fn expect(t: i32) void {
    const t1 = next();
    if (t == t1)
        return;
    const s1: [*c]const u8 = if (ttoa[@intCast(t)] != null) ttoa[@intCast(t)] else "??";
    const s2: [*c]const u8 = if (ttoa[@intCast(t1)] != null) ttoa[@intCast(t1)] else "??";
    err("{s} expected, got {s} instead", .{ cs(s1), cs(s2) });
}

fn tmpref() Ref {
    var t: i32 = undefined;
    var i: i32 = undefined;

    if (@divTrunc(tmphcap, 2) <= curf.*.ntmp - Tmp0) {
        efree(@ptrCast(tmph));
        tmphcap = if (tmphcap != 0) tmphcap * 2 else TMask + 1;
        tmph = ealloc(i32, tmphcap);
        t = Tmp0;
        while (t < curf.*.ntmp) : (t += 1) {
            i = @bitCast(hash(curf.*.tmp[@intCast(t)].name) & @as(u32, @intCast(tmphcap - 1)));
            while (tmph[@intCast(i)] != 0) : (i = (i + 1) & (tmphcap - 1)) {}
            tmph[@intCast(i)] = t;
        }
    }
    i = @bitCast(hash(tokval.str) & @as(u32, @intCast(tmphcap - 1)));
    while (tmph[@intCast(i)] != 0) : (i = (i + 1) & (tmphcap - 1)) {
        t = tmph[@intCast(i)];
        if (streq(curf.*.tmp[@intCast(t)].name, tokval.str))
            return TMP(t);
    }
    t = curf.*.ntmp;
    tmph[@intCast(i)] = t;
    _ = newtmp(null, Kx, curf);
    curf.*.tmp[@intCast(t)].name = strf(PFn, "{s}", .{cs(tokval.str)});
    return TMP(t);
}

fn parseref() Ref {
    var c: Con = std.mem.zeroes(Con);
    var tok = next();
    switch (tok) {
        Ttmp => return tmpref(),
        Tint => {
            c.type = CBits;
            c.bits.i = tokval.num;
        },
        Tflts => {
            c.type = CBits;
            c.bits.s = tokval.flts;
            c.flt = 1;
        },
        Tfltd => {
            c.type = CBits;
            c.bits.d = tokval.fltd;
            c.flt = 2;
        },
        else => {
            if (tok != Tglo) {
                while (true) : (tok = next()) {
                    switch (tok) {
                        Textern => {
                            c.sym.type |= SExt;
                            continue;
                        },
                        Tthread => {
                            c.sym.type |= SThr;
                            continue;
                        },
                        else => {},
                    }
                    break;
                }
                if (tok != Tglo)
                    return R;
            }
            // case Tglo:
            c.type = CAddr;
            c.sym.id = intern(tokval.str);
        },
    }
    return newcon(&c, curf);
}

fn findtyp(i_: i32) i32 {
    var i = i_;
    while (true) {
        i -= 1;
        if (i < 0) break;
        if (streq(tokval.str, all.typ[@intCast(i)].name))
            return i;
    }
    err("undefined type :{s}", .{cs(tokval.str)});
}

fn parsecls(tyn: *i32) i32 {
    switch (next()) {
        Ttyp => {
            tyn.* = findtyp(@intCast(ntyp));
            return Kc;
        },
        Tsb => return Ksb,
        Tub => return Kub,
        Tsh => return Ksh,
        Tuh => return Kuh,
        Tw => return Kw,
        Tl => return Kl,
        Ts => return Ks,
        Td => return Kd,
        else => err("invalid class specifier", .{}),
    }
}

inline fn mkins(op: anytype, k: anytype, to: Ref, a0: Ref, a1: Ref) Ins {
    return .{ .op = @intCast(op), .cls = @intCast(k), .to = to, .arg = .{ a0, a1 } };
}

fn parserefl(arg: bool) bool {
    var k: i32 = undefined;
    var ty: i32 = undefined;
    var env: bool = undefined;
    var r: Ref = undefined;

    var hasenv = false;
    var vararg = false;
    expect(Tlparen);
    while (peek() != Trparen) {
        if (ptrdiff(all.curi, @as([*c]Ins, &all.insb)) >= NIns)
            err("too many instructions", .{});
        if (!arg and vararg)
            err("no parameters allowed after '...'", .{});
        var skip = false;
        switch (peek()) {
            Tdots => {
                if (vararg)
                    err("only one '...' allowed", .{});
                vararg = true;
                if (arg) {
                    all.curi.* = std.mem.zeroes(Ins);
                    all.curi.*.op = Oargv;
                    all.curi += 1;
                }
                _ = next();
                skip = true; // goto Next
            },
            Tenv => {
                if (hasenv)
                    err("only one environment allowed", .{});
                hasenv = true;
                env = true;
                _ = next();
                k = Kl;
            },
            else => {
                env = false;
                k = parsecls(&ty);
            },
        }
        if (!skip) {
            r = parseref();
            if (req(r, R))
                err("invalid argument", .{});
            if (!arg and rtype(r) != RTmp)
                err("invalid function parameter", .{});
            if (env) {
                if (arg)
                    all.curi.* = mkins(Oarge, k, R, r, R)
                else
                    all.curi.* = mkins(Opare, k, r, R, R);
            } else if (k == Kc) {
                if (arg)
                    all.curi.* = mkins(Oargc, Kl, R, TYPE(ty), r)
                else
                    all.curi.* = mkins(Oparc, Kl, r, TYPE(ty), R);
            } else if (k >= Ksb) {
                if (arg)
                    all.curi.* = mkins(Oargsb + (k - Ksb), Kw, R, r, R)
                else
                    all.curi.* = mkins(Oparsb + (k - Ksb), Kw, r, R, R);
            } else {
                if (arg)
                    all.curi.* = mkins(Oarg, k, R, r, R)
                else
                    all.curi.* = mkins(Opar, k, r, R, R);
            }
            all.curi += 1;
        }
        // Next:
        if (peek() == Trparen)
            break;
        expect(Tcomma);
    }
    expect(Trparen);
    return vararg;
}

fn findblk() [*c]Blk {
    const h = hash(tokval.str) & BMask;
    var b = blkh[h];
    while (b != null) : (b = b.*.dlink)
        if (streq(b.*.name, tokval.str))
            return b;
    b = newblk();
    b.*.id = @intCast(nblk);
    nblk += 1;
    b.*.name = strf(PFn, "{s}", .{cs(tokval.str)});
    b.*.dlink = blkh[h];
    blkh[h] = b;
    return b;
}

fn closeblk() void {
    idup(curb, &all.insb, @intCast(ptrdiff(all.curi, @as([*c]Ins, &all.insb))));
    blink = &curb.*.link;
    all.curi = &all.insb;
}

fn parseline(ps: PState) PState {
    var arg: [NPred]Ref = @splat(R);
    var blk: [NPred]*Blk = undefined;
    var r: Ref = R;
    var op: i32 = 0;
    var i: usize = undefined;
    var k: i32 = 0;
    var ty: i32 = 0;

    var t = nextnl();
    if (ps == PLbl and t != Tlbl and t != Trbrace)
        err("label or }} expected", .{});
    const Flow = enum { normal, jump, close, ins };
    var flow: Flow = .normal;
    switch (t) {
        Ttmp => {
            r = tmpref();
            expect(Teq);
            k = parsecls(&ty);
            op = next();
        },
        Tblit, Tcall, Ovastart => {
            // operations without result
            r = R;
            k = Kw;
            op = t;
        },
        Trbrace => return PEnd,
        Tlbl => {
            const b = findblk();
            if (curb != null and curb.*.jmp.type == Jxxx) {
                closeblk();
                curb.*.jmp.type = Jjmp;
                curb.*.s1 = b;
            }
            if (b.*.jmp.type != Jxxx)
                err("multiple definitions of block @{s}", .{cs(b.*.name)});
            blink.* = b;
            curb = b;
            plink = &curb.*.phi;
            expect(Tnl);
            return PPhi;
        },
        Tret => {
            curb.*.jmp.type = @intCast(Jretw + rcls);
            if (peek() == Tnl)
                curb.*.jmp.type = Jret0
            else if (rcls != K0) {
                r = parseref();
                if (req(r, R))
                    err("invalid return value", .{});
                curb.*.jmp.arg = r;
            }
            flow = .close;
        },
        Tjmp => {
            curb.*.jmp.type = Jjmp;
            flow = .jump;
        },
        Tjnz => {
            curb.*.jmp.type = Jjnz;
            r = parseref();
            if (req(r, R))
                err("invalid argument for jnz jump", .{});
            curb.*.jmp.arg = r;
            expect(Tcomma);
            flow = .jump;
        },
        Thlt => {
            curb.*.jmp.type = Jhlt;
            flow = .close;
        },
        Odbgloc => {
            op = t;
            k = Kw;
            r = R;
            expect(Tint);
            arg[0] = INT(tokval.num);
            if (arg[0].val != tokval.num)
                err("line number too big", .{});
            if (peek() == Tcomma) {
                _ = next();
                expect(Tint);
                arg[1] = INT(tokval.num);
                if (arg[1].val != tokval.num)
                    err("column number too big", .{});
            } else arg[1] = INT(0);
            flow = .ins;
        },
        else => {
            if (isstore(t)) {
                r = R;
                k = Kw;
                op = t;
            } else err("label, instruction or jump expected", .{});
        },
    }
    if (flow == .jump) {
        expect(Tlbl);
        curb.*.s1 = findblk();
        if (curb.*.jmp.type != Jjmp) {
            expect(Tcomma);
            expect(Tlbl);
            curb.*.s2 = findblk();
        }
        if (curb.*.s1 == curf.*.start or curb.*.s2 == curf.*.start)
            err("invalid jump to the start block", .{});
        flow = .close;
    }
    if (flow == .close) {
        expect(Tnl);
        closeblk();
        return PLbl;
    }
    if (flow == .normal and op == Tcall) {
        curf.*.leaf = 0;
        arg[0] = parseref();
        _ = parserefl(true);
        op = Ocall;
        expect(Tnl);
        if (k == Kc) {
            k = Kl;
            arg[1] = TYPE(ty);
        }
        if (k >= Ksb)
            k = Kw;
        flow = .ins;
    }
    if (flow == .normal) {
        if (op == Tloadw)
            op = Oloadsw;
        if (op >= Tloadl and op <= Tloadd)
            op = Oload;
        if (op == Talloc1 or op == Talloc2)
            op = Oalloc;
        if (op == Ovastart and curf.*.vararg == 0)
            err("cannot use vastart in non-variadic function", .{});
        if (k >= Ksb)
            err("size class must be w, l, s, or d", .{});
        i = 0;
        if (peek() != Tnl)
            while (true) {
                if (i == NPred)
                    err("too many arguments", .{});
                if (op == Tphi) {
                    expect(Tlbl);
                    blk[i] = findblk();
                }
                arg[i] = parseref();
                if (req(arg[i], R))
                    err("invalid instruction argument", .{});
                i += 1;
                t = peek();
                if (t == Tnl)
                    break;
                if (t != Tcomma)
                    err(", or end of line expected", .{});
                _ = next();
            };
        _ = next();
        switch (op) {
            Tphi => {
                if (ps != PPhi or curb == curf.*.start)
                    err("unexpected phi instruction", .{});
                const phi: ?*Phi = palloc(Phi, 1);
                phi.?.to = r;
                phi.?.cls = @intCast(k);
                phi.?.arg = vnewT(Ref, i, PFn);
                @memcpy(phi.?.arg[0..i], arg[0..i]);
                phi.?.blk = vnewT(*Blk, i, PFn);
                @memcpy(phi.?.blk[0..i], blk[0..i]);
                phi.?.narg = @intCast(i);
                plink.* = phi;
                plink = &phi.?.link;
                return PPhi;
            },
            Tblit => {
                if (ptrdiff(all.curi, @as([*c]Ins, &all.insb)) >= NIns - 1)
                    err("too many instructions", .{});
                @memset(all.curi[0..2], std.mem.zeroes(Ins));
                all.curi.*.op = Oblit0;
                all.curi.*.arg[0] = arg[0];
                all.curi.*.arg[1] = arg[1];
                all.curi += 1;
                if (rtype(arg[2]) != RCon)
                    err("blit size must be constant", .{});
                const c = &curf.*.con[arg[2].val];
                r = INT(c.bits.i);
                if (c.type != CBits or rsval(r) < 0 or rsval(r) != c.bits.i)
                    err("invalid blit size", .{});
                all.curi.*.op = Oblit1;
                all.curi.*.arg[0] = r;
                all.curi += 1;
                return PIns;
            },
            else => {
                if (op >= NPubOp)
                    err("invalid instruction", .{});
            },
        }
    }
    // Ins:
    if (ptrdiff(all.curi, @as([*c]Ins, &all.insb)) >= NIns)
        err("too many instructions", .{});
    all.curi.*.op = @intCast(op);
    all.curi.*.cls = @intCast(k);
    all.curi.*.to = r;
    all.curi.*.arg[0] = arg[0];
    all.curi.*.arg[1] = arg[1];
    all.curi += 1;
    return PIns;
}

fn usecheck(r: Ref, k: i32, f: *Fn) bool {
    return rtype(r) != RTmp or f.tmp[r.val].cls == k or (f.tmp[r.val].cls == Kl and k == Kw);
}

fn typecheck(f: *Fn) void {
    var pb: BSet = undefined;
    var ppb: BSet = undefined;
    var k: i32 = undefined;
    var t: [*c]Tmp = undefined;
    var r: Ref = undefined;

    fillpreds(f);
    bsinit(&pb, f.nblk);
    bsinit(&ppb, f.nblk);
    var b_it: ?*Blk = f.start;
    while (b_it) |b| : (b_it = b.link) {
        var p_it: ?*Phi = b.phi;
        while (p_it) |p| : (p_it = p.link)
            f.tmp[p.to.val].cls = p.cls;
        for (b.ins[0..b.nins]) |*i|
            if (rtype(i.to) == RTmp) {
                t = &f.tmp[i.to.val];
                if (clsmerge(&t.*.cls, @intCast(i.cls)))
                    err("temporary %{s} is assigned with multiple types", .{cs(t.*.name)});
            };
    }
    b_it = f.start;
    while (b_it) |b| : (b_it = b.link) {
        bszero(&pb);
        var n: uint = 0;
        while (n < b.npred) : (n += 1)
            bsset(&pb, b.pred[n].id);
        var p_it: ?*Phi = b.phi;
        while (p_it) |p| : (p_it = p.link) {
            bszero(&ppb);
            t = &f.tmp[p.to.val];
            n = 0;
            while (n < p.narg) : (n += 1) {
                k = t.*.cls;
                if (bshas(&ppb, p.blk[n].id))
                    err("multiple entries for @{s} in phi %{s}", .{cs(p.blk[n].name), cs(t.*.name)});
                if (!usecheck(p.arg[n], k, f))
                    err("invalid type for operand %{s} in phi %{s}", .{cs(f.tmp[p.arg[n].val].name), cs(t.*.name)});
                bsset(&ppb, p.blk[n].id);
            }
            if (!bsequal(&pb, &ppb))
                err("predecessors not matched in phi %{s}", .{cs(t.*.name)});
        }
        for (b.ins[0..b.nins]) |*i| {
            n = 0;
            while (n < 2) : (n += 1) {
                k = all.optab[i.op].argcls[n][i.cls];
                r = i.arg[n];
                t = &f.tmp[r.val];
                const which: [*c]const u8 = if (n == 1) "second" else "first";
                if (k == Ke)
                    err("invalid instruction type in {s}", .{cs(all.optab[i.op].name)});
                if (rtype(r) == RType)
                    continue;
                if (rtype(r) != -1 and k == Kx)
                    err("no {s} operand expected in {s}", .{cs(which), cs(all.optab[i.op].name)});
                if (rtype(r) == -1 and k != Kx)
                    err("missing {s} operand in {s}", .{cs(which), cs(all.optab[i.op].name)});
                if (!usecheck(r, k, f))
                    err("invalid type for {s} operand %{s} in {s}", .{cs(which), cs(t.*.name), cs(all.optab[i.op].name)});
            }
        }
        r = b.jmp.arg;
        var jerr = false;
        if (isret(b.jmp.type)) {
            if (b.jmp.type == Jretc)
                k = Kl
            else if (b.jmp.type >= Jretsb)
                k = Kw
            else
                k = b.jmp.type - Jretw;
            if (!usecheck(r, k, f))
                jerr = true;
        }
        if (jerr or (b.jmp.type == Jjnz and !usecheck(r, Kw, f)))
            err("invalid type for jump argument %{s} in block @{s}", .{cs(f.tmp[r.val].name), cs(b.name)});
        if (b.s1 != null and b.s1.?.jmp.type == Jxxx)
            err("block @{s} is used undefined", .{cs(b.s1.?.name)});
        if (b.s2 != null and b.s2.?.jmp.type == Jxxx)
            err("block @{s} is used undefined", .{cs(b.s2.?.name)});
    }
}

fn parsefn(lnk: [*c]Lnk) [*c]Fn {
    var ps: PState = undefined;

    curb = null;
    nblk = 0;
    all.curi = &all.insb;
    curf = palloc(Fn, 1);
    curf.*.ntmp = 0;
    curf.*.ncon = 2;
    curf.*.tmp = vnewT(Tmp, curf.*.ntmp, PFn);
    curf.*.con = vnewT(Con, curf.*.ncon, PFn);
    var i: i32 = 0;
    while (i < Tmp0) : (i += 1)
        if (all.T.fpr0 <= i and i < all.T.fpr0 + all.T.nfpr) {
            _ = newtmp(null, Kd, curf);
        } else {
            _ = newtmp(null, Kl, curf);
        };
    curf.*.con[0].type = CBits;
    curf.*.con[0].bits.i = 0xdeaddead; // UNDEF
    curf.*.con[1].type = CBits;
    curf.*.lnk = lnk.*;
    curf.*.leaf = 1;
    blink = &curf.*.start;
    curf.*.retty = Kx;
    if (peek() != Tglo)
        rcls = parsecls(&curf.*.retty)
    else
        rcls = K0;
    if (next() != Tglo)
        err("function name expected", .{});
    curf.*.name = strf(PFn, "{s}", .{cs(tokval.str)});
    curf.*.vararg = @intFromBool(parserefl(false));
    if (nextnl() != Tlbrace)
        err("function body must start with {{", .{});
    ps = PLbl;
    while (true) {
        ps = parseline(ps);
        if (ps == PEnd) break;
    }
    if (curb == null)
        err("empty function", .{});
    if (curb.*.jmp.type == Jxxx)
        err("last block misses jump", .{});
    curf.*.mem = vnewT(Mem, 0, PFn);
    curf.*.nmem = 0;
    curf.*.nblk = @intCast(nblk);
    curf.*.rpo = vnewT(*Blk, nblk, PFn);
    var b: ?*Blk = curf.*.start;
    while (b != null) : (b = b.?.link)
        b.?.dlink = null; // was trashed by findblk()
    i = 0;
    while (i < BMask + 1) : (i += 1)
        blkh[@intCast(i)] = null;
    if (tmphcap != 0) @memset(tmph[0..@intCast(tmphcap)], 0);
    typecheck(curf);
    return curf;
}

fn parsefields(fld: [*c]Field, ty: *Typ, t_: i32) void {
    var t = t_;
    var ty1: [*c]Typ = undefined;
    var c: i32 = undefined;
    var a: i32 = undefined;
    var @"type": i32 = undefined;
    var s: u64 = undefined;

    var n: usize = 0;
    var sz: u64 = 0;
    var al = ty.@"align";
    while (t != Trbrace) {
        ty1 = null;
        switch (t) {
            Td => {
                @"type" = Fd;
                s = 8;
                a = 3;
            },
            Tl => {
                @"type" = Fl;
                s = 8;
                a = 3;
            },
            Ts => {
                @"type" = Fs;
                s = 4;
                a = 2;
            },
            Tw => {
                @"type" = Fw;
                s = 4;
                a = 2;
            },
            Th => {
                @"type" = Fh;
                s = 2;
                a = 1;
            },
            Tb => {
                @"type" = Fb;
                s = 1;
                a = 0;
            },
            Ttyp => {
                @"type" = FTyp;
                ty1 = &all.typ[@intCast(findtyp(@as(i32, @intCast(ntyp)) - 1))];
                s = ty1.*.size;
                a = ty1.*.@"align";
            },
            else => err("invalid type member specifier", .{}),
        }
        if (a > al)
            al = a;
        a = (@as(i32, 1) << @intCast(a)) - 1;
        const am: u64 = @bitCast(@as(i64, a));
        a = @truncate(@as(i64, @bitCast(((sz +% am) & ~am) -% sz)));
        if (a != 0) {
            if (n < NField) {
                // padding
                fld[n].type = FPad;
                fld[n].len = @bitCast(a);
                n += 1;
            }
        }
        t = nextnl();
        if (t == Tint) {
            c = @truncate(tokval.num);
            t = nextnl();
        } else c = 1;
        sz +%= @as(u64, @bitCast(@as(i64, a))) +% @as(u64, @bitCast(@as(i64, c))) *% s;
        if (@"type" == FTyp)
            s = @intCast(ptrdiff(ty1, all.typ));
        while (c > 0 and n < NField) : ({
            c -= 1;
            n += 1;
        }) {
            fld[n].type = @"type";
            fld[n].len = @truncate(s);
        }
        if (t != Tcomma)
            break;
        t = nextnl();
    }
    if (t != Trbrace)
        err(", or }} expected", .{});
    fld[n].type = FEnd;
    a = @as(i32, 1) << @intCast(al);
    if (sz < ty.size)
        sz = ty.size;
    const au: u64 = @bitCast(@as(i64, a));
    ty.size = (sz +% au -% 1) & (0 -% au);
    ty.@"align" = al;
}

fn parsetyp() void {
    var t: i32 = undefined;
    var al: i32 = undefined;

    // be careful if extending the syntax
    // to handle nested types, any pointer
    // held to typ[] might be invalidated!
    vgrow(&all.typ, ntyp + 1);
    const ty = &all.typ[ntyp];
    ntyp += 1;
    ty.isdark = 0;
    ty.isunion = 0;
    ty.@"align" = -1;
    ty.size = 0;
    if (nextnl() != Ttyp or nextnl() != Teq)
        err("type name and then = expected", .{});
    ty.name = strf(PHeap, "{s}", .{cs(tokval.str)});
    t = nextnl();
    if (t == Talign) {
        if (nextnl() != Tint)
            err("alignment expected", .{});
        al = 0;
        while (true) : (al += 1) {
            tokval.num = @divTrunc(tokval.num, 2);
            if (tokval.num == 0) break;
        }
        ty.@"align" = al;
        t = nextnl();
    }
    if (t != Tlbrace)
        err("type body must start with {{", .{});
    t = nextnl();
    if (t == Tint) {
        ty.isdark = 1;
        ty.size = @bitCast(tokval.num);
        if (ty.@"align" == -1)
            err("dark types need alignment", .{});
        if (nextnl() != Trbrace)
            err("}} expected", .{});
        return;
    }
    var n: uint = 0;
    ty.fields = vnewT([NField + 1]Field, 1, PHeap);
    if (t == Tlbrace) {
        ty.isunion = 1;
        while (true) {
            if (t != Tlbrace)
                err("invalid union member", .{});
            vgrow(&ty.fields, n + 1);
            parsefields(&ty.fields[n], ty, nextnl());
            n += 1;
            t = nextnl();
            if (t == Trbrace) break;
        }
    } else {
        parsefields(&ty.fields[n], ty, t);
        n += 1;
    }
    ty.nunion = n;
}

fn parsedatref(d: *Dat) void {
    d.isref = 1;
    d.u.ref.name = strf(PFn, "{s}", .{cs(tokval.str)});
    d.u.ref.off = 0;
    const t = peek();
    if (t == Tplus) {
        _ = next();
        if (next() != Tint)
            err("invalid token after offset in ref", .{});
        d.u.ref.off = tokval.num;
    }
}

fn parsedatstr(d: *Dat) void {
    d.isstr = 1;
    d.u.str = strf(PFn, "{s}", .{cs(tokval.str)});
}

fn parsedat(cb: *const fn (*Dat) void, lnk: [*c]Lnk) void {
    var t: i32 = undefined;
    var d: Dat = undefined;

    if (nextnl() != Tglo or nextnl() != Teq)
        err("data name, then = expected", .{});
    const name = strf(PFn, "{s}", .{cs(tokval.str)});
    t = nextnl();
    lnk.*.@"align" = 8;
    if (t == Talign) {
        if (nextnl() != Tint)
            err("alignment expected", .{});
        if (tokval.num <= 0 or tokval.num > 127 or (tokval.num & (tokval.num - 1)) != 0)
            err("invalid alignment", .{});
        lnk.*.@"align" = @intCast(tokval.num);
        t = nextnl();
    }
    d.type = DStart;
    d.name = name;
    d.lnk = lnk;
    cb(&d);

    if (t != Tlbrace)
        err("expected data contents in {{ .. }}", .{});
    outer: while (true) {
        switch (nextnl()) {
            Trbrace => break :outer,
            Tl => d.type = DL,
            Tw => d.type = DW,
            Th => d.type = DH,
            Tb => d.type = DB,
            Ts => d.type = DW,
            Td => d.type = DL,
            Tz => d.type = DZ,
            else => err("invalid size specifier {c} in data", .{tokval.chr}),
        }
        t = nextnl();
        while (true) {
            d.isstr = 0;
            d.isref = 0;
            d.u = std.mem.zeroes(@TypeOf(d.u));
            if (t == Tflts)
                d.u.flts = tokval.flts
            else if (t == Tfltd)
                d.u.fltd = tokval.fltd
            else if (t == Tint)
                d.u.num = tokval.num
            else if (t == Tglo)
                parsedatref(&d)
            else if (t == Tstr)
                parsedatstr(&d)
            else
                err("constant literal expected", .{});
            cb(&d);
            t = nextnl();
            if (!(t == Tint or t == Tflts or t == Tfltd or t == Tstr or t == Tglo)) break;
        }
        if (t == Trbrace)
            break;
        if (t != Tcomma)
            err(", or }} expected", .{});
    }
    // Done:
    d.type = DEnd;
    cb(&d);
}

fn parselnk(lnk: *Lnk) i32 {
    var haslnk = false;
    while (true) : (haslnk = true) {
        const t = nextnl();
        switch (t) {
            Texport => lnk.@"export" = 1,
            Tthread => lnk.thread = 1,
            Tcommon => lnk.common = 1,
            Tsection => {
                if (lnk.sec != null)
                    err("only one section allowed", .{});
                if (next() != Tstr)
                    err("section \"name\" expected", .{});
                lnk.sec = strf(PFn, "{s}", .{cs(tokval.str)});
                if (peek() == Tstr) {
                    _ = next();
                    lnk.secf = strf(PFn, "{s}", .{cs(tokval.str)});
                }
            },
            else => {
                if (t == Tfunc and lnk.thread != 0)
                    err("only data may have thread linkage", .{});
                if (haslnk and t != Tdata and t != Tfunc)
                    err("only data and function have linkage", .{});
                return t;
            },
        }
    }
}

pub fn parse(text: []const u8, path: []const u8, dbgfile: *const fn ([*c]u8) void, data: *const fn (*Dat) void, func: *const fn (*Fn) void) void {
    var lnk: Lnk = undefined;

    lexinit();
    in = text;
    ipos = 0;
    inpath = path;
    lnum = 1;
    thead = Txxx;
    ntyp = 0;
    all.typ = vnewT(Typ, 0, PHeap);
    tokval.str = vnewT(u8, 128, PHeap);
    while (true) {
        lnk = std.mem.zeroes(Lnk);
        switch (parselnk(&lnk)) {
            Tdbgfile => {
                expect(Tstr);
                dbgfile(tokval.str);
            },
            Tfunc => {
                lnk.@"align" = 16;
                func(parsefn(&lnk));
            },
            Tdata => parsedat(data, &lnk),
            Ttype => parsetyp(),
            Teof => {
                var n: uint = 0;
                while (n < ntyp) : (n += 1) {
                    efree(@ptrCast(all.typ[n].name));
                    if (all.typ[n].nunion != 0)
                        vfree(@ptrCast(all.typ[n].fields));
                }
                vfree(@ptrCast(all.typ));
                return;
            },
            else => err("top-level definition expected", .{}),
        }
    }
}

fn printcon(c: *Con, f: *Writer) Writer.Error!void {
    switch (c.type) {
        CUndef => {},
        CAddr => {
            if ((c.sym.type & SExt) != 0)
                try f.print("extern ", .{});
            if ((c.sym.type & SThr) != 0)
                try f.print("thread ", .{});
            try f.print("${s}", .{cs(str(c.sym.id))});
            if (c.bits.i != 0)
                try f.print("{d:1}", .{c.bits.i});
        },
        CBits => {
            if (c.flt == 1)
                try f.print("s_{f}", .{cfloat(c.bits.s)})
            else if (c.flt == 2)
                try f.print("d_{f}", .{cfloat(c.bits.d)})
            else
                try f.print("{d}", .{c.bits.i});
        },
        else => {},
    }
}

pub fn printref(r: Ref, f: *Fn, fp: *Writer) Writer.Error!void {
    switch (rtype(r)) {
        RTmp => {
            if (r.val < Tmp0)
                try fp.print("R{d}", .{r.val})
            else
                try fp.print("%{s}", .{cs(f.tmp[r.val].name)});
        },
        RCon => {
            if (req(r, UNDEF))
                try fp.print("UNDEF", .{})
            else
                try printcon(&f.con[r.val], fp);
        },
        RSlot => try fp.print("S{d}", .{rsval(r)}),
        RCall => try fp.print("{x:0>4}", .{r.val}),
        RType => try fp.print(":{s}", .{cs(all.typ[r.val].name)}),
        RMem => {
            var i = false;
            const m = &f.mem[r.val];
            try fp.writeByte('[');
            if (m.offset.type != CUndef) {
                try printcon(&m.offset, fp);
                i = true;
            }
            if (!req(m.base, R)) {
                if (i)
                    try fp.print(" + ", .{});
                try printref(m.base, f, fp);
                i = true;
            }
            if (!req(m.index, R)) {
                if (i)
                    try fp.print(" + ", .{});
                try fp.print("{d} * ", .{m.scale});
                try printref(m.index, f, fp);
            }
            try fp.writeByte(']');
        },
        RInt => try fp.print("{d}", .{rsval(r)}),
        -1 => try fp.print("R", .{}),
        else => {},
    }
}

pub fn printfn(f: *Fn, fp: *Writer) Writer.Error!void {
    const ktoc = "wlsd";
    const jtoa = &all.jmp_names;

    try fp.print("function ${s}() {{\n", .{cs(f.name)});
    var b_it: ?*Blk = f.start;
    while (b_it) |b| : (b_it = b.link) {
        try fp.print("@{s}\n", .{cs(b.name)});
        var p_it: ?*Phi = b.phi;
        while (p_it) |p| : (p_it = p.link) {
            try fp.print("\t", .{});
            try printref(p.to, f, fp);
            try fp.print(" ={c} phi ", .{ktoc[@intCast(p.cls)]});
            assert(p.narg != 0);
            var n: uint = 0;
            while (true) : (n += 1) {
                try fp.print("@{s} ", .{cs(p.blk[n].name)});
                try printref(p.arg[n], f, fp);
                if (n == p.narg - 1) {
                    try fp.print("\n", .{});
                    break;
                } else try fp.print(", ", .{});
            }
        }
        for (b.ins[0..b.nins]) |*i| {
            try fp.print("\t", .{});
            if (!req(i.to, R)) {
                try printref(i.to, f, fp);
                try fp.print(" ={c} ", .{ktoc[i.cls]});
            }
            assert(all.optab[i.op].name != null);
            try fp.print("{s}", .{cs(all.optab[i.op].name)});
            if (req(i.to, R))
                switch (i.op) {
                    Oarg, Oswap, Oxcmp, Oacmp, Oacmn, Oafcmp, Oxtest, Oxdiv, Oxidiv => try fp.writeByte(ktoc[i.cls]),
                    else => {},
                };
            if (!req(i.arg[0], R)) {
                try fp.print(" ", .{});
                try printref(i.arg[0], f, fp);
            }
            if (!req(i.arg[1], R)) {
                try fp.print(", ", .{});
                try printref(i.arg[1], f, fp);
            }
            try fp.print("\n", .{});
        }
        switch (b.jmp.type) {
            Jret0, Jretsb, Jretub, Jretsh, Jretuh, Jretw, Jretl, Jrets, Jretd, Jretc => {
                try fp.print("\t{s}", .{cs(jtoa[@intCast(b.jmp.type - 1)].ptr)});
                if (b.jmp.type != Jret0 or !req(b.jmp.arg, R)) {
                    try fp.print(" ", .{});
                    try printref(b.jmp.arg, f, fp);
                }
                if (b.jmp.type == Jretc)
                    try fp.print(", :{s}", .{cs(all.typ[@intCast(f.retty)].name)});
                try fp.print("\n", .{});
            },
            Jhlt => try fp.print("\thlt\n", .{}),
            Jjmp => {
                if (b.s1 != b.link)
                    try fp.print("\tjmp @{s}\n", .{cs(b.s1.?.name)});
            },
            else => {
                try fp.print("\t{s} ", .{cs(jtoa[@intCast(b.jmp.type - 1)].ptr)});
                if (b.jmp.type == Jjnz) {
                    try printref(b.jmp.arg, f, fp);
                    try fp.print(", ", .{});
                }
                assert(b.s1 != null and b.s2 != null);
                try fp.print("@{s}, @{s}\n", .{cs(b.s1.?.name), cs(b.s2.?.name)});
            },
        }
    }
    try fp.print("}}\n", .{});
}
