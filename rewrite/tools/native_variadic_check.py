#!/usr/bin/env python3
"""Independent promoted C stdarg and raw AL probes for call sites only."""
from pathlib import Path
import argparse
import platform
import resource
import subprocess
import tempfile

MASK=(1<<64)-1
RESULTS=('w','l','s','d','sb','ub','sh','uh')
C_TYPES={'w':'uint32_t','l':'uint64_t','s':'float','d':'double','sb':'int8_t','ub':'uint8_t','sh':'int16_t','uh':'uint16_t'}

def observe(value,kind):
    if kind=='l': return value&MASK
    if kind=='w': return value&0xffffffff
    if kind in ('s','d'): return value&65535
    width=8 if kind in ('sb','ub') else 16
    low=value&((1<<width)-1)
    if kind in ('sb','sh') and low>=1<<(width-1):low-=1<<width
    return low&MASK

def value(kind,signature,seed,index):
    raw=(signature*109+seed*193+index*419+0x8081)&65535
    if kind in ('s','d'):
        number=(signature+seed*7+index*3)%127
        return f'{kind}_{number}',number
    if kind=='l':
        number=0x9876543200000000|raw
        return str(number),number
    if kind=='w':
        number=0xabcdef00|raw
        return str(number),number
    width=8 if kind in ('sb','ub') else 16
    low=raw&((1<<width)-1)
    number=low-(1<<width) if kind in ('sb','sh') and low>=1<<(width-1) else low
    return str((0xabcdef00 if width==8 else 0xabcd0000)|low),number

def observation(kind):
    return {'w':'%observed =l extuw %raw','l':'%observed =l copy %raw',
            's':'%observed =l stosi %raw','d':'%observed =l dtosi %raw',
            'sb':'%observed =l extsb %raw','ub':'%observed =l extub %raw',
            'sh':'%observed =l extsh %raw','uh':'%observed =l extuh %raw'}[kind]

def call_source(name,target,result,types,values,prefix,indirect):
    items=[f'{t} {v}' for t,v in zip(types,values)]
    items.insert(prefix,'...')
    source=f'\nexport function l ${name}() {{\n@e\n'
    if indirect:source+=f'%target =l copy ${target}\n'
    source+=f'%raw ={result} call '+('%target' if indirect else '$'+target)+'('+', '.join(items)+')\n'
    return source+observation(result)+'\nret %observed\n}\n'

