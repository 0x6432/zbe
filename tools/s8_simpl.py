# stage 8a: algebraic simplification / strength reduction in simpl.zig
# (disabled when QBE_COMPAT is set, so output stays identical to C qbe)
R='/data/qbe-zig/src/'
def fix(f, a, b, n=1):
    p=R+f; s=open(p).read()
    assert s.count(a)==n,(f,a,s.count(a))
    open(p,'w').write(s.replace(a,b))

fix('all.zig', 'pub var outw: ?*Writer = null;',
'''pub var outw: ?*Writer = null;
/// QBE_COMPAT set in the environment: skip the optimizations that upstream
/// C qbe does not have, so output stays byte-identical to it.
pub var compat: bool = false;''')

fix('main.zig', '    const argv = init.minimal.args.vector;',
'''    const argv = init.minimal.args.vector;
    all.compat = init.environ_map.get("QBE_COMPAT") != null;''')

fix('simpl.zig', 'const Oudiv = all.ops.Oudiv;',
'''const Oudiv = all.ops.Oudiv;
const O = all.ops;''')

fix('simpl.zig', '''        Oudiv, Ourem => {''',
'''        O.Omul, O.Odiv, O.Oadd, O.Osub, O.Oor, O.Oxor, O.Oand, O.Oshl, O.Oshr, O.Osar => {
            if (!all.compat) algebra(i, f);
        },
        Oudiv, Ourem => {''')

fix('simpl.zig', '''fn ins(pk: *uint, new: *bool, b: *Blk, f: *Fn) void {''',
'''/// Integer identities with a constant right operand (stage 8a):
///   x*0 -> 0   x*1, x/1, x+0, x-0, x|0, x^0, x<<0, x>>0, x&-1 -> x
///   x&0 -> 0   x*2^n -> x<<n
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
    if (i.op == O.Omul and ispow2(sv)) {
        i.op = O.Oshl;
        i.arg[1] = getcon(ulog2(sv), f);
    }
}

fn ins(pk: *uint, new: *bool, b: *Blk, f: *Fn) void {''')
print('ok')
