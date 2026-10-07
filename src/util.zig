//! One-to-one translation of util.c
const std = @import("std");
const assert = std.debug.assert;
const c = @import("libc.zig");
// -- imports --
const all = @import("all.zig");
const BIT = all.BIT;
const BSet = all.BSet;
const Blk = all.Blk;
const CAddr = all.CAddr;
const CBits = all.CBits;
const CON = all.CON;
const CUndef = all.CUndef;
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
const INRANGE = all.INRANGE;
const Ins = all.Ins;
const Kd = all.Kd;
const Kl = all.Kl;
const Ks = all.Ks;
const Kw = all.Kw;
const Kx = all.Kx;
const NBit = all.NBit;
const NCmp = all.NCmp;
const NCmpI = all.NCmpI;
const Num = all.Num;
const Oadd = all.ops.Oadd;
const Oand = all.ops.Oand;
const Oarg = all.ops.Oarg;
const Oblit0 = all.ops.Oblit0;
const Oblit1 = all.ops.Oblit1;
const Ocall = all.ops.Ocall;
const Ocmpd = all.Ocmpd;
const Ocmpd1 = all.Ocmpd1;
const Ocmpl = all.Ocmpl;
const Ocmpl1 = all.Ocmpl1;
const Ocmps = all.Ocmps;
const Ocmps1 = all.Ocmps1;
const Ocmpw = all.Ocmpw;
const Ocmpw1 = all.Ocmpw1;
const Onop = all.ops.Onop;
const Opar = all.ops.Opar;
const Osalloc = all.ops.Osalloc;
const Osel0 = all.ops.Osel0;
const Osel1 = all.ops.Osel1;
const PFn = all.PFn;
const PHeap = all.PHeap;
const Phi = all.Phi;
const Pool = all.Pool;
const R = all.R;
const RCon = all.RCon;
const RTmp = all.RTmp;
const Ref = all.Ref;
const Sym = all.Sym;
const TMP = all.TMP;
const Tmp = all.Tmp;
const Tmp0 = all.Tmp0;
const bits = all.bits;
const err = all.err;
const isarg = all.isarg;
const ispar = all.ispar;
const rtype = all.rtype;
const uchar = all.uchar;
const uint = all.uint;
const ulong = all.ulong;
// -- end imports --

const Vec = extern struct {
    mag: ulong align(16),
    pool: Pool,
    esz: usize,
    cap: ulong,
};

const Bucket = extern struct {
    nstr: uint,
    str: [*c][*c]u8,
};

const VMin = 2;
const VMag = 0xcabba9e;
const NPtr = 256;
const IBits = 12;
const IMask = (1 << IBits) - 1;

var ptr: [NPtr]?*anyopaque = @splat(null);
var pool: [*c]?*anyopaque = &ptr;
var nptr: i32 = 1;

var itbl: [IMask + 1]Bucket = @splat(.{ .nstr = 0, .str = null }); // string interning table

/// helper for C pointer subtraction (p - q)
pub inline fn ptrdiff(p: anytype, q: @TypeOf(p)) isize {
    const T = @typeInfo(@TypeOf(p)).pointer.child;
    return @divExact(@as(isize, @bitCast(@intFromPtr(p) -% @intFromPtr(q))), @sizeOf(T));
}

pub fn hash(s0: [*c]const u8) u32 {
    var s = s0;
    var h: u32 = 0;
    while (s.* != 0) : (s += 1)
        h = @as(u32, s.*) +% 17 *% h;
    return h;
}

pub fn die_(file: [*c]const u8, s: [*c]const u8, ...) callconv(.c) noreturn {
    _ = c.fprintf(c.stderr, "%s: dying: ", file);
    var ap = @cVaStart();
    _ = c.vfprintf(c.stderr, s, ap);
    @cVaEnd(&ap);
    _ = c.fputc('\n', c.stderr);
    c.abort();
}

