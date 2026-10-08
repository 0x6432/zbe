#!/usr/bin/env python3
"""ABI fuzzer for qbe (own test). Generates random function signatures with
scalar and aggregate (struct) parameters / return values, then emits
  - callee.ssa : QBE functions that are called from C and check their args,
                 and QBE functions that call C functions with constant args
  - caller.c   : C side (checks/returns values, main driver)
Builds with $QBE + cc, runs the binary (native amd64_sysv only) and also
compares asm of $QBE vs $QBEREF for all targets if QBEREF is set.

usage: abifuzz.py [-n NFUNCS] [-s SEED] [-k ITERATIONS] [--keep DIR]
"""
import argparse, os, random, subprocess, sys, tempfile, shutil

SC = {  # qbe ext type -> (C type, size, align, qbe load op, cmp class, kind)
    'sb': ('signed char', 1, 1, 'loadsb', 'w', 'i'),
    'ub': ('unsigned char', 1, 1, 'loadub', 'w', 'i'),
    'sh': ('short', 2, 2, 'loadsh', 'w', 'i'),
    'uh': ('unsigned short', 2, 2, 'loaduh', 'w', 'i'),
    'w': ('int', 4, 4, 'loadsw', 'w', 'i'),
    'l': ('long', 8, 8, 'loadl', 'l', 'i'),
    's': ('float', 4, 4, 'loads', 's', 'f'),
    'd': ('double', 8, 8, 'loadd', 'd', 'f'),
}
# aggregate field letters in qbe -> scalar key
FIELD = {'b': 'sb', 'h': 'sh', 'w': 'w', 'l': 'l', 's': 's', 'd': 'd'}
STORE = {'sb': 'storeb', 'ub': 'storeb', 'sh': 'storeh', 'uh': 'storeh',
         'w': 'storew', 'l': 'storel', 's': 'stores', 'd': 'stored'}

def val(R, k):
    if k == 'sb': return R.randint(-128, 127)
    if k == 'ub': return R.randint(0, 255)
    if k == 'sh': return R.randint(-32768, 32767)
    if k == 'uh': return R.randint(0, 65535)
    if k == 'w': return R.choice([R.randint(-2**31, 2**31 - 1), R.randint(-100, 100)])
    if k == 'l': return R.choice([R.randint(-2**63, 2**63 - 1), R.randint(-100, 100)])
    return R.randint(-4000, 4000) / 4  # exactly representable floats

def qc(k, v):  # qbe constant
    if k == 's': return 's_%r' % float(v)
    if k == 'd': return 'd_%r' % float(v)
    return str(v)

def cc(k, v):  # C constant
    if k == 's': return '%rf' % float(v)
    if k == 'd': return '%r' % float(v)
    if k == 'l': return '(long)%dLL' % v if v != -2**63 else '(-9223372036854775807LL-1)'
    if k == 'w': return '(int)%dLL' % v
    return '%d' % v

class Agg:
    def __init__(self, R, name):
        self.name = name
        self.fields = []  # (scalar key, count)
        for _ in range(R.randint(1, 5)):
            f = R.choice('bhwlsd' if R.random() < .6 else 'sd')
            n = 1 if R.random() < .8 else R.randint(2, 4)
            self.fields.append((FIELD[f], n, f))
        # layout
        self.elems = []  # (key, offset)
        off = 0; al = 1
        for k, n, _ in self.fields:
            sz, a = SC[k][1], SC[k][2]
            off = (off + a - 1) // a * a
            al = max(al, a)
            for j in range(n):
                self.elems.append((k, off)); off += sz
        self.size = (off + al - 1) // al * al
    def qdef(self):
        return 'type :%s = { %s }' % (self.name, ', '.join(
            f + ('' if n == 1 else ' %d' % n) for _, n, f in self.fields))
    def cdef(self):
        fs = []
        for i, (k, n, _) in enumerate(self.fields):
            fs.append('%s f%d%s;' % (SC[k][0], i, '' if n == 1 else '[%d]' % n))
        return 'struct %s { %s };' % (self.name, ' '.join(fs))
    def cfields(self):  # C lvalue paths in elems order
        out = []
        for i, (k, n, _) in enumerate(self.fields):
            for j in range(n):
                out.append('f%d' % i + ('' if n == 1 else '[%d]' % j))
        return out
    def rand(self, R):
        return [val(R, k) for k, _ in self.elems]

