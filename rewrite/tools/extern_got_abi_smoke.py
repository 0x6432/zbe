#!/usr/bin/env python3
"""Focused Linux AMD64 GOT-call ABI pressure smoke; not the full ABI ledger."""
import argparse
import os
from pathlib import Path
import platform
import resource
import subprocess
import tempfile

IL = '''export function l $invoke_gp() {
@entry
%r =l call extern $external_gp(l 1, l 2, l 3, l 4, l 5, l 6, l 7)
ret %r
}
export function d $invoke_fp() {
@entry
%r =d call extern $external_fp(d d_1.0, d d_2.0, d d_3.0, d d_4.0, d d_5.0, d d_6.0, d d_7.0, d d_8.0, d d_9.0)
ret %r
}
export function d $invoke_mixed() {
@entry
%r =d call extern $external_mixed(l 1, d d_1.0, l 2, d d_2.0, l 3, d d_3.0, l 4, d d_4.0, l 5, d d_5.0, l 6, d d_6.0, l 7, d d_7.0, d d_8.0, d d_9.0)
ret %r
}
export function l $invoke_env() {
@entry
%r =l call extern $external_env(env 37, l 11)
ret %r
}
export function l $invoke_capture() {
@entry
%r =l call extern $external_capture(l 7, ..., d d_1.0, d d_2.0, d d_3.0, d d_4.0, d d_5.0, d d_6.0, d d_7.0, d d_8.0, d d_9.0)
ret %r
}
export function d $invoke_var() {
@entry
%r =d call extern $external_var(l 7, ..., d d_1.0, d d_2.0, d d_3.0, d d_4.0, d d_5.0, d d_6.0, d d_7.0, d d_8.0, d d_9.0)
ret %r
}
'''
PROVIDER = '''#include <stdint.h>
#include <stdarg.h>
uint64_t external_gp(uint64_t a,uint64_t b,uint64_t c,uint64_t d,uint64_t e,uint64_t f,uint64_t g) { return BASE+a+2*b+3*c+4*d+5*e+6*f+7*g; }
double external_fp(double a,double b,double c,double d,double e,double f,double g,double h,double i) { return BASE+a+2*b+3*c+4*d+5*e+6*f+7*g+8*h+9*i; }
double external_mixed(uint64_t a,double b,uint64_t c,double d,uint64_t e,double f,uint64_t g,double h,uint64_t i,double j,uint64_t k,double l,uint64_t m,double n,double o,double p) { return BASE+a+b+2*c+2*d+3*e+3*f+4*g+4*h+5*i+5*j+6*k+6*l+7*m+7*n+8*o+9*p; }
double external_var(uint64_t marker,...) { va_list ap; va_start(ap,marker); double sum=BASE+marker; for(int i=1;i<=9;i++) sum+=i*va_arg(ap,double); va_end(ap); return sum; }
'''
ASM = '''.text
.globl external_env
.type external_env, @function
external_env:
 leaq (%rax,%rdi,2), %rax
 addq $BASE, %rax
 ret
.size external_env, .-external_env
.globl external_capture
.type external_capture, @function
external_capture:
 cmpb $8, %al
 jne .Lcapture_bad
 cmpq $7, %rdi
 jne .Lcapture_bad
 movq %xmm0, %r10
 movabsq $0x3ff0000000000000, %r11
 cmpq %r11, %r10
 jne .Lcapture_bad
 movq %xmm1, %r10
 movabsq $0x4000000000000000, %r11
 cmpq %r11, %r10
 jne .Lcapture_bad
 movq %xmm2, %r10
 movabsq $0x4008000000000000, %r11
 cmpq %r11, %r10
 jne .Lcapture_bad
 movq %xmm3, %r10
 movabsq $0x4010000000000000, %r11
 cmpq %r11, %r10
 jne .Lcapture_bad
 movq %xmm4, %r10
 movabsq $0x4014000000000000, %r11
 cmpq %r11, %r10
 jne .Lcapture_bad
 movq %xmm5, %r10
 movabsq $0x4018000000000000, %r11
 cmpq %r11, %r10
 jne .Lcapture_bad
 movq %xmm6, %r10
 movabsq $0x401c000000000000, %r11
 cmpq %r11, %r10
 jne .Lcapture_bad
 movq %xmm7, %r10
 movabsq $0x4020000000000000, %r11
 cmpq %r11, %r10
 jne .Lcapture_bad
 movabsq $0x4022000000000000, %r11
 cmpq %r11, 8(%rsp)
 jne .Lcapture_bad
 movl $1, %eax
 ret
.Lcapture_bad:
 xorl %eax, %eax
 ret
.size external_capture, .-external_capture
.section .note.GNU-stack,"",@progbits
'''
MAIN = '''#include <stdint.h>
#include <stdlib.h>
extern uint64_t invoke_gp(void),invoke_env(void),invoke_capture(void);
extern double invoke_fp(void),invoke_var(void),invoke_mixed(void);
int main(int argc,char **argv) {
 if(argc!=2) return 20;
 unsigned long base=strtoul(argv[1],0,10);
 if(invoke_gp()!=base+140) return 21;
 if(invoke_fp()!=(double)(base+285)) return 22;
 if(invoke_var()!=(double)(base+292)) return 23;
 if(invoke_mixed()!=(double)(base+425)) return 24;
 if(invoke_env()!=base+59) return 25;
 if(invoke_capture()!=1) return 26;
 return 0;
}
'''

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--compiler', type=Path, required=True)
    parser.add_argument('--fold-integers', action='store_true')
    parser.add_argument('--reuse-stack-homes', action='store_true')
    parser.add_argument('--callee-saved-homes', action='store_true')
    args = parser.parse_args()
    if platform.system() != 'Linux' or platform.machine() not in ('x86_64','amd64'):
        raise SystemExit('Linux AMD64 required')
    resource.setrlimit(resource.RLIMIT_CORE, (0,0))
    compiler = args.compiler.resolve(strict=True)
    with tempfile.TemporaryDirectory(prefix='zbe-got-abi-') as tmp:
        d=Path(tmp)
        (d/'input.ssa').write_text(IL); (d/'provider.c').write_text(PROVIDER); (d/'provider_asm.S').write_text(ASM); (d/'main.c').write_text(MAIN)
        clean={k:os.environ[k] for k in ('PATH','HOME','TMPDIR') if k in os.environ}
        clean['LC_ALL']='C'
        def run(argv,env=None):
            p=subprocess.run([str(x) for x in argv], cwd=d, env=clean if env is None else env, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=90)
            if p.returncode:
                raise RuntimeError(f'{argv!r}: exit {p.returncode}: {p.stderr.decode(errors="replace")}')
            return p.stdout.decode(errors='replace')
        flags=[flag for enabled,flag in ((args.fold_integers,'--fold-integers'),(args.reuse_stack_homes,'--reuse-stack-homes'),(args.callee_saved_homes,'--callee-saved-homes')) if enabled]
        run([compiler,*flags,'input.ssa','generated.s'])
        asm=(d/'generated.s').read_text()
        for sym in ('external_gp','external_fp','external_var','external_mixed','external_env','external_capture'):
            if f'{sym}@GOTPCREL' not in asm: raise RuntimeError(f'missing GOT target {sym}')
        run(['cc','-shared','-fPIC','-DBASE=10','provider.c','provider_asm.S','-o','libprovider.so'])
        run(['cc','-shared','-fPIC','-DBASE=200','provider.c','provider_asm.S','-o','liboverride.so'])
        run(['cc','-shared','-fPIC','-Wl,--no-relax','generated.s','-L.','-Wl,--no-as-needed','-lprovider','-Wl,-rpath,$ORIGIN','-o','libsubject.so'])
        run(['cc','main.c','-L.','-Wl,--no-as-needed','-lsubject','-Wl,-rpath,$ORIGIN','-o','check'])
        run(['./check','10'],env=clean)
        run(['./check','200'],env=dict(clean,LD_PRELOAD=str(d/'liboverride.so')))
        # Probe the AL-count mutation only with a purpose-built assembly callee:
        # unlike va_arg, it reads the actual AL and incoming registers safely.
        begin=asm.index('invoke_capture:')
        end=asm.index('.size invoke_capture, .-invoke_capture',begin)
        function=asm[begin:end]
        if function.count('movb $8, %al') != 1: raise RuntimeError('capture AL control did not match exactly once')
        mutated=asm[:begin]+function.replace('movb $8, %al','movb $0, %al')+asm[end:]
        (d/'mutant.s').write_text(mutated)
        run(['cc','-shared','-fPIC','-Wl,--no-relax','mutant.s','-L.','-Wl,--no-as-needed','-lprovider','-Wl,-rpath,$ORIGIN','-o','libsubject.so'])
        p=subprocess.run(['./check','10'],cwd=d,env=clean,stdout=subprocess.PIPE,stderr=subprocess.PIPE,timeout=90)
        if p.returncode != 26: raise RuntimeError(f'AL mutant expected assembly capture exit 26, got {p.returncode}')
        # Independent control: corrupt the final ENV by loading the GOT target
        # after ENV setup, while preserving R11 so the call itself still runs.
        good='\tmovq external_env@GOTPCREL(%rip), %rax\n\tmovq %rax, %r11\n\tmovabsq $0x25, %rax'
        bad='\tmovabsq $0x25, %rax\n\tmovq external_env@GOTPCREL(%rip), %rax\n\tmovq %rax, %r11'
        if asm.count(good)!=1: raise RuntimeError('ENV schedule control did not match exactly once')
        (d/'mutant.s').write_text(asm.replace(good,bad))
        run(['cc','-shared','-fPIC','-Wl,--no-relax','mutant.s','-L.','-Wl,--no-as-needed','-lprovider','-Wl,-rpath,$ORIGIN','-o','libsubject.so'])
        p=subprocess.run(['./check','10'],cwd=d,env=clean,stdout=subprocess.PIPE,stderr=subprocess.PIPE,timeout=90)
        if p.returncode != 25: raise RuntimeError(f'ENV mutant expected environment assertion exit 25, got {p.returncode}')
        print(f'GOT GP7, FP9, mixed overflow, ENV and variadic FP9 passed provider and preload; AL and ENV negative controls rejected; flags={flags!r}')

if __name__=='__main__': main()