/// die(...) macro: die_(__FILE__, ...)
pub fn die(s: [*c]const u8, args: anytype) noreturn {
    @call(.auto, die_, .{ @as([*c]const u8, "qbe"), s } ++ args);
}

pub fn emalloc(n: usize) ?*anyopaque {
    const p = c.calloc(1, n);
    if (p == null)
        die("emalloc, out of memory", .{});
    return p;
}

pub fn alloc(n: usize) ?*anyopaque {
    var pp: [*c]?*anyopaque = undefined;

    if (n == 0)
        return null;
    if (nptr >= NPtr) {
        pp = @ptrCast(@alignCast(emalloc(NPtr * @sizeOf(?*anyopaque))));
        pp[0] = @ptrCast(pool);
        pool = pp;
        nptr = 1;
    }
    const p = emalloc(n);
    pool[@intCast(nptr)] = p;
    nptr += 1;
    return p;
}

pub fn freeall() void {
    var pp: [*c]?*anyopaque = undefined;

    while (true) {
        pp = &pool[1];
        while (pp < &pool[@intCast(nptr)]) : (pp += 1)
            c.free(pp.*);
        pp = @ptrCast(@alignCast(pool[0]));
        if (pp == null)
            break;
        c.free(@ptrCast(pool));
        pool = pp;
        nptr = NPtr;
    }
    nptr = 1;
}

pub fn vnew(len: ulong, esz: usize, pl: Pool) ?*anyopaque {
    var cap: ulong = VMin;
    while (cap < len) cap *= 2;
    const f = if (pl == PHeap) &emalloc else &alloc;
    const v: [*c]Vec = @ptrCast(@alignCast(f(cap * esz + @sizeOf(Vec))));
    v.*.mag = VMag;
    v.*.cap = cap;
    v.*.esz = esz;
    v.*.pool = pl;
    return @ptrCast(v + 1);
}

/// typed convenience wrapper: (T *)vnew(len, sizeof(T), pool)
pub inline fn vnewT(comptime T: type, len: anytype, pl: Pool) [*c]T {
    return @ptrCast(@alignCast(vnew(@intCast(len), @sizeOf(T), pl)));
}

pub fn vfree(p: ?*anyopaque) void {
    const v: [*c]Vec = @as([*c]Vec, @ptrCast(@alignCast(p))) - 1;
    assert(v.*.mag == VMag);
    if (v.*.pool == PHeap) {
        v.*.mag = 0;
        c.free(@ptrCast(v));
    }
}

pub fn vgrow(vp: anytype, len: anytype) void {
    const v: [*c]Vec = @as([*c]Vec, @ptrCast(@alignCast(vp.*))) - 1;
    assert(v.*.mag == VMag);
    if (v.*.cap >= len)
        return;
    const v1 = vnew(@intCast(len), v.*.esz, v.*.pool);
    _ = c.memcpy(v1, @ptrCast(v + 1), v.*.cap * v.*.esz);
    vfree(@ptrCast(v + 1));
    vp.* = @ptrCast(@alignCast(v1));
}

pub fn addins(pvins: *[*c]Ins, pnins: *uint, i: [*c]Ins) void {
    if (i.*.op == Onop)
        return;
    pnins.* += 1;
    vgrow(pvins, pnins.*);
    pvins.*[pnins.* - 1] = i.*;
}

pub fn addbins(pvins: *[*c]Ins, pnins: *uint, b: [*c]Blk) void {
    var i = b.*.ins;
    while (i < &b.*.ins[b.*.nins]) : (i += 1)
        addins(pvins, pnins, i);
}

fn vstrf(pl: Pool, s: [*c]const u8, ...) callconv(.c) [*c]u8 {
    var ap = @cVaStart();
    var ap2 = @cVaCopy(&ap);
    const n = c.vsnprintf(null, 0, s, ap);
    @cVaEnd(&ap);
    const p: [*c]u8 = @ptrCast((if (pl == PFn) &alloc else &emalloc)(@intCast(n + 1)));
    _ = c.vsnprintf(p, @intCast(n + 1), s, ap2);
    @cVaEnd(&ap2);
    return p;
}

