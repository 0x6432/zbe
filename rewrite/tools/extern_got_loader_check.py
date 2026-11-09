#!/usr/bin/env python3
"""Focused Linux x86-64 ELF extern/GOT loader check, not ledger certification.

Run with --compiler and a NEW --evidence-dir. The script serializes itself using
/data/zbe-coordination/full-verification.lock, caps inherited CPU affinity to two
and virtual address space to 4 GiB. --full selects the three optimization flags;
without it the default compiler configuration is tested. Evidence is retained.
Uses GCC/GNU binutils and the startup loader, not dlopen or dlsym. Unsupported
linker behavior fails closed. The ordinary-LEA shared-link negative is recorded,
not misrepresented as a runtime control if GNU ld rejects it.
"""
import argparse
import fcntl
import hashlib
import json
import os
from pathlib import Path
import platform
import re
import resource
import shutil
import subprocess
import sys
import time

IL = '''export function l $subject_data() {
@entry
ret extern $external_data
}
export function l $subject_read() {
@entry
%p =l add extern $external_data, 8
%v =l loadl %p
ret %v
}
export function $subject_write(l %v) {
@entry
%p =l add extern $external_data, 8
storel %v, %p
ret
}
export function l $subject_fn() {
@entry
ret extern $external_fn
}
export function l $subject_call(l %v) {
@entry
%r =l call extern $external_fn(l %v)
ret %r
}
'''
PROVIDER = '''#include <stdint.h>
struct datum { uint64_t lo, value, hi; };
struct datum external_data = { 0x123456789abcdef0ULL, BASE, 0xfedcba9876543210ULL };
uint64_t external_fn(uint64_t x) { return x + BASE; }
'''
ORACLE = '''#include <stdint.h>
struct datum { uint64_t lo, value, hi; };
extern struct datum external_data;
extern uint64_t external_fn(uint64_t);
struct datum *oracle_data(void) { return &external_data; }
uint64_t (*oracle_fn(void))(uint64_t) { return external_fn; }
uint64_t oracle_call(uint64_t x) { return external_fn(x); }
'''
SLOT = '''.text
.globl oracle_slot
.type oracle_slot,@function
oracle_slot:
 leaq external_data@GOTPCREL(%rip), %rax
 ret
.section .note.GNU-stack,"",@progbits
'''
MAIN = '''#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
struct datum { uint64_t lo, value, hi; };
extern struct datum *oracle_data(void);
extern void *oracle_slot(void);
extern uint64_t (*oracle_fn(void))(uint64_t), oracle_call(uint64_t);
extern uintptr_t subject_data(void), subject_fn(void);
extern uint64_t subject_read(void), subject_call(uint64_t);
extern void subject_write(uint64_t);
#define CHECK(c,n) do { if (!(c)) { printf("check %d failed\\n",n); return n; } } while (0)
int main(int argc, char **argv) {
 CHECK(argc==2,30);
 uint64_t expected=strtoull(argv[1],0,10);
 struct datum *p=oracle_data();
 CHECK(p && subject_data()==(uintptr_t)p,31);
 CHECK((void*)p != oracle_slot(),32);
 CHECK(p->lo==0x123456789abcdef0ULL && p->hi==0xfedcba9876543210ULL,33);
 CHECK(p->value==expected && subject_read()==expected,34);
 uint64_t (*f)(uint64_t)=oracle_fn();
 CHECK(f && subject_fn()==(uintptr_t)f,35);
 CHECK(f(17)==expected+17 && oracle_call(17)==expected+17 && subject_call(17)==expected+17,36);
 subject_write(expected+77);
 CHECK(p->value==expected+77 && subject_read()==expected+77,37);
 CHECK(p->lo==0x123456789abcdef0ULL && p->hi==0xfedcba9876543210ULL,38);
 p->value=expected+99;
 CHECK(subject_read()==expected+99,39);
 printf("binding=%llu data=%p slot=%p function=%p checks=9\\n", (unsigned long long)expected,(void*)p,oracle_slot(),(void*)(uintptr_t)f);
 return 0;
}
'''
LOCAL = '''.data
.hidden local_data
.globl local_data
.type local_data,@object
.size local_data,8
local_data: .quad 123
.text
.globl local_get
.type local_get,@function
local_get:
 movq local_data@GOTPCREL(%rip), %rax
 ret
.section .note.GNU-stack,"",@progbits
'''
LOCAL_MAIN = '''#include <stdint.h>
extern const uint64_t *local_get(void);
int main(void) { const uint64_t *p = local_get(); return !p || *p != 123; }
'''


