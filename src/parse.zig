//! One-to-one translation of parse.c
const std = @import("std");
const assert = std.debug.assert;
// -- imports --
const all = @import("all.zig");
const Cls = all.Cls;
const J = all.J;
const Opc = all.Opc;
const Op = all.Op;
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
const intRef = all.intRef;
const Ins = all.Ins;
const Lnk = all.Lnk;
const Mem = all.Mem;
const NField = all.NField;
const NIns = all.NIns;
const NOp = all.NOp;
const NPubOp = all.NPubOp;
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
const tmpRef = all.tmpRef;
const typeRef = all.typeRef;
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
const pnew = all.pnew;
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
const Km = Cls.l; // memory pointer

fn kcls(ch: u8) i16 {
    return switch (ch) {
        'w' => @intFromEnum(Cls.w),
        'l' => @intFromEnum(Cls.l),
        's' => @intFromEnum(Cls.s),
        'd' => @intFromEnum(Cls.d),
        'm' => @intFromEnum(Km),
        'x' => @intFromEnum(Cls.x),
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

const PState = enum {
    label,
    phi,
    instruction,
    end,
};

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

var kwmap: [Ntok]?[*:0]const u8 = blk: {
    var m: [Ntok]?[*:0]const u8 = @splat(null);
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

/// Lexer and parser state for the input being read.
const State = struct {
    lexh: [1 << (32 - M)]uchar = @splat(0),
    lex_initialized: bool = false,
    in: []const u8 = "",
    ipos: usize = 0,
    inpath: []const u8 = "",
    thead: i32 = 0,
    lnum: i32 = 0,
    curf: *Fn = undefined,
    tmph: []i32 = &.{}, // cached hash-table capacity; cleared between functions
    plink: *?*Phi = undefined,
    curb: ?*Blk = null,
    blink: *?*Blk = undefined,
    blkh: [BMask + 1]?*Blk = @splat(null),
    nblk: i32 = 0,
    rcls: i32 = 0,
};
var st: State = .{};
/// input text and read position (replaces FILE* + fgetc/ungetc)
const EOF: i32 = -1;

fn getc() i32 {
    if (st.ipos >= st.in.len) return EOF;
    const c = st.in[st.ipos];
    st.ipos += 1;
    return c;
}

fn ungetc(c: i32) void {
    if (c != EOF) st.ipos -= 1;
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
    const start = st.ipos - @intFromBool(c != EOF);
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
    var txt = st.in[start..st.ipos];
    const neg = txt[0] == '-';
    if (txt[0] == '-' or txt[0] == '+') txt = txt[1..];
    const v = std.fmt.parseFloat(F, txt) catch return false;
    out.* = if (neg) -v else v;
    return true;
}

var tokval: struct {
    chr: u8,
    fltd: f64,
    flts: f32,
    num: i64,
    str: [*:0]u8, // growable token buffer (vector), NUL-terminated by lex()
} = .{ .chr = 0, .fltd = 0, .flts = 0, .num = 0, .str = undefined };


pub const Error = error{InvalidInput};

/// Reports a syntax or type error at the current input line and returns
/// `error.InvalidInput`; the caller decides whether to exit or recover.
/// The backends use it too, so the message names the input file.
pub fn fail(comptime fmt: []const u8, args: anytype) Error {
    dprint("qbe:{s}:{d}: " ++ fmt ++ "\n", .{ st.inpath, st.lnum } ++ args);
    all.dbg.flush() catch {};
    return error.InvalidInput;
}

fn lexinit() void {
    if (st.lex_initialized)
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
            const h = (hash(kwmap[i].?) *% K) >> M;
            assert(st.lexh[h] == Txxx);
            st.lexh[h] = @intCast(i);
        };
    st.lex_initialized = true;
}

fn getint() Error!i64 {
    var n: u64 = 0;
    var c = getc();
    const m = (c == '-');
    if (m) {
        c = getc();
        if (!isdigit(c))
            return fail("integer expected", .{});
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

fn lex() Error!i32 {
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
            st.lnum += 1;
            return Tnl;
        },
        else => {},
    }
    if (go == .none) {
        if (isdigit(c) or c == '-') {
            ungetc(c);
            tokval.num = try getint();
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
                return fail("unterminated string", .{});
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
        return fail("invalid character {c} ({d})", .{ @as(u8, @truncate(@as(c_uint, @bitCast(c)))), c });
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
    t = st.lexh[(hash(tokval.str) *% K) >> M];
    if (t == Txxx or !streq(kwmap[@intCast(t)], tokval.str)) {
        return fail("unknown keyword {s}", .{cs(tokval.str)});
    }
    return t;
}

fn peek() Error!i32 {
    if (st.thead == Txxx)
        st.thead = try lex();
    return st.thead;
}

fn next() Error!i32 {
    const t = try peek();
    st.thead = Txxx;
    return t;
}

fn nextnl() Error!i32 {
    var t: i32 = undefined;
    while (true) {
        t = try next();
        if (t != Tnl) break;
    }
    return t;
}

const ttoa: [Ntok]?[]const u8 = blk: {
    var m: [Ntok]?[]const u8 = @splat(null);
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

fn expect(t: i32) Error!void {
    const t1 = try next();
    if (t == t1)
        return;
    const s1 = ttoa[@intCast(t)] orelse "??";
    const s2 = ttoa[@intCast(t1)] orelse "??";
    return fail("{s} expected, got {s} instead", .{ s1, s2 });
}

fn tmpref() Ref {
    if (st.tmph.len / 2 <= @as(usize, @intCast(st.curf.ntmp - Tmp0))) {
        const capacity: i32 = if (st.tmph.len != 0)
            @as(i32, @intCast(st.tmph.len)) * 2
        else
            TMask + 1;
        if (st.tmph.len != 0) efree(st.tmph.ptr);
        st.tmph = all.eallocSlice(i32, capacity);
        const mask = st.tmph.len - 1;
        for (st.curf.tmps()[Tmp0..], Tmp0..) |temp, t| {
            var i: usize = hash(temp.name.?) & @as(u32, @intCast(mask));
            while (st.tmph[i] != 0) : (i = (i + 1) & mask) {}
            st.tmph[i] = @intCast(t);
        }
    }
    const mask = st.tmph.len - 1;
    var i: usize = hash(tokval.str) & @as(u32, @intCast(mask));
    while (st.tmph[i] != 0) : (i = (i + 1) & mask) {
        const t = st.tmph[i];
        if (streq(st.curf.tmps()[@intCast(t)].name, tokval.str))
            return tmpRef(t);
    }
    const t = st.curf.ntmp;
    st.tmph[i] = t;
    _ = newtmp(null, .x, st.curf);
    st.curf.tmps()[@intCast(t)].name = strf(PFn, "{s}", .{cs(tokval.str)});
    return tmpRef(t);
}

fn parseref() Error!Ref {
    var c: Con = std.mem.zeroes(Con);
    var tok = try next();
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
                while (true) : (tok = try next()) {
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
    return newcon(c, st.curf);
}

fn findtyp(i_: i32) Error!i32 {
    var i = i_;
    while (true) {
        i -= 1;
        if (i < 0) break;
        if (streq(tokval.str, all.typ[@intCast(i)].name))
            return i;
    }
    return fail("undefined type :{s}", .{cs(tokval.str)});
}

fn parsecls(tyn: *i32) Error!i32 {
    switch (try next()) {
        Ttyp => {
            tyn.* = try findtyp(@intCast(all.typ.len));
            return Kc;
        },
        Tsb => return Ksb,
        Tub => return Kub,
        Tsh => return Ksh,
        Tuh => return Kuh,
        Tw => return Cls.w.int(),
        Tl => return Cls.l.int(),
        Ts => return Cls.s.int(),
        Td => return Cls.d.int(),
        else => return fail("invalid class specifier", .{}),
    }
}

inline fn mkins(op: Opc, k: anytype, to: Ref, a0: Ref, a1: Ref) Ins {
    return .{ .op = op, .cls = all.kof(k), .to = to, .arg = .{ a0, a1 } };
}

fn parserefl(arg: bool) Error!bool {
    var k: i32 = undefined;
    var ty: i32 = undefined;
    var env: bool = undefined;
    var r: Ref = undefined;

    var hasenv = false;
    var vararg = false;
    try expect(Tlparen);
    while (try peek() != Trparen) {
        if (all.insbHead() >= NIns)
            return fail("too many instructions", .{});
        if (!arg and vararg)
            return fail("no parameters allowed after '...'", .{});
        var skip = false;
        switch (try peek()) {
            Tdots => {
                if (vararg)
                    return fail("only one '...' allowed", .{});
                vararg = true;
                if (arg) {
                    all.curi[0] = std.mem.zeroes(Ins);
                    all.curi[0].op = .argv;
                    all.curi += 1;
                }
                _ = try next();
                skip = true; // goto Next
            },
            Tenv => {
                if (hasenv)
                    return fail("only one environment allowed", .{});
                hasenv = true;
                env = true;
                _ = try next();
                k = Cls.l.int();
            },
            else => {
                env = false;
                k = try parsecls(&ty);
            },
        }
        if (!skip) {
            r = try parseref();
            if (req(r, R))
                return fail("invalid argument", .{});
            if (!arg and rtype(r) != RTmp)
                return fail("invalid function parameter", .{});
            if (env) {
                if (arg)
                    all.curi[0] = mkins(.arge, k, R, r, R)
                else
                    all.curi[0] = mkins(.pare, k, r, R, R);
            } else if (k == Kc) {
                if (arg)
                    all.curi[0] = mkins(.argc, .l, R, typeRef(ty), r)
                else
                    all.curi[0] = mkins(.parc, .l, r, typeRef(ty), R);
            } else if (k >= Ksb) {
                if (arg)
                    all.curi[0] = mkins(Opc.argsb.offset(k - Ksb), .w, R, r, R)
                else
                    all.curi[0] = mkins(Opc.parsb.offset(k - Ksb), .w, r, R, R);
            } else {
                if (arg)
                    all.curi[0] = mkins(.arg, k, R, r, R)
                else
                    all.curi[0] = mkins(.par, k, r, R, R);
            }
            all.curi += 1;
        }
        // Next:
        if (try peek() == Trparen)
            break;
        try expect(Tcomma);
    }
    try expect(Trparen);
    return vararg;
}

fn findblk() *Blk {
    const h = hash(tokval.str) & BMask;
    var b_it = st.blkh[h];
    while (b_it) |b| : (b_it = b.dlink)
        if (streq(b.name, tokval.str))
            return b;
    const b = newblk();
    b.id = @intCast(st.nblk);
    st.nblk += 1;
    b.name = strf(PFn, "{s}", .{cs(tokval.str)});
    b.dlink = st.blkh[h];
    st.blkh[h] = b;
    return b;
}

fn closeblk() void {
    idup(st.curb.?, all.insbHeadSlice());
    st.blink = &st.curb.?.link;
    all.curi = &all.insb;
}

fn parseline(ps: PState) Error!PState {
    var arg: [NPred]Ref = @splat(R);
    var blk: [NPred]*Blk = undefined;
    var r: Ref = R;
    var op: i32 = 0;
    var i: usize = undefined;
    var k: i32 = 0;
    var ty: i32 = 0;

    var t = try nextnl();
    if (ps == .label and t != Tlbl and t != Trbrace)
        return fail("label or }} expected", .{});
    const Flow = enum { normal, jump, close, ins };
    var flow: Flow = .normal;
    switch (t) {
        Ttmp => {
            r = tmpref();
            try expect(Teq);
            k = try parsecls(&ty);
            op = try next();
        },
        Tblit, Tcall, all.ops.num(.vastart) => {
            // operations without result
            r = R;
            k = Cls.w.int();
            op = t;
        },
        Trbrace => return .end,
        Tlbl => {
            const b = findblk();
            if (st.curb != null and st.curb.?.jmp.type == .xxx) {
                closeblk();
                st.curb.?.jmp.type = .jmp;
                st.curb.?.s1 = b;
            }
            if (b.jmp.type != .xxx)
                return fail("multiple definitions of block @{s}", .{cs(b.name)});
            st.blink.* = b;
            st.curb = b;
            st.plink = &b.phi;
            try expect(Tnl);
            return .phi;
        },
        Tret => {
            st.curb.?.jmp.type = J.retw.add(st.rcls);
            if (try peek() == Tnl)
                st.curb.?.jmp.type = .ret0
            else if (st.rcls != K0) {
                r = try parseref();
                if (req(r, R))
                    return fail("invalid return value", .{});
                st.curb.?.jmp.arg = r;
            }
            flow = .close;
        },
        Tjmp => {
            st.curb.?.jmp.type = .jmp;
            flow = .jump;
        },
        Tjnz => {
            st.curb.?.jmp.type = .jnz;
            r = try parseref();
            if (req(r, R))
                return fail("invalid argument for jnz jump", .{});
            st.curb.?.jmp.arg = r;
            try expect(Tcomma);
            flow = .jump;
        },
        Thlt => {
            st.curb.?.jmp.type = .hlt;
            flow = .close;
        },
        all.ops.num(.dbgloc) => {
            op = t;
            k = Cls.w.int();
            r = R;
            try expect(Tint);
            arg[0] = intRef(tokval.num);
            if (arg[0].val != tokval.num)
                return fail("line number too big", .{});
            if (try peek() == Tcomma) {
                _ = try next();
                try expect(Tint);
                arg[1] = intRef(tokval.num);
                if (arg[1].val != tokval.num)
                    return fail("column number too big", .{});
            } else arg[1] = intRef(0);
            flow = .ins;
        },
        else => {
            if (all.inRange(t, Opc.storeb, Opc.stored)) {
                r = R;
                k = Cls.w.int();
                op = t;
            } else return fail("label, instruction or jump expected", .{});
        },
    }
    if (flow == .jump) {
        try expect(Tlbl);
        st.curb.?.s1 = findblk();
        if (st.curb.?.jmp.type != .jmp) {
            try expect(Tcomma);
            try expect(Tlbl);
            st.curb.?.s2 = findblk();
        }
        if (st.curb.?.s1 == st.curf.start or st.curb.?.s2 == st.curf.start)
            return fail("invalid jump to the start block", .{});
        flow = .close;
    }
    if (flow == .close) {
        try expect(Tnl);
        closeblk();
        return .label;
    }
    if (flow == .normal and op == Tcall) {
        st.curf.leaf = 0;
        arg[0] = try parseref();
        _ = try parserefl(true);
        op = all.ops.num(.call);
        try expect(Tnl);
        if (k == Kc) {
            k = Cls.l.int();
            arg[1] = typeRef(ty);
        }
        if (k >= Ksb)
            k = Cls.w.int();
        flow = .ins;
    }
    if (flow == .normal) {
        if (op == Tloadw)
            op = all.ops.num(.loadsw);
        if (op >= Tloadl and op <= Tloadd)
            op = all.ops.num(.load);
        if (op == Talloc1 or op == Talloc2)
            op = all.ops.num(Opc.alloc_first);
        if (op == Opc.vastart.int() and st.curf.vararg == 0)
            return fail("cannot use vastart in non-variadic function", .{});
        if (k >= Ksb)
            return fail("size class must be w, l, s, or d", .{});
        i = 0;
        if (try peek() != Tnl)
            while (true) {
                if (i == NPred)
                    return fail("too many arguments", .{});
                if (op == Tphi) {
                    try expect(Tlbl);
                    blk[i] = findblk();
                }
                arg[i] = try parseref();
                if (req(arg[i], R))
                    return fail("invalid instruction argument", .{});
                i += 1;
                t = try peek();
                if (t == Tnl)
                    break;
                if (t != Tcomma)
                    return fail(", or end of line expected", .{});
                _ = try next();
            };
        _ = try next();
        switch (op) {
            Tphi => {
                if (ps != .phi or st.curb == st.curf.start)
                    return fail("unexpected phi instruction", .{});
                const phi = pnew(Phi);
                phi.to = r;
                phi.cls = all.kof(k);
                phi.arg = vnewT(Ref, i, PFn);
                phi.blk = vnewT(*Blk, i, PFn);
                phi.narg = @intCast(i);
                @memcpy(phi.args(), arg[0..i]);
                @memcpy(phi.blks(), blk[0..i]);
                st.plink.* = phi;
                st.plink = &phi.link;
                return .phi;
            },
            Tblit => {
                if (all.insbHead() >= NIns - 1)
                    return fail("too many instructions", .{});
                @memset(all.curi[0..2], std.mem.zeroes(Ins));
                all.curi[0].op = .blit0;
                all.curi[0].arg[0] = arg[0];
                all.curi[0].arg[1] = arg[1];
                all.curi += 1;
                if (rtype(arg[2]) != RCon)
                    return fail("blit size must be constant", .{});
                const c = &st.curf.cons()[arg[2].val];
                r = intRef(c.bits.i);
                if (c.type != CBits or rsval(r) < 0 or rsval(r) != c.bits.i)
                    return fail("invalid blit size", .{});
                all.curi[0].op = .blit1;
                all.curi[0].arg[0] = r;
                all.curi += 1;
                return .instruction;
            },
            else => {
                if (op >= NPubOp)
                    return fail("invalid instruction", .{});
            },
        }
    }
    // Ins:
    if (all.insbHead() >= NIns)
        return fail("too many instructions", .{});
    all.curi[0].op = all.ops.of(op);
    all.curi[0].cls = all.kof(k);
    all.curi[0].to = r;
    all.curi[0].arg[0] = arg[0];
    all.curi[0].arg[1] = arg[1];
    all.curi += 1;
    return .instruction;
}

fn usecheck(r: Ref, k: i32, f: *Fn) bool {
    return rtype(r) != RTmp or f.tmps()[r.val].cls.int() == k or (f.tmps()[r.val].cls == .l and k == Cls.w.int());
}

fn typecheck(f: *Fn) Error!void {
    var pb: BSet = undefined;
    var ppb: BSet = undefined;
    var k: i32 = undefined;
    var t: ?*Tmp = undefined;
    var r: Ref = undefined;

    fillpreds(f);
    bsinit(&pb, f.nblk);
    bsinit(&ppb, f.nblk);
    var b_it: ?*Blk = f.start;
    while (b_it) |b| : (b_it = b.link) {
        var p_it: ?*Phi = b.phi;
        while (p_it) |p| : (p_it = p.link)
            f.tmps()[p.to.val].cls = p.cls;
        for (b.insns()) |*i|
            if (rtype(i.to) == RTmp) {
                t = &f.tmps()[i.to.val];
                if (clsmerge(&t.?.cls, i.cls))
                    return fail("temporary %{s} is assigned with multiple types", .{cs(t.?.name)});
            };
    }
    b_it = f.start;
    while (b_it) |b| : (b_it = b.link) {
        bszero(&pb);
        var n: uint = 0;
        while (n < b.npred) : (n += 1)
            bsset(&pb, b.preds()[n].id);
        var p_it: ?*Phi = b.phi;
        while (p_it) |p| : (p_it = p.link) {
            bszero(&ppb);
            t = &f.tmps()[p.to.val];
            n = 0;
            while (n < p.narg) : (n += 1) {
                k = t.?.cls.int();
                if (bshas(&ppb, p.blks()[n].id))
                    return fail("multiple entries for @{s} in phi %{s}", .{cs(p.blks()[n].name), cs(t.?.name)});
                if (!usecheck(p.args()[n], k, f))
                    return fail("invalid type for operand %{s} in phi %{s}", .{cs(f.tmps()[p.args()[n].val].name), cs(t.?.name)});
                bsset(&ppb, p.blks()[n].id);
            }
            if (!bsequal(&pb, &ppb))
                return fail("predecessors not matched in phi %{s}", .{cs(t.?.name)});
        }
        for (b.insns()) |*i| {
            n = 0;
            while (n < 2) : (n += 1) {
                k = all.optab[i.op.int()].argcls[n][i.cls.idx()];
                r = i.arg[n];
                const which: []const u8 = if (n == 1) "second" else "first";
                if (k == Ke)
                    return fail("invalid instruction type in {s}", .{cs(all.optab[i.op.int()].name)});
                if (rtype(r) == RType)
                    continue;
                if (rtype(r) != -1 and k == Cls.x.int())
                    return fail("no {s} operand expected in {s}", .{which, cs(all.optab[i.op.int()].name)});
                if (rtype(r) == -1 and k != Cls.x.int())
                    return fail("missing {s} operand in {s}", .{which, cs(all.optab[i.op.int()].name)});
                if (!usecheck(r, k, f)) {
                    const operand = &f.tmps()[r.val];
                    return fail("invalid type for {s} operand %{s} in {s}", .{which, cs(operand.name), cs(all.optab[i.op.int()].name)});
                }
            }
        }
        r = b.jmp.arg;
        var jerr = false;
        if (isret(b.jmp.type)) {
            if (b.jmp.type == .retc)
                k = Cls.l.int()
            else if (b.jmp.type.int() >= J.retsb.int())
                k = Cls.w.int()
            else
                k = b.jmp.type.int() - J.retw.int();
            if (!usecheck(r, k, f))
                jerr = true;
        }
        if (jerr or (b.jmp.type == .jnz and !usecheck(r, Cls.w.int(), f)))
            return fail("invalid type for jump argument %{s} in block @{s}", .{cs(f.tmps()[r.val].name), cs(b.name)});
        if (b.s1 != null and b.s1.?.jmp.type == .xxx)
            return fail("block @{s} is used undefined", .{cs(b.s1.?.name)});
        if (b.s2 != null and b.s2.?.jmp.type == .xxx)
            return fail("block @{s} is used undefined", .{cs(b.s2.?.name)});
    }
}

fn parsefn(lnk: *Lnk) Error!*Fn {
    var ps: PState = undefined;

    st.curb = null;
    st.nblk = 0;
    all.curi = &all.insb;
    st.curf = pnew(Fn);
    st.curf.ntmp = 0;
    st.curf.ncon = 2;
    st.curf.tmp = vnewT(Tmp, st.curf.ntmp, PFn);
    st.curf.con = vnewT(Con, st.curf.ncon, PFn);
    var i: i32 = 0;
    while (i < Tmp0) : (i += 1)
        if (all.T.fpr0 <= i and i < all.T.fpr0 + all.T.nfpr) {
            _ = newtmp(null, .d, st.curf);
        } else {
            _ = newtmp(null, .l, st.curf);
        };
    st.curf.cons()[0].type = CBits;
    st.curf.cons()[0].bits.i = 0xdeaddead; // UNDEF
    st.curf.cons()[1].type = CBits;
    st.curf.lnk = lnk.*;
    st.curf.leaf = 1;
    st.blink = &st.curf.start;
    st.curf.retty = Cls.x.int();
    if (try peek() != Tglo)
        st.rcls = try parsecls(&st.curf.retty)
    else
        st.rcls = K0;
    if (try next() != Tglo)
        return fail("function name expected", .{});
    st.curf.name = strf(PFn, "{s}", .{cs(tokval.str)});
    st.curf.vararg = @intFromBool(try parserefl(false));
    if (try nextnl() != Tlbrace)
        return fail("function body must start with {{", .{});
    ps = .label;
    while (true) {
        ps = try parseline(ps);
        if (ps == .end) break;
    }
    if (st.curb == null)
        return fail("empty function", .{});
    if (st.curb.?.jmp.type == .xxx)
        return fail("last block misses jump", .{});
    st.curf.mem = vnewT(Mem, 0, PFn);
    st.curf.nmem = 0;
    st.curf.nblk = @intCast(st.nblk);
    st.curf.rpo = vnewT(*Blk, st.nblk, PFn);
    var b_it = st.curf.start;
    while (b_it) |b| : (b_it = b.link)
        b.dlink = null; // was trashed by findblk()
    st.blkh = @splat(null);
    @memset(st.tmph, 0);
    try typecheck(st.curf);
    return st.curf;
}

fn parsefields(fld: *[NField + 1]Field, ty: *Typ, t_: i32) Error!void {
    var t = t_;
    var ty1: usize = undefined; // index of the member type
    var c: i32 = undefined;
    var a: i32 = undefined;
    var @"type": i32 = undefined;
    var s: u64 = undefined;

    var n: usize = 0;
    var sz: u64 = 0;
    var al = ty.@"align";
    while (t != Trbrace) {
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
                ty1 = @intCast(try findtyp(@as(i32, @intCast(all.typ.len)) - 1));
                s = all.typ[ty1].size;
                a = all.typ[ty1].@"align";
            },
            else => return fail("invalid type member specifier", .{}),
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
        t = try nextnl();
        if (t == Tint) {
            c = @truncate(tokval.num);
            t = try nextnl();
        } else c = 1;
        sz +%= @as(u64, @bitCast(@as(i64, a))) +% @as(u64, @bitCast(@as(i64, c))) *% s;
        if (@"type" == FTyp)
            s = ty1;
        while (c > 0 and n < NField) : ({
            c -= 1;
            n += 1;
        }) {
            fld[n].type = @"type";
            fld[n].len = @truncate(s);
        }
        if (t != Tcomma)
            break;
        t = try nextnl();
    }
    if (t != Trbrace)
        return fail(", or }} expected", .{});
    fld[n].type = FEnd;
    // C: `1 << al` with al == -1 for an empty type; match x86 shift masking
    a = @as(i32, 1) << @as(u5, @truncate(@as(u32, @bitCast(al))));
    if (sz < ty.size)
        sz = ty.size;
    const au: u64 = @bitCast(@as(i64, a));
    ty.size = (sz +% au -% 1) & (0 -% au);
    ty.@"align" = al;
}

fn parsetyp() Error!void {
    var t: i32 = undefined;
    var al: i32 = undefined;

    // be careful if extending the syntax
    // to handle nested types, any pointer
    // held to typ[] might be invalidated!
    const index = all.typ.len;
    var storage = all.typ.ptr;
    vgrow(&storage, index + 1);
    all.typ = storage[0 .. index + 1];
    const ty = &all.typ[index];
    ty.* = std.mem.zeroes(Typ);
    ty.isdark = 0;
    ty.isunion = 0;
    ty.@"align" = -1;
    ty.size = 0;
    if (try nextnl() != Ttyp or try nextnl() != Teq)
        return fail("type name and then = expected", .{});
    ty.name = strf(PHeap, "{s}", .{cs(tokval.str)});
    t = try nextnl();
    if (t == Talign) {
        if (try nextnl() != Tint)
            return fail("alignment expected", .{});
        al = 0;
        while (true) : (al += 1) {
            tokval.num = @divTrunc(tokval.num, 2);
            if (tokval.num == 0) break;
        }
        ty.@"align" = al;
        t = try nextnl();
    }
    if (t != Tlbrace)
        return fail("type body must start with {{", .{});
    t = try nextnl();
    if (t == Tint) {
        ty.isdark = 1;
        ty.size = @bitCast(tokval.num);
        if (ty.@"align" == -1)
            return fail("dark types need alignment", .{});
        if (try nextnl() != Trbrace)
            return fail("}} expected", .{});
        return;
    }
    var n: uint = 0;
    ty.fields = vnewT([NField + 1]Field, 1, PHeap);
    ty.nunion = 1; // publish ownership before a field parser can fail
    if (t == Tlbrace) {
        ty.isunion = 1;
        while (true) {
            if (t != Tlbrace)
                return fail("invalid union member", .{});
            vgrow(&ty.fields, n + 1);
            ty.nunion = n + 1;
            try parsefields(&ty.fieldSets()[n], ty, try nextnl());
            n += 1;
            t = try nextnl();
            if (t == Trbrace) break;
        }
    } else {
        try parsefields(&ty.fieldSets()[n], ty, t);
        n += 1;
    }
    ty.nunion = n;
}

fn parsedatref(d: *Dat) Error!void {
    d.isref = 1;
    d.u.ref.name = strf(PFn, "{s}", .{cs(tokval.str)});
    d.u.ref.off = 0;
    const t = try peek();
    if (t == Tplus) {
        _ = try next();
        if (try next() != Tint)
            return fail("invalid token after offset in ref", .{});
        d.u.ref.off = tokval.num;
    }
}

fn parsedatstr(d: *Dat) void {
    d.isstr = 1;
    d.u.str = strf(PFn, "{s}", .{cs(tokval.str)});
}

fn parsedat(cb: *const fn (*Dat) Error!void, lnk: ?*Lnk) Error!void {
    var t: i32 = undefined;
    var d: Dat = undefined;

    if (try nextnl() != Tglo or try nextnl() != Teq)
        return fail("data name, then = expected", .{});
    const name = strf(PFn, "{s}", .{cs(tokval.str)});
    t = try nextnl();
    lnk.?.@"align" = 8;
    if (t == Talign) {
        if (try nextnl() != Tint)
            return fail("alignment expected", .{});
        if (tokval.num <= 0 or tokval.num > 127 or (tokval.num & (tokval.num - 1)) != 0)
            return fail("invalid alignment", .{});
        lnk.?.@"align" = @intCast(tokval.num);
        t = try nextnl();
    }
    d.type = DStart;
    d.name = name;
    d.lnk = lnk;
    try cb(&d);

    if (t != Tlbrace)
        return fail("expected data contents in {{ .. }}", .{});
    outer: while (true) {
        switch (try nextnl()) {
            Trbrace => break :outer,
            Tl => d.type = DL,
            Tw => d.type = DW,
            Th => d.type = DH,
            Tb => d.type = DB,
            Ts => d.type = DW,
            Td => d.type = DL,
            Tz => d.type = DZ,
            else => return fail("invalid size specifier {c} in data", .{tokval.chr}),
        }
        t = try nextnl();
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
                try parsedatref(&d)
            else if (t == Tstr)
                parsedatstr(&d)
            else
                return fail("constant literal expected", .{});
            try cb(&d);
            t = try nextnl();
            if (!(t == Tint or t == Tflts or t == Tfltd or t == Tstr or t == Tglo)) break;
        }
        if (t == Trbrace)
            break;
        if (t != Tcomma)
            return fail(", or }} expected", .{});
    }
    // Done:
    d.type = DEnd;
    try cb(&d);
}

fn parselnk(lnk: *Lnk) Error!i32 {
    var haslnk = false;
    while (true) : (haslnk = true) {
        const t = try nextnl();
        switch (t) {
            Texport => lnk.@"export" = 1,
            Tthread => lnk.thread = 1,
            Tcommon => lnk.common = 1,
            Tsection => {
                if (lnk.sec != null)
                    return fail("only one section allowed", .{});
                if (try next() != Tstr)
                    return fail("section \"name\" expected", .{});
                lnk.sec = strf(PFn, "{s}", .{cs(tokval.str)});
                if (try peek() == Tstr) {
                    _ = try next();
                    lnk.secf = strf(PFn, "{s}", .{cs(tokval.str)});
                }
            },
            else => {
                if (t == Tfunc and lnk.thread != 0)
                    return fail("only data may have thread linkage", .{});
                if (haslnk and t != Tdata and t != Tfunc)
                    return fail("only data and function have linkage", .{});
                return t;
            },
        }
    }
}

pub fn parse(text: []const u8, path: []const u8, dbgfile: *const fn ([*:0]const u8) void, data: *const fn (*Dat) Error!void, func: *const fn (*Fn) Error!void) Error!void {
    var lnk: Lnk = undefined;

    lexinit();
    st.in = text;
    st.ipos = 0;
    st.inpath = path;
    st.lnum = 1;
    st.thead = Txxx;
    all.typ = vnewT(Typ, 0, PHeap)[0..0];
    tokval.str = @ptrCast(vnewT(u8, 128, PHeap));
    defer {
        for (all.typ) |ty| {
            efree(ty.name);
            if (ty.nunion != 0) vfree(ty.fields);
        }
        vfree(all.typ.ptr);
        all.typ = &.{};
        vfree(tokval.str);
        tokval.str = undefined;
        // Retain the cached hash allocation, but never leave references to
        // failed function/pool storage for a subsequent library call.
        @memset(st.tmph, 0);
        st.blkh = @splat(null);
    }
    errdefer all.freeall();
    while (true) {
        lnk = std.mem.zeroes(Lnk);
        switch (try parselnk(&lnk)) {
            Tdbgfile => {
                try expect(Tstr);
                dbgfile(tokval.str);
            },
            Tfunc => {
                lnk.@"align" = 16;
                try func(try parsefn(&lnk));
            },
            Tdata => try parsedat(data, &lnk),
            Ttype => try parsetyp(),
            Teof => return,
            else => return fail("top-level definition expected", .{}),
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
                try fp.print("%{s}", .{cs(f.tmps()[r.val].name)});
        },
        RCon => {
            if (req(r, UNDEF))
                try fp.print("UNDEF", .{})
            else
                try printcon(&f.cons()[r.val], fp);
        },
        RSlot => try fp.print("S{d}", .{rsval(r)}),
        RCall => try fp.print("{x:0>4}", .{r.val}),
        RType => try fp.print(":{s}", .{cs(all.typ[r.val].name)}),
        RMem => {
            var i = false;
            const m = &f.mems()[r.val];
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
            try fp.print(" ={c} phi ", .{ktoc[p.cls.idx()]});
            assert(p.narg != 0);
            var n: uint = 0;
            while (true) : (n += 1) {
                try fp.print("@{s} ", .{cs(p.blks()[n].name)});
                try printref(p.args()[n], f, fp);
                if (n == p.narg - 1) {
                    try fp.print("\n", .{});
                    break;
                } else try fp.print(", ", .{});
            }
        }
        for (b.insns()) |*i| {
            try fp.print("\t", .{});
            if (!req(i.to, R)) {
                try printref(i.to, f, fp);
                try fp.print(" ={c} ", .{ktoc[i.cls.idx()]});
            }
            assert(all.optab[i.op.int()].name != null);
            try fp.print("{s}", .{cs(all.optab[i.op.int()].name)});
            if (req(i.to, R))
                switch (i.op) {
                    .arg, .swap, .xcmp, .acmp, .acmn, .afcmp, .xtest, .xdiv, .xidiv => try fp.writeByte(ktoc[i.cls.idx()]),
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
            .ret0, .retsb, .retub, .retsh, .retuh, .retw, .retl, .rets, .retd, .retc => {
                try fp.print("\t{s}", .{cs(jtoa[@intCast(b.jmp.type.int() - 1)].ptr)});
                if (b.jmp.type != .ret0 or !req(b.jmp.arg, R)) {
                    try fp.print(" ", .{});
                    try printref(b.jmp.arg, f, fp);
                }
                if (b.jmp.type == .retc)
                    try fp.print(", :{s}", .{cs(all.typ[@intCast(f.retty)].name)});
                try fp.print("\n", .{});
            },
            .hlt => try fp.print("\thlt\n", .{}),
            .jmp => {
                if (b.s1 != b.link)
                    try fp.print("\tjmp @{s}\n", .{cs(b.s1.?.name)});
            },
            else => {
                try fp.print("\t{s} ", .{cs(jtoa[@intCast(b.jmp.type.int() - 1)].ptr)});
                if (b.jmp.type == .jnz) {
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

test "temporary hash slice: initial allocation, deduplication, and reuse" {
    const saved = st;
    const saved_token = tokval;
    st = .{};
    defer {
        if (st.tmph.len != 0) efree(st.tmph.ptr);
        st = saved;
        tokval = saved_token;
        all.freeall();
    }
    var f = std.mem.zeroes(Fn);
    f.ntmp = Tmp0;
    f.tmp = vnewT(Tmp, Tmp0, PFn);
    st.curf = &f;
    try std.testing.expectEqual(@as(usize, 0), st.tmph.len);
    tokval.str = @constCast("alpha");
    const alpha = tmpref();
    try std.testing.expect(req(alpha, tmpRef(Tmp0)));
    try std.testing.expectEqual(@as(usize, TMask + 1), st.tmph.len);
    const cached = st.tmph.ptr;
    try std.testing.expect(req(alpha, tmpref()));
    try std.testing.expectEqual(@as(i32, Tmp0 + 1), f.ntmp);
    tokval.str = @constCast("beta");
    try std.testing.expect(req(tmpref(), tmpRef(Tmp0 + 1)));
    try std.testing.expectEqual(cached, st.tmph.ptr);

    // Match parsefn's table clear without discarding its cached allocation.
    @memset(st.tmph, 0);
    f.ntmp = Tmp0;
    f.tmp = vnewT(Tmp, Tmp0, PFn);
    tokval.str = @constCast("beta");
    try std.testing.expect(req(tmpref(), tmpRef(Tmp0)));
    try std.testing.expectEqual(cached, st.tmph.ptr);
    try std.testing.expectEqual(@as(usize, TMask + 1), st.tmph.len);
    try std.testing.expectEqualStrings("beta", cs(f.tmps()[Tmp0].name));
}

test "temporary hash slice: wrapped collisions and rehash preserve references" {
    const saved = st;
    const saved_token = tokval;
    st = .{};
    defer {
        if (st.tmph.len != 0) efree(st.tmph.ptr);
        st = saved;
        tokval = saved_token;
        all.freeall();
    }
    var f = std.mem.zeroes(Fn);
    f.ntmp = Tmp0;
    f.tmp = vnewT(Tmp, Tmp0, PFn);
    st.curf = &f;
    // A small owned power-of-two table exercises the production growth path.
    st.tmph = all.eallocSlice(i32, 8);
    var names: [2][*:0]u8 = undefined;
    var found: usize = 0;
    for (0..1024) |n| {
        const name = strf(PFn, "collision{d}", .{n});
        if (hash(name) & 7 != 7) continue;
        names[found] = name;
        found += 1;
        if (found == names.len) break;
    }
    try std.testing.expectEqual(names.len, found);
    tokval.str = names[0];
    const first = tmpref();
    tokval.str = names[1];
    const second = tmpref();
    try std.testing.expectEqual(@as(i32, Tmp0), st.tmph[7]);
    try std.testing.expectEqual(@as(i32, Tmp0 + 1), st.tmph[0]);
    try std.testing.expect(req(second, tmpref()));
    tokval.str = @constCast("third");
    const third = tmpref();
    tokval.str = @constCast("fourth");
    const fourth = tmpref();
    try std.testing.expectEqual(@as(usize, 8), st.tmph.len);
    tokval.str = names[0];
    try std.testing.expect(req(first, tmpref())); // grows and rehashes at half full
    try std.testing.expectEqual(@as(usize, 16), st.tmph.len);
    tokval.str = names[1];
    try std.testing.expect(req(second, tmpref()));
    tokval.str = @constCast("third");
    try std.testing.expect(req(third, tmpref()));
    tokval.str = @constCast("fourth");
    try std.testing.expect(req(fourth, tmpref()));
    try std.testing.expectEqual(@as(i32, Tmp0 + 4), f.ntmp);
}

test "typed parser states: label rejection and closing transition" {
    const saved = st;
    const saved_token = tokval;
    const saved_debug = all.dbg;
    st = .{};
    lexinit();
    tokval.str = @ptrCast(vnewT(u8, 128, PHeap));
    defer {
        vfree(tokval.str);
        st = saved;
        tokval = saved_token;
        all.dbg = saved_debug;
    }
    var buffer: [256]u8 = undefined;
    var debug = Writer.fixed(&buffer);
    all.dbg = &debug;
    st.inpath = "<state-test>";
    st.in = "%bad =w copy 0\n";
    st.lnum = 1;
    try std.testing.expectError(error.InvalidInput, parseline(.label));
    try std.testing.expectEqualStrings("qbe:<state-test>:1: label or } expected\n", debug.buffered());
    st.in = "}\n";
    st.ipos = 0;
    st.thead = Txxx;
    try std.testing.expectEqual(PState.end, try parseline(.label));
}

test "type table slices: growth, nested types, union alternatives, and dark types" {
    const saved = st;
    const saved_token = tokval;
    const saved_types = all.typ;
    const saved_debug = all.dbg;
    var debug_buffer: [4096]u8 = undefined;
    var diagnostics = Writer.fixed(&debug_buffer);
    all.dbg = &diagnostics;
    st = .{};
    defer {
        if (st.tmph.len != 0) efree(st.tmph.ptr);
        st = saved;
        tokval = saved_token;
        all.typ = saved_types;
        all.dbg = saved_debug;
        all.freeall();
    }
    const Callbacks = struct {
        fn debugfile(_: [*:0]const u8) void {}
        fn func(_: *Fn) Error!void {
            return error.InvalidInput;
        }
        fn data(_: *Dat) Error!void {
            if (all.typ.len != 42 or all.typ[39].size != 320 or
                all.typ[39].nunion != 1 or all.typ[40].nunion != 9 or
                all.typ[41].isdark != 1 or all.typ[41].size != 16 or
                all.typ[41].fieldSets().len != 0) return error.InvalidInput;
            for (all.typ[40].fieldSets()) |fields| {
                if (fields[0].type != Fw or fields[1].type != FEnd)
                    return error.InvalidInput;
            }
        }
    };
    var text: Writer.Allocating = .init(std.testing.allocator);
    defer text.deinit();
    try text.writer.writeAll("type :t0 = { w }\n");
    for (1..40) |n|
        try text.writer.print("type :t{d} = {{ :t{d}, l }}\n", .{ n, n - 1 });
    try text.writer.writeAll("type :u = {");
    for (0..9) |_| try text.writer.writeAll(" { w }");
    try text.writer.writeAll(" }\ntype :opaque = align 8 { 16 }\ndata $probe = { w 1 }\n");
    try parse(text.written(), "<types>", Callbacks.debugfile, Callbacks.data, Callbacks.func);
    try std.testing.expectEqual(@as(usize, 0), all.typ.len);
}

test "parser cleanup: malformed type definitions then valid input" {
    const saved = st;
    const saved_token = tokval;
    const saved_types = all.typ;
    const saved_debug = all.dbg;
    st = .{};
    defer {
        if (st.tmph.len != 0) efree(st.tmph.ptr);
        st = saved;
        tokval = saved_token;
        all.typ = saved_types;
        all.dbg = saved_debug;
        all.freeall();
    }
    var buffer: [4096]u8 = undefined;
    var debug = Writer.fixed(&buffer);
    all.dbg = &debug;
    const Callbacks = struct {
        fn debugfile(_: [*:0]const u8) void {}
        fn data(_: *Dat) Error!void {}
        fn func(_: *Fn) Error!void {
            return error.InvalidInput;
        }
    };
    for ([_][]const u8{
        "type\n",                                        "type :bad = { w\n", "type :bad = { { w } { d\n",
        "type :one = { w }\ntype :bad = { :missing }\n",
    }) |text| {
        try std.testing.expectError(error.InvalidInput, parse(text, "<bad-types>", Callbacks.debugfile, Callbacks.data, Callbacks.func));
        try std.testing.expectEqual(@as(usize, 0), all.typ.len);
        try parse("type :good = { w }\n", "<good-types>", Callbacks.debugfile, Callbacks.data, Callbacks.func);
        try std.testing.expectEqual(@as(usize, 0), all.typ.len);
    }
}

test "typecheck: type and constant references never index the temporary table" {
    defer all.freeall();
    var f = std.mem.zeroes(Fn);
    f.ntmp = Tmp0 + 1;
    f.tmp = vnewT(Tmp, f.ntmp, PFn);
    f.tmps()[Tmp0].cls = .l;
    f.ncon = 400;
    f.con = vnewT(Con, f.ncon, PFn);
    f.cons()[399].type = CBits;
    var instructions = [_]Ins{
        all.mkIns(.parc, .l, tmpRef(Tmp0), typeRef(299), R),
        all.mkIns(.copy, .l, tmpRef(Tmp0), all.conRef(399), R),
    };
    var block = std.mem.zeroes(Blk);
    block.ins = &instructions;
    block.nins = instructions.len;
    block.pred = vnewT(*Blk, 0, PFn);
    block.jmp.type = .ret0;
    f.start = &block;
    f.nblk = 1;
    try typecheck(&f);
}
