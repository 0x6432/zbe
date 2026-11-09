#!/usr/bin/env python3
"""Focused Linux AMD64 N12/N13/N14 scheduling witnesses, not ledger coverage.

Run only when the shared verification/CI policy permits. One invocation uses one
explicit compiler-option combination. The caller supplies a genuine object as
ENV; assembly checks its address without dereferencing an invalid value. C PIC
providers independently check all pointers and defined record fields. The source
frontend has no syntax for the API-only direct-GOT wrapper target.
"""
import argparse
import os
from pathlib import Path
import platform
import re
import resource
import subprocess
import tempfile

IL = r'''type :Big = { l 3 }
type :Mix = { l, d }
export function l $run_scalar(l %env) {
@entry
%r =l call extern $sched_scalar(env %env, l extern $sched_data_a, l 2, l extern $sched_data_b, l 4, l extern $sched_data_a, l 6, l extern $sched_data_b)
ret %r
}
export function l $run_computed(l %env) {
@entry
%target =l copy extern $sched_scalar
%r =l call %target(env %env, l extern $sched_data_a, l 2, l extern $sched_data_b, l 4, l extern $sched_data_a, l 6, l extern $sched_data_b)
ret %r
}
export function l $run_var() {
@entry
%r =l call extern $sched_var(l extern $sched_data_a, ..., d d_1.0, d d_2.0)
ret %r
}
export function :Big $run_record(l %env, l %big, l %mix) {
@entry
%r =:Big call extern $sched_record(env %env, :Mix %mix, l extern $sched_data_a, l 2, l extern $sched_data_b, l 4, l 5, l 6, l 7, :Big %big, :Big %big)
ret %r
}
export function l $run_loop(l %env, l %source, w %count) {
@entry
%first =l copy extern $sched_a
%second =l copy extern $sched_b
jmp @loop
@loop
%n =w phi @entry %count, @body %next
%acc =l phi @entry 0, @body %sum
%target =l phi @entry %first, @body %other
%other =l phi @entry %second, @body %target
jnz %n, @body, @done
@body
%pressure =l call extern $sched_clobber(l extern $sched_data_a, l extern $sched_data_b, l 3, l 4, l 5, l 6, l 7)
%wide =l extuw %n
%v =l call %target(env %env, l %source, l extern $sched_data_b, l %wide)
%part =l add %acc, %v
%sum =l add %part, %pressure
%next =w sub %n, 1
jmp @loop
@done
ret %acc
}
function l $recur(env %env, l %target, l %source, w %n) {
@entry
jnz %n, @step, @base
@step
%next =w sub %n, 1
%prior =l call $recur(env %env, l %target, l %source, w %next)
jmp @join
@base
jmp @join
@join
%sum =l phi @step %prior, @base 0
%pressure =l call extern $sched_clobber(l extern $sched_data_a, l extern $sched_data_b, l 3, l 4, l 5, l 6, l 7)
%wide =l extuw %n
%v =l call %target(env %env, l %source, l extern $sched_data_b, l %wide)
%part =l add %sum, %v
%out =l add %part, %pressure
ret %out
}
export function l $run_recur(l %env, l %source, w %n) {
@entry
%target =l copy extern $sched_a
%r =l call $recur(env %env, l %target, l %source, w %n)
ret %r
}
'''

PROVIDER = r'''#include <stdint.h>
#include <stddef.h>
uint64_t sched_env = BASE + 900, sched_data_a = BASE + 901, sched_data_b = BASE + 902;
void *get_env(void) { return &sched_env; }
void *get_source(void) { return &sched_data_a; }
struct big { uint64_t a,b,c; };
struct mix { uint64_t a; double b; };
_Static_assert(sizeof(struct big)==24 && sizeof(struct mix)==16 && offsetof(struct mix,b)==8, "layout");
uint64_t sched_scalar_impl(const uint64_t *a, uint64_t b, const uint64_t *c, uint64_t d,
                           const uint64_t *e, uint64_t f, const uint64_t *g) {
 if (a!=&sched_data_a || b!=2 || c!=&sched_data_b || d!=4 || e!=&sched_data_a || f!=6 || g!=&sched_data_b) return 0;
 return BASE+101;
}
struct big sched_record_impl(struct mix m, const uint64_t *a, uint64_t b, const uint64_t *c,
                             uint64_t d, uint64_t e, uint64_t f, uint64_t g, struct big x, struct big y) {
 if (m.a!=17 || m.b!=3.0 || a!=&sched_data_a || b!=2 || c!=&sched_data_b || d!=4 || e!=5 || f!=6 || g!=7 ||
     x.a!=41 || x.b!=42 || x.c!=43 || y.a!=41 || y.b!=42 || y.c!=43) return (struct big){0,0,0};
 return (struct big){BASE+51, BASE+52, BASE+53};
}
uint64_t sched_a_impl(const uint64_t *a, const uint64_t *b, uint64_t n) {
 return a==&sched_data_a && b==&sched_data_b ? BASE+201+n : 0;
}
uint64_t sched_b_impl(const uint64_t *a, const uint64_t *b, uint64_t n) {
 return a==&sched_data_a && b==&sched_data_b ? BASE+202+n : 0;
}
'''

