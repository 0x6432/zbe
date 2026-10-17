#!/usr/bin/env python3
"""Independent C/IL scalar variadic-body and protected fixed-frame checks."""
from pathlib import Path
import argparse
import platform
import re
import resource
import signal
import subprocess
import tempfile

MASK=(1<<64)-1
C_TYPES={'w':'uint32_t','l':'uint64_t','s':'float','d':'double','sb':'int8_t','ub':'uint8_t','sh':'int16_t','uh':'uint16_t'}

def observation(kind,destination,operand):
    op={'w':'extuw','l':'copy','s':'stoui','d':'dtoui','sb':'extsb','ub':'extub','sh':'extsh','uh':'extuh'}[kind]
    return f'{destination} =l {op} {operand}\n'

def number(kind,case,seed,index):
    n=(case*11+seed*31+index*7+1)%97
    if kind=='l':n|=0x9876543200000000
    if kind in ('sb','sh'):n=-n
    il=(f'{kind}_{n}' if kind in ('s','d') else str(n&MASK))
    c=(f'{n}.0' if kind in ('s','d') else f'({C_TYPES[kind]})({n})' if kind in ('sb','sh') else f'UINT64_C({n})' if kind=='l' else f'{n}U')
    return il,c,n&MASK

def pressure(count):
    lines=[f'export function l $varfn_guard{count}(...) {{','@entry','ret 42','@unused']
    lines += [f'%v{i} =l call $varfn_unknown()' for i in range(count)]
    previous='%v0'
    for i in range(1,count):lines += [f'%sum{i} =l add {previous}, %v{i}'];previous=f'%sum{i}'
    return '\n'.join(lines+[f'ret {previous}','}'])+'\n'