pub fn strf(pl: Pool, s: [*c]const u8, args: anytype) [*c]u8 {
    return @call(.auto, vstrf, .{ pl, s } ++ args);
}

pub fn intern(s: [*c]const u8) u32 {
    const h = hash(s) & IMask;
    const b = &itbl[h];
    const n = b.nstr;

    var i: uint = 0;
    while (i < n) : (i += 1)
        if (c.strcmp(s, b.str[i]) == 0)
            return h + (i << IBits);

    if (n == 1 << (32 - IBits))
        die("interning table overflow", .{});
    if (n == 0)
        b.str = vnewT([*c]u8, 1, PHeap)
    else if ((n & (n -% 1)) == 0)
        vgrow(&b.str, n + n);

    b.str[n] = @ptrCast(emalloc(c.strlen(s) + 1));
    b.nstr = n + 1;
    _ = c.strcpy(b.str[n], s);
    return h + (n << IBits);
}

pub fn str(id: u32) [*c]u8 {
    assert(id >> IBits < itbl[id & IMask].nstr);
    return itbl[id & IMask].str[id >> IBits];
}

pub fn isreg(r: Ref) bool {
    return rtype(r) == RTmp and r.val < Tmp0;
}

pub fn iscmp(op: anytype, pk: *i32, pc: *i32) bool {
    const o: i32 = @intCast(op);
    if (Ocmpw <= o and o <= Ocmpw1) {
        pc.* = o - Ocmpw;
        pk.* = Kw;
    } else if (Ocmpl <= o and o <= Ocmpl1) {
        pc.* = o - Ocmpl;
        pk.* = Kl;
    } else if (Ocmps <= o and o <= Ocmps1) {
        pc.* = NCmpI + o - Ocmps;
        pk.* = Ks;
    } else if (Ocmpd <= o and o <= Ocmpd1) {
        pc.* = NCmpI + o - Ocmpd;
        pk.* = Kd;
    } else return false;
    return true;
}

pub fn igroup(b: [*c]Blk, i_: [*c]Ins, i_0: *[*c]Ins, i_1: *[*c]Ins) void {
    var i = i_;
    const ib = b.*.ins;
    const ie = ib + b.*.nins;
    sw: switch (i.*.op) {
        Oblit0 => {
            i_0.* = i;
            i_1.* = i + 2;
            return;
        },
        Oblit1 => {
            i_0.* = i - 1;
            i_1.* = i + 1;
            return;
        },
        Opar => { // case_Opar
            while (i > ib and ispar((i - 1).*.op)) i -= 1;
            i_0.* = i;
            while (i < ie and ispar(i.*.op)) i += 1;
            i_1.* = i;
            return;
        },
        Ocall, Oarg => { // case_Oarg
            while (i > ib and isarg((i - 1).*.op)) i -= 1;
            i_0.* = i;
            while (i < ie and i.*.op != Ocall) i += 1;
            assert(i < ie);
            i_1.* = i + 1;
            return;
        },
        Osel1 => {
            while (i > ib and (i - 1).*.op == Osel1) i -= 1;
            assert(i.*.op == Osel0);
            continue :sw Osel0;
        },
        Osel0 => {
            i_0.* = i;
            i += 1;
            while (i < ie and i.*.op == Osel1) i += 1;
            i_1.* = i;
            return;
        },
        else => {
            if (ispar(i.*.op))
                continue :sw Opar;
            if (isarg(i.*.op))
                continue :sw Oarg;
            i_0.* = i;
            i_1.* = i + 1;
            return;
        },
    }
}

