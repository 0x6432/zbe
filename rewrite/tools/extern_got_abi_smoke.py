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
double external_var(uint64_t marker,...) { va_list ap; va_start(ap,marker); double sum=BASE+marker; for(int i=1;i<=9;i++) sum+=i*va_arg(ap,double); va_end(ap); return sum; }
'''
MAIN = '''#include <stdint.h>
#include <stdlib.h>
extern uint64_t invoke_gp(void);
extern double invoke_fp(void),invoke_var(void);
int main(int argc,char **argv) {
 if(argc!=2) return 20;
 unsigned long base=strtoul(argv[1],0,10);
 if(invoke_gp()!=base+140) return 21;
 if(invoke_fp()!=(double)(base+285)) return 22;
 if(invoke_var()!=(double)(base+292)) return 23;
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
        (d/'input.ssa').write_text(IL); (d/'provider.c').write_text(PROVIDER); (d/'main.c').write_text(MAIN)
        def run(argv,env=None):
            p=subprocess.run([str(x) for x in argv], cwd=d, env=env, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=90)
            if p.returncode:
                raise RuntimeError(f'{argv!r}: exit {p.returncode}: {p.stderr.decode(errors="replace")}')
            return p.stdout.decode(errors='replace')
        flags=[flag for enabled,flag in ((args.fold_integers,'--fold-integers'),(args.reuse_stack_homes,'--reuse-stack-homes'),(args.callee_saved_homes,'--callee-saved-homes')) if enabled]
        run([compiler,*flags,'input.ssa','generated.s'])
        asm=(d/'generated.s').read_text()
        for sym in ('external_gp','external_fp','external_var'):
            if f'{sym}@GOTPCREL' not in asm: raise RuntimeError(f'missing GOT target {sym}')
        if 'movb $8, %al' not in asm: raise RuntimeError('variadic call lacks expected SSE-count AL')
        run(['cc','-shared','-fPIC','-DBASE=10','provider.c','-o','libprovider.so'])
        run(['cc','-shared','-fPIC','-DBASE=200','provider.c','-o','liboverride.so'])
        run(['cc','-shared','-fPIC','-Wl,--no-relax','generated.s','-L.','-Wl,--no-as-needed','-lprovider','-Wl,-rpath,$ORIGIN','-o','libsubject.so'])
        run(['cc','main.c','-L.','-Wl,--no-as-needed','-lsubject','-Wl,-rpath,$ORIGIN','-o','check'])
        clean={k:v for k,v in os.environ.items() if k not in ('LD_PRELOAD','LD_LIBRARY_PATH','LD_AUDIT')}
        run(['./check','10'],env=clean)
        run(['./check','200'],env=dict(clean,LD_PRELOAD=str(d/'liboverride.so')))
        # Negative control must execute: zero AL loses floating varargs save state.
        mutated=asm.replace('movb $8, %al','movb $0, %al')
        if mutated == asm: raise RuntimeError('AL mutant failed to match')
        (d/'mutant.s').write_text(mutated)
        run(['cc','-shared','-fPIC','-Wl,--no-relax','mutant.s','-L.','-Wl,--no-as-needed','-lprovider','-Wl,-rpath,$ORIGIN','-o','libsubject.so'])
        p=subprocess.run(['./check','10'],cwd=d,env=clean,stdout=subprocess.PIPE,stderr=subprocess.PIPE,timeout=90)
        if p.returncode != 23: raise RuntimeError(f'AL mutant expected variadic assertion exit 23, got {p.returncode}')
        print(f'GOT GP7, FP9 and variadic FP9 passed provider and preload; AL negative control rejected; flags={flags!r}')

if __name__=='__main__': main()
