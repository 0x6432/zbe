#!/usr/bin/env python3
"""Unverified, bounded N11 operand-site runtime probe for Linux x86-64 ELF.

Run only after hosted CI is inactive and local execution is authorized. Supply
an already-built zbe-native with --compiler. Default and --full are individual
configurations, not the N11 all-options/PIE matrix. Uses a shared nonblocking
verification lock. Builds two independent C provider DSOs, one IL subject DSO,
and a separate C client in a fresh temporary directory; runs normal and preload
bindings. It does not implement or certify N11/U05, or run allocation-size,
call/ENV/vaarg, function-address, or punctuation-name cases.
"""
import argparse
import fcntl
import os
from pathlib import Path
import platform
import re
import resource
import shutil
import subprocess
import tempfile

IL = '''export function l $site_return() {
@entry
ret extern $n11_target
}
export function l $site_quote() {
@entry
ret extern $"n11_target"
}
export function l $site_copy() {
@entry
%x =l copy extern $n11_target
ret %x
}
export function l $site_phi(w %c) {
@entry
jnz %c, @left, @right
@left
jmp @join
@right
jmp @join
@join
%x =l phi @left 7, @right extern $n11_target
ret %x
}
export function l $site_sub_left(l %v) {
@entry
%x =l sub extern $n11_target, %v
ret %x
}
export function l $site_sub_right(l %v) {
@entry
%x =l sub %v, extern $n11_target
ret %x
}
export function w $site_equal_left(l %v) {
@entry
%x =w ceql extern $n11_target, %v
ret %x
}
export function w $site_equal_right(l %v) {
@entry
%x =w ceql %v, extern $n11_target
ret %x
}
export function l $site_load() {
@entry
%x =l loadl extern $n11_target
ret %x
}
export function $site_store_value(l %p) {
@entry
storel extern $n11_target, %p
ret
}
export function $site_store_address(l %v) {
@entry
storel %v, extern $n11_target
ret
}
export function $site_blit_source(l %p) {
@entry
blit extern $n11_target, %p, 8
ret
}
export function $site_blit_destination(l %p) {
@entry
blit %p, extern $n11_sink, 8
ret
}
'''

# Each external symbol is a real writable, naturally aligned 16-byte object.
# Native operations touch exactly its first eight bytes; the second eight are a
# canary. Both providers use identical types/layouts and different markers.
PROVIDER = '''#include <stdint.h>
uint64_t n11_target[2] = { MARKER, UINT64_C(0x39485766758493a2) };
uint64_t n11_sink[2] = { UINT64_C(0x9182736455463728), UINT64_C(0xabcdef0123456789) };
'''