def main():
    root=Path(__file__).resolve().parents[1]
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--compiler',type=Path,default=root/'zig-out/bin/zbe-native')
    parser.add_argument('--cc',default='cc')
    options=('fold-integers','reuse-stack-homes','callee-saved-homes')
    for option in options:parser.add_argument('--'+option,action='store_true')
    args=parser.parse_args()
    if platform.system()!='Linux' or platform.machine() not in ('x86_64','amd64'):
        raise SystemExit('Variadic checks require Linux AMD64; no result claimed.')
    resource.setrlimit(resource.RLIMIT_CORE,(0,0))
    flags=['--'+option for option in options if getattr(args,option.replace('-','_'))]
    source=(root/'src/fixtures/variadic-calls.ssa').read_text()
    declarations=[];helpers=[];checks=[]
    for signature in range(64):
        gp=['l']*(signature%8)
        fp=['d']*(signature%9)
        if fp and signature%4==0:fp[0]='s' # Fixed single, never a C variable float.
        if gp and signature%5==0:gp[0]=('sb' if signature%2 else 'uh')
        named=(gp+fp if signature%2 else fp+gp)+['w']
        tail=[('w','d','l','d','l','w')[(signature+i)%6] for i in range(4+signature%17)]
        kinds=named+tail
        names=[f'a{i}' for i in range(len(named))]
        params=', '.join(f'{C_TYPES[t]} {n}' for t,n in zip(named,names))+', ...'
        lines=[f'{C_TYPES[RESULTS[signature%8]]} vararg_case_{signature}({params}) {{',
               'uint64_t acc=0; va_list ap;',f'va_start(ap,{names[-1]});']
        for i,(kind,name) in enumerate(zip(named,names)):
            term=f'(uint64_t)(int64_t){name}' if kind in ('sb','sh') else f'(uint64_t){name}'
            lines.append(f'acc+=({term})*UINT64_C({i+1});')
        for i,kind in enumerate(tail,len(named)):
            lines.append(f'acc+=(uint64_t)va_arg(ap,{C_TYPES[kind]})*UINT64_C({i+1});')
        lines.append('va_end(ap);')
        result=RESULTS[signature%8]
        if result in ('s','d'): lines.append(f'return ({C_TYPES[result]})(acc&UINT64_C(65535));')
        elif result in ('w','l'): lines.append(f'return ({C_TYPES[result]})acc;')
        else:
            width=8 if result in ('sb','ub') else 16
            lines.append(f'int64_t low=(int64_t)(acc&UINT64_C({(1<<width)-1}));')
            if result in ('sb','sh'):lines.append(f'if(low>={1<<(width-1)}) low-={1<<width};')
            lines.append(f'return ({C_TYPES[result]})low;')
        helpers.append('\n'.join(lines)+'\n}')
        for seed in range(3):
            pairs=[value(kind,signature,seed,i) for i,kind in enumerate(kinds)]
            values=[p[0] for p in pairs]
            expected=observe(sum((i+1)*p[1] for i,p in enumerate(pairs)),result)
            for indirect in (False,True):
                name=f'vararg_wrapper_{signature}_{seed}_{int(indirect)}'
                source+=call_source(name,f'vararg_case_{signature}',result,kinds,values,len(named),indirect)
                declarations.append(f'extern uint64_t {name}(void);')
                checks.append(f'REQUIRE({name}()==UINT64_C({expected}));')
    assert len(checks)==384
    probe_count=0
    for floats in range(13):
        types=['s' if i%2 else 'd' for i in range(floats)]+['w']
        values=[f'{t}_1' for t in types[:-1]]+['253']
        for prefix in sorted({0,floats//2,len(types)}):
            for indirect in (False,True):
                name=f'vararg_al_{floats}_{prefix}_{int(indirect)}'
                source+=call_source(name,'vararg_al_probe','w',types,values,prefix,indirect)
                declarations.append(f'extern uint64_t {name}(void);')
                checks.append(f'REQUIRE({name}()=={min(floats,8)});')
                probe_count+=1
    assert probe_count==74
    for indirect in (False,True):
        name=f'vararg_no_arguments_{int(indirect)}'
        source+=call_source(name,'vararg_al_probe','w',[],[],0,indirect)
        declarations.append(f'extern uint64_t {name}(void);')
        checks.append(f'REQUIRE({name}()==0);')
        name=f'vararg_no_tail_{int(indirect)}'
        source+=call_source(name,'vararg_empty','l',['d','w'],['d_2','253'],2,indirect)
        declarations.append(f'extern uint64_t {name}(void);')
        checks.append(f'REQUIRE({name}()==255);')
    source+='''
export function l $vararg_preserved() {
@e
%a =l copy 81985529216486895
%b =l copy 18364758544493064720
%c =l copy 1234605616436508552
%d =l copy 9833440827789222417
%e =l copy 1084818905618843912
%unused =w call $vararg_al_probe(w 253, ...)
%ab =l xor %a, %b
%cd =l xor %c, %d
%abcd =l xor %ab, %cd
%r =l xor %abcd, %e
ret %r
}
'''
    preserved=81985529216486895^18364758544493064720^1234605616436508552^9833440827789222417^1084818905618843912
    checks.extend([f'REQUIRE(vararg_preserved()==UINT64_C({preserved}));','REQUIRE(zbe_check_preserved(vararg_preserved)==0);'])
    c='''#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <stdarg.h>
#include <string.h>
extern uint64_t vararg_sum(void),vararg_allocated(void),vararg_preserved(void);
extern uint32_t vararg_effects(void),vararg_phi(uint32_t),vararg_safe(uint32_t,uintptr_t),vararg_format(unsigned char *);
extern uint32_t vararg_al_probe(void);
extern uint64_t zbe_check_preserved(uint64_t (*)(void));
static unsigned accumulate_calls,recorded;
uint64_t vararg_accumulate(uint32_t count,...) {
 if(count!=3) abort();
 va_list ap;va_start(ap,count);
 uint32_t a=va_arg(ap,uint32_t);uint64_t b=va_arg(ap,uint64_t);double c=va_arg(ap,double);
 va_end(ap);++accumulate_calls;return a+3*b+5*(uint64_t)c;
}
void vararg_record(uint32_t tag,...) {
 if(tag!=1) abort();
 va_list ap;va_start(ap,tag);unsigned a=va_arg(ap,unsigned);double b=va_arg(ap,double);va_end(ap);
 recorded+=a+(unsigned)b;
}
uint64_t vararg_many(uint32_t count,...) {
 if(count!=10) abort();
 va_list ap;va_start(ap,count);uint64_t sum=0;
 for(unsigned i=0;i<10;++i) sum+=va_arg(ap,uint64_t)*(i+1);
 va_end(ap);return sum;
}
uint64_t vararg_empty(double named,uint32_t seed,...) {
 va_list ap;va_start(ap,seed);va_end(ap);return (uint64_t)named+seed;
}
#define REQUIRE(c) do {++count;if(!(c)){fprintf(stderr,"variadic check %zu failed\\n",count);return 1;}} while(0)
'''+ '\n'.join(declarations+helpers)+'''\nint main(int argc,char **argv) {
 (void)argv;
 if(argc>1 && ((uintptr_t)vararg_al_probe>>32)==0) {fprintf(stderr,"PIE callback high-address precondition failed\\n");return 2;}
 size_t count=0;
 REQUIRE(vararg_sum()==88);
 REQUIRE(vararg_allocated()==UINT64_C(4294967682));
 accumulate_calls=0;recorded=0;
 REQUIRE(vararg_effects()==9);REQUIRE(accumulate_calls==1);REQUIRE(recorded==19);
 for(unsigned i=0;i<32;++i) REQUIRE(vararg_phi(i)==44*i);
 REQUIRE(vararg_safe(0,0)==42);
 REQUIRE(vararg_safe(1,(uintptr_t)vararg_al_probe)==0);
 unsigned char buffer[64];memset(buffer,0xa5,sizeof buffer);
 REQUIRE(vararg_format(buffer)==7);REQUIRE(strcmp((const char *)buffer,"123 1.5")==0);
 for(unsigned i=8;i<64;++i) REQUIRE(buffer[i]==0xa5);
'''+ '\n'.join(checks)+f'\n if(count!={97+len(checks)}) return 3;\n printf("%zu native variadic call/AL checks passed\\n",count);\n return 0;\n}}\n'
    adapters='''.text
.globl vararg_al_probe
.type vararg_al_probe, @function
vararg_al_probe:
 movzbl %al, %eax
 ret
.section .note.GNU-stack,"",@progbits
'''
    with tempfile.TemporaryDirectory(prefix='zbe-variadic-') as directory:
        work=Path(directory)
        src,asm,driver,adapter,binary=[work/name for name in ('variadic.ssa','variadic.s','main.c','adapters.s','check')]
        src.write_text(source);driver.write_text(c);adapter.write_text(adapters)
        compiler=str(args.compiler.resolve())
        subprocess.run([compiler,*flags,str(src),str(asm)],check=True,timeout=120)
        for pie in (False,True):
            mode=['-fPIE','-pie'] if pie else ['-fno-pie','-no-pie']
            subprocess.run([args.cc,'-std=c11','-O2','-Wall','-Wextra','-Werror',*mode,str(driver),str(asm),str(adapter),str(root/'src/fixtures/check-preserved.s'),'-o',str(binary)],check=True,timeout=90)
            subprocess.run([str(binary),*(['high-address'] if pie else [])],check=True,timeout=30)
            dynamic=subprocess.run(['readelf','-d',str(binary)],capture_output=True,text=True,check=True,timeout=30).stdout
            if 'TEXTREL' in dynamic:raise SystemExit('Variadic calls introduced a dynamic text relocation')
        print('2 variadic executable no-TEXTREL checks passed')
        bad=[
            'function $f(...) {\n@e\nret\n}',
            'function w $f(w %n, ...) {\n@e\nret %n\n}',
            'function w $f() {\n@e\n%x =w call $g(..., ...)\nret %x\n}',
            'function w $f() {\n@e\n%x =w call $g(w 1, ..., w 2, ...)\nret %x\n}',
            'function w $f() {\n@e\n%x =w call $g(...,)\nret %x\n}',
            'function w $f() {\n@e\n%x =w call $g(... w 1)\nret %x\n}',
            'function w $f() {\n@e\n%x =w call $g(w 1 ...)\nret %x\n}',
            'function w $f() {\n@e\n%x =w call $g(,...)\nret %x\n}',
            'function w $f() {\n@e\n%x =w call $g(...)\nret %x\n}\nfunction w $g() {\n@e\nret 1\n}',
            'function $f() {\n@e\ncall $g(...)\nret\n}\nfunction $g() {\n@e\nret\n}',
            'function w $f() {\n@e\n%x =sb call $g(sb 1, ...)\nret 0\n}\nfunction sb $g(sb %x) {\n@e\nret %x\n}',
            'function w $f() {\n@e\nret 0\n@u\n%x =w call $g(...)\nret %x\n}\nfunction w $g() {\n@e\nret 1\n}',
            'function $f(l %p) {\n@e\nvastart %p\nret\n}',
            'function w $f(l %p) {\n@e\n%x =w vaarg %p\nret %x\n}',
            'function $f() {\n@e\ncall $g(env 0, ...)\nret\n}',
            'function w $f(w %p) {\n@e\n%x =w call %p(...)\nret %x\n}',
        ]
        assert len(bad)==16
        for text in bad:
            src.write_text(text)
            if asm.exists():asm.unlink()
            for exists in (False,True):
                if exists:asm.write_text('preserve-variadic-output')
                result=subprocess.run([compiler,*flags,str(src),str(asm)],capture_output=True,timeout=30)
                if result.returncode==0:raise SystemExit('Invalid/unsupported variadic call accepted')
                if (exists and asm.read_text()!='preserve-variadic-output') or (not exists and asm.exists()):
                    raise SystemExit('Rejected variadic call changed output')
        print('32 variadic rejection/output-preservation checks passed')

if __name__=='__main__':main()
