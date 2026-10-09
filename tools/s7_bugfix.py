# stage 7: fix the three upstream bugs from BUGS.md (Zig side)
R='/data/qbe-zig/src/'
def fix(f, a, b):
    p=R+f; s=open(p).read()
    assert s.count(a)==1,(f,a,s.count(a))
    open(p,'w').write(s.replace(a,b))

# 1. x86 shifts with a (masked) count of 0 leave the flags untouched,
#    so they must not be marked SetsZeroFlag
for op in ('sar','shr','shl'):
    fix('ops.zig',
        '.{ .name = "%s", .t = .{ .{ \'w\', \'l\', \'e\', \'e\' }, .{ \'w\', \'w\', \'e\', \'e\' } }, .f = .{ 1, 1, 0, 0, 0, 0, 0, 0, 0, 0 }, .x = .{ 1, 1, 0 }, .v = 1 },' % op,
        '.{ .name = "%s", .t = .{ .{ \'w\', \'l\', \'e\', \'e\' }, .{ \'w\', \'w\', \'e\', \'e\' } }, .f = .{ 1, 1, 0, 0, 0, 0, 0, 0, 0, 0 }, .x = .{ 1, 0, 0 }, .v = 1 },' % op)

# 2. constant shift counts are masked to the operand width (x86 semantics)
fix('amd64/isel.zig',
'''            r0 = i.arg[1];
            if (rtype(r0) == RCon)
                continue :sw Ocopy; // goto Emit''',
'''            r0 = i.arg[1];
            if (rtype(r0) == RCon) {
                // x86 masks the count; an immediate >= width does not assemble
                const c = &f.con[r0.val];
                if (c.type == CBits) {
                    const m: i64 = if (k == Kw) 31 else 63;
                    if (c.bits.i & m != c.bits.i)
                        i.arg[1] = getcon(c.bits.i & m, f);
                }
                continue :sw Ocopy; // goto Emit
            }''')

# 3. igroup(): after skipping the sel1 run, step back onto the sel0
fix('util.zig',
'''            // NOTE: same (unreachable in practice) assert as upstream
            while (n > 0 and ins[n - 1].op == Osel1) n -= 1;
            assert(ins[n].op == Osel0);''',
'''            while (n > 0 and ins[n - 1].op == Osel1) n -= 1;
            assert(n > 0 and ins[n - 1].op == Osel0);
            n -= 1;''')
print('ok')
