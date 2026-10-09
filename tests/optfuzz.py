#!/usr/bin/env python3
"""Differential optimizer fuzzer: random integer op chains emitted both as QBE
IL and as an equivalent C function (compiled by gcc -O0 as the oracle). Both
are linked into one program and compared on edge-case and random inputs, for
qbe -O0/-O1/-O2 on the host target. Operands are biased toward the constants
that the -O1/-O2 rewrites match (0, +-1, powers of two, division constants)
and toward same-operand forms (x-x, x^x, x&x, x|x). Also checks that the other
targets compile every program at -O1/-O2.
Usage: optfuzz.py [-n funcs] [-s seed] [-k iterations]
"""
import os, random, subprocess, sys, tempfile

D = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
Z = os.environ.get('ZQBE', os.path.join(D, 'zig-out/bin/qbe'))
CC = os.environ.get('CC', 'gcc').split()      # e.g. 'aarch64-linux-gnu-gcc -static'
RUN = os.environ.get('RUN', '').split()       # e.g. 'qemu-aarch64'
TGT = ['-t', os.environ['QBET']] if os.environ.get('QBET') else []
TARGETS = ['amd64_apple', 'amd64_win', 'arm64', 'arm64_apple', 'rv64']

SPECIAL = [0, 1, -1, 2, -2, 3, 5, 6, 7, 9, 10, 12, 25, 100, 641, 1000, 4096,
           65535, 65536, 0x7fffffff, -0x80000000, 0x80000000, 0xffffffff,
           1 << 32, (1 << 62), -(1 << 63), (1 << 63) - 1]
POW2 = [1 << i for i in range(63)]

def C(k):
    return ('int32_t', 'uint32_t', 32) if k == 'w' else ('int64_t', 'uint64_t', 64)

def wrap(k, v):
    b = 32 if k == 'w' else 64
    v &= (1 << b) - 1
    return v - (1 << b) if v >> (b - 1) else v

def lit(k, v):
    t, u, b = C(k)
    v = wrap(k, v)
    return '((%s)%dull)' % (t, v & ((1 << b) - 1))

def const(R, k):
    r = R.random()
    if r < .45: v = R.choice(SPECIAL)
    elif r < .75: v = R.choice(POW2[:31 if k == 'w' else 63]) * R.choice([1, 1, -1])
    else: v = R.randint(-(1 << 40), 1 << 40)
    return wrap(k, v)

def gen(R, name):
    k = R.choice('wl')
    t, u, b = C(k)
    il = ['export function %s $%s(%s %%a, %s %%b) {' % (k, name, k, k), '@start']
    c = ['%s r_%s(%s a, %s b) {' % (t, name, t, t)]
    vals = ['a', 'b']
    def opnd():
        if R.random() < .4:
            v = const(R, k)
            return str(v), lit(k, v), v
        x = R.choice(vals)
        return '%' + x, x, None
    for i in range(R.randint(1, 10)):
        x = '%' + R.choice(vals); xc = x[1:]
        op = R.choice(['add', 'sub', 'mul', 'and', 'or', 'xor', 'shl', 'shr',
                       'sar', 'div', 'rem', 'udiv', 'urem', 'same', 'mul', 'div',
                       'udiv', 'urem'])
        d = 'v%d' % i
        if op == 'same':
            op = R.choice(['sub', 'xor', 'and', 'or'])
            yi, yc = x, xc
            ce = {'sub': '0', 'xor': '0', 'and': xc, 'or': xc}[op]
            ce = '(%s)(%s)' % (t, ce)
        elif op in ('div', 'rem', 'udiv', 'urem'):
            v = const(R, k)
            if R.random() < .5:
                v = R.choice(POW2[:31 if k == 'w' else 63])
            if v == 0 or (op in ('div', 'rem') and v == -1):
                v = 7
            yi, yc = str(v), lit(k, v)
            if op in ('div', 'rem'):
                # avoid INT_MIN / -1 (undefined); v != -1 already
                ce = '(%s)(%s %s %s)' % (t, xc, '/' if op == 'div' else '%', yc)
            else:
                ce = '(%s)((%s)%s %s (%s)%s)' % (t, u, xc, '/' if op == 'udiv' else '%', u, yc)
        else:
            yi, yc, v = opnd()
            if op in ('shl', 'shr', 'sar'):
                cnt = '((%s)%s & %d)' % (u, yc, b - 1)
                if op == 'shl': ce = '(%s)((%s)%s << %s)' % (t, u, xc, cnt)
                elif op == 'shr': ce = '(%s)((%s)%s >> %s)' % (t, u, xc, cnt)
                else: ce = '(%s)(%s >> %s)' % (t, xc, cnt)
            else:
                sym = {'add': '+', 'sub': '-', 'mul': '*', 'and': '&', 'or': '|', 'xor': '^'}[op]
                ce = '(%s)((%s)%s %s (%s)%s)' % (t, u, xc, sym, u, yc)
        il.append('\t%%%s =%s %s %s, %s' % (d, k, op, x, yi))
        c.append('  %s %s = %s;' % (t, d, ce))
        vals.append(d)
    il += ['\tret %%%s' % vals[-1], '}']
    c += ['  return %s;' % vals[-1], '}']
    return k, '\n'.join(il), '\n'.join(c)

