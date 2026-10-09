#!/usr/bin/env python3
"""Benchmarks, printed as Markdown (used in CI release notes).

1. Compile speed: C qbe (reference) vs zbe (ReleaseFast) at -O0 and -O2 on
   every IL file in test/, bench IL and optional corpus files.
2. Generated-code speed: bench/*.c -> cproc -emit-qbe -> {C qbe, zbe -O0,
   zbe -O2} -> cc, run natively; gcc -O0/-O2 shown for reference. All builds
   of a program must print identical output (checked).

Env: QBEREF (C qbe), ZQBE (zbe binary, should be ReleaseFast), CPROC
(cproc driver with -emit-qbe), CC (default cc), CORPUS (glob of extra IL),
REPS (timing repetitions, default 3).
"""
import glob, os, platform, subprocess, sys, tempfile, time

D = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
REF = os.environ.get('QBEREF', '/data/qbe-cfix/qbe')
Z = os.environ.get('ZQBE', os.path.join(D, 'zig-out/bin/qbe'))
CPROC = os.environ.get('CPROC', '/data/cproc/cproc')
CC = os.environ.get('CC', 'cc')
REPS = int(os.environ.get('REPS', '3'))
ENV = dict(os.environ); ENV.pop('QBE_COMPAT', None)

def run(cmd, **kw):
    return subprocess.run(cmd, env=ENV, capture_output=True, text=True, **kw)

def best(f):
    ts = []
    for _ in range(REPS):
        t = time.perf_counter(); f(); ts.append(time.perf_counter() - t)
    return min(ts)

def main():
    w = tempfile.mkdtemp()
    benches = sorted(glob.glob(os.path.join(D, 'bench/*.c')))
    il = {}
    for c in benches:
        n = os.path.basename(c)[:-2]; f = os.path.join(w, n + '.qbe')
        r = run([CPROC, '-emit-qbe', '-o', f, c])
        if r.returncode: print('cproc failed on %s: %s' % (n, r.stderr[:300])); sys.exit(1)
        il[n] = f
    files = sorted(glob.glob(os.path.join(D, 'test/*.ssa'))) + list(il.values())
    if os.environ.get('CORPUS'):
        files += sorted(glob.glob(os.environ['CORPUS']))
    files = [f for f in files if run([REF, f]).returncode == 0]
    out = []
    p = out.append
    p('### Benchmarks\n')
    p('Host: %s %s, %s; %d reps, best time.\n' % (platform.system(), platform.machine(), platform.processor() or '', REPS))
    def comp(cmd):
        def go():
            for f in files:
                subprocess.run(cmd + [f], env=ENV, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        return go
    tr = best(comp([REF]))
    tz0 = best(comp([Z, '-O0']))
    tz2 = best(comp([Z, '-O2']))
    p('#### Compile speed (%d IL files, one process each)\n' % len(files))
    p('| compiler | time | vs C qbe |')
    p('|---|---|---|')
    p('| C qbe | %.3f s | 1.00x |' % tr)
    p('| zbe -O0 | %.3f s | %.2fx |' % (tz0, tz0 / tr))
    p('| zbe -O2 | %.3f s | %.2fx |' % (tz2, tz2 / tr))
    p('')
    cfgs = [('C qbe', [REF]), ('zbe -O0', [Z, '-O0']), ('zbe -O2', [Z, '-O2'])]
    p('#### Generated code speed (run time, lower is better)\n')
    p('| program | C qbe | zbe -O0 | zbe -O2 | -O2 vs C qbe | gcc -O0 | gcc -O2 |')
    p('|---|---|---|---|---|---|---|')
    bad = 0
    for c in benches:
        n = os.path.basename(c)[:-2]
        exes = []
        for name, cmd in cfgs:
            s = os.path.join(w, '%s_%d.s' % (n, len(exes))); e = s[:-2]
            r = run(cmd + ['-o', s, il[n]])
            if r.returncode or run([CC, '-o', e, s]).returncode:
                print('build failed: %s %s %s' % (n, name, r.stderr[:200])); sys.exit(1)
            exes.append(e)
        for o in ('-O0', '-O2'):
            e = os.path.join(w, '%s_gcc%s' % (n, o))
            run([CC, o, '-w', '-o', e, c]); exes.append(e)
        outs = [run([e]).stdout for e in exes]
        if len(set(outs)) != 1:
            bad += 1; p('| %s | OUTPUT MISMATCH: %s |' % (n, ' / '.join(o.strip() for o in outs)))
            continue
        t = [best(lambda e=e: subprocess.run([e], stdout=subprocess.DEVNULL)) for e in exes]
        p('| %s | %.3f s | %.3f s | %.3f s | %+.1f%% | %.3f s | %.3f s |' %
          (n, t[0], t[1], t[2], (t[2] / t[0] - 1) * 100, t[3], t[4]))
    p('')
    p('All builds of each program printed identical output.' if not bad else '%d programs MISMATCHED.' % bad)
    txt = '\n'.join(out)
    print(txt)
    if len(sys.argv) > 1:
        open(sys.argv[1], 'w').write(txt + '\n')
    sys.exit(bad != 0)

main()
