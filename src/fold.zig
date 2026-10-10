//! One-to-one translation of fold.c
const std = @import("std");
const assert = std.debug.assert;
// -- imports --
const all = @import("all.zig");
const Opc = all.Opc;
const CAddr = all.CAddr;
const CBits = all.CBits;
const CON_Z = all.CON_Z;
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
const Ins = all.Ins;
const KWIDE = all.KWIDE;
const Kd = all.Kd;
const Kl = all.Kl;
const Ks = all.Ks;
const Kw = all.Kw;
const R = all.R;
const RCon = all.RCon;
const RTmp = all.RTmp;
const Ref = all.Ref;
const Sym = all.Sym;
const cs = all.cs;
const die = all.die;
const err = all.err;
const newcon = all.newcon;
const req = all.req;
const rtype = all.rtype;
const symeq = all.symeq;
// -- end imports --

// boring folding code

fn iscon(c: *Con, w: bool, k: u64) bool {
    if (c.type != CBits)
        return false;
    if (w)
        return @as(u64, @bitCast(c.bits.i)) == k
    else
        return @as(u32, @truncate(@as(u64, @bitCast(c.bits.i)))) == @as(u32, @truncate(k));
}

/// C float -> integer conversion; out-of-range values yield what
/// amd64 cvtt* instructions produce instead of trapping
fn f2i(comptime T: type, x: anytype) T {
    const F = @TypeOf(x);
    const hi: F = @floatFromInt(@as(i128, std.math.maxInt(T)) + 1);
    const lo: F = @floatFromInt(@as(i128, std.math.minInt(T)));
    if (std.math.isNan(x) or x >= hi or x < lo) {
        if (@typeInfo(T).int.signedness == .signed)
            return std.math.minInt(T);
        if (T == u32) return @truncate(@as(u64, @bitCast(f2i(i64, x))));
        if (x >= 0x1p63 and x < 0x1p64) return @intFromFloat(x);
        return @bitCast(f2i(i64, x));
    }
    return @intFromFloat(x);
}

const U = extern union {
    s: i64,
    u: u64,
    fs: f32,
    fd: f64,
};

inline fn sx32(x: u64) u64 {
    return @bitCast(@as(i64, @as(i32, @bitCast(@as(u32, @truncate(x))))));
}

