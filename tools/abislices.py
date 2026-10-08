"""Helpers for rewriting ABI files: pointer-range loops over [i_0, i_1)
with a parallel Class pointer become `for (ins, ca) |*i, *c|` loops."""
import re
LOOP = re.compile(r'''( *)(?:var )?i = i_0;\n\1(?:var )?c = ca;\n\1while \(i < i_1\) : \(\{\n\1    i \+= 1;\n\1    c \+= 1;\n\1\}\) \{''')
def loops(t):
    return LOOP.sub(lambda m: m.group(1) + 'for (ins, ca) |*i, *c| {', t)
def derefs(t, names=('c', 'i', 'i_1', 'b', 'il')):
    for n in names:
        t = re.sub(r'(?<![\w.])' + n + r'\.\*\.', n + '.', t)
    return t

PHI_OLD = '''    b0.phi = pnew(Phi);
    b0.phi.?.* = std.mem.zeroes(Phi);
    b0.phi.?.cls = Kl;
    b0.phi.?.to = loc;
    b0.phi.?.narg = 2;
    b0.phi.?.blk = vnewT(*Blk, 2, PFn);
    b0.phi.?.arg = vnewT(Ref, 2, PFn);
    b0.phi.?.blk[0] = bstk;
    b0.phi.?.blk[1] = breg;
    b0.phi.?.arg[0] = lstk;
    b0.phi.?.arg[1] = lreg;'''
PHI_NEW = '''    const p = pnew(Phi);
    p.* = std.mem.zeroes(Phi);
    p.cls = Kl;
    p.to = loc;
    p.narg = 2;
    p.blk = vnewT(*Blk, 2, PFn);
    p.arg = vnewT(Ref, 2, PFn);
    p.blk[0] = bstk;
    p.blk[1] = breg;
    p.arg[0] = lstk;
    p.arg[1] = lreg;
    b0.phi = p;'''
def vaarg_blocks(s):
    for v in ['b0', 'breg', 'bstk']:
        s = s.replace(v + '.*.', v + '.')
    return s.replace(PHI_OLD, PHI_NEW)

def abi_driver(s, fname, parcall, callcall, extra_cases, lname, ltype):
    """rewrite the pointer-walking driver function fname"""
    a = s.index('pub fn ' + fname + '(f: *Fn) void {')
    e = s.index('\n}\n', a) + 3
    new = '''pub fn %(fname)s(f: *Fn) void {
    var b_it = f.start;
    while (b_it) |b| : (b_it = b.link)
        b.visit = 0;

    // lower parameters
    const start = f.start.?;
    var np: uint = 0;
    while (np < start.nins and ispar(start.ins[np].op))
        np += 1;
    %(parcall)s
    const n0: uint = @intCast(all.insbTail());
    const n1: uint = start.nins - np;
    vgrow(&start.ins, n0 + n1);
    _ = icpy(start.ins + n0, start.ins + np, n1);
    _ = icpy(start.ins, all.curi, n0);
    start.nins = n0 + n1;

    // lower calls, returns, and vararg instructions
    var %(lname)s: ?*%(ltype)s = null;
    var b = start;
    while (true) {
        b = b.link orelse start; // do the start block last
        if (b.visit == 0) {
            all.curi = all.insbEnd();
            selret(b, f);
            var n = b.nins;
            while (n != 0) {
                n -= 1;
                const i = &b.ins[n];
                switch (i.op) {
                    else => emiti(i.*),
                    Ocall => {
                        var n0_ = n;
                        while (n0_ > 0 and isarg(b.ins[n0_ - 1].op))
                            n0_ -= 1;
                        %(callcall)s
                        n = n0_;
                    },
%(extra_cases)s
                    Oarg, Oargc => die("unreachable", .{}),
                }
            }
            if (b == start) {
                while (%(lname)s) |l| : (%(lname)s = l.link)
                    emiti(l.i);
            }
            idup(b, all.curi, @intCast(all.insbTail()));
        }
        if (b == start) break;
    }

    if (all.debug['A'] != 0) {
        dprint("\\n> After ABI lowering:\\n", .{});
        printfn(f, all.dbg) catch {};
    }
}
''' % dict(fname=fname, parcall=parcall, callcall=callcall, extra_cases=extra_cases, lname=lname, ltype=ltype)
    return s[:a] + new + s[e:]
