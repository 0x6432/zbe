#!/usr/bin/env python3
"""Mutation testing of the optimizer tests: inject one realistic bug at a
time into src/simpl.zig, rebuild, and require that the optimization tests
(opt.sh, optfuzz.py, then optsweep.sh) catch it. The source is restored
after each mutant (git checkout). A surviving mutant = a gap in the tests.
Usage: mutate.py [mutant-index ...]
"""
import os, subprocess, sys

D = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = 'src/simpl.zig'
M = [
    ('x%1 treated as identity', 'O.Omul, O.Odiv => sv == 1,', 'O.Omul, O.Odiv, O.Orem => sv == 1,'),
    ('x+1 treated as identity', 'else => sv == 0,', 'else => sv <= 1,'),
    ('and-mask identity too wide', 'O.Oand => sv == mask,', 'O.Oand => sv == mask or sv == 0x7fffffff,'),
    ('x*-1 -> x instead of neg', 'i.op = O.Oneg;', 'i.op = O.Ocopy;'),
    ('mul pow2 shift off by one', 'i.arg[1] = getcon(ulog2(sv), f);', 'i.arg[1] = getcon(ulog2(sv) + 1, f);'),
    ('sdiv bias shift off by one', 'getcon(w - n, f)', 'getcon(w - n + 1, f)'),
    ('srem mask wrong', 'getcon(-sv, f)', 'getcon(~sv, f)'),
    ('sdiv accepts divisor 1', 'if (sv < 2 or !ispow2', 'if (sv < 1 or !ispow2'),
    ('udiv magic bound loosened', '<= (@as(u128, 1) << @intCast(sh - 32))', '<= (@as(u128, 1) << @intCast(sh - 30))'),
    ('udiv sign-extends x', 'emit(O.Oextuw, Kl, t0, x, R);', 'emit(O.Oextsw, Kl, t0, x, R);'),
    ('rewrites machine registers', 'return virt(i.to) and virt(i.arg[0]) and virt(i.arg[1]);', 'return true;'),
]
TESTS = [
    ('opt.sh', 'timeout 120 sh tools/opt.sh'),
    ('optfuzz', 'timeout 200 python3 tests/optfuzz.py -n 20 -s 1 -k 4'),
    ('optsweep', 'timeout 300 sh tools/optsweep.sh test/*.ssa'),
]

def sh(c):
    env = dict(os.environ); env.pop('QBE_COMPAT', None)
    return subprocess.run(c, shell=True, cwd=D, env=env, capture_output=True, text=True).returncode

def main():
    idx = [int(a) for a in sys.argv[1:]] or range(len(M))
    orig = open(os.path.join(D, SRC)).read()
    survived = 0
    try:
        for k in idx:
            name, a, b = M[k]
            assert orig.count(a) == 1, ('pattern not unique', name)
            open(os.path.join(D, SRC), 'w').write(orig.replace(a, b))
            if sh('zig build') != 0:
                print('mutant %d (%s): build failed?' % (k, name)); survived += 1; continue
            by = next((t for t, c in TESTS if sh(c) != 0), None)
            if by: print('mutant %d killed by %s: %s' % (k, by, name))
            else: print('mutant %d SURVIVED: %s' % (k, name)); survived += 1
            sys.stdout.flush()
    finally:
        open(os.path.join(D, SRC), 'w').write(orig)
        sh('zig build')
    print('mutate: %d killed, %d survived' % (len(idx) - survived, survived))
    sys.exit(survived != 0)

main()
