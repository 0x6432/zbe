#!/usr/bin/env python3
"""Independent defined-low-bit Linux AMD64 subword ABI checks, not full ABI parity."""
from pathlib import Path
import argparse
import platform
import resource
import subprocess
import tempfile

NARROW = ('sb', 'ub', 'sh', 'uh')
C_TYPES = {'sb':'int8_t', 'ub':'uint8_t', 'sh':'int16_t', 'uh':'uint16_t',
           'w':'uint32_t', 'l':'uint64_t', 's':'float', 'd':'double'}
EXTEND = {'sb':'extsb', 'ub':'extub', 'sh':'extsh', 'uh':'extuh'}

def observe(bits, kind):
    width = 8 if kind in ('sb', 'ub') else 16
    low = bits & ((1 << width) - 1)
    return low - (1 << width) if kind in ('sb', 'sh') and low >= (1 << (width-1)) else low

def inputs(types, signature, seed):
    il, c, values = [], [], []
    for i, kind in enumerate(types):
        raw = (signature*109 + seed*193 + i*419 + 0x8081) & 0xffff
        if kind in NARROW:
            # IL deliberately uses a poisoned full word; C arguments stay in range.
            il.append(str(0xabcdef00 | (raw & 255)) if kind in ('sb','ub') else str(0xabcd0000 | raw))
            value = observe(raw, kind)
            c.append(str(value))
        elif kind == 'l':
            il.append(str(0x1234567800000000 | raw))
            c.append(f'UINT64_C({0x1234567800000000 | raw})')
            value = raw
        elif kind == 'w':
            il.append(str(0xabcd0000 | raw)); c.append(f'UINT32_C({0xabcd0000 | raw})'); value = raw
        else:
            value = (signature + seed*7 + i*3) % 127
            il.append(f'{kind}_{value}'); c.append(str(value)+('.0f' if kind=='s' else '.0'))
        values.append(value)
    return il, c, values

