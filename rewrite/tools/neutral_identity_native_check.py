#!/usr/bin/env python3
"""Independent neutral-identity runtime, projection, symbol and fault controls."""
import argparse
from pathlib import Path
import platform
import resource
import signal
import subprocess
import tempfile


def main():
    root=Path(__file__).resolve().parents[1]
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--compiler',type=Path,default=root/'zig-out/bin/zbe-native');p.add_argument('--cc',default='cc')
    for f in ('fold-integers','reuse-stack-homes','callee-saved-homes'): p.add_argument('--'+f,action='store_true')
    args=p.parse_args()
    if platform.system()!='Linux' or platform.machine() not in ('amd64','x86_64'): raise SystemExit('Requires Linux AMD64; no passing claim')
    resource.setrlimit(resource.RLIMIT_CORE,(0,0))
    flags=['--'+f for f in ('fold-integers','reuse-stack-homes','callee-saved-homes') if getattr(args,f.replace('-','_'))]
    declarations=[];functions=[];checks=[]
    for i,line in enumerate(x for x in (root/'src/fixtures/neutral_identity_oracle.tsv').read_text().splitlines() if not x.startswith('#')):
        ty,op,side,n,x,expected,_=line.split();ctype='uint32_t' if ty=='w' else 'uint64_t'
        a,b=(n,'%x') if side=='1' else ('%x',n)
        # Shift amount is word, so the symmetric input-side near miss is binary only.
        functions.append(f'export function {ty} $ni_{i}({ty} %x) {{\n@e\n%r ={ty} {op} {a}, {b}\nret %r\n}}')
        declarations.append(f'extern {ctype} ni_{i}({ctype});')
        checks.append(f'REQUIRE(ni_{i}(({ctype})UINT64_C({x}))==({ctype})UINT64_C({expected}));')
    functions += ['''export function w $ni_project(l %x) {
@e
%n =l copy 4294967328
%r =w sar %x, %n
ret %r
}
export function l $ni_symbol() {
@e
%r =l add $ni_storage+7, 0
ret %r
}
export function l $ni_fault(l %x,l %y) {
@e
%n =l mul %x, 1
%r =l div %n, %y
ret %r
}
export function l $ni_order(l %p) {
@e
storel 77, %p
%v =l loadl %p
%r =l add %v, 0
ret %r
}''']
    declarations += ['extern uint32_t ni_project(uint64_t);','extern uintptr_t ni_symbol(void);','extern uint64_t ni_fault(uint64_t,uint64_t);','extern uint64_t ni_order(void *);','unsigned char ni_storage[32];']
    checks += ['REQUIRE(ni_project(UINT64_C(0xdeadbeef80000001))==UINT32_C(0x80000001));','REQUIRE(ni_symbol()==(uintptr_t)&ni_storage[7]);','uint64_t cell=0; REQUIRE(ni_order(&cell)==77 && cell==77);']
    c='#include <stdint.h>\n#include <stdio.h>\n'+ '\n'.join(declarations)+ '\n#define REQUIRE(c) do { ++count; if (!(c)) { fprintf(stderr,"neutral identity check %zu failed\\n",count); return 1; } } while(0)\nint main(int argc,char **argv) { (void)argv; if(argc>1) { volatile uint64_t r=ni_fault(argc==2?1:UINT64_C(0x8000000000000000),argc==2?0:UINT64_MAX); (void)r; return 0; } size_t count=0;\n'+ '\n'.join(checks)+'\nprintf("%zu native neutral identity checks passed\\n",count); return 0; }\n'
    with tempfile.TemporaryDirectory(prefix='zbe-neutral-identity-') as d:
        work=Path(d);src=work/'n.ssa';asm=work/'n.s';driver=work/'main.c';binary=work/'check'
        src.write_text('\n'.join(functions));driver.write_text(c)
        subprocess.run([str(args.compiler.resolve()),*flags,str(src),str(asm)],check=True,timeout=90)
        for link in (['-fPIE','-pie'],['-fno-pie','-no-pie']):
            subprocess.run([args.cc,'-std=c11','-O2','-Wall','-Wextra','-Werror',*link,str(asm),str(driver),'-o',str(binary)],check=True,timeout=90)
            subprocess.run([str(binary)],check=True,timeout=30)
            for a in (['zero'],['min','minus-one']):
                r=subprocess.run([str(binary),*a],capture_output=True,timeout=30)
                if r.returncode != -signal.SIGFPE: raise SystemExit('Integer fault erased')
        print('4 neutral identity integer-fault controls passed (PIE/non-PIE)')
if __name__=='__main__': main()
