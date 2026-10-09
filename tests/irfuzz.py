#!/usr/bin/env python3
"""Random IR program fuzzer (own test). Generates QBE functions with random
integer/float arithmetic, comparisons, extensions, conditional branches
(phis), select-like diamonds, loops and memory traffic, evaluates them in
Python with QBE semantics, and checks the native (amd64_sysv) result.
Also compares asm against $QBEREF on all targets if set.

usage: irfuzz.py [-n NFUNCS] [-s SEED] [-k ITERATIONS] [--keep DIR]
"""
import argparse, os, random, subprocess, sys, tempfile, shutil, struct

# cross execution, same convention as optfuzz.py: CC='aarch64-linux-gnu-gcc -static'
# RUN=qemu-aarch64 QBET=arm64 (defaults: native cc, host target)
CC = os.environ.get('CC', 'cc').split()
RUN = os.environ.get('RUN', '').split()
TGT = ['-t', os.environ['QBET']] if os.environ.get('QBET') else []

M = {'w': (1 << 32) - 1, 'l': (1 << 64) - 1}
BITS = {'w': 32, 'l': 64}

SHIFTS = set()
SHIFT_FLAGS = False

def wrap(k, v): return v & M[k]
def sgn(k, v):
    v &= M[k]
    return v - (1 << BITS[k]) if v >> (BITS[k] - 1) else v

def f32(x): return struct.unpack('f', struct.pack('f', x))[0]

