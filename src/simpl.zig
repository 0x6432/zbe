//! One-to-one translation of simpl.c
const std = @import("std");
const assert = std.debug.assert;
// -- imports --
const all = @import("all.zig");
const Opc = all.Opc;
const Blk = all.Blk;
const CBits = all.CBits;
const Fn = all.Fn;
const Ins = all.Ins;
const KBASE = all.KBASE;
const Kl = all.Kl;
const Kw = all.Kw;
const O = all.ops;
const R = all.R;
const RCon = all.RCon;
const RTmp = all.RTmp;
const Ref = all.Ref;
const emit = all.emit;
const emiti = all.emiti;
const getcon = all.getcon;
const icpy = all.icpy;
const idup = all.idup;
const newtmp = all.newtmp;
const rsval = all.rsval;
const rtype = all.rtype;
const ulong = all.ulong;
const uint = all.uint;
// -- end imports --

fn blit(sd: *[2]Ref, sz_: i32, f: *Fn) void {
    const E = struct { st: all.Opc, ld: all.Opc, cls: all.Cls, size: i32 };
    const tbl = [_]E{
        .{ .st = .storel, .ld = .load, .cls = Kl, .size = 8 },
        .{ .st = .storew, .ld = .load, .cls = Kw, .size = 4 },
        .{ .st = .storeh, .ld = .loaduh, .cls = Kw, .size = 2 },
        .{ .st = .storeb, .ld = .loadub, .cls = Kw, .size = 1 },
    };

    const fwd = sz_ >= 0;
    var sz: i32 = if (sz_ < 0) -sz_ else sz_;
    var off: i32 = if (fwd) sz else 0;
    var pi: usize = 0;
    while (sz != 0) : (pi += 1) {
        const p = &tbl[pi];
        const n = p.size;
        while (sz >= n) : (sz -= n) {
            off -= if (fwd) n else 0;
            const r = newtmp("blt", Kl, f);
            var r1 = newtmp("blt", Kl, f);
            const ro = getcon(off, f);
            emit(p.st, 0, R, r, r1);
            emit(.add, Kl, r1, sd[1], ro);
            r1 = newtmp("blt", Kl, f);
            emit(p.ld, p.cls, r, r1, R);
            emit(.add, Kl, r1, sd[0], ro);
            off += if (fwd) 0 else n;
        }
    }
}

const ulog2_tab64 = [64]i32{
    63, 0,  1,  41, 37, 2,  16, 42,
    38, 29, 32, 3,  12, 17, 43, 55,
    39, 35, 30, 53, 33, 21, 4,  23,
    13, 9,  18, 6,  25, 44, 48, 56,
    62, 40, 36, 15, 28, 31, 11, 54,
    34, 52, 20, 22, 8,  5,  24, 47,
    61, 14, 27, 10, 51, 19, 7,  46,
    60, 26, 50, 45, 59, 49, 58, 57,
};

fn ulog2(pow2: u64) i32 {
    return ulog2_tab64[((pow2 *% 0x5b31ab928877a7e) >> 58)];
}

fn ispow2(v: u64) bool {
    return v != 0 and (v & (v - 1)) == 0;
}

/// Integer identities with a constant right operand (stage 8a):
///   x*0 -> 0   x*1, x/1, x+0, x-0, x|0, x^0, x<<0, x>>0, x&-1 -> x
///   x&0 -> 0   x*2^n -> x<<n   x*-1 -> neg x   x-x, x^x -> 0   x&x, x|x -> x
/// True unless r is a machine register: the abi passes emit arithmetic on
/// physical registers (e.g. arm64 `%abi =l add R32, 0` for sp) that must not
/// be turned into register copies, so the rewrites only touch virtual temps.
fn virt(r: Ref) bool {
    return rtype(r) != RTmp or r.val >= all.Tmp0;
}

fn allvirt(i: *Ins) bool {
    return virt(i.to) and virt(i.arg[0]) and virt(i.arg[1]);
}

