#!/usr/bin/env python3
"""Bounded GOT-backed scalar vaarg/vastart runtime witness, Linux x86-64 ELF.

An independently initialized live C va_list is consumed by the IL subject;
C va_arg checks every value and the final cursor. A separate IL variadic entry
initializes and consumes its descriptor before returning. All eight optimization
combinations, PIE/non-PIE clients and normal/LD_PRELOAD bindings are exercised.
This is a partial N11 witness, not the N11 bundle or integration-gate evidence.
Follow repository verification coordination; this script takes the supplied
nonblocking lock. With --evidence-dir, retain commands, output and inputs there.
"""
import argparse
import fcntl
import hashlib
import itertools
import json
import os
from pathlib import Path
import platform
import re
import resource
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
FIXTURES = ROOT / 'src/fixtures/extern-got-varargs'
FLAGS = ('--fold-integers', '--reuse-stack-homes', '--callee-saved-homes')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--compiler', required=True, type=Path)
    parser.add_argument('--cc', default='cc')
    parser.add_argument('--readelf', default='readelf')
    parser.add_argument('--lock', type=Path, default=Path('/data/zbe-coordination/full-verification.lock'))
    parser.add_argument('--evidence-dir', type=Path, help='new directory for retained evidence')
    args = parser.parse_args()
    if platform.system() != 'Linux' or platform.machine() not in ('x86_64', 'amd64'):
        parser.error('Linux x86-64 ELF required')
    compiler = args.compiler.resolve(strict=True)
    cc, readelf = shutil.which(args.cc), shutil.which(args.readelf)
    if cc is None or readelf is None:
        parser.error('C compiler and readelf required')
    clean = {'PATH': os.environ.get('PATH', '/usr/bin:/bin'), 'LC_ALL': 'C'}
    resource.setrlimit(resource.RLIMIT_CORE, (0, 0))
    soft, hard = resource.getrlimit(resource.RLIMIT_AS)
    cap = min(x for x in (4 * 1024**3, soft, hard) if x != resource.RLIM_INFINITY)
    resource.setrlimit(resource.RLIMIT_AS, (cap, hard))
    if hasattr(os, 'sched_getaffinity'):
        os.sched_setaffinity(0, sorted(os.sched_getaffinity(0))[:2])
    with args.lock.open('a') as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            raise SystemExit('verification lock is busy; no commands were run')
        if args.evidence_dir:
            args.evidence_dir.mkdir(parents=True, exist_ok=False)
            exercise(args.evidence_dir.resolve(), compiler, cc, readelf, clean)
        else:
            with tempfile.TemporaryDirectory(prefix='zbe-got-vaarg-') as tmp:
                exercise(Path(tmp), compiler, cc, readelf, clean)


def exercise(d, compiler, cc, readelf, clean):
    for name in ('subject.ssa', 'provider.c', 'client.c'):
        shutil.copyfile(FIXTURES / name, d / name)
    hashes = {str(p.name): hashlib.sha256(p.read_bytes()).hexdigest()
              for p in (compiler, *(d / n for n in ('subject.ssa', 'provider.c', 'client.c')))}
    (d / 'sha256.json').write_text(json.dumps(hashes, indent=2) + '\n')
    journal = d / 'commands.jsonl'

    def run(argv, env=None, expect_success=True):
        argv = [str(x) for x in argv]
        actual_env = clean if env is None else env
        try:
            p = subprocess.run(argv, cwd=d, env=actual_env, capture_output=True,
                               text=True, errors='replace', timeout=90)
            record = {'argv': argv, 'env': actual_env, 'exit': p.returncode,
                      'stdout': p.stdout, 'stderr': p.stderr}
        except subprocess.TimeoutExpired as exc:
            record = {'argv': argv, 'env': actual_env, 'timeout': str(exc)}
            with journal.open('a') as f:
                f.write(json.dumps(record) + '\n')
            raise
        with journal.open('a') as f:
            f.write(json.dumps(record) + '\n')
        if expect_success and p.returncode != 0:
            raise RuntimeError(f'{argv!r}: exit {p.returncode}\n{p.stdout}\n{p.stderr}')
        return p

    for name, marker in (('provider', '1'), ('override', '2')):
        run([cc, '-std=c11', '-O2', '-Wall', '-Wextra', '-Werror', '-fPIC', '-shared',
             '-DMARKER=' + marker, 'provider.c', '-Wl,-soname,lib' + name + '.so',
             '-o', 'lib' + name + '.so'])
    successes = 0
    for bits in itertools.product((False, True), repeat=3):
        flags = [flag for flag, enabled in zip(FLAGS, bits) if enabled]
        run([compiler, *flags, 'subject.ssa', 'subject.s'])
        run([cc, '-fPIC', '-c', 'subject.s', '-o', 'subject.o'])
        run([cc, '-shared', 'subject.o', '-Wl,--no-relax', '-L.', '-Wl,--no-as-needed',
             '-lprovider', '-Wl,-rpath,$ORIGIN', '-o', 'libsubject.so'])
        reloc = run([readelf, '-rW', 'libsubject.so']).stdout
        if not any('R_X86_64_GLOB_DAT' in line and re.search(r'\bn11_vlist\b', line)
                   for line in reloc.splitlines()):
            raise RuntimeError('missing dynamic GOT relocation for n11_vlist')
        for pie in (False, True):
            mode = ['-fPIE', '-pie'] if pie else ['-fno-pie', '-no-pie']
            run([cc, '-std=c11', '-O2', '-Wall', '-Wextra', '-Werror', *mode,
                 'client.c', '-L.', '-Wl,--no-as-needed', '-lsubject', '-lprovider',
                 '-Wl,-rpath,$ORIGIN', '-Wl,-rpath-link,.', '-ldl', '-o', 'client'])
            for binary in ('libprovider.so', 'liboverride.so', 'libsubject.so', 'client'):
                if 'R_X86_64_COPY' in run([readelf, '-rW', binary]).stdout:
                    raise RuntimeError(f'COPY relocation invalidates oracle: {binary}')
                dynamic = run([readelf, '-dW', binary]).stdout
                if 'TEXTREL' in dynamic or 'SYMBOLIC' in dynamic:
                    raise RuntimeError(f'TEXTREL or SYMBOLIC invalidates oracle: {binary}')
            preload = {**clean, 'LD_PRELOAD': str(d / 'liboverride.so')}
            for marker, env in (('1', clean), ('2', preload)):
                p = run(['./client', marker], env)
                if 'guarded varargs checks passed' not in p.stdout:
                    raise RuntimeError('client success marker missing')
                successes += 1
            # A valid loaded program with a deliberately wrong expected provider
            # must fail its identity assertion; this does not mutate descriptors.
            p = run(['./client', '1'], preload, expect_success=False)
            if p.returncode == 0 or 'provider_marker() == expected' not in p.stderr:
                raise RuntimeError('wrong-provider negative control not detected')
    if successes != 32:
        raise RuntimeError(f'wrong invocation count: {successes}')
    print('32 scalar GOT vaarg/vastart runtime invocations passed; 16 provider-identity negative controls detected')


if __name__ == '__main__':
    main()