# ENV is checked against the loader-resolved address, not dereferenced. A bad
# ENV or bad variadic state returns a defined sentinel, rather than crashing.
ASM = r'''.text
.macro env_thunk name, implementation
.globl \name
.type \name,@function
\name:
 movq sched_env@GOTPCREL(%rip), %r10
 cmpq %r10, %rax
 jne .Lbad\@
 jmp \implementation@PLT
.Lbad\@:
 xorl %eax, %eax
 ret
.size \name,.-\name
.endm
env_thunk sched_scalar, sched_scalar_impl
env_thunk sched_a, sched_a_impl
env_thunk sched_b, sched_b_impl
# MEMORY-return error path must return its valid hidden result pointer and fill it.
.globl sched_record
.type sched_record,@function
sched_record:
 movq sched_env@GOTPCREL(%rip), %r10
 cmpq %r10, %rax
 jne .Lrecord_bad
 jmp sched_record_impl@PLT
.Lrecord_bad:
 movq $0, 0(%rdi)
 movq $0, 8(%rdi)
 movq $0, 16(%rdi)
 movq %rdi, %rax
 ret
.size sched_record,.-sched_record
.globl sched_var
.type sched_var,@function
sched_var:
 cmpb $2, %al
 jne .Lvar_bad
 movq sched_data_a@GOTPCREL(%rip), %r10
 cmpq %r10, %rdi
 jne .Lvar_bad
 movq %xmm0, %r10
 movabsq $0x3ff0000000000000, %r11
 cmpq %r11, %r10
 jne .Lvar_bad
 movq %xmm1, %r10
 movabsq $0x4000000000000000, %r11
 cmpq %r11, %r10
 jne .Lvar_bad
 movq $(BASE+701), %rax
 ret
.Lvar_bad:
 xorl %eax, %eax
 ret
.size sched_var,.-sched_var
# Explicit caller-saved clobber creates pressure across the same live list.
.globl sched_clobber
.type sched_clobber,@function
sched_clobber:
 movabsq $0x123456789abcdef0, %r10
 movabsq $0xfedcba9876543210, %r11
 pxor %xmm0, %xmm0
 movl $3, %eax
 ret
.size sched_clobber,.-sched_clobber
# Same scalar ABI as sched_scalar, safe even with a valid ENV and stack args.
.globl sched_wrong
.type sched_wrong,@function
sched_wrong:
 xorl %eax, %eax
 ret
.size sched_wrong,.-sched_wrong
.section .note.GNU-stack,"",@progbits
'''