pub fn argcls(i: [*c]Ins, n: anytype) i32 {
    return all.optab[i.*.op].argcls[@intCast(n)][i.*.cls];
}

pub fn emit(op: anytype, k: anytype, to: Ref, arg0: Ref, arg1: Ref) void {
    if (all.curi == @as([*c]Ins, &all.insb))
        die("emit, too many instructions", .{});
    all.curi -= 1;
    all.curi.* = Ins{
        .op = @intCast(op),
        .cls = @intCast(k),
        .to = to,
        .arg = .{ arg0, arg1 },
    };
}

pub fn emiti(i: Ins) void {
    emit(i.op, i.cls, i.to, i.arg[0], i.arg[1]);
}

pub fn idup(b: [*c]Blk, s: [*c]Ins, n: ulong) void {
    vgrow(&b.*.ins, n);
    _ = icpy(b.*.ins, s, n);
    b.*.nins = @intCast(n);
}

pub fn icpy(d: [*c]Ins, s: [*c]Ins, n: ulong) [*c]Ins {
    if (n != 0)
        _ = c.memmove(@ptrCast(d), @ptrCast(s), n * @sizeOf(Ins));
    return d + n;
}

const cmptab: [NCmp][2]i32 = blk: {
    var t: [NCmp][2]i32 = undefined;
    // negation swap
    t[Ciule] = .{ Ciugt, Ciuge };
    t[Ciult] = .{ Ciuge, Ciugt };
    t[Ciugt] = .{ Ciule, Ciult };
    t[Ciuge] = .{ Ciult, Ciule };
    t[Cisle] = .{ Cisgt, Cisge };
    t[Cislt] = .{ Cisge, Cisgt };
    t[Cisgt] = .{ Cisle, Cislt };
    t[Cisge] = .{ Cislt, Cisle };
    t[Cieq] = .{ Cine, Cieq };
    t[Cine] = .{ Cieq, Cine };
    t[NCmpI + Cfle] = .{ -1, NCmpI + Cfge };
    t[NCmpI + Cflt] = .{ -1, NCmpI + Cfgt };
    t[NCmpI + Cfgt] = .{ -1, NCmpI + Cflt };
    t[NCmpI + Cfge] = .{ -1, NCmpI + Cfle };
    t[NCmpI + Cfeq] = .{ -1, NCmpI + Cfeq };
    t[NCmpI + Cfne] = .{ -1, NCmpI + Cfne };
    t[NCmpI + Cfo] = .{ -1, NCmpI + Cfo };
    t[NCmpI + Cfuo] = .{ -1, NCmpI + Cfuo };
    break :blk t;
};

pub fn cmpop(cc: anytype) i32 {
    assert(0 <= cc and cc < NCmp);
    return cmptab[@intCast(cc)][1];
}

pub fn cmpwlneg(op: anytype) i32 {
    const o: i32 = @intCast(op);
    if (INRANGE(o, Ocmpw, Ocmpw1))
        return cmptab[@intCast(o - Ocmpw)][0] + Ocmpw;
    if (INRANGE(o, Ocmpl, Ocmpl1))
        return cmptab[@intCast(o - Ocmpl)][0] + Ocmpl;
    die("not a wl comparison", .{});
}

pub fn clsmerge(pk: *i16, k: i16) bool {
    const k1 = pk.*;
    if (k1 == Kx) {
        pk.* = k;
        return false;
    }
    if ((k1 == Kw and k == Kl) or (k1 == Kl and k == Kw)) {
        pk.* = Kw;
        return false;
    }
    return k1 != k;
}

pub fn phicls(t: i32, tmp: [*c]Tmp) i32 {
    var t1 = tmp[@intCast(t)].phi;
    if (t1 == 0)
        return t;
    t1 = phicls(t1, tmp);
    tmp[@intCast(t)].phi = t1;
    return t1;
}