class Gen:
    def __init__(self, R, nf):
        self.R = R
        self.aggs = []
        self.q = []  # qbe text
        self.c = []  # c text
        self.nchk = 0
        self.funcs = []
        for i in range(nf):
            self.funcs.append(self.sig(i))

    def ty(self, allow_void=False):
        R = self.R
        r = R.random()
        if allow_void and r < .1: return None
        if r < .45:
            a = Agg(R, 't%d' % len(self.aggs)); self.aggs.append(a); return a
        return R.choice(list(SC))

    def sig(self, i):
        ret = self.ty(True)
        params = [self.ty() for _ in range(self.R.randint(0, 12))]
        va = self.R.random() < .2  # variadic tail of l/d values
        vargs = [self.R.choice('ld') for _ in range(self.R.randint(1, 5))] if va else []
        return (i, ret, params, vargs)

    # --- helpers
    def ctype(self, t):
        return 'struct %s' % t.name if isinstance(t, Agg) else SC[t][0]
    def qtype(self, t):
        return ':' + t.name if isinstance(t, Agg) else t
    def cval(self, t, v):
        if isinstance(t, Agg):
            return '(%s){%s}' % (self.ctype(t), ', '.join(
                '.' + p + '=' + cc(k, x) for p, (k, _), x in zip(t.cfields(), t.elems, v)))
        return cc(t, v)
    def rval(self, t):
        return t.rand(self.R) if isinstance(t, Agg) else val(self.R, t)

    # C check of value expr e of type t against v
    def cchk(self, e, t, v):
        out = []
        if isinstance(t, Agg):
            for p, (k, _), x in zip(t.cfields(), t.elems, v):
                self.nchk += 1
                out.append('\tif ((%s).%s != %s) fail(%d);' % (e, p, cc(k, x), self.nchk))
        else:
            self.nchk += 1
            out.append('\tif (%s != %s) fail(%d);' % (e, cc(t, v), self.nchk))
        return out

    # QBE check of temp %r (scalar value or aggregate pointer)
    def qchk(self, r, t, v, lbl):
        out = []
        if isinstance(t, Agg):
            for j, ((k, off), x) in enumerate(zip(t.elems, v)):
                out.append('\t%%a%s.%d =l add %s, %d' % (lbl, j, r, off))
                kk = SC[k][4]
                out.append('\t%%v%s.%d =%s %s %%a%s.%d' % (lbl, j, kk, SC[k][3], lbl, j))
                out += self.qcmp('%%v%s.%d' % (lbl, j), kk, x, '%s.%d' % (lbl, j))
        else:
            kk = SC[t][4]
            out += self.qcmp(r, kk, v, lbl)
        return out

    def qcmp(self, r, kk, x, lbl):
        self.nchk += 1
        cmp = {'w': 'ceqw', 'l': 'ceql', 's': 'ceqs', 'd': 'ceqd'}[kk]
        return ['\t%%c%s =w %s %s, %s' % (lbl, cmp, r, qc(kk if kk in 'sd' else kk, x)),
                '\tjnz %%c%s, @ok%s, @bad%s' % (lbl, lbl, lbl),
                '@bad%s' % lbl,
                '\tcall $fail(w %d)' % self.nchk,
                '@ok%s' % lbl]

    # QBE build value of type t into operand; returns (prelude lines, operand)
    def qbuild(self, t, v, lbl):
        if isinstance(t, Agg):
            out = ['\t%%s%s =l alloc8 %d' % (lbl, t.size)]
            for j, ((k, off), x) in enumerate(zip(t.elems, v)):
                out.append('\t%%p%s.%d =l add %%s%s, %d' % (lbl, j, lbl, off))
                out.append('\t%s %s, %%p%s.%d' % (STORE[k], qc(SC[k][4], x), lbl, j))
            return out, '%%s%s' % lbl
        return [], qc(SC[t][4], v)

    def emit(self):
        R = self.R
        c, q = self.c, self.q
        c.append('#include <stdio.h>\n#include <stdlib.h>\n#include <stdarg.h>')
        c.append('static int nfail;\nvoid fail(int n) { printf("check %d failed\\n", n); nfail++; }')
        for a in self.aggs:
            c.append(a.cdef()); q.append(a.qdef())
        main = ['int main(void) {']
        for (i, ret, params, vargs) in self.funcs:
            pv = [self.rval(t) for t in params]
            vv = [self.rval(t) for t in vargs]
            rv = self.rval(ret) if ret is not None else None
            cret = self.ctype(ret) if ret is not None else 'void'
            cparams = ', '.join(['%s p%d' % (self.ctype(t), j) for j, t in enumerate(params)] +
                                (['...'] if vargs else [])) or 'void'
            if vargs and not params:
                cparams = 'int p_, ...'  # C needs a named param
            # ---- A: C calls QBE function fa<i>
            c.append('%s fa%d(%s);' % (cret, i, cparams))
            qp = ['%s %%p%d' % (self.qtype(t), j) for j, t in enumerate(params)]
            if vargs and not params: qp = ['w %p_']
            if vargs: qp.append('...')
            q.append('export function %s $fa%d(%s) {' % (self.qtype(ret) if ret is not None else '', i, ', '.join(qp)))
            q.append('@start')
            for j, (t, v) in enumerate(zip(params, pv)):
                q += self.qchk('%%p%d' % j, t, v, 'A%d_%d' % (i, j))
            if vargs:
                q.append('\t%ap =l alloc8 32')
                q.append('\tvastart %ap')
                for j, (t, v) in enumerate(zip(vargs, vv)):
                    q.append('\t%%va%d =%s vaarg %%ap' % (j, t))
                    q += self.qchk('%%va%d' % j, t, v, 'V%d_%d' % (i, j))
            if ret is None:
                q.append('\tret')
            else:
                pre, op = self.qbuild(ret, rv, 'R%d' % i)
                q += pre; q.append('\tret %s' % op)
            q.append('}')
            args = [self.cval(t, v) for t, v in zip(params, pv)]
            if vargs and not params: args = ['0']
            args += [self.cval(t, v) for t, v in zip(vargs, vv)]
            call = 'fa%d(%s)' % (i, ', '.join(args))
            if ret is None:
                main.append('\t%s;' % call)
            else:
                main.append('\t{ %s r = %s;' % (cret, call))
                main += self.cchk('r', ret, rv)
                main.append('\t}')
            # ---- B: QBE function qb<i> calls C function fb<i>
            pv = [self.rval(t) for t in params]
            vv = [self.rval(t) for t in vargs]
            rv = self.rval(ret) if ret is not None else None
            c.append('%s fb%d(%s) {' % (cret, i, cparams))
            for j, (t, v) in enumerate(zip(params, pv)):
                c += self.cchk('p%d' % j, t, v)
            if vargs:
                c.append('\tva_list ap; va_start(ap, %s);' % ('p%d' % (len(params) - 1) if params else 'p_'))
                for j, (t, v) in enumerate(zip(vargs, vv)):
                    c.append('\t{ %s x = va_arg(ap, %s);' % (SC[t][0], SC[t][0]))
                    c += self.cchk('x', t, v)
                    c.append('\t}')
                c.append('\tva_end(ap);')
            if ret is not None:
                c.append('\treturn %s;' % self.cval(ret, rv))
            c.append('}')
            q.append('export function $qb%d() {' % i)
            q.append('@start')
            ops = []
            for j, (t, v) in enumerate(zip(params, pv)):
                pre, op = self.qbuild(t, v, 'B%d_%d' % (i, j))
                q += pre; ops.append('%s %s' % (self.qtype(t), op))
            if vargs and not params: ops.append('w 0')
            if vargs:
                ops.append('...')
                for t, v in zip(vargs, vv):
                    ops.append('%s %s' % (t, qc(t, v)))
            if ret is None:
                q.append('\tcall $fb%d(%s)' % (i, ', '.join(ops)))
            else:
                rk = ret if isinstance(ret, str) else None
                rcls = self.qtype(ret) if rk is None else SC[rk][4]
                # sub-word returns: declare ext type, result is w
                rt = self.qtype(ret)
                q.append('\t%%r%d =%s call $fb%d(%s)' % (i, rt, i, ', '.join(ops)))
                res = '%%r%d' % i
                if rk in ('sb', 'ub', 'sh', 'uh'):
                    # sub-word call results are not extended by qbe
                    q.append('\t%%x%d =w ext%s %%r%d' % (i, rk, i))
                    res = '%%x%d' % i
                q += self.qchk(res, ret, rv, 'BR%d' % i)
            q.append('\tret')
            q.append('}')
            c.append('void qb%d(void);' % i)
            main.append('\tqb%d();' % i)
        main.append('\tif (nfail) printf("%d failures\\n", nfail);')
        main.append('\treturn nfail != 0;\n}')
        c += main
        return '\n'.join(c) + '\n', '\n'.join(q) + '\n'