def main():
    root = Path(__file__).resolve().parents[1]
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--compiler', type=Path, default=root/'zig-out/bin/zbe-native')
    parser.add_argument('--cc', default='cc')
    options = ('fold-integers','reuse-stack-homes','callee-saved-homes')
    for option in options: parser.add_argument('--'+option,action='store_true')
    args = parser.parse_args()
    if platform.system()!='Linux' or platform.machine() not in ('x86_64','amd64'):
        raise SystemExit('Subword checks require Linux AMD64; no result claimed.')
    resource.setrlimit(resource.RLIMIT_CORE,(0,0))
    flags=['--'+option for option in options if getattr(args,option.replace('-','_'))]
    source=(root/'src/fixtures/subword-abi.ssa').read_text()
    declarations=[]; helpers=[]; checks=[]
    for signature in range(64):
        # Both independent bank overflow orders; all four narrow classes, full
        # words/longs and exact floating values. Expectations never use a cursor.
        integers=[NARROW[(signature+i)%4] if i%3!=2 else ('w' if i%2 else 'l') for i in range(10)]
        floats=['s' if (signature+i)%2 else 'd' for i in range(10)]
        types=(integers+floats if signature%2 else floats+integers)
        if signature%3==0: types=[t for pair in zip(integers,floats) for t in pair]
        result=NARROW[signature%4]
        names=[f'a{i}' for i in range(len(types))]
        params=','.join(f'{C_TYPES[t]} {n}' for t,n in zip(types,names))
        expressions=[]
        for i,(kind,name) in enumerate(zip(types,names)):
            if kind in ('sb','sh'): term=f'(uint64_t)(int64_t){name}'
            elif kind in ('w','l'): term=f'({name}&UINT64_C(65535))'
            else: term=f'(uint64_t){name}'
            expressions.append(f'({term})*UINT64_C({i+1})')
        width=8 if result in ('sb','ub') else 16
        # Cast to signed narrow only AFTER mapping into its defined small range.
        finish=(f'int64_t value=(int64_t)(acc&UINT64_C({(1<<width)-1})); '
                + (f'if(value>={1<<(width-1)}) value-={1<<width}; ' if result in ('sb','sh') else '')
                + f'return ({C_TYPES[result]})value;')
        helpers.append(f'{C_TYPES[result]} narrow_external_{signature}({params}) {{ uint64_t acc='+ '+'.join(expressions)+'; '+finish+' }')
        il_values,_,values=inputs(types,signature,0)
        argument_text=', '.join(f'{t} {v}' for t,v in zip(types,il_values))
        source+=f'\nexport function w $narrow_out_{signature}() {{\n@e\n%target =l copy $narrow_external_{signature}\n%a ={result} call $narrow_external_{signature}({argument_text})\n%b ={result} call %target({argument_text})\n%x =w {EXTEND[result]} %a\n%y =w {EXTEND[result]} %b\n%r =w add %x, %y\nret %r\n}}\n'
        source+=f'\nexport function {result} $narrow_in_{signature}('+', '.join(f'{t} %{n}' for t,n in zip(types,names))+') {\n@e\n'
        source+=f'%r ={result} call $narrow_external_{signature}('+', '.join(f'{t} %{n}' for t,n in zip(types,names))+')\nret %r\n}\n'
        declarations.append(f'extern uint32_t narrow_out_{signature}(void);')
        declarations.append(f'extern {C_TYPES[result]} narrow_in_{signature}({params});')
        expected=observe(sum((i+1)*v for i,v in enumerate(values)),result)
        checks.append(f'REQUIRE(narrow_out_{signature}()==UINT32_C({(2*expected)&0xffffffff}));')
        for seed in range(3):
            _,c_values,values=inputs(types,signature,seed)
            expected=observe(sum((i+1)*v for i,v in enumerate(values)),result)
            checks.append(f'REQUIRE((uint32_t)narrow_in_{signature}('+','.join(c_values)+f')==UINT32_C({expected&0xffffffff}));')
    poison=0x0123456789ab80ff
    assembly=['.text']
    for kind in NARROW:
        source+=f'\nexport function w $narrow_return_{kind}() {{\n@e\n%x ={kind} call $narrow_poison_{kind}()\n%r =w {EXTEND[kind]} %x\nret %r\n}}\n'
        declarations.append(f'extern uint32_t narrow_return_{kind}(void);')
        checks.append(f'REQUIRE(narrow_return_{kind}()==UINT32_C({observe(poison,kind)&0xffffffff}));')
        assembly.extend([f'.globl narrow_poison_{kind}',f'.type narrow_poison_{kind}, @function',f'narrow_poison_{kind}:',f' movabsq ${poison}, %rax',' ret'])
    poison_types=('sb','ub','sh','uh','sb','sh','ub','uh')
    poison_values=[0x12345678abcdef81,0xabcdef01987654fe,0x876543219abc8001,0x76543210abcdffff,
                   0xfedcba98765432ff,0x12345678abcd7fff,0x9876543212345680,0xabcdef0123458000]
    source+='\nexport function w $narrow_poison_parameters('+', '.join(f'{t} %p{i}' for i,t in enumerate(poison_types))+') {\n@e\n'
    for i,t in enumerate(poison_types):
        source+=f'%v{i} =w {EXTEND[t]} %p{i}\n%m{i} =w mul %v{i}, {i+1}\n'
        if i: source+=f'%s{i} =w add '+('%m0' if i==1 else f'%s{i-1}')+f', %m{i}\n'
    source+='ret %s7\n}\n'
    assembly.extend(['.globl narrow_poison_incoming','.type narrow_poison_incoming, @function','narrow_poison_incoming:',' subq $24, %rsp'])
    for reg,value in zip(('rdi','rsi','rdx','rcx','r8','r9'),poison_values[:6]): assembly.append(f' movabsq ${value}, %{reg}')
    for i,value in enumerate(poison_values[6:]):assembly.extend([f' movabsq ${value}, %rax',f' movq %rax, {i*8}(%rsp)'])
    assembly.extend([' call narrow_poison_parameters',' addq $24, %rsp',' ret','.section .note.GNU-stack,"",@progbits'])
    declarations.append('extern uint32_t narrow_poison_incoming(void);')
    expected=sum((i+1)*observe(v,t) for i,(v,t) in enumerate(zip(poison_values,poison_types)))&0xffffffff
    checks.append(f'REQUIRE(narrow_poison_incoming()==UINT32_C({expected}));')
    source+='''
export function w $narrow_unused() {
@e
%a =sb call $narrow_effect(ub 4294967169)
%b =uh call $narrow_effect_half(sh 2882371585)
ret 9
}
export function l $narrow_preserved() {
@e
%a =l copy 81985529216486895
%b =l copy 18364758544493064720
%c =l copy 1234605616436508552
%d =l copy 9833440827789222417
%e =l copy 1084818905618843912
%x =sb call $narrow_poison_sb()
%ab =l xor %a, %b
%cd =l xor %c, %d
%abcd =l xor %ab, %cd
%r =l xor %abcd, %e
ret %r
}
'''
    preserved=81985529216486895^18364758544493064720^1234605616436508552^9833440827789222417^1084818905618843912
    checks.extend(['REQUIRE(narrow_unused()==9);','REQUIRE(effect_count==2);',f'REQUIRE(narrow_preserved()==UINT64_C({preserved}));','REQUIRE(zbe_check_preserved(narrow_preserved)==0);'])
    c='''#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
extern uint32_t subword_entry(uint64_t),subword_loop(uint32_t,int8_t,int8_t);
extern uint16_t subword_rec(uint8_t,uint16_t);
extern uint32_t narrow_unused(void);
extern uint64_t narrow_preserved(void),zbe_check_preserved(uint64_t (*)(void));
static unsigned effect_count;
int8_t narrow_effect(uint8_t x) {if(x!=129) abort(); ++effect_count;return -1;}
uint16_t narrow_effect_half(int16_t x) {if(x!=-32767) abort(); ++effect_count;return 65535;}
#define REQUIRE(c) do {++count;if(!(c)){fprintf(stderr,"subword check %zu failed\\n",count);return 1;}} while(0)
'''+ '\n'.join(declarations+helpers)+'''\nint main(void) {
size_t count=0;
for(unsigned i=0;i<256;++i) {
 uint64_t bits=UINT64_C(0xabcdef0180000000)+i*257;
 uint32_t byte=(uint32_t)bits&255,half=(uint32_t)bits&65535;
 int64_t sb=(int64_t)byte-(byte>=128?256:0),sh=(int64_t)half-(half>=32768?65536:0);
 REQUIRE(subword_entry(bits)==(uint32_t)(sb+byte+sh+half));
 REQUIRE(subword_rec((uint8_t)(i%8),(uint16_t)(65532+i))==(uint16_t)(65532+i+i%8));
 int32_t expected=i%2?127-257*127:-127+257*127;
 REQUIRE(subword_loop(i%8,-127,127)==(uint32_t)expected);
}
'''+ '\n'.join(checks)+f'\nif(count!={768+len(checks)}) return 3;\nprintf("%zu native subword ABI defined-bit checks passed\\n",count);\nreturn 0;\n}}\n'
    with tempfile.TemporaryDirectory(prefix='zbe-subword-') as directory:
        work=Path(directory)
        src,asm,driver,adapters,binary=[work/name for name in ('subword.ssa','subword.s','main.c','adapters.s','check')]
        src.write_text(source);driver.write_text(c);adapters.write_text('\n'.join(assembly)+'\n')
        compiler=str(args.compiler.resolve())
        subprocess.run([compiler,*flags,str(src),str(asm)],check=True,timeout=120)
        for pie in (False,True):
            mode=['-fPIE','-pie'] if pie else ['-fno-pie','-no-pie']
            subprocess.run([args.cc,'-std=c11','-O2','-Wall','-Wextra','-Werror',*mode,str(driver),str(asm),str(adapters),str(root/'src/fixtures/check-preserved.s'),'-o',str(binary)],check=True,timeout=90)
            subprocess.run([str(binary)],check=True,timeout=30)
            dynamic=subprocess.run(['readelf','-d',str(binary)],capture_output=True,text=True,check=True,timeout=30).stdout
            if 'TEXTREL' in dynamic:raise SystemExit('Subword ABI introduced a dynamic text relocation')
        print('2 subword ABI executable no-TEXTREL checks passed')
        bad=[]
        for kind in NARROW:
            bad.extend([f'function w $f() {{\n@e\n%x ={kind} copy 1\nret 0\n}}',
                        f'function w $f() {{\n@e\n%x ={kind} phi @e 1\nret 0\n}}',
                        f'function w $f() {{\n@e\n%x ={kind} call $g()\nret 0\n}}\nfunction w $g() {{\n@e\nret 1\n}}',
                        f'function w $f() {{\n@e\n%x =w call $g({kind} 1)\nret 0\n}}\nfunction w $g(w %x) {{\n@e\nret %x\n}}'])
        bad.extend(['function sb $f(sb %x) {\n@e\n%r =sb add %x, 1\nret %r\n}',
                    'function w $f(s %x) {\n@e\n%r =sb call $g(sb %x)\nret 0\n}',
                    'function l $f(sb %x) {\n@e\n%r =l copy %x\nret %r\n}',
                    'function w $f() {\n@e\n%x =sb call $g(sb 1, ..., ...)\nret 0\n}'])
        assert len(bad)==20
        for text in bad:
            src.write_text(text)
            if asm.exists():asm.unlink()
            for exists in (False,True):
                if exists:asm.write_text('preserve-subword-output')
                result=subprocess.run([compiler,*flags,str(src),str(asm)],capture_output=True,timeout=30)
                if result.returncode==0:raise SystemExit('Invalid subword ABI accepted')
                if (exists and asm.read_text()!='preserve-subword-output') or (not exists and asm.exists()):
                    raise SystemExit('Rejected subword ABI changed output')
        print('40 subword ABI rejection/output-preservation checks passed')

if __name__=='__main__':main()