pub fn phiargn(p: [*c]Phi, b: [*c]Blk) uint {
    if (p != null) {
        var n: uint = 0;
        while (n < p.*.narg) : (n += 1)
            if (p.*.blk[n] == b)
                return n;
    }
    return std.math.maxInt(uint);
}

pub fn phiarg(p: [*c]Phi, b: [*c]Blk) Ref {
    const n = phiargn(p, b);
    assert(n != std.math.maxInt(uint)); // block not found
    return p.*.arg[n];
}

var newtmp_n: i32 = 0;
pub fn newtmp(prfx: [*c]const u8, k: anytype, f: [*c]Fn) Ref {
    const t: usize = @intCast(f.*.ntmp);
    f.*.ntmp += 1;
    vgrow(&f.*.tmp, f.*.ntmp);
    f.*.tmp[t] = std.mem.zeroes(Tmp);
    if (prfx != null) {
        newtmp_n += 1;
        f.*.tmp[t].name = strf(PFn, "%s.%d", .{ prfx, @as(c_int, newtmp_n) });
    }
    f.*.tmp[t].cls = @intCast(k);
    f.*.tmp[t].slot = -1;
    f.*.tmp[t].nuse = 1;
    f.*.tmp[t].ndef = 1;
    return TMP(t);
}

pub fn chuse(r: Ref, du: i32, f: [*c]Fn) void {
    if (rtype(r) == RTmp)
        f.*.tmp[r.val].nuse = @bitCast(@as(i32, @bitCast(f.*.tmp[r.val].nuse)) +% du);
}

pub fn symeq(s0: Sym, s1: Sym) bool {
    return s0.type == s1.type and s0.id == s1.id;
}

pub fn newcon(c0: [*c]Con, f: [*c]Fn) Ref {
    var i: i32 = 1;
    while (i < f.*.ncon) : (i += 1) {
        const c1 = &f.*.con[@intCast(i)];
        if (c0.*.type == c1.*.type and symeq(c0.*.sym, c1.*.sym) and c0.*.bits.i == c1.*.bits.i)
            return CON(i);
    }
    f.*.ncon += 1;
    vgrow(&f.*.con, f.*.ncon);
    f.*.con[@intCast(i)] = c0.*;
    return CON(i);
}

pub fn getcon(val: i64, f: [*c]Fn) Ref {
    var cc: i32 = 1;
    while (cc < f.*.ncon) : (cc += 1)
        if (f.*.con[@intCast(cc)].type == CBits and f.*.con[@intCast(cc)].bits.i == val)
            return CON(cc);
    f.*.ncon += 1;
    vgrow(&f.*.con, f.*.ncon);
    f.*.con[@intCast(cc)] = std.mem.zeroes(Con);
    f.*.con[@intCast(cc)].type = CBits;
    f.*.con[@intCast(cc)].bits.i = val;
    return CON(cc);
}

pub fn addcon(c0: [*c]Con, c1: [*c]Con, m: i32) bool {
    if (m != 1 and c1.*.type == CAddr)
        return false;
    if (c0.*.type == CUndef) {
        c0.* = c1.*;
        c0.*.bits.i *%= m;
    } else {
        if (c1.*.type == CAddr) {
            if (c0.*.type == CAddr)
                return false;
            c0.*.type = CAddr;
            c0.*.sym = c1.*.sym;
        }
        c0.*.bits.i +%= c1.*.bits.i *% m;
    }
    return true;
}

pub fn isconbits(f: [*c]Fn, r: Ref, v: *i64) bool {
    if (rtype(r) == RCon) {
        const cn = &f.*.con[r.val];
        if (cn.*.type == CBits) {
            v.* = cn.*.bits.i;
            return true;
        }
    }
    return false;
}