fn algebra(i: *Ins, f: *Fn) void {
    if (KBASE(i.cls) != 0 or !allvirt(i))
        return;
    if (all.req(i.arg[0], i.arg[1]) and rtype(i.arg[0]) == RTmp) {
        switch (i.op) {
            // x-x, x^x -> 0
            .sub, .xor => {
                i.op = .copy;
                i.arg[0] = getcon(0, f);
                i.arg[1] = R;
            },
            // x&x, x|x -> x
            Opc.@"and", Opc.@"or" => {
                i.op = .copy;
                i.arg[1] = R;
            },
            else => {},
        }
        return;
    }
    if (rtype(i.arg[1]) != RCon)
        return;
    const c = &f.con[i.arg[1].val];
    if (c.type != CBits)
        return;
    const wide = i.cls == Kl;
    const mask: u64 = if (wide) ~@as(u64, 0) else 0xffffffff;
    const v: u64 = @as(u64, @bitCast(c.bits.i)) & mask;
    const shift = i.op == .shl or i.op == .shr or i.op == .sar;
    // shift counts are taken modulo the width
    const sv: u64 = if (shift) v & @as(u64, if (wide) 63 else 31) else v;
    const ident = switch (i.op) {
        .mul, .div => sv == 1,
        Opc.@"and" => sv == mask,
        else => sv == 0,
    };
    if (ident) {
        i.op = .copy;
        i.arg[1] = R;
        return;
    }
    if ((i.op == .mul or i.op == Opc.@"and") and sv == 0) {
        i.op = .copy;
        i.arg[0] = getcon(0, f);
        i.arg[1] = R;
        return;
    }
    if (i.op == .mul and sv == mask) { // x * -1 -> neg x
        i.op = .neg;
        i.arg[1] = R;
        return;
    }
    if (i.op == .mul and ispow2(sv)) {
        i.op = .shl;
        i.arg[1] = getcon(ulog2(sv), f);
    }
}

/// Switch block b to the rewritten form (instructions after k are already
/// in the emit buffer), so that a replacement sequence can be emitted.
fn startnew(new: *bool, b: *Blk, k: uint) void {
    if (!new.*) {
        all.curi = all.insbEnd();
        const ni: ulong = b.nins - (k + 1);
        all.curi -= ni;
        _ = icpy(all.curi, b.ins + k + 1, ni);
        new.* = true;
    }
}

/// Signed x / 2^n and x % 2^n (1 <= n <= width-2) without idiv:
///   t1 = x sar (W-1); t2 = t1 shr (W-n); t3 = x + t2
///   div: t3 sar n            rem: x - (t3 & -2^n)
fn sdivpow2(i: *Ins, b: *Blk, k: uint, new: *bool, f: *Fn) bool {
    if (KBASE(i.cls) != 0 or rtype(i.arg[0]) != RTmp or rtype(i.arg[1]) != RCon or !allvirt(i))
        return false;
    const c = &f.con[i.arg[1].val];
    if (c.type != CBits)
        return false;
    const wide = i.cls == Kl;
    const sv: i64 = if (wide) c.bits.i else @as(i32, @truncate(c.bits.i));
    if (sv < 2 or !ispow2(@bitCast(sv)))
        return false;
    const w: i64 = if (wide) 64 else 32;
    const n: i64 = ulog2(@bitCast(sv));
    const cls: i32 = all.knum(i.cls);
    const x = i.arg[0];
    const to = i.to;
    const isdiv = i.op == .div;
    startnew(new, b, k);
    const t1 = newtmp("sdv", cls, f);
    const t2 = newtmp("sdv", cls, f);
    const t3 = newtmp("sdv", cls, f);
    if (isdiv) {
        emit(.sar, cls, to, t3, getcon(n, f));
    } else {
        const t4 = newtmp("sdv", cls, f);
        emit(.sub, cls, to, x, t4);
        emit(Opc.@"and", cls, t4, t3, getcon(-sv, f));
    }
    emit(.add, cls, t3, x, t2);
    emit(.shr, cls, t2, t1, getcon(w - n, f));
    emit(.sar, cls, t1, x, getcon(w - 1, f));
    return true;
}

/// Magic number for unsigned 32-bit division by d (not a power of two):
/// the smallest s in 32..63 with m = ceil(2^s/d) < 2^32 and
/// m*d - 2^s <= 2^(s-32); then x/d == (x*m) >> s for every x < 2^32
/// (the error x*(m*d-2^s)/(d*2^s) stays below 1/d), and x*m < 2^64.
/// Divisors needing a 33-bit magic (e.g. 7) are handled by udivmagic33.
pub fn udivmagic(d: u32, m: *u64, s: *u32) bool {
    return udivmagicw(d, 32, m, s);
}

/// Like udivmagic but allows m < 2^33 (the "add" case, e.g. d = 7).
/// With m = 2^32 + m', x*m >> s == ((x*m' >> 32) + x) >> (s - 32), and
/// (x*m' >> 32) + x < 2^33, so everything fits in 64-bit registers.
pub fn udivmagic33(d: u32, m: *u64, s: *u32) bool {
    return udivmagicw(d, 33, m, s);
}

