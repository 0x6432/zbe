#!/usr/bin/env python3
"""Systematic optimizer table test: f(x) = x OP c for every integer op x every
interesting constant c x both classes (w, l), plus the same-operand forms
x-x, x^x, x&x, x|x. Each function is checked natively against a gcc -O0 C
oracle at qbe -O0/-O1/-O2 on edge-case inputs, including the worst-case
dividends for each divisor (largest x with x mod d == d-1, which is where a
too-small magic multiplier first fails), INT_MIN/INT_MAX and neighbours.
Also checks every program compiles on all other targets at -O1/-O2.
"""
import os, random, subprocess, sys, tempfile

D = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
Z = os.environ.get('ZQBE', os.path.join(D, 'zig-out/bin/qbe'))
CC = os.environ.get('CC', 'gcc').split()      # e.g. 'aarch64-linux-gnu-gcc -static'
RUN = os.environ.get('RUN', '').split()       # e.g. 'qemu-aarch64'
TGT = ['-t', os.environ['QBET']] if os.environ.get('QBET') else []
TARGETS = ['amd64_apple', 'amd64_win', 'arm64', 'arm64_apple', 'rv64']
OPS = ['add', 'sub', 'mul', 'and', 'or', 'xor', 'shl', 'shr', 'sar',
       'div', 'rem', 'udiv', 'urem']

def bits(k): return 32 if k == 'w' else 64
def ty(k): return ('int32_t', 'uint32_t') if k == 'w' else ('int64_t', 'uint64_t')

def wrap(k, v):
    b = bits(k); v &= (1 << b) - 1
    return v - (1 << b) if v >> (b - 1) else v

def lit(k, v):
    return '((%s)%dull)' % (ty(k)[0], v & ((1 << bits(k)) - 1))

def consts(k):
    b = bits(k); M = (1 << b) - 1
    cs = set(range(-17, 33)) | {100, 255, 256, 641, 1000, 4096, 10007, 65535, 65536,
                                 641 * 6700417, 0x7fffffff, 0x80000000, 0xffff, 0xffffffff,
                                 0xfffffffe, 0xfffffffd, 1 << 32, (1 << 32) + 1, M, M - 1,
                                 M >> 1, (M >> 1) + 1, 0x55555555, 0xaaaaaaaa, 1000000007}
    for i in range(b):
        cs |= {1 << i, -(1 << i), (1 << i) - 1, (1 << i) + 1}
    return sorted({wrap(k, c) for c in cs})

def inputs(k, op, c):
    b = bits(k); M = (1 << b) - 1
    xs = {0, 1, -1, 2, -2, 3, 7, 1 << (b - 1), (1 << (b - 1)) - 1, (1 << (b - 1)) + 1,
          M, M - 1, 0x7fffffff, 0x80000000, 0xffffffff, 12345678, -12345678}
    xs |= {wrap(k, c), wrap(k, -c), wrap(k, c + 1), wrap(k, c - 1)}
    if op in ('div', 'rem', 'udiv', 'urem'):
        if op in ('udiv', 'urem'):
            d = c & M
            if d:
                hi = (M + 1) // d * d - 1                  # largest x == d-1 (mod d)
                if hi > M: hi -= d
                xs |= {hi, hi - d, hi - 1, d - 1, d, 2 * d - 1, M - M % d, M - M % d - 1}
        else:
            d = abs(c)
            if d:
                top = (1 << (b - 1)) - 1
                hi = (top + 1) // d * d - 1
                xs |= {hi, -hi, hi - d, -(hi - d), d - 1, -(d - 1), d, -d, -(1 << (b - 1)) + d - 1}
    R = random.Random(hash((k, op, c)) & 0xffffffff)
    xs |= {R.getrandbits(b) for _ in range(6)}
    return sorted({wrap(k, x) for x in xs})