def main():
    root=Path(__file__).resolve().parents[1]
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--compiler',type=Path,default=root/'zig-out/bin/zbe-native');p.add_argument('--cc',default='cc')
    option_names=('fold-integers','reuse-stack-homes','callee-saved-homes')
    for name in option_names:p.add_argument('--'+name,action='store_true')
    args=p.parse_args()
    if platform.system()!='Linux' or platform.machine() not in ('x86_64','amd64'):raise SystemExit('Variadic body checks require Linux AMD64; no result claimed')
    resource.setrlimit(resource.RLIMIT_CORE,(0,0))
    flags=['--'+n for n in option_names if getattr(args,n.replace('-','_'))]
    source=(root/'src/fixtures/variadic-functions.ssa').read_text()+'\n'+pressure(1024)+pressure(1536)
    declarations=[];readers=[];checks=[]
    for case in range(64):
        gp=['l']*(case%9);fp=['d']*((case*3)%11)
        if gp and case%4==0:gp[0]=('sb','ub','sh','uh')[case//4%4]
        if fp and case%5==0:fp[0]='s' # Named single is legal; never a C variable float.
        named=(gp+fp if case%2 else fp+gp)+['w']
        tail=[('w','l','d','l','d')[(case+i)%5] for i in range(2+case%21)]
        params=', '.join(f'{t} %p{i}' for i,t in enumerate(named))
        name=f'varfn_case_{case}'
        source+=f'\nexport function l ${name}({params}, ...) {{\n@entry\n%list =l alloc16 24\nvastart %list\n%ctail =l call $varfn_reader_{case}(l %list)\nvastart %list\n'
        previous='%ctail'
        for i,t in enumerate(named):
            source+=observation(t,f'%named{i}',f'%p{i}')+f'%nm{i} =l mul %named{i}, {i+1}\n%ns{i} =l add {previous}, %nm{i}\n';previous=f'%ns{i}'
        for i,t in enumerate(tail):
            source+=f'%v{i} ={t} vaarg %list\n'+observation(t,f'%x{i}',f'%v{i}')+f'%m{i} =l mul %x{i}, {len(named)+i+1}\n%sum{i} =l add {previous}, %m{i}\n';previous=f'%sum{i}'
        source+=f'ret {previous}\n}}\n'
        declarations.append(f'extern uint64_t {name}('+', '.join(C_TYPES[t] for t in named)+', ...);')
        gp_count=sum(t not in ('s','d') for t in named);fp_count=len(named)-gp_count
        reader=[f'uint64_t varfn_reader_{case}(va_list ap) {{', 'uint32_t fields[2];memcpy(fields,ap,8);void *save;memcpy(&save,(char *)ap+16,8);',f'INTERNAL(fields[0]=={min(gp_count,6)*8} && fields[1]=={48+min(fp_count,8)*16});','INTERNAL(((uintptr_t)save&15)==0);','uint64_t sum=0;']
        for i,t in enumerate(tail):reader.append(f'sum+=(uint64_t)va_arg(ap,{C_TYPES[t]})*UINT64_C({len(named)+i+1});')
        reader.append('return sum;}');readers.append('\n'.join(reader))
        for seed in range(3):
            vals=[number(t,case,seed,i) for i,t in enumerate(named+tail)]
            expected=sum(n*(i+1) for i,(_,_,n) in enumerate(vals))
            expected+=sum(vals[len(named)+i][2]*(len(named)+i+1) for i in range(len(tail)))
            checks.append(f'REQUIRE({name}('+','.join(c for _,c,_ in vals)+f')==UINT64_C({expected&MASK}));')
            if seed==0:
                items=[f'{t} {v}' for t,(v,_,_) in zip(named+tail,vals)];items.insert(len(named),'...')
                for indirect in (False,True):
                    caller=f'varfn_call_{case}_{int(indirect)}'
                    source+=f'\nexport function l ${caller}() {{\n@e\n'
                    if indirect:source+=f'%target =l copy ${name}\n'
                    source+=f'%r =l call '+('%target' if indirect else '$'+name)+'('+', '.join(items)+')\nret %r\n}\n'
                    declarations.append(f'extern uint64_t {caller}(void);');checks.append(f'REQUIRE({caller}()==UINT64_C({expected&MASK}));')
    for result in ('w','l','s','d','sb','ub','sh','uh'):
        name='varfn_return_'+result
        source+=f'\nexport function {result} ${name}(w %anchor, ...) {{\n@e\n%list =l alloc16 24\nvastart %list\n%value =w vaarg %list\n'
        if result=='l':source+='%result =l extuw %value\nret %result\n}\n'
        elif result in ('s','d'):source+=f'%result ={result} swtof %value\nret %result\n}}\n'
        else:source+='ret %value\n}\n'
        declarations.append(f'extern {C_TYPES[result]} {name}(uint32_t,...);')
        checks.append(f'REQUIRE({name}(0,21U)==21);')
        for indirect in (False,True):
            caller=f'varfn_return_call_{result}_{int(indirect)}'
            source+=f'\nexport function l ${caller}() {{\n@e\n'
            if indirect:source+=f'%target =l copy ${name}\n'
            source+=f'%raw ={result} call '+('%target' if indirect else '$'+name)+'(w 0, ..., w 21)\n'
            source+=observation(result,'%result','%raw')+'ret %result\n}\n'
            declarations.append(f'extern uint64_t {caller}(void);')
            checks.append(f'REQUIRE({caller}()==21);')
    # Raw IL-to-IL single tails are deliberately not C va_arg(float) contracts.
    for kind,integer,patterns in (
        ('s','w',(0,0x80000000,1,0x7f800000,0x7fc12345,0x7f800001,0xffffffff,0x3f800000)),
        ('d','l',(0,0x8000000000000000,1,0x7ff0000000000000,0x7ff8123456789abc,0x7ff0000000000001,MASK,0x3ff0000000000000))):
        for length in (1,9):
            callee=f'varfn_raw_{kind}_{length}'
            source+=f'\nfunction {integer} ${callee}(w %anchor, ...) {{\n@e\n%list =l alloc16 24\nvastart %list\n'
            for i in range(length):source+=f'%v{i} ={kind} vaarg %list\n'
            source+=f'%bits ={integer} cast %v{length-1}\nret %bits\n}}\n'
            for index,bits in enumerate(patterns):
                caller=f'varfn_raw_call_{kind}_{length}_{index}'
                source+=f'\nexport function l ${caller}() {{\n@e\n%bits ={integer} copy {bits}\n%value ={kind} cast %bits\n%zero ={kind} copy {kind}_0\n'
                arguments=['w 0','...']+[f'{kind} %zero']*(length-1)+[f'{kind} %value']
                source+=f'%raw ={integer} call ${callee}('+', '.join(arguments)+')\n'
                source+=observation(integer,'%result','%raw')+'ret %result\n}\n'
                declarations.append(f'extern uint64_t {caller}(void);')
                checks.append(f'REQUIRE({caller}()==UINT64_C({bits}));')
    source+='''
export function l $varfn_outgoing(w %anchor, ...) {
@e
%object =l alloc16 16
storel 4294967297, %object
%list =l alloc16 24
vastart %list
%a =l vaarg %list
%c =l call $varfn_many(l 1, l 2, l 3, l 4, l 5, l 6, l 7, l 8, l 9, l 10)
%b =l vaarg %list
%saved =l loadl %object
%sum =l add %a, %b
%with_call =l add %sum, %c
%result =l add %with_call, %saved
ret %result
}
export function l $varfn_recursive(w %depth, ...) {
@e
%list =l alloc16 24
vastart %list
%first =l vaarg %list
jnz %depth, @child, @base
@child
%next =w sub %depth, 1
%a =l add %first, 1
%b =l add %first, 12
%child_sum =l call $varfn_recursive(w %next, ..., l %a, l %b)
%second =l vaarg %list
%pair =l add %first, %second
%result =l add %pair, %child_sum
ret %result
@base
%last =l vaarg %list
%base_sum =l add %first, %last
ret %base_sum
}
'''
    c=r'''#define _GNU_SOURCE
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdarg.h>
#include <sys/mman.h>
static size_t count;
#define REQUIRE(x) do {if(!(x)){fprintf(stderr,"varfn check failed line %d\n",__LINE__);exit(1);}++count;}while(0)
#define INTERNAL(x) do {if(!(x)){fprintf(stderr,"varfn descriptor failed line %d\n",__LINE__);abort();}}while(0)
_Static_assert(sizeof(va_list)==24,"SysV descriptor required");
extern uint64_t vaf_sum(uint32_t,...),vaf_copy(uint32_t,...),vaf_external(uint32_t,...),vaf_internal(void);
extern double vaf_double(uint32_t,...);
extern uint32_t vaf_named(uint32_t,...),vaf_safe(uint32_t,...);
extern uint64_t varfn_guard1024(void),varfn_guard1536(void);
extern uint64_t zbe_check_preserved(uint64_t (*)(void));
extern uint64_t zbe_on_stack(void *,uint64_t (*)(void));
uint64_t varfn_unknown(void){abort();}
uint64_t vaf_c_reader(va_list ap){uint64_t a=va_arg(ap,uint64_t);uint64_t b=va_arg(ap,uint64_t);return a+b;}
extern uint64_t varfn_outgoing(uint32_t,...);
extern uint64_t varfn_recursive(uint32_t,...);
uint64_t varfn_many(uint64_t a,uint64_t b,uint64_t c,uint64_t d,uint64_t e,uint64_t f,uint64_t g,uint64_t h,uint64_t i,uint64_t j) {
 return a+2*b+3*c+4*d+5*e+6*f+7*g+8*h+9*i+10*j;
}
'''+ '\n'.join(declarations)+'\n'+'\n'.join(readers)+r'''
int main(int argc,char **argv) {
 if(argc>1 && argv[1][0]>='0' && argv[1][0]<='9'){
   int index=atoi(argv[1]);if(index<1 || index>2)return 2;
   size_t bytes=32*4096;
   unsigned char *memory=mmap(NULL,bytes,PROT_NONE,MAP_PRIVATE|MAP_ANONYMOUS,-1,0);
   if(memory==MAP_FAILED)return 3;
   if(mprotect(memory,30*4096,PROT_READ|PROT_WRITE) || mprotect(memory+31*4096,4096,PROT_READ|PROT_WRITE))return 4;
   uint64_t result=zbe_on_stack(memory+bytes-128,index==1?varfn_guard1024:varfn_guard1536);
   if(munmap(memory,bytes))return 5;
   return result==42?0:6;
 }
 if(argc>1 && (uintptr_t)vaf_sum<=UINT32_MAX)return 7;
'''+ '\n'.join(checks)+r'''
 REQUIRE(vaf_sum(0)==0);REQUIRE(vaf_sum(1,UINT64_C(11))==11);
 REQUIRE(vaf_sum(10,UINT64_C(1),UINT64_C(2),UINT64_C(3),UINT64_C(4),UINT64_C(5),UINT64_C(6),UINT64_C(7),UINT64_C(8),UINT64_C(9),UINT64_C(10))==55);
 REQUIRE(vaf_double(0)==0.0);REQUIRE(vaf_double(10,1.0,2.0,3.0,4.0,5.0,6.0,7.0,8.0,9.0,10.0)==55.0);
 REQUIRE(vaf_named(42)==42);REQUIRE(vaf_named(42,UINT64_C(1),2.0)==42);REQUIRE(vaf_safe(0)==42);
 REQUIRE(vaf_copy(0,UINT64_C(11),UINT64_C(22))==44);
 REQUIRE(vaf_external(0,UINT64_C(11),UINT64_C(22))==33);
 REQUIRE(vaf_internal()==66);
 REQUIRE(varfn_outgoing(0,UINT64_C(11),UINT64_C(22))==UINT64_C(4294967715));
 REQUIRE(varfn_recursive(3,UINT64_C(11),UINT64_C(22))==144);
 REQUIRE(varfn_guard1024()==42);REQUIRE(varfn_guard1536()==42);
 REQUIRE(zbe_check_preserved(varfn_guard1024)==0);REQUIRE(zbe_check_preserved(varfn_guard1536)==0);
 if(count!=393)return 8;
 printf("%zu native variadic body checks passed\n",count);return 0;
}
'''
    with tempfile.TemporaryDirectory(prefix='zbe-varfn-') as directory:
        work=Path(directory);src,asm,driver,binary,mutated,control=[work/n for n in ('input.ssa','output.s','main.c','check','unprobed.s','control')]
        src.write_text(source);driver.write_text(c);compiler=str(args.compiler.resolve())
        subprocess.run([compiler,*flags,str(src),str(asm)],check=True,timeout=120)
        assembly=asm.read_text()
        for n in (1024,1536):
            prologue=assembly.split(f'varfn_guard{n}:\n',1)[1].split('".Lzbe@',1)[0]
            steps=list(map(int,re.findall(r'\tsubq \$(\d+), %rsp\n',prologue)))
            if not steps or sum(steps)<8192+176 or any(not 0<s<=4096 or s%16 for s in steps):raise SystemExit('Variadic frame reservation is not bounded/aligned')
            if prologue.count('\ttestb $0, (%rsp)\n')!=len(steps):raise SystemExit('Missing variadic frame probes')
            if prologue.count('movdqu %xmm')!=8:raise SystemExit('Incomplete variadic SSE save bank')
        adapters=[str(root/'src/fixtures/frame-stack.s'),str(root/'src/fixtures/check-preserved.s')]
        for pie in (False,True):
            mode=['-fPIE','-pie'] if pie else ['-fno-pie','-no-pie']
            link=[args.cc,'-std=c11','-O2','-Wall','-Wextra','-Werror',*mode,str(driver)]
            subprocess.run([*link,str(asm),*adapters,'-o',str(binary)],check=True,timeout=90)
            subprocess.run([str(binary),*(['high-address'] if pie else [])],check=True,timeout=30)
            dynamic=subprocess.run(['readelf','-d',str(binary)],capture_output=True,text=True,check=True,timeout=30).stdout
            if 'TEXTREL' in dynamic:raise SystemExit('Variadic body introduced a text relocation')
        print('2 variadic body no-TEXTREL checks passed')
        for index in (1,2):
            result=subprocess.run([str(binary),str(index)],capture_output=True,timeout=30)
            if result.returncode!=-signal.SIGSEGV:raise SystemExit('Variadic frame did not stop at protected guard')
        print('2 variadic frame guard-page SIGSEGV checks passed')
        mutated.write_text(assembly.replace('\ttestb $0, (%rsp)\n',''))
        subprocess.run([*link,str(mutated),*adapters,'-o',str(control)],check=True,timeout=90)
        for index in (1,2):subprocess.run([str(control),str(index)],check=True,timeout=30)
        print('2 unprobed variadic frame negative controls passed')
        bad=[
            'function $f(..., w %p) {\n@e\nret\n}',
            'function $f(..., ...) {\n@e\nret\n}',
            'function $f(w %p, ...,) {\n@e\nret\n}',
            'function $f(w %p ...) {\n@e\nret\n}',
            'function $f(l %p) {\n@e\nvastart %p\nret\n}',
            'function $f(w %p, ...) {\n@e\nvastart %p\nret\n}',
            'function $f(l %p, ...) {\n@e\nvastart %p, %p\nret\n}',
            'function $f() {\n@e\ncall $g(w 1)\nret\n}\nfunction $g(w %p, ...) {\n@e\nret\n}',
            'function $f() {\n@e\ncall $g(..., w 1)\nret\n}\nfunction $g(w %p, ...) {\n@e\nret\n}',
            'function $f() {\n@e\ncall $g(l 1, ...)\nret\n}\nfunction $g(w %p, ...) {\n@e\nret\n}',
        ]
        for text in bad:
            src.write_text(text)
            if asm.exists():asm.unlink()
            for exists in (False,True):
                if exists:asm.write_text('preserve-varfn-output')
                result=subprocess.run([compiler,*flags,str(src),str(asm)],capture_output=True,timeout=30)
                if result.returncode==0:raise SystemExit('Invalid variadic body accepted')
                if (exists and asm.read_text()!='preserve-varfn-output') or (not exists and asm.exists()):raise SystemExit('Rejected variadic body changed output')
        print('20 variadic body rejection/output-preservation checks passed')

if __name__=='__main__':main()