fn udivmagicw(d: u32, mbits: u32, m: *u64, s: *u32) bool {
    if (d < 3 or ispow2(d))
        return false;
    var sh: u32 = 32;
    while (sh < 64) : (sh += 1) {
        const p: u128 = @as(u128, 1) << @intCast(sh);
        const mm: u128 = (p + d - 1) / d;
        if (mm >= (@as(u128, 1) << @intCast(mbits)))
            continue;
        if (mm * d - p <= (@as(u128, 1) << @intCast(sh - 32))) {
            m.* = @intCast(mm);
            s.* = sh;
            return true;
        }
    }
    return false;
}

/// Unsigned 32-bit x / d and x % d by a constant: one 64-bit multiply.
fn udivconst(i: *Ins, b: *Blk, k: uint, new: *bool, f: *Fn) bool {
    if (i.cls != Kw or rtype(i.arg[0]) != RTmp or !allvirt(i))
        return false;
    const d: u32 = @truncate(@as(u64, @bitCast(f.con[i.arg[1].val].bits.i)));
    var m: u64 = 0;
    var s: u32 = 0;
    const wide = !udivmagic(d, &m, &s);
    if (wide and !udivmagic33(d, &m, &s))
        return false;
    const x = i.arg[0];
    const to = i.to;
    const isdiv = i.op == .udiv;
    startnew(new, b, k);
    const t0 = newtmp("udv", Kl, f);
    const t1 = newtmp("udv", Kl, f);
    const t2 = newtmp("udv", Kl, f);
    if (isdiv) {
        emit(.copy, Kw, to, t2, R);
    } else {
        const q = newtmp("udv", Kw, f);
        const t3 = newtmp("udv", Kw, f);
        emit(.sub, Kw, to, x, t3);
        emit(.mul, Kw, t3, q, getcon(d, f));
        emit(.copy, Kw, q, t2, R);
    }
    if (wide) {
        // q = ((x * m' >> 32) + x) >> (s - 32), m' = m - 2^32
        const t3 = newtmp("udv", Kl, f);
        const t4 = newtmp("udv", Kl, f);
        emit(.shr, Kl, t2, t4, getcon(s - 32, f));
        emit(.add, Kl, t4, t3, t0);
        emit(.shr, Kl, t3, t1, getcon(32, f));
        emit(.mul, Kl, t1, t0, getcon(@bitCast(m - (@as(u64, 1) << 32)), f));
    } else {
        emit(.shr, Kl, t2, t1, getcon(s, f));
        emit(.mul, Kl, t1, t0, getcon(@bitCast(m), f));
    }
    emit(.extuw, Kl, t0, x, R);
    return true;
}

fn ins(pk: *uint, new: *bool, b: *Blk, f: *Fn) void {
    const k = pk.*;
    const i = &b.ins[k];
    // simplify more instructions here;
    // copy 0 into xor, bit rotations,
    // etc.
    switch (i.op) {
        .blit1 => {
            assert(k > 0);
            assert(b.ins[k - 1].op == .blit0);
            if (!new.*) {
                all.curi = all.insbEnd();
                const ni: ulong = b.nins - (k + 1);
                all.curi -= ni;
                _ = icpy(all.curi, b.ins + k + 1, ni);
                new.* = true;
            }
            blit(&b.ins[k - 1].arg, rsval(i.arg[0]), f);
            pk.* = k - 1;
            return;
        },
        .mul, .div, .rem, .add, .sub, Opc.@"or", .xor, Opc.@"and", .shl, .shr, .sar => {
            if (all.optlevel >= 1) algebra(i, f);
            if (all.optlevel >= 2 and (i.op == .div or i.op == .rem))
                if (sdivpow2(i, b, k, new, f)) {
                    return;
                };
        },
        .udiv, .urem => {
            const r = i.arg[1];
            if (KBASE(i.cls) == 0)
                if (rtype(r) == RCon) {
                    const c = &f.con[r.val];
                    if (c.type == CBits)
                        if (ispow2(@bitCast(c.bits.i))) {
                            const n = ulog2(@bitCast(c.bits.i));
                            if (i.op == .urem) {
                                i.op = .@"and";
                                i.arg[1] = getcon(@bitCast((@as(u64, 1) << @intCast(n)) - 1), f);
                            } else {
                                i.op = .shr;
                                i.arg[1] = getcon(n, f);
                            }
                        } else if (all.optlevel >= 2 and udivconst(i, b, k, new, f)) {
                            return;
                        };
                };
        },
        else => {},
    }
    if (new.*)
        emiti(i.*);
}


pub fn simpl(f: *Fn) void {
    var b_it: ?*Blk = f.start;
    while (b_it) |b| : (b_it = b.link) {
        var new = false;
        var k: uint = b.nins;
        while (k != 0) {
            k -= 1;
            ins(&k, &new, b, f);
        }
        if (new)
            idup(b, all.curi, (all.insbTail()));
    }
}
