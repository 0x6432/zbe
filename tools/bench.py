#!/usr/bin/env python3
"""Benchmarks, printed as Markdown (used in CI release notes).

1. Compile speed: C qbe (reference) vs zbe (ReleaseFast) at -O0 and -O2 on
   every IL file in test/, bench IL and optional corpus files.
2. Generated-code speed: bench/*.c -> cproc -emit-qbe -> {C qbe, zbe -O0,
   zbe -O2} -> cc, run natively; gcc -O0/-O2 shown for reference. All builds
   of a program must print identical output (checked).

Env: QBEREF (C qbe), ZQBE (zbe binary, should be ReleaseFast), CPROC
(cproc driver with -emit-qbe), CC (default cc), CORPUS (glob of extra IL),
REPS (timing repetitions, default 3), BENCH_TIMEOUT (per-command seconds,
default 120). Failed or timed-out commands invalidate the benchmark.
"""
import glob, os, platform, subprocess, sys, tempfile, time

D = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
REF = os.environ.get('QBEREF', '/data/qbe-cfix/qbe')
Z = os.environ.get('ZQBE', os.path.join(D, 'zig-out/bin/qbe'))
CPROC = os.environ.get('CPROC', '/data/cproc/cproc')
CC = os.environ.get('CC', 'cc')
REPS = int(os.environ.get('REPS', '3'))
TIMEOUT = float(os.environ.get('BENCH_TIMEOUT', '120'))
if REPS <= 0 or not (0 < TIMEOUT < float('inf')):
    raise ValueError('REPS and BENCH_TIMEOUT must be positive and finite')
ENV = dict(os.environ); ENV.pop('QBE_COMPAT', None)

def run(cmd, **kw):
    return subprocess.run(cmd, env=ENV, capture_output=True, text=True, timeout=TIMEOUT, **kw)

def checked(cmd, **kw):
    return run(cmd, check=True, **kw)

def timed(cmd):
    subprocess.run(cmd, env=ENV, stdout=subprocess.DEVNULL,
                   stderr=subprocess.DEVNULL, check=True, timeout=TIMEOUT)

def best(f):
    ts = []
    for _ in range(REPS):
        t = time.perf_counter(); f(); ts.append(time.perf_counter() - t)
    return min(ts)

def benchmark(w):
    benches = sorted(glob.glob(os.path.join(D, 'bench/*.c')))
    il = {}
    for c in benches:
        n = os.path.basename(c)[:-2]; f = os.path.join(w, n + '.qbe')
        r = run([CPROC, '-emit-qbe', '-o', f, c])
        if r.returncode: raise RuntimeError('cproc failed on %s: %s' % (n, r.stderr[:300]))
        il[n] = f
    files = sorted(glob.glob(os.path.join(D, 'test/*.ssa'))) + list(il.values())
    if os.environ.get('CORPUS'):
        files += sorted(glob.glob(os.environ['CORPUS']))
    valid = []
    for f in files:
        result = run([REF, f])
        if result.returncode == 0:
            valid.append(f)
        elif result.returncode == 1:
            # The upstream fixture set includes intentional invalid input.
            continue
        else:
            raise RuntimeError('reference crashed or failed unexpectedly on %s (exit %d)' % (f, result.returncode))
    files = valid
    if not files or not benches:
        raise RuntimeError('benchmark requires accepted IL and generated-code fixtures')
    out = []
    p = out.append
    p('### Benchmarks\n')
    p('Host: %s %s, %s; %d reps, best time.\n' % (platform.system(), platform.machine(), platform.processor() or '', REPS))
    def comp(cmd):
        def go():
            for f in files:
                timed(cmd + [f])
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
            checked(cmd + ['-o', s, il[n]])
            checked([CC, '-o', e, s])
            exes.append(e)
        for o in ('-O0', '-O2'):
            e = os.path.join(w, '%s_gcc%s' % (n, o))
            checked([CC, o, '-w', '-o', e, c]); exes.append(e)
        outs = [checked([e]).stdout for e in exes]
        if len(set(outs)) != 1:
            bad += 1; p('| %s | OUTPUT MISMATCH: %s |' % (n, ' / '.join(o.strip() for o in outs)))
            continue
        t = [best(lambda e=e: timed([e])) for e in exes]
        p('| %s | %.3f s | %.3f s | %.3f s | %+.1f%% | %.3f s | %.3f s |' %
          (n, t[0], t[1], t[2], (t[2] / t[0] - 1) * 100, t[3], t[4]))
    p('')
    p('All builds of each program printed identical output.' if not bad else '%d programs MISMATCHED.' % bad)
    txt = '\n'.join(out)
    print(txt)
    if len(sys.argv) > 1:
        open(sys.argv[1], 'w').write(txt + '\n')
    return int(bad != 0)

def main():
    try:
        with tempfile.TemporaryDirectory(prefix='zbe-bench-') as work:
            return benchmark(work)
    except (OSError, ValueError, RuntimeError, subprocess.SubprocessError) as error:
        print('benchmark failed: %s' % error, file=sys.stderr)
        return 1

if __name__ == '__main__':
    sys.exit(main())
