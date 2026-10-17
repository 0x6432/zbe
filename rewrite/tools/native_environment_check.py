#!/usr/bin/env python3
"""Independent Linux AMD64 hidden-RAX environment ABI checks; no host interpreter."""
from pathlib import Path
import argparse
import platform
import resource
import subprocess
import tempfile

MASK=(1<<64)-1
TYPES={'w':'uint32_t','l':'uint64_t','s':'float','d':'double','sb':'int8_t','ub':'uint8_t','sh':'int16_t','uh':'uint16_t'}

def observe(kind,out,value):
    return f'{out} =l '+{'w':'extuw','l':'copy','s':'stoui','d':'dtoui','sb':'extsb','ub':'extub','sh':'extsh','uh':'extuh'}[kind]+f' {value}\n'

def main():
    root=Path(__file__).resolve().parents[1]
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--compiler',type=Path,default=root/'zig-out/bin/zbe-native')
    parser.add_argument('--cc',default='cc')
    options=('fold-integers','reuse-stack-homes','callee-saved-homes')
    for o in options:parser.add_argument('--'+o,action='store_true')
    args=parser.parse_args()
    if platform.system()!='Linux' or platform.machine() not in ('x86_64','amd64'):raise SystemExit('Environment checks require Linux AMD64; no success claimed')
    resource.setrlimit(resource.RLIMIT_CORE,(0,0))
    flags=['--'+o for o in options if getattr(args,o.replace('-','_'))]
    source=(root/'src/fixtures/environment-calls.ssa').read_text()
    declarations=[];helpers=[];checks=[];adapters=['.text']
    # Assembly thunks set only RAX and tail-jump, leaving C banks/overflow intact.
    # Independent outbound thunks capture RAX before entering ordinary C readers.
    for case in range(64):
        gp=['l']*(case%9);fp=['d']*((case*3)%11)
        if gp and case%4==0:gp[0]=('sb','ub','sh','uh')[(case//4)%4]
        if fp and case%5==0:fp[0]='s'
        types=gp+fp if case%2 else fp+gp
        params=', '.join(f'{t} %p{i}' for i,t in enumerate(types))
        name=f'environment_case_{case}'
        source+=f'\nexport function l ${name}(env %hidden'+(', '+params if params else '')+') {\n@e\n'
        previous='%hidden'
        for i,t in enumerate(types):
            source+=observe(t,f'%v{i}',f'%p{i}')+f'%m{i} =l mul %v{i}, {i+1}\n%sum{i} =l add {previous}, %m{i}\n';previous=f'%sum{i}'
        source+=f'ret {previous}\n}}\n'
        signature=', '.join(TYPES[t]+f' p{i}' for i,t in enumerate(types)) or 'void'
        helpers.append(f'uint64_t environment_reader_{case}({signature}) {{ return environment_seen'+''.join(f'+(uint64_t)p{i}*UINT64_C({i+1})' for i in range(len(types)))+'; }')
        probe=f'environment_probe_{case}'
        adapters += [f'.globl {probe}',f'.type {probe}, @function',f'{probe}:','movq %rax, environment_seen(%rip)',f'jmp environment_reader_{case}',f'.size {probe}, .-{probe}']
        for seed in range(3):
            hidden=(0x98765432000000a5+case*0x10001+seed*0x8000000001)&MASK
            vals=[]
            for i,t in enumerate(types):
                n=(case*11+seed*31+i*7+1)%97
                if t=='l':n|=0x1234567800000000
                if t in ('sb','sh'):n=-n
                il=f'{t}_{n}' if t in ('s','d') else str(n&MASK)
                c=f'{n}.0' if t in ('s','d') else f'({TYPES[t]})({n})' if t in ('sb','ub','sh','uh') else f'UINT64_C({n})' if t=='l' else f'{n}U'
                vals.append((il,c,n&MASK))
            expected=(hidden+sum(n*(i+1) for i,(_,_,n) in enumerate(vals)))&MASK
            thunk=f'environment_in_{case}_{seed}'
            adapters += [f'.globl {thunk}',f'.type {thunk}, @function',f'{thunk}:',f'movabsq ${hidden}, %rax',f'jmp {name}',f'.size {thunk}, .-{thunk}']
            declarations.append(f'extern uint64_t {thunk}({signature});')
            checks.append(f'REQUIRE({thunk}('+','.join(c for _,c,_ in vals)+f')==UINT64_C({expected}));')
            for external in (False,True):
                for indirect in (False,True):
                    target=probe if external else name
                    caller=f'environment_call_{case}_{seed}_{int(external)}_{int(indirect)}'
                    source+=f'\nexport function l ${caller}() {{\n@e\n'
                    if indirect:source+=f'%target =l copy ${target}\n'
                    callargs=[f'env {hidden}']+[f'{t} {v}' for t,(v,_,_) in zip(types,vals)]
                    source+='%r =l call '+('%target' if indirect else '$'+target)+'('+', '.join(callargs)+')\nret %r\n}\n'
                    declarations.append(f'extern uint64_t {caller}(void);')
                    checks.append(f'REQUIRE({caller}()==UINT64_C({expected}));')
    for result in TYPES:
        name='environment_return_'+result
        source+=f'\nexport function {result} ${name}(env %hidden, uh %p) {{\n@e\n%h =w copy %hidden\n%pwide =w extuh %p\n%v =w add %h, %pwide\n'
        if result=='l':source+='%out =l extuw %v\nret %out\n}\n'
        elif result in ('s','d'):source+=f'%out ={result} swtof %v\nret %out\n}}\n'
        else:source+='ret %v\n}\n'
        thunk=name+'_in'
        adapters += [f'.globl {thunk}',f'{thunk}:','movq $14, %rax',f'jmp {name}']
        declarations.append(f'extern {TYPES[result]} {thunk}(uint16_t);')
        checks.append(f'REQUIRE({thunk}(7)==21);')
        for indirect in (False,True):
            caller=name+f'_call{int(indirect)}'
            source+=f'\nexport function l ${caller}() {{\n@e\n'
            if indirect:source+=f'%target =l copy ${name}\n'
            source+=f'%raw ={result} call '+('%target' if indirect else '$'+name)+'(env 14, uh 7)\n'+observe(result,'%answer','%raw')+'ret %answer\n}\n'
            declarations.append(f'extern uint64_t {caller}(void);');checks.append(f'REQUIRE({caller}()==21);')
    for i,bits in enumerate((0,1,0x100000001,0x8000000000000000,0xffff000000000001,MASK-1,MASK)):
        thunk=f'environment_bits_{i}'
        adapters += [f'.globl {thunk}',f'{thunk}:',f'movabsq ${bits}, %rax','jmp env_get']
        declarations.append(f'extern uint64_t {thunk}(void);');checks.append(f'REQUIRE({thunk}()==UINT64_C({bits}));')
        caller=thunk+'_call'
        source+=f'\nexport function l ${caller}() {{\n@e\n%r =l call $env_get(env {bits})\nret %r\n}}\n'
        declarations.append(f'extern uint64_t {caller}(void);');checks.append(f'REQUIRE({caller}()==UINT64_C({bits}));')
    # Used after a large probed prologue; frame pressure is unreachable but live.
    source+='\nexport function l $environment_large(env %hidden) {\n@e\nret %hidden\n@dead\n'
    source+='\n'.join(f'%v{i} =l call $environment_unknown()' for i in range(1024))+'\n'
    previous='%v0'
    for i in range(1,1024):source+=f'%sum{i} =l add {previous}, %v{i}\n';previous=f'%sum{i}'
    source+=f'ret {previous}\n}}\n'
    adapters += ['.globl environment_large_in','environment_large_in:','movabsq $0xdeadbeef01234567, %rax','jmp environment_large',
                 '.globl environment_recursive_in','environment_recursive_in:','movq $100, %rax','jmp env_recursive',
                 '.globl environment_phi_in','environment_phi_in:','movq $100, %rax','jmp env_phi',
                 '.globl environment_identity_probe','environment_identity_probe:','ret',
                 '.section .note.GNU-stack,"",@progbits']
    source+='''
export function l $environment_alias() {
@e
%target =l copy $environment_identity_probe
%answer =l call %target(env %target, l 999, l 888, l 777, l 666, l 555, l 444, l 333)
ret %answer
}
export function l $environment_ignored() {
@e
%answer =l call $environment_plain(env 18446744073709551615, l 123)
ret %answer
}
export function l $environment_void_direct() {
@e
call $env_store(env $environment_slot, l 1311768467463790320)
%answer =l loadl $environment_slot
ret %answer
}
export function l $environment_void_indirect() {
@e
%target =l copy $env_store
call %target(env $environment_slot, l 18364758544493064720)
%answer =l loadl $environment_slot
ret %answer
}
export function l $environment_live(env %hidden, w %count) {
@entry
%answer =l call $environment_plain(l 999)
%result =l add %answer, %hidden
ret %result
}
export function l $environment_live_call() {
@entry
%answer =l call $environment_live(env 4294967297, w 9)
ret %answer
}
'''
    declarations += ['extern uint64_t environment_large_in(void),environment_recursive_in(uint32_t),environment_phi_in(uint32_t);',
        'extern uint64_t environment_alias(void),environment_ignored(void),environment_void_direct(void),environment_void_indirect(void),environment_live_call(void),env_direct(void);',
        'extern uint32_t env_unused(uint32_t);','extern void environment_identity_probe(void);','extern uint64_t zbe_check_preserved(uint64_t (*)(void));']
    checks += ['REQUIRE(environment_large_in()==UINT64_C(0xdeadbeef01234567));','REQUIRE(environment_recursive_in(3)==406);',
        'REQUIRE(environment_phi_in(0)==7);','REQUIRE(environment_phi_in(1)==100);','REQUIRE(env_unused(123)==123);',
        'REQUIRE(environment_alias()==(uintptr_t)environment_identity_probe);','REQUIRE(environment_ignored()==123);',
        'REQUIRE(environment_void_direct()==UINT64_C(1311768467463790320));','REQUIRE(environment_slot==UINT64_C(1311768467463790320));',
        'REQUIRE(environment_void_indirect()==UINT64_C(18364758544493064720));','REQUIRE(environment_slot==UINT64_C(18364758544493064720));',
        'REQUIRE(environment_live_call()==UINT64_C(4294968296));',
        'REQUIRE(zbe_check_preserved(env_direct)==0);','REQUIRE(zbe_check_preserved(environment_live_call)==0);',
        'REQUIRE(zbe_check_preserved(environment_alias)==0);']
    assert len(checks)==1013,len(checks)
    c='''#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
uint64_t environment_seen,environment_slot;
uint64_t environment_plain(uint64_t value) {return value;}
uint64_t environment_unknown(void) {abort();}
#define REQUIRE(c) do {++count; if(!(c)) {fprintf(stderr,"environment check %zu failed\\n",count);return 1;}} while(0)
'''+ '\n'.join(declarations+helpers)+'''
int main(int argc,char **argv) {
(void)argv;
if(argc>1 && ((uintptr_t)environment_identity_probe>>32)==0) return 2;
size_t count=0;
'''+ '\n'.join(checks)+ '\nprintf("%zu native environment ABI checks passed\\n",count);\nreturn 0;\n}\n'
    with tempfile.TemporaryDirectory(prefix='zbe-environment-') as directory:
        work=Path(directory);src,asm,driver,adapter,binary=[work/n for n in ('input.ssa','output.s','main.c','adapter.s','check')]
        src.write_text(source);driver.write_text(c);adapter.write_text('\n'.join(adapters)+'\n');compiler=str(args.compiler.resolve())
        subprocess.run([compiler,*flags,str(src),str(asm)],check=True,timeout=120)
        for pie in (False,True):
            mode=['-fPIE','-pie'] if pie else ['-fno-pie','-no-pie']
            subprocess.run([args.cc,'-std=c11','-O2','-Wall','-Wextra','-Werror',*mode,str(driver),str(asm),str(adapter),str(root/'src/fixtures/check-preserved.s'),'-o',str(binary)],check=True,timeout=90)
            subprocess.run([str(binary),*(['high-address'] if pie else [])],check=True,timeout=30)
            dynamic=subprocess.run(['readelf','-d',str(binary)],capture_output=True,text=True,check=True,timeout=30).stdout
            if 'TEXTREL' in dynamic:raise SystemExit('Environment call introduced a text relocation')
        print('2 environment executable no-TEXTREL checks passed')
        bad=[
            'function $f(w %p, env %e) {\n@e\nret\n}',
            'function $f(env %p, env %q) {\n@e\nret\n}',
            'function $f(env %p, ...) {\n@e\nret\n}',
            'function $f(env %p,) {\n@e\nret\n}',
            'function $f() {\n@e\ncall $g(w 1, env 2)\nret\n}',
            'function $f() {\n@e\ncall $g(env 1, env 2)\nret\n}',
            'function $f() {\n@e\ncall $g(env 1, ...)\nret\n}',
            'function $f(w %p) {\n@e\ncall $g(env %p)\nret\n}',
            'function $f() {\n@e\ncall $g()\nret\n}\nfunction $g(env %e) {\n@e\nstorel 1, %e\nret\n}',
            'function $f() {\n@e\ncall $g(env 1, l 2)\nret\n}\nfunction $g(env %e, w %p) {\n@e\nret\n}',
        ]
        for text in bad:
            src.write_text(text)
            if asm.exists():asm.unlink()
            for exists in (False,True):
                if exists:asm.write_text('preserve-environment-output')
                result=subprocess.run([compiler,*flags,str(src),str(asm)],capture_output=True,timeout=30)
                if result.returncode==0:raise SystemExit('Invalid environment call accepted')
                if (exists and asm.read_text()!='preserve-environment-output') or (not exists and asm.exists()):raise SystemExit('Rejected environment call changed output')
        print('20 environment rejection/output-preservation checks passed')

if __name__=='__main__':main()