def inputs(R, k):
    xs = [wrap(k, v) for v in SPECIAL] + [wrap(k, v - 1) for v in POW2[1:]] + \
         [wrap(k, R.getrandbits(64)) for _ in range(40)]
    return xs

def one(seed, n, w):
    R = random.Random(seed)
    fs = [gen(R, 'f%d' % i) for i in range(n)]
    ssa = os.path.join(w, 'p.ssa'); open(ssa, 'w').write('\n\n'.join(f[1] for f in fs) + '\n')
    m = ['#include <stdint.h>', '#include <stdio.h>']
    body = []
    for i, (k, il, cc) in enumerate(fs):
        t = C(k)[0]
        m.append('%s f%d(%s, %s);' % (t, i, t, t))
        m.append(cc)
        xs = inputs(R, k)
        arr = ', '.join(lit(k, x) for x in xs)
        body.append('  { %s v[] = {%s}; unsigned n = sizeof v / sizeof *v;' % (t, arr))
        body.append('    for (unsigned i = 0; i < n; i++) for (unsigned j = 0; j < n; j += 3)')
        body.append('      if (f%d(v[i], v[j]) != r_f%d(v[i], v[j])) { printf("f%d %%u %%u\\n", i, j); bad++; break; } }' % (i, i, i))
    m.append('int main(void) { int bad = 0;')
    m += body
    m.append('  return bad != 0; }')
    cf = os.path.join(w, 'm.c'); open(cf, 'w').write('\n'.join(m) + '\n')
    env = dict(os.environ); env.pop('QBE_COMPAT', None)
    for o in ('0', '1', '2'):
        s = os.path.join(w, 'p%s.s' % o)
        r = subprocess.run([Z] + TGT + ['-O' + o, '-o', s, ssa], env=env, capture_output=True, text=True)
        if r.returncode: return 'qbe -O%s failed: %s' % (o, r.stderr[:200])
        exe = os.path.join(w, 't' + o)
        r = subprocess.run(CC + ['-O0', '-w', '-o', exe, cf, s], capture_output=True, text=True)
        if r.returncode: return 'gcc failed (-O%s): %s' % (o, r.stderr[:300])
        r = subprocess.run(RUN + [exe], capture_output=True, text=True, timeout=300)
        if r.returncode: return '-O%s mismatch: %s' % (o, r.stdout[:200])
    for tg in TARGETS:
        for o in ('1', '2'):
            r = subprocess.run([Z, '-t', tg, '-O' + o, ssa], env=env, capture_output=True, text=True)
            if r.returncode: return '%s -O%s failed: %s' % (tg, o, r.stderr[:200])
    return None

def main():
    a = sys.argv[1:]
    n, s, k = 20, 1, 10
    while a:
        f, v = a[0], int(a[1]); a = a[2:]
        if f == '-n': n = v
        elif f == '-s': s = v
        elif f == '-k': k = v
    ok = 0
    with tempfile.TemporaryDirectory() as w:
        for seed in range(s, s + k):
            e = one(seed, n, w)
            if e: print('seed %d: %s' % (seed, e))
            else: ok += 1
    print('optfuzz: %d/%d iterations ok (seeds %d..%d, %d funcs each)' % (ok, k, s, s + k - 1, n))
    sys.exit(ok != k)

main()