pub fn salloc(rt: Ref, rs: Ref, f: [*c]Fn) void {
    // we need to make sure
    // the stack remains aligned
    // (rsp = 0) mod 16
    f.*.dynalloc = 1;
    if (rtype(rs) == RCon) {
        var sz = f.*.con[rs.val].bits.i;
        if (sz < 0 or sz >= std.math.maxInt(c_int) - 15)
            err("invalid alloc size %ld", .{@as(c_long, sz)});
        sz = (sz + 15) & -16;
        emit(Osalloc, Kl, rt, getcon(sz, f), R);
    } else {
        // r0 = (r + 15) & -16
        const r0 = newtmp("isel", Kl, f);
        const r1 = newtmp("isel", Kl, f);
        emit(Osalloc, Kl, rt, r0, R);
        emit(Oand, Kl, r0, r1, getcon(-16, f));
        emit(Oadd, Kl, r1, rs, getcon(15, f));
        if (f.*.tmp[rs.val].slot != -1)
            err("unlikely alloc argument %%%s for %%%s", .{ f.*.tmp[rs.val].name, f.*.tmp[rt.val].name });
    }
}

pub fn bsinit(bs: [*c]BSet, n_: uint) void {
    const n = (n_ + NBit - 1) / NBit;
    bs.*.nt = n;
    bs.*.t = @ptrCast(@alignCast(alloc(n * @sizeOf(bits))));
}

comptime {
    assert(NBit == 64);
}
inline fn popcnt(b_: bits) uint {
    var b = b_;
    b = (b & 0x5555555555555555) + ((b >> 1) & 0x5555555555555555);
    b = (b & 0x3333333333333333) + ((b >> 2) & 0x3333333333333333);
    b = (b & 0x0f0f0f0f0f0f0f0f) + ((b >> 4) & 0x0f0f0f0f0f0f0f0f);
    b +%= (b >> 8);
    b +%= (b >> 16);
    b +%= (b >> 32);
    return @intCast(b & 0xff);
}

inline fn firstbit(b_: bits) i32 {
    var b = b_;
    var n: i32 = 0;
    if ((b & 0xffffffff) == 0) {
        n += 32;
        b >>= 32;
    }
    if ((b & 0xffff) == 0) {
        n += 16;
        b >>= 16;
    }
    if ((b & 0xff) == 0) {
        n += 8;
        b >>= 8;
    }
    if ((b & 0xf) == 0) {
        n += 4;
        b >>= 4;
    }
    n += ([16]i32{ 4, 0, 1, 0, 2, 0, 1, 0, 3, 0, 1, 0, 2, 0, 1, 0 })[@intCast(b & 0xf)];
    return n;
}

pub fn bscount(bs: [*c]BSet) uint {
    var n: uint = 0;
    var i: uint = 0;
    while (i < bs.*.nt) : (i += 1)
        n += popcnt(bs.*.t[i]);
    return n;
}

inline fn bsmax(bs: [*c]BSet) uint {
    return bs.*.nt * NBit;
}

pub fn bsset(bs: [*c]BSet, elt: anytype) void {
    assert(elt < bsmax(bs));
    const e: uint = @intCast(elt);
    bs.*.t[e / NBit] |= BIT(e % NBit);
}

pub fn bsclr(bs: [*c]BSet, elt: anytype) void {
    assert(elt < bsmax(bs));
    const e: uint = @intCast(elt);
    bs.*.t[e / NBit] &= ~BIT(e % NBit);
}

pub fn bscopy(a: [*c]BSet, b: [*c]BSet) void {
    assert(a.*.nt == b.*.nt);
    var i: uint = 0;
    while (i < a.*.nt) : (i += 1) a.*.t[i] = b.*.t[i];
}
pub fn bsunion(a: [*c]BSet, b: [*c]BSet) void {
    assert(a.*.nt == b.*.nt);
    var i: uint = 0;
    while (i < a.*.nt) : (i += 1) a.*.t[i] |= b.*.t[i];
}
pub fn bsinter(a: [*c]BSet, b: [*c]BSet) void {
    assert(a.*.nt == b.*.nt);
    var i: uint = 0;
    while (i < a.*.nt) : (i += 1) a.*.t[i] &= b.*.t[i];
}
pub fn bsdiff(a: [*c]BSet, b: [*c]BSet) void {
    assert(a.*.nt == b.*.nt);
    var i: uint = 0;
    while (i < a.*.nt) : (i += 1) a.*.t[i] &= ~b.*.t[i];
}

