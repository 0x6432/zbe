#!/usr/bin/env python3
"""Dynamic native allocation extents, alignment, lifetime, calls and guard probing."""
from pathlib import Path
import argparse
import os
import platform
import resource
import signal
import subprocess
import tempfile


def main() -> None:
    root=Path(__file__).resolve().parents[1]
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--compiler',type=Path,default=root/'zig-out/bin/zbe-native');parser.add_argument('--cc',default='cc')
    for flag in ('fold-integers','reuse-stack-homes','callee-saved-homes'):parser.add_argument('--'+flag,action='store_true')
    args=parser.parse_args()
    if platform.system()!='Linux' or platform.machine() not in ('x86_64','amd64') or os.sysconf('SC_PAGE_SIZE')!=4096:
        raise SystemExit('Allocation guard checks require Linux x86_64 with 4096-byte pages; no result claimed.')
    resource.setrlimit(resource.RLIMIT_CORE,(0,0))
    flags=['--'+f for f in ('fold-integers','reuse-stack-homes','callee-saved-homes') if getattr(args,f.replace('-','_'))]
    sizes=(0,1,2,3,4,7,8,15,16,17,31,32,33,63,64,255,256,257,4095,4096,4097,8191,8192)
    seeds=(0,1,127,128,255,256,0xdeadbeef800000ff,(1<<64)-1)
    checks=[]
    for align in (4,8,16):
        for size in sizes:
            for seed in seeds:
                expected=sum((seed+i)&255 for i in range(size))
                checks.append(f'REQUIRE(alloc_checksum{align}({size},UINT64_C({seed}))==UINT64_C({expected}));')
    for n in (0,1,2,10,100,300):checks.append(f'REQUIRE(alloc_fresh({n})=={sum(i&255 for i in range(n))});')
    for size in (1,2,7,15,16,17,33,4096):checks.append(f'REQUIRE(alloc_outgoing({size})=={238+size});')
    for n in (0,1,2,8,16,32):checks.append(f'REQUIRE(alloc_recursive({n})=={n*(n+1)//2});')
    for size in (1,16,17,4096):checks.append(f'REQUIRE(alloc_indirect(callback,{size})=={105+size});')
    checks += ['REQUIRE(alloc_outgoing_wrapper()==239);','REQUIRE(zbe_check_preserved(alloc_outgoing_wrapper)==0);','REQUIRE(alloc_guard8192()==42);','REQUIRE(alloc_guard12288()==42);']
    assert len(checks)==580
    c='''#define _GNU_SOURCE
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
extern uint64_t alloc_checksum4(uint64_t,uint64_t),alloc_checksum8(uint64_t,uint64_t),alloc_checksum16(uint64_t,uint64_t);
extern uint64_t alloc_fresh(uint64_t),alloc_outgoing(uint64_t),alloc_outgoing_wrapper(void),alloc_recursive(uint64_t),alloc_guard(uint64_t),alloc_guard8192(void),alloc_guard12288(void);
extern uint64_t alloc_indirect(uint64_t (*)(unsigned char *,uint64_t,uint64_t,uint64_t,uint64_t,uint64_t,uint64_t,uint64_t),uint64_t);
extern uint64_t zbe_check_preserved(uint64_t (*)(void)),zbe_on_stack(void *,uint64_t (*)(void));
uint64_t alloc_mutate(unsigned char *p,unsigned char *q,uint64_t a,uint64_t b,uint64_t c,uint64_t d,uint64_t e,uint64_t f,uint64_t g,uint64_t h,double floating) {
 if(p==q || *p!=17 || *q!=23 || floating!=2.5) abort();
 *p=99;*q=101;return a+b+c+d+e+f+g+h+(uint64_t)floating;
}
static uint64_t callback(unsigned char *p,uint64_t a,uint64_t b,uint64_t c,uint64_t d,uint64_t e,uint64_t f,uint64_t g) {
 if(*p!=9) { abort(); } *p=77; return a+b+c+d+e+f+g;
}
#define REQUIRE(c) do { ++count; if (!(c)) { fprintf(stderr,"allocation check %zu failed\\n",count); return 1; } } while (0)
int main(int argc,char **argv) {
 if(argc>1 && !strcmp(argv[1],"guard")) {
  if(argc!=3) return 2;
  uint64_t (*target)(void)=atoi(argv[2])==0?alloc_guard8192:alloc_guard12288;
  size_t page=4096,bytes=32*page;
  unsigned char *memory=mmap(NULL,bytes,PROT_NONE,MAP_PRIVATE|MAP_ANONYMOUS,-1,0);
  if(memory==MAP_FAILED) return 3;
  if(mprotect(memory,30*page,PROT_READ|PROT_WRITE) || mprotect(memory+31*page,page,PROT_READ|PROT_WRITE)) return 4;
  uint64_t result=zbe_on_stack(memory+bytes-128,target);
  if(munmap(memory,bytes)) return 5;
  return result==42?0:6;
 }
 if(argc>1 && !strcmp(argv[1],"overflow")) {
  if(argc!=3) return 7;
  uint64_t offset=atoi(argv[2])==2?14:(uint64_t)atoi(argv[2]);
  return alloc_guard(UINT64_MAX-offset)==42?8:9;
 }
 size_t count=0;
'''+ '\n'.join(checks)+ '\nprintf("%zu native dynamic-allocation checks passed\\n",count);return 0; }\n'
    with tempfile.TemporaryDirectory(prefix='zbe-allocations-') as directory:
        work=Path(directory);src,asm,driver,binary,mutated,control=[work/n for n in ('allocations.ssa','allocations.s','main.c','check','unprobed.s','control')]
        src.write_text((root/'src/fixtures/native-allocations.ssa').read_text());driver.write_text(c)
        subprocess.run([str(args.compiler.resolve()),*flags,str(src),str(asm)],check=True,timeout=120)
        link=[args.cc,'-std=c11','-O2','-Wall','-Wextra','-Werror','-fPIE','-pie',str(driver)]
        adapters=[str(root/'src/fixtures/frame-stack.s'),str(root/'src/fixtures/check-preserved.s')]
        subprocess.run([*link,str(asm),*adapters,'-o',str(binary)],check=True,timeout=90)
        subprocess.run([str(binary)],check=True,timeout=30)
        for index in (0,1):
            result=subprocess.run([str(binary),'guard',str(index)],capture_output=True,timeout=30)
            if result.returncode!=-signal.SIGSEGV:raise SystemExit('Dynamic allocation skipped controlled guard')
        print('2 dynamic-allocation guard-page SIGSEGV checks passed')
        for index in (0,1,2):
            result=subprocess.run([str(binary),'overflow',str(index)],capture_output=True,timeout=30)
            if result.returncode!=-signal.SIGILL:raise SystemExit('Invalid allocation round-up overflow did not trap')
        print('3 allocation round-up overflow trap checks passed')
        mutated.write_text(asm.read_text().replace('\ttestb $0, (%rsp)\n',''))
        subprocess.run([*link,str(mutated),*adapters,'-o',str(control)],check=True,timeout=90)
        for index in (0,1):subprocess.run([str(control),'guard',str(index)],check=True,timeout=30)
        print('2 unprobed dynamic-allocation negative controls passed')
        for text in (
            'function w $f() {\n@e\n%r =w alloc4 4\nret %r\n}',
            'function s $f() {\n@e\n%r =s alloc8 4\nret %r\n}',
            'function l $f(w %n) {\n@e\n%r =l alloc16 %n\nret %r\n}',
            'function l $f() {\n@e\n%r =l alloc4 d_4\nret %r\n}',
            'function l $f() {\n@e\n%r =l alloc4 4, 4\nret %r\n}',
            'function l $f() {\n@e\n%r =l alloc4\nret %r\n}',
        ):
            src.write_text(text);asm.unlink()
            for exists in (False,True):
                if exists:asm.write_text('preserve-allocation-output')
                result=subprocess.run([str(args.compiler.resolve()),*flags,str(src),str(asm)],capture_output=True,timeout=30)
                if result.returncode==0:raise SystemExit('Invalid allocation accepted')
                if (exists and asm.read_text()!='preserve-allocation-output') or (not exists and asm.exists()):raise SystemExit('Invalid allocation changed output')
        print('12 allocation rejection/output-preservation checks passed')


if __name__=='__main__':main()