pub fn foldint(res: *Con, op_: i32, w_: bool, cl: *Con, cr: *Con) bool {
    var op = op_;
    const w = w_;
    var l: U = undefined;
    var r: U = undefined;
    var x: u64 = undefined;
    var sym: Sym = std.mem.zeroes(Sym);
    var typ: i32 = CBits;

    l.s = cl.bits.i;
    r.s = cr.bits.i;
    if (op == Opc.add.int()) {
        if (cl.type == CAddr) {
            if (cr.type == CAddr)
                return true;
            typ = CAddr;
            sym = cl.sym;
        } else if (cr.type == CAddr) {
            typ = CAddr;
            sym = cr.sym;
        }
    } else if (op == Opc.sub.int()) {
        if (cl.type == CAddr) {
            if (cr.type != CAddr) {
                typ = CAddr;
                sym = cl.sym;
            } else if (!symeq(cl.sym, cr.sym))
                return true;
        } else if (cr.type == CAddr)
            return true;
    } else if (cl.type == CAddr or cr.type == CAddr)
        return true;
    if (op == Opc.div.int() or op == Opc.rem.int() or op == Opc.udiv.int() or op == Opc.urem.int()) {
        if (iscon(cr, w, 0))
            return true;
        if (op == Opc.div.int() or op == Opc.rem.int()) {
            x = if (w) @bitCast(@as(i64, std.math.minInt(i64))) else @bitCast(@as(i64, std.math.minInt(i32)));
            if (iscon(cr, w, @bitCast(@as(i64, -1))))
                if (iscon(cl, w, x))
                    return true;
        }
    }
    const sh: u6 = @intCast(r.u & (31 | (@as(u64, @intFromBool(w)) << 5)));
    switch (op) {
        all.ops.num(.add) => x = l.u +% r.u,
        all.ops.num(.sub) => x = l.u -% r.u,
        all.ops.num(.neg) => x = 0 -% l.u,
        all.ops.num(.div) => x = if (w) @bitCast(@divTrunc(l.s, r.s)) else sx32(@bitCast(@as(i64, @divTrunc(@as(i32, @truncate(l.s)), @as(i32, @truncate(r.s)))))),
        all.ops.num(.rem) => x = if (w) @bitCast(@rem(l.s, r.s)) else sx32(@bitCast(@as(i64, @rem(@as(i32, @truncate(l.s)), @as(i32, @truncate(r.s)))))),
        all.ops.num(.udiv) => x = if (w) l.u / r.u else @as(u32, @truncate(l.u)) / @as(u32, @truncate(r.u)),
        all.ops.num(.urem) => x = if (w) l.u % r.u else @as(u32, @truncate(l.u)) % @as(u32, @truncate(r.u)),
        all.ops.num(.mul) => x = l.u *% r.u,
        all.ops.num(.@"and") => x = l.u & r.u,
        all.ops.num(.@"or") => x = l.u | r.u,
        all.ops.num(.xor) => x = l.u ^ r.u,
        all.ops.num(.sar) => x = @bitCast((if (w) l.s else @as(i64, @as(i32, @truncate(l.s)))) >> sh),
        all.ops.num(.shr) => x = (if (w) l.u else @as(u64, @as(u32, @truncate(l.u)))) >> sh,
        all.ops.num(.shl) => x = l.u << sh,
        all.ops.num(.extsb) => x = @bitCast(@as(i64, @as(i8, @bitCast(@as(u8, @truncate(l.u)))))),
        all.ops.num(.extub) => x = @as(u8, @truncate(l.u)),
        all.ops.num(.extsh) => x = @bitCast(@as(i64, @as(i16, @bitCast(@as(u16, @truncate(l.u)))))),
        all.ops.num(.extuh) => x = @as(u16, @truncate(l.u)),
        all.ops.num(.extsw) => x = sx32(l.u),
        all.ops.num(.extuw) => x = @as(u32, @truncate(l.u)),
        all.ops.num(.stosi) => x = if (w) @bitCast(f2i(i64, cl.bits.s)) else @bitCast(@as(i64, f2i(i32, cl.bits.s))),
        all.ops.num(.stoui) => x = if (w) f2i(u64, cl.bits.s) else f2i(u32, cl.bits.s),
        all.ops.num(.dtosi) => x = if (w) @bitCast(f2i(i64, cl.bits.d)) else @bitCast(@as(i64, f2i(i32, cl.bits.d))),
        all.ops.num(.dtoui) => x = if (w) f2i(u64, cl.bits.d) else f2i(u32, cl.bits.d),
        all.ops.num(.cast) => {
            x = l.u;
            if (cl.type == CAddr) {
                typ = CAddr;
                sym = cl.sym;
            }
        },
        else => {
            if (all.ops.num(Opc.cmpw_first) <= op and op <= all.ops.num(Opc.cmpl_last)) {
                if (op <= all.ops.num(Opc.cmpw_last)) {
                    l.u = sx32(l.u);
                    r.u = sx32(r.u);
                } else op -= Opc.cmpl_first.diff(Opc.cmpw_first);
                x = @intFromBool(switch (op - all.ops.num(Opc.cmpw_first)) {
                    Ciule => l.u <= r.u,
                    Ciult => l.u < r.u,
                    Cisle => l.s <= r.s,
                    Cislt => l.s < r.s,
                    Cisgt => l.s > r.s,
                    Cisge => l.s >= r.s,
                    Ciugt => l.u > r.u,
                    Ciuge => l.u >= r.u,
                    Cieq => l.u == r.u,
                    Cine => l.u != r.u,
                    else => die("unreachable", .{}),
                });
            } else if (all.ops.num(Opc.cmps_first) <= op and op <= all.ops.num(Opc.cmps_last)) {
                x = @intFromBool(switch (op - all.ops.num(Opc.cmps_first)) {
                    Cfle => l.fs <= r.fs,
                    Cflt => l.fs < r.fs,
                    Cfgt => l.fs > r.fs,
                    Cfge => l.fs >= r.fs,
                    Cfne => l.fs != r.fs,
                    Cfeq => l.fs == r.fs,
                    Cfo => l.fs < r.fs or l.fs >= r.fs,
                    Cfuo => !(l.fs < r.fs or l.fs >= r.fs),
                    else => die("unreachable", .{}),
                });
            } else if (all.ops.num(Opc.cmpd_first) <= op and op <= all.ops.num(Opc.cmpd_last)) {
                x = @intFromBool(switch (op - all.ops.num(Opc.cmpd_first)) {
                    Cfle => l.fd <= r.fd,
                    Cflt => l.fd < r.fd,
                    Cfgt => l.fd > r.fd,
                    Cfge => l.fd >= r.fd,
                    Cfne => l.fd != r.fd,
                    Cfeq => l.fd == r.fd,
                    Cfo => l.fd < r.fd or l.fd >= r.fd,
                    Cfuo => !(l.fd < r.fd or l.fd >= r.fd),
                    else => die("unreachable", .{}),
                });
            } else die("unreachable", .{});
        },
    }
    res.* = std.mem.zeroes(Con);
    res.type = typ;
    res.sym = sym;
    res.bits.i = @bitCast(x);
    return false;
}