# The client never directly references either data symbol: dlsym is an
# independent loader oracle, and avoids executable COPY relocations. All
# integer arithmetic is unsigned modulo 2^64; pointer-to-uintptr_t conversion
# is the Linux x86-64 ABI convention under examination, not pointer arithmetic.
CLIENT = r'''#include <dlfcn.h>
#include <inttypes.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

extern uint64_t site_return(void), site_quote(void), site_copy(void);
extern uint64_t site_phi(uint32_t), site_sub_left(uint64_t), site_sub_right(uint64_t);
extern uint32_t site_equal_left(uint64_t), site_equal_right(uint64_t);
extern uint64_t site_load(void);
extern void site_store_value(uint64_t *), site_store_address(uint64_t);
extern void site_blit_source(void *), site_blit_destination(const void *);

#define CHECK(x) do { if (!(x)) { fprintf(stderr, "FAIL line %d: %s\n", __LINE__, #x); return 1; } } while (0)
struct guarded { uint64_t before, value, after; };
int main(int argc, char **argv) {
    CHECK(argc == 2);
    char *end = NULL;
    uint64_t marker = strtoull(argv[1], &end, 0);
    CHECK(end && *end == '\0');
    uint64_t *p = dlsym(RTLD_DEFAULT, "n11_target");
    uint64_t *sink = dlsym(RTLD_DEFAULT, "n11_sink");
    CHECK(p && sink && p != sink);
    CHECK(p[0] == marker && p[1] == UINT64_C(0x39485766758493a2));
    CHECK(sink[0] == UINT64_C(0x9182736455463728));
    CHECK(sink[1] == UINT64_C(0xabcdef0123456789));
    const uint64_t addr = (uint64_t)(uintptr_t)p;
    CHECK(site_return() == addr);
    CHECK(site_quote() == addr);
    CHECK(site_copy() == addr);
    CHECK(site_phi(0) == addr && site_phi(1) == 7);
    const uint64_t v = UINT64_C(0xfedcba9876543210);
    CHECK(site_sub_left(v) == addr - v);
    CHECK(site_sub_right(v) == v - addr);
    CHECK(site_equal_left(addr) == 1 && site_equal_left(addr ^ UINT64_C(1)) == 0);
    CHECK(site_equal_right(addr) == 1 && site_equal_right(addr ^ UINT64_C(1)) == 0);
    CHECK(site_load() == marker);

    struct guarded out = { UINT64_C(0x1122334455667788), 0, UINT64_C(0x8877665544332211) };
    site_store_value(&out.value);
    CHECK(out.value == addr);
    CHECK(out.before == UINT64_C(0x1122334455667788) && out.after == UINT64_C(0x8877665544332211));

    struct guarded copied = { UINT64_C(0x1029384756abcdef), 0, UINT64_C(0xfedcba6547382910) };
    unsigned char expected[8];
    memcpy(expected, p, sizeof expected);
    site_blit_source(&copied.value);
    CHECK(memcmp(&copied.value, expected, sizeof expected) == 0);
    CHECK(copied.before == UINT64_C(0x1029384756abcdef) && copied.after == UINT64_C(0xfedcba6547382910));
    CHECK(p[0] == marker && p[1] == UINT64_C(0x39485766758493a2));

    struct guarded input = { UINT64_C(0x123456789abcdef0), UINT64_C(0x76543210fedcba98), UINT64_C(0x0fedcba987654321) };
    memcpy(expected, &input.value, sizeof expected);
    site_blit_destination(&input.value);
    CHECK(memcmp(sink, expected, sizeof expected) == 0);
    CHECK(sink[1] == UINT64_C(0xabcdef0123456789));
    CHECK(input.before == UINT64_C(0x123456789abcdef0) && input.value == UINT64_C(0x76543210fedcba98) && input.after == UINT64_C(0x0fedcba987654321));

    site_store_address(UINT64_C(0x3141592653589793));
    CHECK(p[0] == UINT64_C(0x3141592653589793));
    CHECK(p[1] == UINT64_C(0x39485766758493a2));
    CHECK(site_load() == UINT64_C(0x3141592653589793));
    puts("bounded operand-site checks passed");
    return 0;
}
'''


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--compiler', type=Path, required=True, help='already-built zbe-native')
    parser.add_argument('--cc', default='cc', help='C compiler with GNU-compatible ELF linker')
    parser.add_argument('--readelf', default='readelf')
    parser.add_argument('--lock', type=Path, default=Path('/data/zbe-coordination/full-verification.lock'))
    parser.add_argument('--full', action='store_true', help='enable all three existing optimization flags')
    args = parser.parse_args()
    if platform.system() != 'Linux' or platform.machine() not in ('x86_64', 'amd64'):
        parser.error('Linux x86-64 ELF required')
    compiler = args.compiler.resolve(strict=True)
    cc = shutil.which(args.cc)
    readelf = shutil.which(args.readelf)
    if cc is None or readelf is None:
        parser.error('C compiler and readelf are required')
    # Never inherit LD_PRELOAD, LD_LIBRARY_PATH, compiler injection variables,
    # or credentials. The preload for the second run is explicitly supplied.
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
        with tempfile.TemporaryDirectory(prefix='zbe-n11-sites-') as tmp:
            d = Path(tmp)
            for name, text in (('subject.ssa', IL), ('provider.c', PROVIDER), ('client.c', CLIENT)):
                (d / name).write_text(text, encoding='utf-8')

            def run(argv, env=None):
                argv = [str(x) for x in argv]
                p = subprocess.run(argv, cwd=d, env=clean if env is None else env,
                                   capture_output=True, text=True, errors='replace', timeout=60)
                if p.returncode:
                    raise RuntimeError(f'{argv!r}: exit {p.returncode}\n{p.stdout}\n{p.stderr}')
                return p.stdout

            flags = ['--fold-integers', '--reuse-stack-homes', '--callee-saved-homes'] if args.full else []
            run([compiler, *flags, 'subject.ssa', 'subject.s'])
            for name, marker in (('provider', '0x1020304050607080ULL'), ('override', '0x8877665544332211ULL')):
                run([cc, '-std=c11', '-Wall', '-Wextra', '-Werror', '-fPIC', '-DMARKER=' + marker,
                     '-c', 'provider.c', '-o', name + '.o'])
                run([cc, '-shared', name + '.o', '-Wl,-soname,lib' + name + '.so', '-o', 'lib' + name + '.so'])
            run([cc, '-fPIC', '-c', 'subject.s', '-o', 'subject.o'])
            run([cc, '-shared', 'subject.o', '-Wl,--no-relax', '-L.', '-Wl,--no-as-needed',
                 '-lprovider', '-Wl,-rpath,$ORIGIN', '-o', 'libsubject.so'])
            run([cc, '-std=c11', '-Wall', '-Wextra', '-Werror', '-fPIE', '-c', 'client.c', '-o', 'client.o'])
            run([cc, '-pie', 'client.o', '-L.', '-Wl,--no-as-needed', '-lsubject',
                 '-Wl,-rpath,$ORIGIN', '-Wl,-rpath-link,.', '-ldl', '-o', 'client'])

            reloc = run([readelf, '-rW', 'libsubject.so'])
            for symbol in ('n11_target', 'n11_sink'):
                if not any('R_X86_64_GLOB_DAT' in line and re.search(r'\b' + symbol + r'\b', line)
                           for line in reloc.splitlines()):
                    raise RuntimeError(f'missing dynamic GOT relocation for {symbol}')
            for binary in ('libsubject.so', 'client'):
                if 'R_X86_64_COPY' in run([readelf, '-rW', binary]):
                    raise RuntimeError(f'COPY relocation invalidates binding oracle: {binary}')
                if 'TEXTREL' in run([readelf, '-dW', binary]):
                    raise RuntimeError(f'TEXTREL in {binary}')
            run(['./client', '0x1020304050607080'])
            run(['./client', '0x8877665544332211'], env={**clean, 'LD_PRELOAD': str(d / 'liboverride.so')})
            print('bounded N11 subset passed: normal + LD_PRELOAD; ' + ('full' if args.full else 'default') + ' options')


if __name__ == '__main__':
    main()
