#!/usr/bin/env python3
"""Bounded fixed-frame guard-page checks with an unprobed negative control."""
from pathlib import Path
import argparse
import os
import platform
import re
import resource
import signal
import subprocess
import tempfile


def pressure_function(count: int) -> str:
    # Calls are unreachable but unknown to integer folding. Their results remain
    # simultaneously live until summation, so coloring cannot collapse the frame.
    lines=[f'export function l $frame_probe{count}() {{','@entry','ret 42','@unreachable']
    lines += [f'%v{i} =l call $frame_unknown()' for i in range(count)]
    previous='%v0'
    for i in range(1,count):
        lines.append(f'%sum{i} =l add {previous}, %v{i}')
        previous=f'%sum{i}'
    lines += [f'ret {previous}','}']
    return '\n'.join(lines)+'\n'


def main() -> None:
    root=Path(__file__).resolve().parents[1]
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--compiler',type=Path,default=root/'zig-out/bin/zbe-native');parser.add_argument('--cc',default='cc')
    for flag in ('fold-integers','reuse-stack-homes','callee-saved-homes'):parser.add_argument('--'+flag,action='store_true')
    args=parser.parse_args()
    if platform.system()!='Linux' or platform.machine() not in ('x86_64','amd64') or os.sysconf('SC_PAGE_SIZE')!=4096:
        raise SystemExit('Frame guard checks require Linux x86_64 with 4096-byte pages; no result claimed.')
    resource.setrlimit(resource.RLIMIT_CORE,(0,0))
    flags=['--'+f for f in ('fold-integers','reuse-stack-homes','callee-saved-homes') if getattr(args,f.replace('-','_'))]
    il='export function l $frame_zero() {\n@entry\nret 42\n}\n'+pressure_function(1024)+pressure_function(1536)
    c='''#define _GNU_SOURCE
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <sys/mman.h>
extern uint64_t frame_zero(void),frame_probe1024(void),frame_probe1536(void);
extern uint64_t zbe_check_preserved(uint64_t (*)(void));
extern uint64_t zbe_on_stack(void *,uint64_t (*)(void));
uint64_t frame_unknown(void) { abort(); }
int main(int argc,char **argv) {
 uint64_t (*functions[])(void)={frame_zero,frame_probe1024,frame_probe1536};
 if (argc>1) {
  int index=atoi(argv[1]); if(index<1 || index>2) return 2;
  size_t page=4096,bytes=32*page;
  unsigned char *memory=mmap(NULL,bytes,PROT_NONE,MAP_PRIVATE|MAP_ANONYMOUS,-1,0);
  if(memory==MAP_FAILED) return 3;
  if(mprotect(memory,30*page,PROT_READ|PROT_WRITE) || mprotect(memory+31*page,page,PROT_READ|PROT_WRITE)) return 4;
  uint64_t result=zbe_on_stack(memory+bytes-128,functions[index]);
  if(munmap(memory,bytes)) return 5;
  return result==42 ? 0 : 6;
 }
 size_t count=0;
 for(size_t i=0;i<3;++i) {
  if(functions[i]()!=42) { return 7; } ++count;
  if(zbe_check_preserved(functions[i])!=0) { return 8; } ++count;
 }
 printf("%zu native fixed-frame result/preserved checks passed\\n",count);return 0;
}
'''
    with tempfile.TemporaryDirectory(prefix='zbe-frames-') as directory:
        work=Path(directory);src,asm,unprobed,driver,binary,control=[work/n for n in ('frame.ssa','frame.s','unprobed.s','main.c','check','control')]
        src.write_text(il);driver.write_text(c)
        subprocess.run([str(args.compiler.resolve()),*flags,str(src),str(asm)],check=True,timeout=120)
        assembly=asm.read_text()
        for count in (1024,1536):
            prologue=assembly.split(f'frame_probe{count}:\n',1)[1].split('".Lzbe@',1)[0]
            steps=list(map(int,re.findall(r'\tsubq \$(\d+), %rsp\n',prologue)))
            if not steps or sum(steps)<8192 or any(not 0<step<=4096 or step%16 for step in steps): raise SystemExit('Large frame reservation is not bounded and page-wise')
            if prologue.count('\ttestb $0, (%rsp)\n')!=len(steps): raise SystemExit('Frame reservation is missing touches')
        link=[args.cc,'-std=c11','-O2','-Wall','-Wextra','-Werror','-fPIE','-pie',str(driver)]
        adapters=[str(root/'src/fixtures/frame-stack.s'),str(root/'src/fixtures/check-preserved.s')]
        subprocess.run([*link,str(asm),*adapters,'-o',str(binary)],check=True,timeout=90)
        subprocess.run([str(binary)],check=True,timeout=30)
        for index in (1,2):
            result=subprocess.run([str(binary),str(index)],capture_output=True,timeout=30)
            if result.returncode!=-signal.SIGSEGV: raise SystemExit(f'Frame guard {index} returned {result.returncode}, expected SIGSEGV')
        print('2 fixed-frame guard-page SIGSEGV checks passed')
        # Test-only mutation: remove the probes, not the reservations or home
        # logic. Both protected-stack calls must then succeed, proving the guard
        # checks distinguish probing from an unrelated later memory access.
        unprobed.write_text(assembly.replace('\ttestb $0, (%rsp)\n',''))
        subprocess.run([*link,str(unprobed),*adapters,'-o',str(control)],check=True,timeout=90)
        for index in (1,2):subprocess.run([str(control),str(index)],check=True,timeout=30)
        print('2 unprobed fixed-frame negative controls passed')


if __name__=='__main__':main()
