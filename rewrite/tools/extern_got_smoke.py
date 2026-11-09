#!/usr/bin/env python3
"""Bounded Linux AMD64 extern/GOT smoke; not the full calibration ledger."""
import argparse
import os
from pathlib import Path
import platform
import resource
import subprocess
import tempfile

IL = '''export function l $get_data() {\n@entry\nret extern $external_data\n}\nexport function l $get_fn() {\n@entry\nret extern $external_fn\n}\nexport function l $invoke(l %x) {\n@entry\n%r =l call extern $external_fn(l %x)\nret %r\n}\n'''
PROVIDER = '''#include <stdint.h>\nuint64_t external_data = BASE;\nuint64_t external_fn(uint64_t x) { return x + BASE; }\n'''
MAIN = '''#define _GNU_SOURCE
#include <stdint.h>\n#include <stdio.h>\n#include <stdlib.h>\n#include <dlfcn.h>\nextern uint64_t get_data(void),get_fn(void),invoke(uint64_t);\nint main(int argc,char **argv) {\n if(argc!=2) return 20; uint64_t expect=strtoull(argv[1],0,10);\n uint64_t *p=(uint64_t *)(uintptr_t)get_data();\n void *data=dlsym(RTLD_DEFAULT,"external_data");\n void *fn=dlsym(RTLD_DEFAULT,"external_fn");\n if(!p || p!=data || get_fn()!=(uintptr_t)fn) return 21;\n if(*p!=expect || invoke(17)!=expect+17) return 22;\n return 0;\n}\n'''


def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--compiler', type=Path, required=True)
    p.add_argument('--cc', default='cc')
    args=p.parse_args()
    if platform.system()!='Linux' or platform.machine() not in ('x86_64','amd64'):
        raise SystemExit('Linux AMD64 required')
    resource.setrlimit(resource.RLIMIT_CORE,(0,0))
    compiler=args.compiler.resolve(strict=True)
    with tempfile.TemporaryDirectory(prefix='zbe-extern-smoke-') as tmp:
        d=Path(tmp); (d/'input.ssa').write_text(IL); (d/'provider.c').write_text(PROVIDER); (d/'main.c').write_text(MAIN)
        def run(argv, env=None):
            proc=subprocess.run([str(x) for x in argv], cwd=d, env=env, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=90)
            if proc.returncode:
                raise RuntimeError(f"command {argv!r} exited {proc.returncode}: {proc.stderr.decode(errors='replace')}")
        run([args.cc,'-fPIC','-shared','-DBASE=10','provider.c','-o','libprovider.so'])
        run([args.cc,'-fPIC','-shared','-DBASE=200','provider.c','-o','liboverride.so'])
        checks=0
        for mask in range(8):
            flags=[flag for n,flag in enumerate(('--fold-integers','--reuse-stack-homes','--callee-saved-homes')) if mask&(1<<n)]
            run([compiler,*flags,'input.ssa','generated.s'])
            asm=(d/'generated.s').read_text()
            assert 'external_data@GOTPCREL' in asm and 'external_fn@GOTPCREL' in asm
            for relax in (True,False):
                linker=[] if relax else ['-Wl,--no-relax']
                run([args.cc,'-shared','-fPIC',*linker,'generated.s','-L.','-Wl,--no-as-needed','-lprovider','-Wl,-rpath,$ORIGIN','-o','libsubject.so'])
                run([args.cc,'main.c','-L.','-Wl,--no-as-needed','-lsubject','-Wl,-rpath,$ORIGIN','-ldl','-o','check'])
                clean={k:v for k,v in os.environ.items() if k not in ('LD_PRELOAD','LD_LIBRARY_PATH','LD_AUDIT')}
                run(['./check','10'],env=clean);checks+=1
                preload=dict(clean,LD_PRELOAD=str(d/'liboverride.so'))
                run(['./check','200'],env=preload);checks+=1
        # Distinguishing negative control: LEA computes the slot address, not
        # the pointer stored in the slot. The identity check must reject it.
        mutated=asm.replace('movq external_data@GOTPCREL', 'leaq external_data@GOTPCREL')
        if mutated == asm:
            raise RuntimeError('slot-address mutation did not match generated assembly')
        (d/'mutant.s').write_text(mutated)
        run([args.cc,'-shared','-fPIC','-Wl,--no-relax','mutant.s','-L.','-Wl,--no-as-needed','-lprovider','-Wl,-rpath,$ORIGIN','-o','libsubject.so'])
        control=subprocess.run(['./check','10'],cwd=d,env=clean,stdout=subprocess.PIPE,stderr=subprocess.PIPE,timeout=90)
        if control.returncode != 21:
            raise RuntimeError(f'slot-address control expected exit 21, got {control.returncode}')
        print(f'{checks} extern/GOT smoke cases passed (8 options × 2 linker modes × 2 providers); slot-address negative control rejected')

if __name__=='__main__':main()
