#!/usr/bin/env python3
"""Bounded native Linux AMD64 constant blits, not memmove or a sandbox."""
from pathlib import Path
import argparse
import platform
import resource
import signal
import subprocess
import tempfile


def main() -> None:
    root = Path(__file__).resolve().parents[1]
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--compiler', type=Path, default=root/'zig-out/bin/zbe-native')
    parser.add_argument('--cc', default='cc')
    for flag in ('fold-integers','reuse-stack-homes','callee-saved-homes'):
        parser.add_argument('--'+flag, action='store_true')
    args = parser.parse_args()
    if platform.system() != 'Linux' or platform.machine() not in ('x86_64','amd64'):
        raise SystemExit('Native blit checks require Linux x86_64; no result claimed.')
    resource.setrlimit(resource.RLIMIT_CORE,(0,0))
    flags = ['--'+f for f in ('fold-integers','reuse-stack-homes','callee-saved-homes') if getattr(args,f.replace('-','_'))]
    counts = [0,1,2,3,7,8,9,15,16,17,31,32,63,64,65,127,128,129,255,256,257,4096]
    il, declarations, checks = [], [], []
    for count in counts:
        il.append(f'export function $blit_{count}(l %src,l %dst) {{\n@e\nblit %src, %dst, {count}\nret\n}}')
        declarations.append(f'extern void blit_{count}(uint64_t,uint64_t);')
        checks.append(f'''for (size_t s=0;s<8;++s) for (size_t d=0;d<8;++d) {{
            memcpy(source,pristine,sizeof source); memset(destination,0xa5,sizeof destination); memset(expected,0xa5,sizeof expected);
            memcpy(expected+d,pristine+s,{count});
            blit_{count}((uint64_t)(uintptr_t)(source+s),(uint64_t)(uintptr_t)(destination+d));
            REQUIRE(memcmp(destination,expected,sizeof destination)==0);
            REQUIRE(memcmp(source,pristine,sizeof source)==0);
        }}
        for (size_t s=0;s<8;++s) {{
            memcpy(source,pristine,sizeof source);
            blit_{count}((uint64_t)(uintptr_t)(source+s),(uint64_t)(uintptr_t)(source+s));
            REQUIRE(memcmp(source,pristine,sizeof source)==0);
        }}
        memset(mapping,0xa5,(size_t)page); memset(page_expected,0xa5,(size_t)page);
        memcpy(page_expected+page-{count},pristine+3,{count});
        blit_{count}((uint64_t)(uintptr_t)(pristine+3),(uint64_t)(uintptr_t)(boundary-{count}));
        REQUIRE(memcmp(mapping,page_expected,(size_t)page)==0);
        memset(destination,0xa5,sizeof destination); memset(expected,0xa5,sizeof expected);
        memcpy(expected+3,boundary-{count},{count});
        blit_{count}((uint64_t)(uintptr_t)(boundary-{count}),(uint64_t)(uintptr_t)(destination+3));
        REQUIRE(memcmp(destination,expected,sizeof destination)==0);''')
    il.append('''export function l $blit_preserved() {
@entry
%s =l call $blit_source()
%d =l call $blit_destination()
blit %s, %d, 31
ret 0
}
export function l $blit_pressure(l %a,l %b,l %c,l %d,l %e,l %f,l %src,l %dst) {
@entry
blit %src, %dst, 31
%r1 =l add %a, %b
%r2 =l add %c, %d
%r3 =l add %e, %f
%r4 =l add %r1, %r2
%r5 =l add %r4, %r3
ret %r5
}''')
    declarations += ['extern uint64_t blit_preserved(void);','extern uint64_t blit_pressure(uint64_t,uint64_t,uint64_t,uint64_t,uint64_t,uint64_t,uint64_t,uint64_t);', 'extern uint64_t zbe_check_preserved(uint64_t (*)(void));']
    expected_checks = len(counts)*138 + 5
    c = '''#define _GNU_SOURCE
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <unistd.h>
'''+'\n'.join(declarations)+'''
static unsigned char callback_source[31],callback_destination[31];
uint64_t blit_source(void) { return (uint64_t)(uintptr_t)callback_source; }
uint64_t blit_destination(void) { return (uint64_t)(uintptr_t)callback_destination; }
#define REQUIRE(c) do { ++count; if (!(c)) { fprintf(stderr,"blit check %zu failed at line %d\\n",count,__LINE__); return 1; } } while (0)
int main(int argc,char **argv) {
    long page=sysconf(_SC_PAGESIZE); if (page<4096) return 2;
    unsigned char *mapping=mmap(NULL,(size_t)page*2,PROT_READ|PROT_WRITE,MAP_PRIVATE|MAP_ANONYMOUS,-1,0);
    if (mapping==MAP_FAILED || mprotect(mapping+page,(size_t)page,PROT_NONE)) return 2;
    unsigned char *boundary=mapping+page;
    unsigned char source[8192],destination[8192],pristine[8192],expected[8192];
    if (argc==2) {
        if (!strcmp(argv[1],"source")) { blit_7((uint64_t)(uintptr_t)boundary,(uint64_t)(uintptr_t)destination); return 3; }
        if (!strcmp(argv[1],"destination")) { blit_7((uint64_t)(uintptr_t)source,(uint64_t)(uintptr_t)boundary); return 3; }
        return 2;
    }
    unsigned char *page_expected=malloc((size_t)page); if (!page_expected) return 2;
    for (size_t i=0;i<sizeof pristine;++i) pristine[i]=(unsigned char)(i*37+11);
    size_t count=0;
'''+'\n'.join(checks)+'''
    blit_0((uint64_t)(uintptr_t)boundary,(uint64_t)(uintptr_t)boundary);
    REQUIRE(((uint64_t)(uintptr_t)boundary >> 32) != 0);
    memcpy(callback_source,pristine,31); memset(callback_destination,0xa5,31);
    REQUIRE(zbe_check_preserved(blit_preserved)==0);
    REQUIRE(memcmp(callback_source,callback_destination,31)==0);
    memset(destination,0xa5,sizeof destination);
    REQUIRE(blit_pressure(1,2,3,4,5,6,(uint64_t)(uintptr_t)pristine,(uint64_t)(uintptr_t)destination)==21);
    REQUIRE(memcmp(pristine,destination,31)==0);
'''+f'    if (count!={expected_checks}) return 2;\n'+'''    printf("%zu native blit checks passed\\n",count);
    free(page_expected); if (munmap(mapping,(size_t)page*2)) return 2;
    return 0;
}
'''
    with tempfile.TemporaryDirectory(prefix='zbe-blit-') as directory:
        work=Path(directory)
        src,asm,driver,binary=[work/n for n in ('blit.ssa','blit.s','main.c','check')]
        src.write_text('\n'.join(il)+'\n'); driver.write_text(c)
        subprocess.run([str(args.compiler.resolve()),*flags,str(src),str(asm)],check=True,timeout=90)
        subprocess.run([args.cc,'-std=c11','-O2','-Wall','-Wextra','-Werror','-fPIE','-pie',str(driver),str(asm),str(root/'src/fixtures/check-preserved.s'),'-o',str(binary)],check=True,timeout=90)
        subprocess.run([str(binary)],check=True,timeout=30)
        for side in ('source','destination'):
            result=subprocess.run([str(binary),side],capture_output=True,timeout=10)
            if result.returncode != -signal.SIGSEGV:
                raise SystemExit(f'blit {side}: expected SIGSEGV, got {result.returncode}')
        print('2 blit memory-fault checks passed')
        for body in ('blit %p, %p, %n','blit %p, %p, -1','blit %p, %p, 2147483648','blit %n, %p, 1','blit %p, %n, 1','blit %p, %p, d_1'):
            src.write_text('function $f(l %p,w %n) {\n@e\n'+body+'\nret\n}')
            asm.unlink()
            for exists in (False,True):
                if exists: asm.write_text('preserve-blit-output')
                result=subprocess.run([str(args.compiler.resolve()),*flags,str(src),str(asm)],capture_output=True,timeout=30)
                if result.returncode==0: raise SystemExit('Invalid blit accepted')
                if (exists and asm.read_text()!='preserve-blit-output') or (not exists and asm.exists()):
                    raise SystemExit('Invalid blit changed output')
        print('12 blit rejection/output-preservation checks passed')


if __name__=='__main__':
    main()