class Fn:
    def __init__(self, R, idx):
        self.R = R; self.idx = idx
        self.lines = []
        self.nt = 0
        self.vals = []  # (name, kind, pyvalue) available in current block
        self.nb = 0

    def tmp(self):
        self.nt += 1
        return '%%t%d' % self.nt

    def pick(self, k):
        c = [v for v in self.vals if v[1] == k]
        R = self.R
        if not c or R.random() < .15:
            if k in 'wl':
                v = R.choice([0, 1, 2, 3, 7, 31, 63, 255, -1, -2, 1 << 20,
                              R.randint(-2**31, 2**31 - 1), R.randint(-2**63, 2**63 - 1)]) if k == 'l' else \
                    R.choice([0, 1, 2, 3, 7, 31, 255, -1, -2, R.randint(-2**31, 2**31 - 1)])
                return (str(v), k, wrap(k, v))
            v = R.randint(-1000, 1000) / 8
            return (('s_%r' if k == 's' else 'd_%r') % v, k, v if k == 'd' else f32(v))
        return R.choice(c)

    def add(self, name, k, v):
        self.vals.append((name, k, v))

    def intop(self, k):
        R = self.R
        a = self.pick(k); b = self.pick(k)
        op = R.choice(['add', 'sub', 'mul', 'and', 'or', 'xor', 'shl', 'shr', 'sar',
                       'div', 'rem', 'udiv', 'urem', 'neg', 'cmp', 'ext', 'copy'])
        t = self.tmp(); A, B = a[2], b[2]
        if op in ('div', 'rem', 'udiv', 'urem'):
            if B == 0 or (op in ('div', 'rem') and sgn(k, B) == -1):
                op = 'add'
        if op == 'neg':
            self.lines.append('\t%s =%s neg %s' % (t, k, a[0])); v = wrap(k, -A)
        elif op == 'copy':
            self.lines.append('\t%s =%s copy %s' % (t, k, a[0])); v = A
        elif op == 'cmp':
            c = R.choice(['eq', 'ne', 'sle', 'slt', 'sge', 'sgt', 'ule', 'ult', 'uge', 'ugt'])
            sa, sb = sgn(k, A), sgn(k, B)
            v = {'eq': A == B, 'ne': A != B, 'sle': sa <= sb, 'slt': sa < sb, 'sge': sa >= sb,
                 'sgt': sa > sb, 'ule': A <= B, 'ult': A < B, 'uge': A >= B, 'ugt': A > B}[c]
            rk = R.choice('wl')
            self.lines.append('\t%s =%s c%s%s %s, %s' % (t, rk, c, k, a[0], b[0]))
            self.add(t, rk, int(v)); return
        elif op == 'ext':
            e = R.choice(['extsb', 'extub', 'extsh', 'extuh', 'extsw', 'extuw'])
            if e in ('extsw', 'extuw'):
                k = 'l'  # only valid with an l result
            src = self.pick('w') if e in ('extsw', 'extuw') else self.pick(R.choice('wl'))
            n = {'b': 8, 'h': 16, 'w': 32}[e[-1]]
            x = src[2] & ((1 << n) - 1)
            if e[3] == 's' and x >> (n - 1): x -= 1 << n
            self.lines.append('\t%s =%s %s %s' % (t, k, e, src[0])); v = wrap(k, x)
        else:
            if op in ('shl', 'shr', 'sar') and not b[0].startswith('%'):
                # upstream qbe emits out-of-range immediate shift
                # counts verbatim (invalid amd64 asm); keep them in range
                B = B & (BITS[k] - 1)
                b = (str(B), k, B)
            if op in ('shl', 'shr', 'sar') and b[0].startswith('%') and not SHIFT_FLAGS:
                # upstream bug (BUGS.md): counts folded to constants
                # >= width are emitted verbatim; mask explicitly
                m = self.tmp()
                self.lines.append('\t%s =%s and %s, %d' % (m, b[1], b[0], BITS[k] - 1))
                B = B & (BITS[k] - 1)
                b = (m, b[1], B)
            sh = B & (BITS[k] - 1)
            sa, sb = sgn(k, A), sgn(k, B)
            v = {'add': lambda: A + B, 'sub': lambda: A - B, 'mul': lambda: A * B,
                 'and': lambda: A & B, 'or': lambda: A | B, 'xor': lambda: A ^ B,
                 'shl': lambda: A << sh, 'shr': lambda: A >> sh, 'sar': lambda: sa >> sh,
                 'div': lambda: int(sa / sb) if abs(sa) < 2**52 and abs(sb) < 2**52 else
                        (abs(sa) // abs(sb)) * (1 if (sa < 0) == (sb < 0) else -1),
                 'rem': lambda: sa - sb * ((abs(sa) // abs(sb)) * (1 if (sa < 0) == (sb < 0) else -1)),
                 'udiv': lambda: A // B, 'urem': lambda: A % B}[op]()
            v = wrap(k, v)
            self.lines.append('\t%s =%s %s %s, %s' % (t, k, op, a[0], b[0]))
            if op in ('shl', 'shr', 'sar'):
                SHIFTS.add(t)
        self.add(t, k, v)

    def fltop(self, k):
        R = self.R
        a = self.pick(k); b = self.pick(k)
        op = R.choice(['add', 'sub', 'mul', 'neg', 'cmp', 'conv', 'tosi', 'fromi'])
        t = self.tmp(); A, B = a[2], b[2]
        rnd = (lambda x: x) if k == 'd' else f32
        if op == 'neg':
            self.lines.append('\t%s =%s neg %s' % (t, k, a[0])); v = -A
        elif op in ('add', 'sub', 'mul'):
            v = rnd({'add': A + B, 'sub': A - B, 'mul': A * B}[op])
            self.lines.append('\t%s =%s %s %s, %s' % (t, k, op, a[0], b[0]))
        elif op == 'cmp':
            c = R.choice(['eq', 'ne', 'le', 'lt', 'ge', 'gt', 'o', 'uo'])
            v = {'eq': A == B, 'ne': A != B, 'le': A <= B, 'lt': A < B, 'ge': A >= B,
                 'gt': A > B, 'o': True, 'uo': False}[c]
            self.lines.append('\t%s =w c%s%s %s, %s' % (t, c, k, a[0], b[0]))
            self.add(t, 'w', int(v)); return
        elif op == 'conv':
            if k == 'd':
                self.lines.append('\t%s =s truncd %s' % (t, a[0])); self.add(t, 's', f32(A)); return
            self.lines.append('\t%s =d exts %s' % (t, a[0])); self.add(t, 'd', A); return
        elif op == 'tosi':
            rk = R.choice('wl')
            self.lines.append('\t%s =%s %stosi %s' % (t, rk, k, a[0]))
            self.add(t, rk, wrap(rk, int(A))); return
        else:
            ik = R.choice('wl'); src = self.pick(ik)
            sv = sgn(ik, src[2])
            if abs(sv) > 2**24: sv = None
            if sv is None:
                self.lines.append('\t%s =%s neg %s' % (t, k, a[0])); v = -A
            else:
                self.lines.append('\t%s =%s s%stof %s' % (t, k, ik, src[0])); v = rnd(float(sv))
        self.add(t, k, v)

    def straight(self, n):
        for _ in range(n):
            r = self.R.random()
            if r < .7: self.intop(self.R.choice('wl'))
            else: self.fltop(self.R.choice('sd'))

    def gen(self):
        R = self.R
        np = R.randint(1, 4)
        params = []
        for j in range(np):
            k = R.choice('wl')
            v = wrap(k, R.choice([R.randint(-50, 50), R.randint(-2**31, 2**31 - 1)]))
            params.append(('%%p%d' % j, k, v))
        self.vals = list(params)
        L = self.lines
        L.append('export function l $f%d(%s) {' % (self.idx, ', '.join('%s %s' % (k, n) for n, k, _ in params)))
        L.append('@start')
        # memory slot traffic
        L.append('\t%mem =l alloc8 16')
        self.straight(R.randint(2, 8))
        for blk in range(R.randint(1, 4)):
            kind = R.choice(['diamond', 'loop', 'mem', 'straight'])
            b = self.nb; self.nb += 1
            if kind == 'straight':
                self.straight(R.randint(1, 6))
            elif kind == 'mem':
                k = R.choice('wl'); a = self.pick(k)
                op = 'store' + k
                L.append('\t%s %s, %%mem' % (op, a[0]))
                t = self.tmp()
                L.append('\t%s =%s load%s %%mem' % (t, k, k if k == 'l' else 'w'))
                self.add(t, k, a[2])
                t2 = self.tmp(); L.append('\t%s =l add %%mem, 8' % t2)
                L.append('\tstoreb %s, %s' % (a[0], t2))
                t3 = self.tmp(); L.append('\t%s =w loadsb %s' % (t3, t2))
                x = a[2] & 255; x = x - 256 if x > 127 else x
                self.add(t3, 'w', wrap('w', x))
            elif kind == 'diamond':
                c = self.pick(R.choice('wl'))
                if c[0] in SHIFTS and not SHIFT_FLAGS:
                    # upstream bug (BUGS.md): jnz on a shift result
                    # reuses flags, but x86 shifts by 0 keep flags
                    c = ('0', 'w', 0) if R.random() < .5 else ('1', 'w', 1)
                # IL spec: jnz compares only the low 32 bits, even of a long
                cond = (c[2] & 0xffffffff) != 0
                saved = list(self.vals)
                L.append('\tjnz %s, @T%d, @F%d' % (c[0], b, b))
                L.append('@T%d' % b)
                self.straight(R.randint(0, 4))
                k = R.choice('wl'); x = self.pick(k)
                self.vals = list(saved)
                L.append('\tjmp @J%d' % b)
                L.append('@F%d' % b)
                self.straight(R.randint(0, 4))
                y = self.pick(k)
                self.vals = list(saved)
                L.append('\tjmp @J%d' % b)
                L.append('@J%d' % b)
                t = self.tmp()
                L.append('\t%s =%s phi @T%d %s, @F%d %s' % (t, k, b, x[0], b, y[0]))
                self.add(t, k, x[2] if cond else y[2])
            else:  # counted loop accumulating
                n = R.randint(0, 12)
                k = R.choice('wl')
                init = self.pick(k); step = self.pick(k)
                i0, a0 = self.tmp(), self.tmp()
                i1, a1, c1 = self.tmp(), self.tmp(), self.tmp()
                L.append('\tjmp @H%d' % b)
                L.append('@H%d' % b)
                pre = 'start' if b == 0 and False else None
                # phis reference predecessor: the block before @H
                L.insert(len(L) - 2, '@P%d' % b)  # label for preheader edge
                L.append('\t%s =w phi @P%d 0, @B%d %s' % (i0, b, b, i1))
                L.append('\t%s =%s phi @P%d %s, @B%d %s' % (a0, k, b, init[0], b, a1))
                L.append('\t%s =w csltw %s, %d' % (c1, i0, n))
                L.append('\tjnz %s, @B%d, @E%d' % (c1, b, b))
                L.append('@B%d' % b)
                op = R.choice(['add', 'xor', 'mul', 'sub'])
                L.append('\t%s =%s %s %s, %s' % (a1, k, op, a0, step[0]))
                L.append('\t%s =w add %s, 1' % (i1, i0))
                L.append('\tjmp @H%d' % b)
                L.append('@E%d' % b)
                v = init[2]
                for _ in range(n):
                    v = wrap(k, {'add': v + step[2], 'xor': v ^ step[2], 'mul': v * step[2],
                                 'sub': v - step[2]}[op])
                saved = [x for x in self.vals]
                self.vals = saved
                self.add(a0, k, v)
                self.add(i0, 'w', n)
        # checksum of all integer values (and floats converted)
        acc = 0
        L.append('\t%acc0 =l copy 0')
        cur = '%acc0'
        n = 0
        for name, k, v in self.vals:
            if k in 'sd':
                if abs(v) >= 2**31: continue
                t = self.tmp(); L.append('\t%s =l %stosi %s' % (t, k, name)); x = wrap('l', int(v))
            elif k == 'w':
                t = self.tmp(); L.append('\t%s =l extsw %s' % (t, name)); x = wrap('l', sgn('w', v))
            else:
                t, x = name, v
            n += 1
            nxt = '%%acc%d' % n
            L.append('\t%s =l mul %s, 31' % (nxt + 'm', cur))
            L.append('\t%s =l xor %s, %s' % (nxt, nxt + 'm', t))
            acc = wrap('l', (acc * 31) ^ x)
            cur = nxt
        L.append('\tret %s' % cur)
        L.append('}')
        return '\n'.join(L), [(k, v) for _, k, v in params], acc

def run(cmd, **kw):
    return subprocess.run(cmd, capture_output=True, text=True, **kw)

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('-n', type=int, default=20)
    ap.add_argument('-s', type=int, default=None)
    ap.add_argument('-k', type=int, default=1)
    ap.add_argument('--keep', default=None)
    ap.add_argument('--upstream-bugs', action='store_true',
                    help='do not avoid known upstream qbe bugs (see BUGS.md)')
    a = ap.parse_args()
    global SHIFT_FLAGS
    SHIFT_FLAGS = a.upstream_bugs
    qbe = os.environ.get('QBE', os.path.join(os.path.dirname(__file__), '..', 'zig-out', 'bin', 'qbe'))
    ref = os.environ.get('QBEREF')
    seed0 = a.s if a.s is not None else random.randrange(1 << 30)
    bad = 0
    for it in range(a.k):
        seed = seed0 + it
        R = random.Random(seed)
        SHIFTS.clear()
        q, c = [], ['#include <stdio.h>', 'int main(void) { int bad = 0;']
        for i in range(a.n):
            txt, params, exp = Fn(R, i).gen()
            q.append(txt)
            ct = ', '.join('int' if k == 'w' else 'long long' for k, _ in params)
            c.insert(1, 'long long f%d(%s);' % (i, ct))
            args = ', '.join('(int)%dLL' % sgn('w', v) if k == 'w' else '(long long)%dLL' % sgn('l', v)
                             if sgn('l', v) != -2**63 else '(-9223372036854775807LL-1)' for k, v in params)
            c.append('\tif ((unsigned long long)f%d(%s) != %dULL) { printf("f%d mismatch\\n"); bad++; }' % (i, args, exp, i))
        c.append('\treturn bad != 0;\n}')
        d = a.keep or tempfile.mkdtemp()
        os.makedirs(d, exist_ok=True)
        open(os.path.join(d, 'main.c'), 'w').write('\n'.join(c) + '\n')
        open(os.path.join(d, 'f.ssa'), 'w').write('\n'.join(q) + '\n')
        ok = True
        r = run([qbe] + TGT + ['-o', os.path.join(d, 'f.s'), os.path.join(d, 'f.ssa')])
        if r.returncode: print('seed %d: qbe failed: %s' % (seed, r.stderr)); ok = False
        if ok:
            r = run(CC + ['-o', os.path.join(d, 'a.out'), os.path.join(d, 'main.c'), os.path.join(d, 'f.s')])
            if r.returncode: print('seed %d: cc failed: %s' % (seed, r.stderr[:2000])); ok = False
        if ok:
            r = run(RUN + [os.path.join(d, 'a.out')], timeout=120)
            if r.returncode: print('seed %d: run failed (%d): %s' % (seed, r.returncode, r.stdout[:500])); ok = False
        if ok and ref:
            for t in ['amd64_sysv', 'amd64_apple', 'amd64_win', 'arm64', 'arm64_apple', 'rv64']:
                x = run([qbe, '-t', t, os.path.join(d, 'f.ssa')])
                y = run([ref, '-t', t, os.path.join(d, 'f.ssa')])
                if x.returncode != y.returncode or x.stdout != y.stdout:
                    print('seed %d: asm differs from reference on %s' % (seed, t)); ok = False
        if not ok:
            bad += 1; print('  kept in', d)
        elif not a.keep:
            shutil.rmtree(d)
    print('irfuzz: %d/%d iterations ok (seeds %d..%d)' % (a.k - bad, a.k, seed0, seed0 + a.k - 1))
    sys.exit(1 if bad else 0)

main()