MAIN = r'''#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
struct big { uint64_t a,b,c; }; struct mix { uint64_t a; double b; };
extern void *get_env(void), *get_source(void);
extern uint64_t run_scalar(void *), run_computed(void *), run_var(void);
extern uint64_t run_loop(void *,void *,uint32_t), run_recur(void *,void *,uint32_t);
extern struct big run_record(void *,const struct big *,const struct mix *);
#define CHECK(x,n) do { if (!(x)) { fprintf(stderr,"assertion %d failed\n",n); return n; } } while (0)
int main(int argc,char **argv) {
 if (argc!=2) return 90;
 uint64_t base=strtoull(argv[1],0,10);
 void *env=get_env(), *source=get_source();
 CHECK(env!=NULL && source!=NULL && env!=source,20);
 CHECK(run_scalar(env)==base+101,21);
 CHECK(run_scalar(source)==0,28);
 CHECK(run_computed(env)==base+101,22);
 CHECK(run_var()==base+701,23);
 struct { uint64_t pre; struct big v; uint64_t post; } big={101,{41,42,43},102};
 struct { uint64_t pre; struct mix v; uint64_t post; } mix={103,{17,3.0},104};
 struct { uint64_t pre; struct big v; uint64_t post; } out={105,{0xa5a5,0xa5a5,0xa5a5},106};
 out.v=run_record(env,&big.v,&mix.v);
 CHECK(out.v.a==base+51 && out.v.b==base+52 && out.v.c==base+53 && out.pre==105 && out.post==106,24);
 struct big bad=run_record(source,&big.v,&mix.v);
 CHECK(bad.a==0 && bad.b==0 && bad.c==0,29);
 CHECK(big.pre==101 && big.post==102 && big.v.a==41 && big.v.b==42 && big.v.c==43 &&
       mix.pre==103 && mix.post==104 && mix.v.a==17 && mix.v.b==3.0,25);
 for (uint32_t count=0; count<=6; ++count) {
  uint64_t want=0;
  for (uint32_t i=0; i<count; ++i) want+=base+(i%2 ? 202 : 201)+(count-i)+3;
  CHECK(run_loop(env,source,count)==want,26);
  want=0;
  for (uint32_t i=0; i<=count; ++i) want+=base+201+i+3;
  CHECK(run_recur(env,source,count)==want,27);
 }
 return 0;
}
'''


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--compiler', type=Path, required=True)
    p.add_argument('--cc', default='cc')
    options = ('fold-integers', 'reuse-stack-homes', 'callee-saved-homes')
    for option in options:
        p.add_argument('--'+option, action='store_true')
    args = p.parse_args()
    if platform.system() != 'Linux' or platform.machine() not in ('x86_64', 'amd64'):
        raise SystemExit('Linux AMD64 required')
    resource.setrlimit(resource.RLIMIT_CORE, (0, 0))
    compiler = args.compiler.resolve(strict=True)
    flags = ['--'+o for o in options if getattr(args, o.replace('-', '_'))]
    with tempfile.TemporaryDirectory(prefix='zbe-got-schedule-') as tmp:
        d = Path(tmp)
        for name, text in (('input.ssa', IL), ('provider.c', PROVIDER), ('provider.S', ASM), ('main.c', MAIN)):
            (d/name).write_text(text)
        clean = {k: os.environ[k] for k in ('PATH', 'HOME', 'TMPDIR') if k in os.environ}
        clean['LC_ALL'] = 'C'
        def run(argv, env=None, expected=0):
            proc = subprocess.run([str(x) for x in argv], cwd=d, env=clean if env is None else env,
                                  capture_output=True, text=True, timeout=90)
            if proc.returncode != expected:
                raise RuntimeError(f'{argv!r}: expected {expected}, got {proc.returncode}; stdout={proc.stdout!r} stderr={proc.stderr!r}')
        run([compiler, *flags, 'input.ssa', 'generated.s'])
        asm = (d/'generated.s').read_text()
        def body(name):
            start = asm.index(name+':\n')
            end = asm.index('.size '+name+',', start)
            return start, end, asm[start:end]
        # Structural controls supplement, not replace, the runtime oracles.
        start, end, scalar = body('run_scalar')
        if not (scalar.rindex('sched_data_b@GOTPCREL') < scalar.index('sched_scalar@GOTPCREL') < scalar.index('call *%r11')):
            raise RuntimeError('dedicated scalar target not after argument GOT loads')
        _, _, computed = body('run_computed')
        if not (computed.index('movq %rax, %r11') < computed.index('sched_data_a@GOTPCREL') < computed.index('call *%r11')):
            raise RuntimeError('computed scalar target not captured before argument GOT loads')
        _, _, record = body('run_record')
        target = record.index('sched_record@GOTPCREL')
        hidden = list(re.finditer(r'leaq -[0-9]+\(%rbp\), %rdi', record))
        if not (record.rindex('rep movsb') < target < record.index('call *%r11') and
                hidden and hidden[-1].start() < target and record.index('movq %rax, %r11') < target):
            raise RuntimeError('record target not after copies, packing and hidden RDI')
        for base, lib in ((10, 'libprovider.so'), (200, 'liboverride.so')):
            run([args.cc, '-std=c11', '-O2', '-Wall', '-Wextra', '-Werror', '-fPIC', '-shared',
                 f'-DBASE={base}', 'provider.c', 'provider.S', '-o', lib])
        def link(source):
            run([args.cc, '-shared', '-fPIC', '-Wl,--no-relax', source, '-L.', '-Wl,--no-as-needed',
                 '-lprovider', '-Wl,-rpath,$ORIGIN', '-o', 'libsubject.so'])
        link('generated.s')
        run([args.cc, '-std=c11', '-O2', '-Wall', '-Wextra', '-Werror', 'main.c', '-L.',
             '-Wl,--no-as-needed', '-lsubject', '-lprovider', '-Wl,-rpath,$ORIGIN', '-o', 'check'])
        run(['./check', '10'])
        run(['./check', '200'], env=dict(clean, LD_PRELOAD=str(d/'liboverride.so')))
        # A real overwrite of parked R11 with a callable same-ABI function. It
        # must produce the scalar result sentinel, never a signal or link error.
        needle = '\tcall *%r11\n'
        if scalar.count(needle) != 1:
            raise RuntimeError('target-clobber control did not match exactly once')
        mutant = scalar.replace(needle, '\tmovq sched_wrong@GOTPCREL(%rip), %r11\n'+needle)
        (d/'mutant.s').write_text(asm[:start]+mutant+asm[end:])
        link('mutant.s')
        run(['./check', '10'], expected=21)
        print(f'Focused scheduling witnesses passed provider and preload; callable R11-clobber control rejected at assertion 21; flags={flags!r}')

if __name__ == '__main__':
    main()