def cexpr(k, op, c):
    t, u = ty(k); b = bits(k); cl = lit(k, c)
    if op in ('shl', 'shr', 'sar'):
        n = c & (b - 1)
        if op == 'shl': return '(%s)((%s)x << %d)' % (t, u, n)
        if op == 'shr': return '(%s)((%s)x >> %d)' % (t, u, n)
        return '(%s)(x >> %d)' % (t, n)
    if op in ('div', 'rem'): return '(%s)(x %s %s)' % (t, '/' if op == 'div' else '%', cl)
    if op in ('udiv', 'urem'): return '(%s)((%s)x %s (%s)%s)' % (t, u, '/' if op == 'udiv' else '%', u, cl)
    s = {'add': '+', 'sub': '-', 'mul': '*', 'and': '&', 'or': '|', 'xor': '^'}[op]
    return '(%s)((%s)x %s (%s)%s)' % (t, u, s, u, cl)

def build(k):
    t = ty(k)[0]
    il, cs, checks = [], [], []
    n = 0
    cases = []
    for op in OPS:
        for c in consts(k):
            if op in ('div', 'rem', 'udiv', 'urem') and c == 0: continue
            if op in ('div', 'rem') and c == -1: continue   # INT_MIN / -1 is UB in C
            cases.append((op, str(c), cexpr(k, op, c), inputs(k, op, c)))
    for op, ce in (('sub', '0'), ('xor', '0'), ('and', 'x'), ('or', 'x')):
        cases.append((op, '%x', '(%s)(%s)' % (t, ce), inputs(k, op, 5)))
    for op, arg, ce, xs in cases:
        il.append('export function %s $f%d(%s %%x) {\n@start\n\t%%r =%s %s %%x, %s\n\tret %%r\n}'
                  % (k, n, k, k, op, arg))
        cs.append('%s f%d(%s);\nstatic %s r%d(%s x) { return %s; }' % (t, n, t, t, n, t, ce))
        checks.append('  { static const %s v[] = {%s}; for (unsigned i = 0; i < %d; i++)'
                      ' if (f%d(v[i]) != r%d(v[i])) { printf("%s %s %s x=%%lld got %%lld want %%lld\\n",'
                      ' (long long)v[i], (long long)f%d(v[i]), (long long)r%d(v[i])); bad++; break; } }'
                      % (t, ', '.join(lit(k, x) for x in xs), len(xs), n, n, k, op,
                         arg.replace('%', '%%'), n, n))
        n += 1
    c = '#include <stdint.h>\n#include <stdio.h>\n' + '\n'.join(cs) + \
        '\nint main(void) { int bad = 0;\n' + '\n'.join(checks) + '\n  return bad != 0; }\n'
    return n, '\n\n'.join(il) + '\n', c

def main():
    env = dict(os.environ); env.pop('QBE_COMPAT', None)
    fails = total = 0
    with tempfile.TemporaryDirectory() as w:
        for k in 'wl':
            n, il, c = build(k)
            total += n
            ssa = os.path.join(w, k + '.ssa'); open(ssa, 'w').write(il)
            cf = os.path.join(w, k + '.c'); open(cf, 'w').write(c)
            mo = os.path.join(w, k + 'm.o')
            r = subprocess.run(CC + ['-O0', '-w', '-c', '-o', mo, cf], capture_output=True, text=True)
            if r.returncode: print('gcc failed:', r.stderr[:400]); sys.exit(1)
            for o in '012':
                s = os.path.join(w, '%s%s.s' % (k, o)); exe = os.path.join(w, 't')
                r = subprocess.run([Z] + TGT + ['-O' + o, '-o', s, ssa], env=env, capture_output=True, text=True)
                ok = r.returncode == 0 and subprocess.run(CC + ['-o', exe, mo, s]).returncode == 0
                out = subprocess.run(RUN + [exe], capture_output=True, text=True, timeout=300) if ok else None
                if not ok or out.returncode:
                    fails += 1
                    print('FAIL %s -O%s: %s' % (k, o, (out.stdout if out else r.stderr)[:600]))
            for tg in TARGETS:
                for o in '12':
                    r = subprocess.run([Z, '-t', tg, '-O' + o, ssa], env=env, capture_output=True, text=True)
                    if r.returncode: fails += 1; print('FAIL %s %s -O%s: %s' % (k, tg, o, r.stderr[:200]))
    print('opttable: %d functions x 3 levels, %d failures' % (total, fails))
    sys.exit(fails != 0)

main()