fn foldflt(res: *Con, op: i32, w: bool, cl: *Con, cr: *Con) void {
    if (cl.type != CBits or cr.type != CBits)
        err("invalid address operand for '{s}'", .{cs(all.optab[@intCast(op)].name)});
    res.* = std.mem.zeroes(Con);
    res.type = CBits;
    if (w) {
        const ld = cl.bits.d;
        const rd = cr.bits.d;
        const xd: f64 = switch (op) {
            all.ops.num(.add) => ld + rd,
            all.ops.num(.sub) => ld - rd,
            all.ops.num(.neg) => -ld,
            all.ops.num(.div) => ld / rd,
            all.ops.num(.mul) => ld * rd,
            all.ops.num(.swtof) => @floatFromInt(@as(i32, @truncate(cl.bits.i))),
            all.ops.num(.uwtof) => @floatFromInt(@as(u32, @truncate(@as(u64, @bitCast(cl.bits.i))))),
            all.ops.num(.sltof) => @floatFromInt(cl.bits.i),
            all.ops.num(.ultof) => @floatFromInt(@as(u64, @bitCast(cl.bits.i))),
            all.ops.num(.exts) => cl.bits.s,
            all.ops.num(.cast) => ld,
            else => die("unreachable", .{}),
        };
        res.bits.d = xd;
        res.flt = 2;
    } else {
        const ls = cl.bits.s;
        const rs = cr.bits.s;
        const xs: f32 = switch (op) {
            all.ops.num(.add) => ls + rs,
            all.ops.num(.sub) => ls - rs,
            all.ops.num(.neg) => -ls,
            all.ops.num(.div) => ls / rs,
            all.ops.num(.mul) => ls * rs,
            all.ops.num(.swtof) => @floatFromInt(@as(i32, @truncate(cl.bits.i))),
            all.ops.num(.uwtof) => @floatFromInt(@as(u32, @truncate(@as(u64, @bitCast(cl.bits.i))))),
            all.ops.num(.sltof) => @floatFromInt(cl.bits.i),
            all.ops.num(.ultof) => @floatFromInt(@as(u64, @bitCast(cl.bits.i))),
            all.ops.num(.truncd) => @floatCast(cl.bits.d),
            all.ops.num(.cast) => ls,
            else => die("unreachable", .{}),
        };
        res.bits.s = xs;
        res.flt = 1;
    }
}

fn opfold(op: i32, cls: i32, cl: *Con, cr: *Con, f: *Fn) Ref {
    var c: Con = undefined;

    if (cls == Kw.int() or cls == Kl.int()) {
        if (foldint(&c, op, cls == Kl.int(), cl, cr))
            return R;
    } else foldflt(&c, op, cls == Kd.int(), cl, cr);
    if (KWIDE(cls) == 0)
        c.bits.i &= 0xffffffff;
    const r = newcon(&c, f);
    assert(!(cls == Ks.int() or cls == Kd.int()) or c.flt != 0);
    return r;
}

/// used by GVN
pub fn foldref(f: *Fn, i: *Ins) Ref {
    if (rtype(i.to) != RTmp)
        return R;
    if (all.optab[i.op.int()].canfold != 0) {
        if (rtype(i.arg[0]) != RCon)
            return R;
        const cl = &f.con[i.arg[0].val];
        var rr = i.arg[1];
        if (req(rr, R))
            rr = CON_Z;
        if (rtype(rr) != RCon)
            return R;
        const cr = &f.con[rr.val];

        return opfold(@intCast(i.op.int()), all.knum(i.cls), cl, cr, f);
    }
    return R;
}
