#!/usr/bin/env python3
"""Bounded N11 operand-site runtime probe for Linux x86-64 ELF.

For local execution follow the repository's verification coordination policy.
Supply an already-built zbe-native with --compiler. Each invocation selects one
option combination and client mode, not the full N11 bundle. Uses a shared nonblocking
verification lock. Builds two independent C provider DSOs, one IL subject DSO,
and a separate C client in a fresh temporary directory; runs normal and preload
bindings. It does not implement or certify N11/U05, or execute allocation-size, cover every call-argument/ENV/vaarg case,
or implement the complete N11 matrix.
"""
import argparse
from contextlib import ExitStack
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
import tempfile

IL = '''type :N11Pair = { l 2 }
export function l $site_dot() {
@entry
ret extern $n11.dot
}
export function l $site_dot_quoted() {
@entry
ret extern $"n11\\x2edot"
}
export function l $site_dollar() {
@entry
ret extern $n11$dollar
}
export function l $site_dollar_quoted() {
@entry
ret extern $"n11\\044dollar"
}
export function l $site_fn_address() {
@entry
ret extern $n11.func
}
export function l $site_fn_call(l %x) {
@entry
%p =l copy extern $"n11.func"
%r =l call %p(l %x)
ret %r
}
export function l $site_record_argument() {
@entry
%r =l call extern $n11_record_sink(:N11Pair extern $n11_target)
ret %r
}
export function w $site_branch() {
@entry
jnz extern $n11_target, @yes, @no
@yes
ret 1
@no
ret 0
}
export function w $site_low_word() {
@entry
%p =l copy extern $n11_target
%x =w copy %p
ret %x
}
export function w $site_load_word() {
@entry
%x =w loadw extern $n11_target
ret %x
}
export function s $site_load_single() {
@entry
%x =s loads extern $n11_target
ret %x
}
export function d $site_load_double() {
@entry
%x =d loadd extern $n11_target
ret %x
}
export function l $site_return() {
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
uint64_t n11_dot[2] __asm__("n11.dot") = { MARKER, UINT64_C(0x123456789abcdef0) };
uint64_t n11_dollar[2] __asm__("n11$dollar") = { MARKER, UINT64_C(0xfedcba9876543210) };
struct n11_pair { uint64_t a, b; };
uint64_t n11_record_sink(struct n11_pair x) { return x.a ^ x.b; }
uint64_t n11_func(uint64_t x) __asm__("n11.func");
uint64_t n11_func(uint64_t x) { return x ^ MARKER; }
'''