pub fn bsequal(a: [*c]BSet, b: [*c]BSet) bool {
    assert(a.*.nt == b.*.nt);
    var i: uint = 0;
    while (i < a.*.nt) : (i += 1)
        if (a.*.t[i] != b.*.t[i])
            return false;
    return true;
}

pub fn bszero(bs: [*c]BSet) void {
    _ = c.memset(@ptrCast(bs.*.t), 0, bs.*.nt * @sizeOf(bits));
}

/// iterates on a bitset, use as follows
///
///     for (i=0; bsiter(set, &i); i++)
///         use(i);
///
pub fn bsiter(bs: [*c]BSet, elt: *i32) bool {
    const i: uint = @intCast(elt.*);
    var t: uint = i / NBit;
    if (t >= bs.*.nt)
        return false;
    var b = bs.*.t[t];
    b &= ~(BIT(i % NBit) -% 1);
    while (b == 0) {
        t += 1;
        if (t >= bs.*.nt)
            return false;
        b = bs.*.t[t];
    }
    elt.* = @as(i32, @intCast(NBit * t)) + firstbit(b);
    return true;
}

pub fn dumpts(bs: [*c]BSet, tmp: [*c]Tmp, f: *FILE) void {
    _ = c.fprintf(f, "[");
    var t: i32 = Tmp0;
    while (bsiter(bs, &t)) : (t += 1)
        _ = c.fprintf(f, " %s", tmp[@intCast(t)].name);
    _ = c.fprintf(f, " ]\n");
}

pub fn runmatch(code: [*c]const uchar, tn: [*c]Num, ref_: Ref, @"var": [*c]Ref) void {
    var ref = ref_;
    var stkbuf: [20]Ref = undefined;
    var stk: [*c]Ref = &stkbuf;
    var s: [*c]const uchar = undefined;
    var pc: [*c]const uchar = code;
    var bc: i32 = undefined;

    assert(rtype(ref) == RTmp);
    while (true) {
        bc = pc.*;
        if (bc == 0) break;
        sw: switch (bc) {
            1, 2 => { // pushsym, push
                assert(stk < @as([*c]Ref, &stkbuf) + 20);
                assert(rtype(ref) == RTmp);
                const nl = tn[ref.val].nl;
                const nr = tn[ref.val].nr;
                if (bc == 1 and nl > nr) {
                    stk.* = tn[ref.val].l;
                    stk += 1;
                    ref = tn[ref.val].r;
                } else {
                    stk.* = tn[ref.val].r;
                    stk += 1;
                    ref = tn[ref.val].l;
                }
                pc += 1;
            },
            3 => { // set
                pc += 1;
                @"var"[pc.*] = ref;
                if ((pc + 1).* == 0)
                    return;
                continue :sw 4;
            },
            4 => { // pop
                assert(stk > @as([*c]Ref, &stkbuf));
                stk -= 1;
                ref = stk.*;
                pc += 1;
            },
            5 => { // switch
                assert(rtype(ref) == RTmp);
                const n = tn[ref.val].n;
                s = pc + 1;
                var i: i32 = s.*;
                s += 1;
                while (i > 0) : ({
                    i -= 1;
                    s += 1;
                }) {
                    const v = s.*;
                    s += 1;
                    if (n == v)
                        break;
                }
                pc += s.*;
            },
            else => { // jump
                assert(bc >= 10);
                pc = code + @as(usize, @intCast(bc - 10));
            },
        }
    }
}
