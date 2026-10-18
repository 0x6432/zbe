#!/usr/bin/env python3
"""Pinned alloc1/alloc2 aliases: defined checksums, calls/homes and overflow boundary."""
from pathlib import Path
import argparse
import platform
import resource
import signal
import subprocess
import tempfile


def main():
    root = Path(__file__).resolve().parents[1]
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--compiler', type=Path, default=root/'zig-out/bin/zbe-native')
    parser.add_argument('--cc', default='cc')
    for flag in ('fold-integers', 'reuse-stack-homes', 'callee-saved-homes'):
        parser.add_argument('--'+flag, action='store_true')
    args = parser.parse_args()
    if platform.system() != 'Linux' or platform.machine() not in ('x86_64','amd64'):
        raise SystemExit('Allocation alias checks require Linux AMD64; no result claimed')
    resource.setrlimit(resource.RLIMIT_CORE, (0, 0))
    flags = ['--'+f for f in ('fold-integers', 'reuse-stack-homes', 'callee-saved-homes') if getattr(args, f.replace('-','_'))]
    sizes = (0,1,2,3,4,7,8,15,16,17,31,32,33,63,64,255,256,257,4095,4096,4097,8191,8192)
    seeds = (0,1,127,128,255,256,0xdeadbeef800000ff,(1<<64)-1)
    checks = []
    for opcode in (1,2,4):
        for size in sizes:
            for seed in seeds:
                expected = sum((seed+i)&255 for i in range(size))
                checks.append(f'REQUIRE(alloc_aliases_{opcode}({size},UINT64_C({seed}))==UINT64_C({expected}));')
    for n in (1,2,7,15,16,17,33,4096):
        checks.append(f'REQUIRE(alloc_aliases_calls({n})=={238+n});')
    for n in (0,1,2,10,31,300):
        checks.append(f'REQUIRE(alloc_aliases_fresh({n})=={78*n});')
    checks += ['REQUIRE(alloc_aliases_wrapper()==255);','REQUIRE(zbe_check_preserved(alloc_aliases_wrapper)==0);']
    assert len(checks) == 568
    driver = r'''
#include <stdint.h>
#include <stdlib.h>
#include <stdio.h>
extern uint64_t alloc_aliases_1(uint64_t,uint64_t),alloc_aliases_2(uint64_t,uint64_t),alloc_aliases_4(uint64_t,uint64_t);
extern uint64_t alloc_aliases_calls(uint64_t),alloc_aliases_fresh(uint64_t),alloc_aliases_wrapper(void);
extern int zbe_check_preserved(uint64_t (*)(void));
uint64_t alloc_aliases_sink(unsigned char *p,unsigned char *q,uint64_t a,uint64_t b,uint64_t c,uint64_t d,uint64_t e,uint64_t f,uint64_t g,uint64_t h,double floating) {
    if(p==q || (uintptr_t)p%4 || (uintptr_t)q%4 || *p!=17 || *q!=23 || floating!=2.5) abort();
    *p=99;*q=101;
    return a+b+c+d+e+f+g+h+(uint64_t)floating;
}
static unsigned count;
#define REQUIRE(x) do {++count;if(!(x)){fprintf(stderr,"Allocation alias check %u failed\n",count);return 1;}}while(0)
int main(int argc,char **argv) {
    if(argc==3) {
        unsigned op=(unsigned)atoi(argv[1]),offset=(unsigned)atoi(argv[2]);
        uint64_t (*target)(uint64_t,uint64_t)=op==1?alloc_aliases_1:op==2?alloc_aliases_2:alloc_aliases_4;
        (void)target(UINT64_MAX-offset,0);return 7;
    }
''' + '\n'.join(checks) + r'''
    if(count!=568)return 3;
    printf("%u native allocation-alias defined-value checks passed\n",count);
    return 0;
}
'''
    with tempfile.TemporaryDirectory(prefix='alloc_aliases_') as temporary:
        work = Path(temporary)
        il,asm,c,binary = [work/name for name in ('input.ssa','output.s','driver.c','run')]
        il.write_text((root/'src/fixtures/alloc_aliases_program.ssa').read_text())
        c.write_text(driver)
        subprocess.run([str(args.compiler.resolve()),*flags,str(il),str(asm)],check=True,timeout=90)
        for link in ('-pie','-no-pie'):
            subprocess.run([args.cc,'-std=c11','-O2','-Wall','-Wextra','-Werror','-fPIE',link,str(c),str(asm),str(root/'src/fixtures/check-preserved.s'),'-o',str(binary)],check=True,timeout=90)
            subprocess.run([str(binary)],check=True,timeout=30)
            for opcode in (1,2,4):
                for offset in (0,1,14):
                    result=subprocess.run([str(binary),str(opcode),str(offset)],capture_output=True,timeout=30)
                    if result.returncode!=-signal.SIGILL:
                        raise SystemExit('Allocation alias round-up-overflow boundary did not retain SIGILL')
        print('18 allocation-alias invalid-size round-up trap checks passed (PIE/non-PIE)')
        rejected = 0
        for opcode in ('alloc1','alloc2'):
            for text in (
                f'function w $f() {{\n@e\n%p =w {opcode} 1\nret %p\n}}',
                f'function l $f(w %n) {{\n@e\n%p =l {opcode} %n\nret %p\n}}',
                f'function l $f() {{\n@e\n%p =l {opcode} d_1\nret %p\n}}',
                f'function l $f() {{\n@e\n%p =l {opcode}\nret %p\n}}',
                f'function l $f() {{\n@e\n%p =l {opcode} 1, 2\nret %p\n}}',
            ):
                il.write_text(text)
                for exists in (False,True):
                    asm.unlink(missing_ok=True)
                    if exists:asm.write_text('preserve-alias-output')
                    result=subprocess.run([str(args.compiler.resolve()),*flags,str(il),str(asm)],capture_output=True,timeout=30)
                    if result.returncode==0 or (exists and asm.read_text()!='preserve-alias-output') or (not exists and asm.exists()):
                        raise SystemExit('Malformed allocation alias accepted or changed output')
                    rejected += 1
        assert rejected==20
        print('20 allocation-alias rejection/output-preservation checks passed')
        print('2 allocation-alias link modes passed')


if __name__=='__main__':
    main()
