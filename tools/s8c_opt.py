# stage 8c: -O levels, same-operand identities, signed div/rem by 2^n,
# unsigned 32-bit div/rem by constant (multiply + shift)
R='/data/qbe-zig/src/'
def fix(f, a, b, n=1):
    p=R+f; s=open(p).read()
    assert s.count(a)==n,(f,a,s.count(a))
    open(p,'w').write(s.replace(a,b))

fix('all.zig', 'pub var compat: bool = false;',
'''pub var compat: bool = false;
/// Optimization level (-O0/-O1/-O2). 0 = exactly upstream qbe.
pub var optlevel: u8 = 2;''')

fix('main.zig', '''    all.compat = init.environ_map.get("QBE_COMPAT") != null;''',
'''    all.compat = init.environ_map.get("QBE_COMPAT") != null;
    if (all.compat) all.optlevel = 0;''')

fix('main.zig', '''            switch (c) {
                'd' => for (optarg) |ch| {''',
'''            if (c == 'O') {
                const lv: u8 = if (k + 1 < arg.len) arg[k + 1] else '1';
                all.optlevel = switch (lv) {
                    '0' => 0,
                    '1', 'g' => 1,
                    '2', '3', 's', 'z' => 2,
                    else => {
                        dprint("{s}: invalid optimization level '{s}'\\n", .{ prog, arg[k..] });
                        usageExit(prog, 1);
                    },
                };
                if (all.compat) all.optlevel = 0;
                k = arg.len;
                continue;
            }
            switch (c) {
                'd' => for (optarg) |ch| {''')

fix('main.zig', '''    try hf.print("\\t{s:<11} dump debug information\\n", .{"-d <flags>"});''',
'''    try hf.print("\\t{s:<11} dump debug information\\n", .{"-d <flags>"});
    try hf.print("\\t{s:<11} optimization level: 0 = upstream qbe output,\\n", .{"-O<level>"});
    try hf.print("\\t{s:<11} 1 = algebraic identities, 2 = also division\\n", .{""});
    try hf.print("\\t{s:<11} by constants (default: 2)\\n", .{""});''')

fix('simpl.zig', '            if (!all.compat) algebra(i, f);',
'''            if (all.optlevel >= 1) algebra(i, f);
            if (all.optlevel >= 2 and (i.op == O.Odiv or i.op == O.Orem))
                if (sdivpow2(i, b, k, new, f)) {
                    return;
                };''')
fix('simpl.zig', 'O.Omul, O.Odiv, O.Oadd,', 'O.Omul, O.Odiv, O.Orem, O.Oadd,')

fix('simpl.zig', '''                                i.op = Oshr;
                                i.arg[1] = getcon(n, f);
                            }
                        };
                };''',
'''                                i.op = Oshr;
                                i.arg[1] = getcon(n, f);
                            }
                        } else if (all.optlevel >= 2 and udivconst(i, b, k, new, f)) {
                            return;
                        };
                };''')

fix('simpl.zig', '''fn ins(pk: *uint, new: *bool, b: *Blk, f: *Fn) void {''',
'''/// Switch block b to the rewritten form (instructions after k are already
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
    if (KBASE(i.cls) != 0 or rtype(i.arg[0]) != RTmp or rtype(i.arg[1]) != RCon)
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
    const cls: i32 = @intCast(i.cls);
    const x = i.arg[0];
    const to = i.to;
    const isdiv = i.op == O.Odiv;
    startnew(new, b, k);
    const t1 = newtmp("sdv", cls, f);
    const t2 = newtmp("sdv", cls, f);
    const t3 = newtmp("sdv", cls, f);
    if (isdiv) {
        emit(O.Osar, cls, to, t3, getcon(n, f));
    } else {
        const t4 = newtmp("sdv", cls, f);
        emit(O.Osub, cls, to, x, t4);
        emit(O.Oand, cls, t4, t3, getcon(-sv, f));
    }
    emit(O.Oadd, cls, t3, x, t2);
    emit(O.Oshr, cls, t2, t1, getcon(w - n, f));
    emit(O.Osar, cls, t1, x, getcon(w - 1, f));
    return true;
}

/// Magic number for unsigned 32-bit division by d (not a power of two):
/// the smallest s in 32..63 with m = ceil(2^s/d) < 2^32 and
/// m*d - 2^s <= 2^(s-32); then x/d == (x*m) >> s for every x < 2^32
/// (the error x*(m*d-2^s)/(d*2^s) stays below 1/d), and x*m < 2^64.
/// Divisors needing a 33-bit magic (e.g. 7) are left alone.
pub fn udivmagic(d: u32, m: *u64, s: *u32) bool {
    if (d < 3 or ispow2(d))
        return false;
    var sh: u32 = 32;
    while (sh < 64) : (sh += 1) {
        const p: u128 = @as(u128, 1) << @intCast(sh);
        const mm: u128 = (p + d - 1) / d;
        if (mm >= (@as(u128, 1) << 32))
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
    if (i.cls != Kw or rtype(i.arg[0]) != RTmp)
        return false;
    const d: u32 = @truncate(@as(u64, @bitCast(f.con[i.arg[1].val].bits.i)));
    var m: u64 = 0;
    var s: u32 = 0;
    if (!udivmagic(d, &m, &s))
        return false;
    const x = i.arg[0];
    const to = i.to;
    const isdiv = i.op == Oudiv;
    startnew(new, b, k);
    const t0 = newtmp("udv", Kl, f);
    const t1 = newtmp("udv", Kl, f);
    const t2 = newtmp("udv", Kl, f);
    if (isdiv) {
        emit(O.Ocopy, Kw, to, t2, R);
    } else {
        const q = newtmp("udv", Kw, f);
        const t3 = newtmp("udv", Kw, f);
        emit(O.Osub, Kw, to, x, t3);
        emit(O.Omul, Kw, t3, q, getcon(d, f));
        emit(O.Ocopy, Kw, q, t2, R);
    }
    emit(O.Oshr, Kl, t2, t1, getcon(s, f));
    emit(O.Omul, Kl, t1, t0, getcon(@bitCast(m), f));
    emit(O.Oextuw, Kl, t0, x, R);
    return true;
}

fn ins(pk: *uint, new: *bool, b: *Blk, f: *Fn) void {''')

fix('simpl.zig', '''fn algebra(i: *Ins, f: *Fn) void {
    if (KBASE(i.cls) != 0 or rtype(i.arg[1]) != RCon)
        return;''',
'''fn algebra(i: *Ins, f: *Fn) void {
    if (KBASE(i.cls) != 0)
        return;
    if (all.req(i.arg[0], i.arg[1]) and rtype(i.arg[0]) == RTmp) {
        switch (i.op) {
            // x-x, x^x -> 0
            O.Osub, O.Oxor => {
                i.op = O.Ocopy;
                i.arg[0] = getcon(0, f);
                i.arg[1] = R;
            },
            // x&x, x|x -> x
            O.Oand, O.Oor => {
                i.op = O.Ocopy;
                i.arg[1] = R;
            },
            else => {},
        }
        return;
    }
    if (rtype(i.arg[1]) != RCon)
        return;''')
fix('simpl.zig', '///   x&0 -> 0   x*2^n -> x<<n   x*-1 -> neg x',
    '///   x&0 -> 0   x*2^n -> x<<n   x*-1 -> neg x   x-x, x^x -> 0   x&x, x|x -> x')
fix('simpl.zig', 'const RCon = all.RCon;', 'const RCon = all.RCon;\nconst RTmp = all.RTmp;')
print('ok')