def run(cmd, **kw):
    return subprocess.run(cmd, capture_output=True, text=True, **kw)

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('-n', type=int, default=20)
    ap.add_argument('-s', type=int, default=None)
    ap.add_argument('-k', type=int, default=1)
    ap.add_argument('--keep', default=None)
    a = ap.parse_args()
    qbe = os.environ.get('QBE', os.path.join(os.path.dirname(__file__), '..', 'zig-out', 'bin', 'qbe'))
    ref = os.environ.get('QBEREF')
    seed0 = a.s if a.s is not None else random.randrange(1 << 30)
    bad = 0
    for it in range(a.k):
        seed = seed0 + it
        R = random.Random(seed)
        csrc, qsrc = Gen(R, a.n).emit()
        d = a.keep or tempfile.mkdtemp()
        os.makedirs(d, exist_ok=True)
        open(os.path.join(d, 'caller.c'), 'w').write(csrc)
        open(os.path.join(d, 'callee.ssa'), 'w').write(qsrc)
        ok = True
        r = run([qbe, '-o', os.path.join(d, 'callee.s'), os.path.join(d, 'callee.ssa')])
        if r.returncode: print('seed %d: qbe failed: %s' % (seed, r.stderr)); ok = False
        if ok:
            r = run(['cc', '-o', os.path.join(d, 'a.out'), os.path.join(d, 'caller.c'), os.path.join(d, 'callee.s')])
            if r.returncode: print('seed %d: cc failed: %s' % (seed, r.stderr[:2000])); ok = False
        if ok:
            r = run([os.path.join(d, 'a.out')], timeout=20)
            if r.returncode: print('seed %d: run failed (%d): %s' % (seed, r.returncode, r.stdout[:500])); ok = False
        if ok and ref:
            for t in ['amd64_sysv', 'amd64_apple', 'amd64_win', 'arm64', 'arm64_apple', 'rv64']:
                x = run([qbe, '-t', t, os.path.join(d, 'callee.ssa')])
                y = run([ref, '-t', t, os.path.join(d, 'callee.ssa')])
                if x.returncode != y.returncode or x.stdout != y.stdout:
                    print('seed %d: asm differs from reference on %s' % (seed, t)); ok = False
        if not ok:
            bad += 1
            print('  kept in', d)
        elif not a.keep:
            shutil.rmtree(d)
    print('abifuzz: %d/%d iterations ok (seeds %d..%d)' % (a.k - bad, a.k, seed0, seed0 + a.k - 1))
    sys.exit(1 if bad else 0)

main()