def sha(path):
    h = hashlib.sha256()
    with open(path, 'rb') as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b''):
            h.update(chunk)
    return h.hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--compiler', type=Path, required=True)
    parser.add_argument('--evidence-dir', type=Path, required=True, help='new directory; retained even on failure')
    parser.add_argument('--cc', default='gcc')
    parser.add_argument('--full', action='store_true', help='enable all three compiler optimizations')
    args = parser.parse_args()
    if platform.system() != 'Linux' or platform.machine() not in ('x86_64', 'amd64'):
        parser.error('requires Linux x86-64 ELF')
    compiler = args.compiler.resolve(strict=True)
    tools = {name: Path(shutil.which(name) or '').resolve(strict=True) for name in (args.cc, 'readelf', 'objdump', 'as', 'ld.bfd')}
    d = args.evidence_dir.absolute()
    d.mkdir(parents=False, exist_ok=False)
    # Do not propagate loader overrides or log arbitrary potentially secret environment.
    env = {k: v for k, v in os.environ.items() if not k.startswith('LD_')}
    env['LC_ALL'] = 'C'
    os.sched_setaffinity(0, sorted(os.sched_getaffinity(0))[:2])
    cap = 4 * 1024**3
    soft, hard = resource.getrlimit(resource.RLIMIT_AS)
    cap = min(cap, hard) if hard != resource.RLIM_INFINITY else cap
    cap = min(cap, soft) if soft != resource.RLIM_INFINITY else cap
    resource.setrlimit(resource.RLIMIT_AS, (cap, hard))
    resource.setrlimit(resource.RLIMIT_CORE, (0, 0))
    record = {'scope': 'focused loader test; not L/K ledger approval', 'commands': [], 'tools': {},
              'compiler': {'path': str(compiler), 'sha256': sha(compiler)}, 'affinity': sorted(os.sched_getaffinity(0)),
              'address_space_limit': cap, 'options': 'full' if args.full else 'default'}
    def run(argv, *, expect=0, extra_env=None):
        argv = [str(x) for x in argv]
        e = dict(env)
        if extra_env:
            e.update(extra_env)
        try:
            p = subprocess.run(argv, cwd=d, env=e, capture_output=True, text=True, errors='replace', timeout=60)
            entry = {'argv': argv, 'env_override': extra_env or {}, 'exit': p.returncode, 'stdout': p.stdout, 'stderr': p.stderr}
        except subprocess.TimeoutExpired as exc:
            entry = {'argv': argv, 'timeout_seconds': 60, 'stdout': str(exc.stdout), 'stderr': str(exc.stderr)}
            record['commands'].append(entry)
            raise RuntimeError('command timed out: ' + repr(argv)) from exc
        record['commands'].append(entry)
        if expect is not None and p.returncode != expect:
            raise RuntimeError(f'{argv!r}: expected exit {expect}, got {p.returncode}: {p.stderr}')
        return p
    def write(name, text):
        (d / name).write_text(text)
    def inspect(path, dynamic=False):
        r = run([tools['readelf'], '-rW', path]).stdout
        s = run([tools['readelf'], '-sW', path]).stdout
        if re.search(r'R_X86_64_COPY\b', r):
            raise RuntimeError(f'COPY relocation: {path}')
        if dynamic:
            dy = run([tools['readelf'], '-dW', path]).stdout
            if 'TEXTREL' in dy:
                raise RuntimeError(f'TEXTREL: {path}')
            if re.search(r'\(SYMBOLIC\)|\(FLAGS\).*SYMBOLIC', dy):
                raise RuntimeError(f'symbolic binding: {path}')
        return r, s
    lock = open('/data/zbe-coordination/full-verification.lock', 'a')
    start = time.monotonic()
    try:
        while True:
            try:
                fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
                break
            except BlockingIOError:
                if time.monotonic() - start > 600:
                    raise RuntimeError('shared verification lock timed out')
                time.sleep(1)
        for name, path in tools.items():
            p = run([path, '--version'])
            record['tools'][name] = {'path': str(path), 'sha256': sha(path), 'version': p.stdout.splitlines()[0]}
        record['gcc_target'] = run([tools[args.cc], '-dumpmachine']).stdout.strip()
        run([tools[args.cc], '-fuse-ld=bfd', '-###', '-shared', '-x', 'c', '/dev/null', '-o', 'probe.so'])
        for name, text in [('subject.ssa', IL), ('provider.c', PROVIDER), ('oracle.c', ORACLE), ('slot.s', SLOT), ('main.c', MAIN), ('local.s', LOCAL), ('local-main.c', LOCAL_MAIN)]:
            write(name, text)
        cc = tools[args.cc]
        common = [cc, '-fuse-ld=bfd']
        flags = ['--fold-integers', '--reuse-stack-homes', '--callee-saved-homes'] if args.full else []
        run([compiler, *flags, 'subject.ssa', 'subject.s'])
        asm = (d / 'subject.s').read_text()
        for sym in ('external_data', 'external_fn'):
            if not re.search(r'\bmovq\s+' + sym + r'@GOTPCREL', asm):
                raise RuntimeError('missing 64-bit GOT load: ' + sym)
        for base, name in [(10, 'provider'), (200, 'override')]:
            run([cc, '-fPIC', '-Wall', '-Wextra', '-Werror', '-DBASE='+str(base), '-c', 'provider.c', '-o', name+'.o'])
            run([*common, '-shared', name+'.o', '-Wl,-soname,lib'+name+'.so', '-o', 'lib'+name+'.so'])
        run([cc, '-fPIC', '-Wall', '-Wextra', '-Werror', '-c', 'oracle.c', '-o', 'oracle.o'])
        for name in ('slot', 'local', 'subject'):
            run([cc, '-fPIC', '-c', name+'.s', '-o', name+'.o'])
        for mode, compile_flags in [('pie', ['-fPIE']), ('nonpie', ['-fno-pie'])]:
            run([cc, *compile_flags, '-Wall', '-Wextra', '-Werror', '-c', 'main.c', '-o', 'main-'+mode+'.o'])
        run([cc, '-fPIE', '-Wall', '-Wextra', '-Werror', '-c', 'local-main.c', '-o', 'local-main.o'])
        run([*common, '-shared', 'oracle.o', 'slot.o', '-L.', '-Wl,--no-as-needed', '-lprovider', '-Wl,-rpath,$ORIGIN', '-o', 'liboracle.so'])
        for name in ('provider.o', 'override.o', 'oracle.o', 'slot.o', 'local.o', 'subject.o', 'main-pie.o', 'main-nonpie.o', 'local-main.o'):
            inspect(name)
        for name in ('libprovider.so', 'liboverride.so', 'liboracle.so'):
            relocations, symbols = inspect(name, True)
            if name != 'liboracle.so':
                for symbol, typ in [('external_data', 'OBJECT'), ('external_fn', 'FUNC')]:
                    if not re.search(r'\b'+typ+r'\s+GLOBAL\s+DEFAULT\s+\d+\s+'+symbol+r'\b', symbols):
                        raise RuntimeError(f'missing global default definition {symbol} in {name}')
            else:
                for symbol in ('external_data', 'external_fn'):
                    if not re.search(r'R_X86_64_GLOB_DAT\s+\S+\s+'+symbol+r'\b', relocations):
                        raise RuntimeError(f'missing oracle GLOB_DAT: {symbol}')
                    if not re.search(r'\bGLOBAL\s+DEFAULT\s+UND\s+'+symbol+r'\b', symbols):
                        raise RuntimeError(f'bad oracle symbol visibility: {symbol}')
        for name in ('external_data', 'external_fn'):
            for obj in ('subject.o', 'oracle.o'):
                rel = run([tools['readelf'], '-rW', obj]).stdout
                if not re.search(r'R_X86_64_(?:REX_)?GOTPCREL(?:X)?\s+\S+\s+'+name+r'\b', rel):
                    raise RuntimeError(f'missing expected object GOT relocation: {obj} {name}')
        # Local-only proof that --no-relax has an actual observable effect.
        for mode, opts in [('no-relax', ['-Wl,--no-relax']), ('relax', [])]:
            run([*common, '-shared', *opts, 'local.o', '-o', 'local-'+mode+'.so'])
            inspect('local-'+mode+'.so', True)
            dis = run([tools['objdump'], '-d', 'local-'+mode+'.so']).stdout
            block = dis.split('<local_get>:', 1)[1].split('\n\n', 1)[0]
            if not re.search(r'\b'+('mov' if mode == 'no-relax' else 'lea')+r'\s+[^\n]*%rax', block):
                raise RuntimeError(f'local {mode} did not show expected instruction: {block}')
            run([*common, '-pie', 'local-main.o', '-L.', '-Wl,--no-as-needed',
                 '-l:local-'+mode+'.so', '-Wl,-rpath,$ORIGIN', '-o', 'check-local-'+mode])
            inspect('check-local-'+mode, True)
            run(['./check-local-'+mode])
        interp = run([tools['readelf'], '-lW', 'check-local-relax']).stdout
        match = re.search(r'Requesting program interpreter:\s*([^\]]+)', interp)
        if not match:
            raise RuntimeError('could not identify ELF interpreter')
        loader = Path(match.group(1)).resolve(strict=True)
        libc_name = run([cc, '-print-file-name=libc.so.6']).stdout.strip()
        libc = Path(libc_name).resolve(strict=True)
        record['loader'] = {'path': str(loader), 'sha256': sha(loader)}
        record['libc'] = {'path': str(libc), 'sha256': sha(libc)}
        total = 0
        for mode, opts in [('no-relax', ['-Wl,--no-relax']), ('relax', [])]:
            subject = 'libsubject-'+mode+'.so'
            run([*common, '-shared', *opts, 'subject.o', '-L.', '-Wl,--no-as-needed', '-lprovider', '-Wl,-rpath,$ORIGIN', '-o', subject])
            rel, syms = inspect(subject, True)
            for symbol in ('external_data', 'external_fn'):
                if not re.search(r'R_X86_64_GLOB_DAT\s+\S+\s+'+symbol+r'\b', rel):
                    raise RuntimeError(f'missing dynamic GLOB_DAT {symbol}: {subject}')
                if not re.search(r'\bGLOBAL\s+DEFAULT\s+UND\s+'+symbol+r'\b', syms):
                    raise RuntimeError(f'bad subject symbol visibility: {symbol}')
            for pie, linkflags in [('pie', ['-pie']), ('nonpie', ['-no-pie'])]:
                for binding in ('provider', 'needed', 'preload'):
                    binary = f'check-{mode}-{pie}-{binding}'
                    libraries = ['-l:libsubject-'+mode+'.so', '-loracle']
                    if binding == 'needed':
                        libraries += ['-loverride']
                    libraries += ['-lprovider']
                    run([*common, *linkflags, 'main-'+pie+'.o', '-L.', '-Wl,--no-as-needed', *libraries, '-Wl,-rpath,$ORIGIN', '-o', binary])
                    inspect(binary, True)
                    dyn = run([tools['readelf'], '-dW', binary]).stdout
                    needed = re.findall(r'\(NEEDED\).*?\[(.*?)\]', dyn)
                    wanted = [subject, 'liboracle.so'] + (['liboverride.so'] if binding == 'needed' else []) + ['libprovider.so']
                    if [n for n in needed if n in wanted] != wanted:
                        raise RuntimeError(f'wrong DT_NEEDED order {binary}: {needed}')
                    ehdr = run([tools['readelf'], '-hW', binary]).stdout
                    if not re.search(r'Type:\s+'+('DYN' if pie == 'pie' else 'EXEC')+r'\b', ehdr):
                        raise RuntimeError('unexpected executable type: '+binary)
                    run(['./'+binary, '10' if binding == 'provider' else '200'], extra_env={'LD_PRELOAD': str(d/'liboverride.so')} if binding == 'preload' else None)
                    total += 1
        # Real emitted load mutated to GOT-slot LEA; use preemption-positive run.
        mutated, n = re.subn(r'\bmovq(\s+external_data@GOTPCREL)', r'leaq\1', asm)
        if not n:
            raise RuntimeError('slot mutation did not match')
        write('slot-mutant.s', mutated)
        run([cc, '-fPIC', '-c', 'slot-mutant.s', '-o', 'slot-mutant.o'])
        run([*common, '-shared', '-Wl,--no-relax', 'slot-mutant.o', '-L.', '-Wl,--no-as-needed', '-lprovider', '-Wl,-rpath,$ORIGIN', '-o', 'libmutant.so'])
        inspect('slot-mutant.o'); inspect('libmutant.so', True)
        run([*common, '-pie', 'main-pie.o', '-L.', '-Wl,--no-as-needed', '-lmutant', '-loracle', '-loverride', '-lprovider', '-Wl,-rpath,$ORIGIN', '-o', 'check-mutant'])
        inspect('check-mutant', True)
        run(['./check-mutant', '200'], expect=31)
        # A PC-relative ordinary-symbol LEA in a shared object is commonly rejected.
        # Preserve its actual link outcome; never call link rejection a runtime witness.
        wrong, n = re.subn(r'\bmovq(\s+external_data)@GOTPCREL', r'leaq\1', asm)
        if not n:
            raise RuntimeError('ordinary LEA mutation did not match')
        write('ordinary-mutant.s', wrong)
        run([cc, '-fPIC', '-c', 'ordinary-mutant.s', '-o', 'ordinary-mutant.o'])
        inspect('ordinary-mutant.o')
        result = run([*common, '-shared', '-Wl,--no-relax', 'ordinary-mutant.o', '-L.', '-Wl,--no-as-needed', '-lprovider', '-Wl,-rpath,$ORIGIN', '-o', 'libordinary.so'], expect=None)
        if result.returncode == 0:
            inspect('libordinary.so', True)
            run([*common, '-pie', 'main-pie.o', '-L.', '-Wl,--no-as-needed', '-lordinary', '-loracle', '-loverride', '-lprovider', '-Wl,-rpath,$ORIGIN', '-o', 'check-ordinary'])
            inspect('check-ordinary', True)
            run(['./check-ordinary', '200'], expect=31)
            record['ordinary_lea_control'] = 'preemption identity rejected at runtime'
        else:
            record['ordinary_lea_control'] = 'shared link rejected; no runtime witness'
        record['result'] = f'{total} loader cases passed; slot-LEA mutant rejected under DT_NEEDED override'
        print(record['result'])
        print('ordinary LEA:', record['ordinary_lea_control'])
        print('evidence:', d)
    except Exception as exc:
        record['error'] = repr(exc)
        raise
    finally:
        record['artifacts'] = {str(p.relative_to(d)): sha(p) for p in sorted(d.iterdir()) if p.is_file() and p.name != 'manifest.json'}
        (d/'manifest.json').write_text(json.dumps(record, indent=2, sort_keys=True)+'\n')
        lock.close()


if __name__ == '__main__':
    try:
        main()
    except Exception as exc:
        print('FAIL:', exc, file=sys.stderr)
        sys.exit(1)
