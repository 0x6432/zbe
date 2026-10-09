//! One-to-one translation of simpl.c
const std = @import("std");
const assert = std.debug.assert;
// -- imports --
const all = @import("all.zig");
const Blk = all.Blk;
const CBits = all.CBits;
const Fn = all.Fn;
const Ins = all.Ins;
const KBASE = all.KBASE;
const Kl = all.Kl;
const Kw = all.Kw;
const Oadd = all.ops.Oadd;
const Oand = all.ops.Oand;
const Oblit0 = all.ops.Oblit0;
const Oblit1 = all.ops.Oblit1;
const Oload = all.ops.Oload;
const Oloadub = all.ops.Oloadub;
const Oloaduh = all.ops.Oloaduh;
const Oshr = all.ops.Oshr;
const Ostoreb = all.ops.Ostoreb;
const Ostoreh = all.ops.Ostoreh;
const Ostorel = all.ops.Ostorel;
const Ostorew = all.ops.Ostorew;
const Oudiv = all.ops.Oudiv;
const O = all.ops;
const Ourem = all.ops.Ourem;
const R = all.R;
const RCon = all.RCon;
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
    const E = struct { st: i32, ld: i32, cls: i32, size: i32 };
    const tbl = [_]E{
        .{ .st = Ostorel, .ld = Oload, .cls = Kl, .size = 8 },
        .{ .st = Ostorew, .ld = Oload, .cls = Kw, .size = 4 },
        .{ .st = Ostoreh, .ld = Oloaduh, .cls = Kw, .size = 2 },
        .{ .st = Ostoreb, .ld = Oloadub, .cls = Kw, .size = 1 },
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
            emit(Oadd, Kl, r1, sd[1], ro);
            r1 = newtmp("blt", Kl, f);
            emit(p.ld, p.cls, r, r1, R);
            emit(Oadd, Kl, r1, sd[0], ro);
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
///   x&0 -> 0   x*2^n -> x<<n   x*-1 -> neg x
fn algebra(i: *Ins, f: *Fn) void {
    if (KBASE(i.cls) != 0 or rtype(i.arg[1]) != RCon)
        return;
    const c = &f.con[i.arg[1].val];
    if (c.type != CBits)
        return;
    const wide = i.cls == Kl;
    const mask: u64 = if (wide) ~@as(u64, 0) else 0xffffffff;
    const v: u64 = @as(u64, @bitCast(c.bits.i)) & mask;
    const shift = i.op == O.Oshl or i.op == O.Oshr or i.op == O.Osar;
    // shift counts are taken modulo the width
    const sv: u64 = if (shift) v & @as(u64, if (wide) 63 else 31) else v;
    const ident = switch (i.op) {
        O.Omul, O.Odiv => sv == 1,
        O.Oand => sv == mask,
        else => sv == 0,
    };
    if (ident) {
        i.op = O.Ocopy;
        i.arg[1] = R;
        return;
    }
    if ((i.op == O.Omul or i.op == O.Oand) and sv == 0) {
        i.op = O.Ocopy;
        i.arg[0] = getcon(0, f);
        i.arg[1] = R;
        return;
    }
    if (i.op == O.Omul and sv == mask) { // x * -1 -> neg x
        i.op = O.Oneg;
        i.arg[1] = R;
        return;
    }
    if (i.op == O.Omul and ispow2(sv)) {
        i.op = O.Oshl;
        i.arg[1] = getcon(ulog2(sv), f);
    }
}

fn ins(pk: *uint, new: *bool, b: *Blk, f: *Fn) void {
    const k = pk.*;
    const i = &b.ins[k];
    // simplify more instructions here;
    // copy 0 into xor, bit rotations,
    // etc.
    switch (i.op) {
        Oblit1 => {
            assert(k > 0);
            assert(b.ins[k - 1].op == Oblit0);
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
        O.Omul, O.Odiv, O.Oadd, O.Osub, O.Oor, O.Oxor, O.Oand, O.Oshl, O.Oshr, O.Osar => {
            if (!all.compat) algebra(i, f);
        },
        Oudiv, Ourem => {
            const r = i.arg[1];
            if (KBASE(i.cls) == 0)
                if (rtype(r) == RCon) {
                    const c = &f.con[r.val];
                    if (c.type == CBits)
                        if (ispow2(@bitCast(c.bits.i))) {
                            const n = ulog2(@bitCast(c.bits.i));
                            if (i.op == Ourem) {
                                i.op = Oand;
                                i.arg[1] = getcon(@bitCast((@as(u64, 1) << @intCast(n)) - 1), f);
                            } else {
                                i.op = Oshr;
                                i.arg[1] = getcon(n, f);
                            }
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