# The client never directly references either data symbol: dlsym is an
# independent loader oracle, and avoids executable COPY relocations. All
# integer arithmetic is unsigned modulo 2^64; pointer-to-uintptr_t conversion
# is the Linux x86-64 ABI convention under examination, not pointer arithmetic.
CLIENT = r'''#define _GNU_SOURCE
#include <dlfcn.h>
#include <inttypes.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

extern uint64_t site_return(void), site_quote(void), site_copy(void);
extern uint64_t site_record_argument(void);
extern uint32_t site_branch(void), site_low_word(void), site_load_word(void);
extern float site_load_single(void);
extern double site_load_double(void);
extern uint64_t site_dot(void), site_dot_quoted(void), site_dollar(void), site_dollar_quoted(void);
extern uint64_t site_fn_address(void), site_fn_call(uint64_t);
extern uint64_t site_phi(uint32_t), site_sub_left(uint64_t), site_sub_right(uint64_t);
extern uint32_t site_equal_left(uint64_t), site_equal_right(uint64_t);
extern uint64_t site_load(void);
extern void site_store_value(uint64_t *), site_store_address(uint64_t);
extern void site_blit_source(void *), site_blit_destination(const void *);

#define CHECK(x) do { if (!(x)) { printf("FAIL line %d: %s\n", __LINE__, #x); return 1; } } while (0)
struct guarded { uint64_t before, value, after; };
int main(int argc, char **argv) {
    CHECK(argc == 2);
    char *end = NULL;
    uint64_t marker = strtoull(argv[1], &end, 0);
    CHECK(end && *end == '\0');
    uint64_t *p = dlsym(RTLD_DEFAULT, "n11_target");
    uint64_t *sink = dlsym(RTLD_DEFAULT, "n11_sink");
    CHECK(p && sink && p != sink);
    uint64_t *dot = dlsym(RTLD_DEFAULT, "n11.dot");
    uint64_t *dollar = dlsym(RTLD_DEFAULT, "n11$dollar");
    void *function = dlsym(RTLD_DEFAULT, "n11.func");
    CHECK(dot && dollar && function && dot != dollar);
    CHECK(site_dot() == (uint64_t)(uintptr_t)dot && site_dot_quoted() == (uint64_t)(uintptr_t)dot);
    CHECK(site_dollar() == (uint64_t)(uintptr_t)dollar && site_dollar_quoted() == (uint64_t)(uintptr_t)dollar);
    CHECK(dot[0] == marker && dot[1] == UINT64_C(0x123456789abcdef0));
    CHECK(dollar[0] == marker && dollar[1] == UINT64_C(0xfedcba9876543210));
    CHECK(site_fn_address() == (uint64_t)(uintptr_t)function);
    CHECK(site_fn_call(UINT64_C(0x55667788)) == (UINT64_C(0x55667788) ^ marker));
    CHECK(p[0] == marker && p[1] == UINT64_C(0x39485766758493a2));
    CHECK(sink[0] == UINT64_C(0x9182736455463728));
    CHECK(sink[1] == UINT64_C(0xabcdef0123456789));
    const uint64_t addr = (uint64_t)(uintptr_t)p;
    CHECK(site_record_argument() == (marker ^ UINT64_C(0x39485766758493a2)));
    CHECK(site_branch() == ((uint32_t)addr != 0));
    CHECK(site_low_word() == (uint32_t)addr);
    uint32_t word_bits, single_bits;
    uint64_t double_bits;
    memcpy(&word_bits, p, sizeof word_bits);
    float single_value = site_load_single();
    double double_value = site_load_double();
    memcpy(&single_bits, &single_value, sizeof single_bits);
    memcpy(&double_bits, &double_value, sizeof double_bits);
    CHECK(site_load_word() == word_bits && single_bits == word_bits && double_bits == marker);
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
    for option in ('fold-integers', 'reuse-stack-homes', 'callee-saved-homes'):
        parser.add_argument('--' + option, action='store_true')
    parser.add_argument('--non-pie', action='store_true', help='build non-PIE client')
    parser.add_argument('--evidence-dir', type=Path, help='new directory for retained evidence')
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
        with ExitStack() as stack:
            if args.evidence_dir:
                args.evidence_dir.mkdir(parents=True, exist_ok=False)
                d = args.evidence_dir.resolve()
            else:
                d = Path(stack.enter_context(tempfile.TemporaryDirectory(prefix='zbe-n11-sites-')))
            hashes = {'compiler': hashlib.sha256(compiler.read_bytes()).hexdigest(),
                      'script': hashlib.sha256(Path(__file__).read_bytes()).hexdigest()}
            (d / 'sha256.json').write_text(json.dumps(hashes, indent=2) + '\n')
            for name, text in (('subject.ssa', IL), ('provider.c', PROVIDER), ('client.c', CLIENT)):
                (d / name).write_text(text, encoding='utf-8')

            def run(argv, env=None):
                argv = [str(x) for x in argv]
                try:
                    p = subprocess.run(argv, cwd=d, env=clean if env is None else env,
                                       capture_output=True, text=True, errors='replace', timeout=60)
                except subprocess.TimeoutExpired as exc:
                    with (d / 'commands.jsonl').open('a') as journal:
                        journal.write(json.dumps({'argv': argv, 'env': clean if env is None else env,
                                                  'timeout': str(exc)}) + '\n')
                    raise
                record = {'argv': argv, 'env': clean if env is None else env,
                          'exit': p.returncode, 'stdout': p.stdout, 'stderr': p.stderr}
                with (d / 'commands.jsonl').open('a') as journal:
                    journal.write(json.dumps(record) + '\n')
                if p.returncode:
                    raise RuntimeError(f'{argv!r}: exit {p.returncode}\n{p.stdout}\n{p.stderr}')
                return p.stdout

            options = ('fold-integers', 'reuse-stack-homes', 'callee-saved-homes')
            flags = ['--' + opt for opt in options if args.full or getattr(args, opt.replace('-', '_'))]
            run([compiler, *flags, 'subject.ssa', 'subject.s'])
            for name, marker in (('provider', '0x1020304050607080ULL'), ('override', '0x8877665544332211ULL')):
                run([cc, '-std=c11', '-Wall', '-Wextra', '-Werror', '-fPIC', '-DMARKER=' + marker,
                     '-c', 'provider.c', '-o', name + '.o'])
                run([cc, '-shared', name + '.o', '-Wl,-soname,lib' + name + '.so', '-o', 'lib' + name + '.so'])
            run([cc, '-fPIC', '-c', 'subject.s', '-o', 'subject.o'])
            run([cc, '-shared', 'subject.o', '-Wl,--no-relax', '-L.', '-Wl,--no-as-needed',
                 '-lprovider', '-Wl,-rpath,$ORIGIN', '-o', 'libsubject.so'])
            compile_mode = '-fno-pie' if args.non_pie else '-fPIE'
            link_mode = '-no-pie' if args.non_pie else '-pie'
            run([cc, '-std=c11', '-Wall', '-Wextra', '-Werror', compile_mode, '-c', 'client.c', '-o', 'client.o'])
            run([cc, link_mode, 'client.o', '-L.', '-Wl,--no-as-needed', '-lsubject',
                 '-Wl,-rpath,$ORIGIN', '-Wl,-rpath-link,.', '-ldl', '-o', 'client'])

            reloc = run([readelf, '-rW', 'libsubject.so'])
            for symbol in ('n11_target', 'n11_sink', 'n11.dot', 'n11$dollar', 'n11.func', 'n11_record_sink'):
                if not any('R_X86_64_GLOB_DAT' in line and re.search(r'(?<![A-Za-z0-9_.$])' + re.escape(symbol) + r'(?![A-Za-z0-9_.$])', line)
                           for line in reloc.splitlines()):
                    raise RuntimeError(f'missing dynamic GOT relocation for {symbol}')
            for binary in ('libprovider.so', 'liboverride.so', 'libsubject.so', 'client'):
                if 'R_X86_64_COPY' in run([readelf, '-rW', binary]):
                    raise RuntimeError(f'COPY relocation invalidates binding oracle: {binary}')
                dynamic = run([readelf, '-dW', binary])
                if 'TEXTREL' in dynamic or 'SYMBOLIC' in dynamic:
                    raise RuntimeError(f'TEXTREL or SYMBOLIC in {binary}')
            run(['./client', '0x1020304050607080'])
            run(['./client', '0x8877665544332211'], env={**clean, 'LD_PRELOAD': str(d / 'liboverride.so')})

            # Branch-only control: invert the branch on the loaded address's
            # low word. This is safe regardless of whether those bits are zero.
            asm = (d / 'subject.s').read_text(encoding='utf-8')
            begin = asm.index('site_branch:\n')
            end = asm.index('.size site_branch,', begin)
            body = asm[begin:end]
            mutant_body, count = re.subn(r'(\ttestl %eax, %eax\n)\tjne ', r'\1\tje ', body)
            if count != 1:
                raise RuntimeError('branch inversion did not match exactly once')
            (d / 'branch-mutant.s').write_text(asm[:begin] + mutant_body + asm[end:], encoding='utf-8')
            run([cc, '-fPIC', '-c', 'branch-mutant.s', '-o', 'branch-mutant.o'])
            run([cc, '-shared', 'branch-mutant.o', '-Wl,--no-relax', '-L.', '-Wl,--no-as-needed',
                 '-lprovider', '-Wl,-rpath,$ORIGIN', '-o', 'libsubject.so'])
            control = subprocess.run(['./client', '0x1020304050607080'], cwd=d, env=clean,
                                     capture_output=True, text=True, errors='replace', timeout=60)
            with (d / 'commands.jsonl').open('a') as journal:
                journal.write(json.dumps({'argv': ['./client', '0x1020304050607080'], 'env': clean,
                                          'exit': control.returncode, 'stdout': control.stdout,
                                          'stderr': control.stderr, 'control': 'branch-inversion'}) + '\n')
            if control.returncode != 1 or 'site_branch() ==' not in control.stdout:
                raise RuntimeError(f'branch inversion control not detected: {control.returncode}\n'
                                   f'{control.stdout}\n{control.stderr}')

            # Slot-address negative control: corrupt only the punctuation-name
            # address calculation. Client compares it before dereferencing it.
            asm = (d / 'subject.s').read_text(encoding='utf-8')
            mutant, count = re.subn(r'\bmovq(\s+n11\.dot@GOTPCREL)', r'leaq\1', asm)
            if count < 1:
                raise RuntimeError('punctuation slot-address mutation did not match')
            (d / 'mutant.s').write_text(mutant, encoding='utf-8')
            run([cc, '-fPIC', '-c', 'mutant.s', '-o', 'mutant.o'])
            run([cc, '-shared', 'mutant.o', '-Wl,--no-relax', '-L.', '-Wl,--no-as-needed',
                 '-lprovider', '-Wl,-rpath,$ORIGIN', '-o', 'libsubject.so'])
            control = subprocess.run(['./client', '0x1020304050607080'], cwd=d, env=clean,
                                     capture_output=True, text=True, errors='replace', timeout=60)
            with (d / 'commands.jsonl').open('a') as journal:
                journal.write(json.dumps({'argv': ['./client', '0x1020304050607080'], 'env': clean,
                                          'exit': control.returncode, 'stdout': control.stdout,
                                          'stderr': control.stderr, 'control': 'slot-address'}) + '\n')
            if control.returncode == 0 or 'site_dot() ==' not in control.stdout:
                raise RuntimeError(f'punctuation slot control not detected: {control.returncode}\n'
                                   f'{control.stdout}\n{control.stderr}')
            print(f'bounded N11 subset passed: normal + LD_PRELOAD; flags={flags!r}, non-pie={args.non_pie}; slot and branch controls rejected')


if __name__ == '__main__':
    main()
