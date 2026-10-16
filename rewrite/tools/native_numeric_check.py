#!/usr/bin/env python3
"""Bounded defined signed/unsigned numeric conversions under round-to-nearest on Linux AMD64."""
from pathlib import Path
import argparse
import platform
import resource
import subprocess
import tempfile


def main() -> None:
    root=Path(__file__).resolve().parents[1]
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--compiler',type=Path,default=root/'zig-out/bin/zbe-native')
    parser.add_argument('--cc',default='cc')
    for flag in ('fold-integers','reuse-stack-homes','callee-saved-homes'):
        parser.add_argument('--'+flag,action='store_true')
    args=parser.parse_args()
    if platform.system()!='Linux' or platform.machine() not in ('x86_64','amd64'):
        raise SystemExit('Numeric native checks require Linux x86_64; no result claimed.')
    resource.setrlimit(resource.RLIMIT_CORE,(0,0))
    flags=['--'+f for f in ('fold-integers','reuse-stack-homes','callee-saved-homes') if getattr(args,f.replace('-','_'))]
    types={'w':'uint32_t','l':'uint64_t','s':'float','d':'double'}
    rows=[]
    for kind in ('signed','unsigned'):
        for line in (root/f'src/fixtures/{kind}-conversion-oracle.tsv').read_text().splitlines():
            if line and not line.startswith('#'): rows.append((kind,*line.split()))
    assert len(rows)==1536
    declarations={}
    checks=[]
    for kind,result_ty,opcode,source_ty,bits,expected in rows:
        name=f'{kind}_{opcode}_{result_ty}'
        declarations[name]=f'extern {types[result_ty]} {name}({types[source_ty]});'
        source=f'UINT64_C({bits})'
        if source_ty=='w': source=f'(uint32_t){source}'
        elif source_ty in ('s','d'): source=f'from_{source_ty}({source})'
        actual=f'{name}({source})'
        if result_ty in ('s','d'): actual=f'bits_{result_ty}({actual})'
        checks.append(f'REQUIRE((uint64_t)({actual})==UINT64_C({expected}));')
    il=(root/'src/fixtures/signed-conversions.ssa').read_text()+(root/'src/fixtures/unsigned-conversions.ssa').read_text()+'''
export function l $numeric_pressure(l %a,l %b,l %c,l %d,l %e,l %f,l %g,s %floating,d %double) {
@entry
%i =s sltof %a
%v =s add %i, %floating
%r =l stosi %v
%q =l dtosi %double
%sum0 =l add %r, %q
%sum1 =l add %sum0, %g
%sum2 =l add %sum1, %b
%sum3 =l add %sum2, %c
%sum4 =l add %sum3, %d
%sum5 =l add %sum4, %e
%sum6 =l add %sum5, %f
ret %sum6
}
export function l $numeric_wrapper() {
@entry
%r =l call $numeric_pressure(l 1,l 2,l 3,l 4,l 5,l 6,l 7,s s_2.5,d d_-1.5)
ret %r
}
export function w $numeric_safe(w %take) {
@entry
jnz %take, @invalid, @safe
@invalid
%v =w dtosi d_nan
ret %v
@safe
ret 42
}
'''
    il += (root/'src/fixtures/signed-conversion-loop.ssa').read_text()
    declarations['sum']='extern uint32_t signed_conversion_sum(uint32_t);'
    checks += [f'REQUIRE(signed_conversion_sum({n})=={n*(n-1)//2});' for n in (0,1,2,10,100)]
    declarations.update({
        'pressure':'extern uint64_t numeric_pressure(uint64_t,uint64_t,uint64_t,uint64_t,uint64_t,uint64_t,uint64_t,float,double);',
        'wrapper':'extern uint64_t numeric_wrapper(void);',
        'preserved':'extern uint64_t zbe_check_preserved(uint64_t (*)(void));',
        'safe':'extern uint32_t numeric_safe(uint32_t);'})
    checks += ['REQUIRE(numeric_pressure(1,2,3,4,5,6,7,2.5f,-1.5)==29);','REQUIRE(numeric_wrapper()==29);','REQUIRE(zbe_check_preserved(numeric_wrapper)==0);','REQUIRE(numeric_safe(0)==42);']
    il += (root/'src/fixtures/unsigned-conversion-loop.ssa').read_text()+'''
export function l $unsigned_numeric_pressure(l %a,l %b,l %c,l %d,l %e,l %f,l %g,s %floating,d %double,w %word) {
@entry
%float =d ultof %a
%back =l dtoui %float
%single =l stoui %floating
%doubleint =l dtoui %double
%wordfloat =d uwtof %word
%wordback =w dtoui %wordfloat
%wideword =l extuw %wordback
%sum0 =l add %back, %single
%sum1 =l add %sum0, %doubleint
%sum2 =l add %sum1, %wideword
%sum3 =l add %sum2, %b
%sum4 =l add %sum3, %c
%sum5 =l add %sum4, %d
%sum6 =l add %sum5, %e
%sum7 =l add %sum6, %f
%sum8 =l add %sum7, %g
ret %sum8
}
export function l $unsigned_numeric_wrapper() {
@entry
%r =l call $unsigned_numeric_pressure(l 9223372036854777856,l 1,l 2,l 3,l 4,l 5,l 6,s s_0.5,d d_-0.75,w 4294967295)
ret %r
}
export function l $unsigned_numeric_literals() {
@entry
%s =s ultof 18446744073709551615
%bits =w cast %s
%d =d ultof 9223372036854775808
%back =l dtoui %d
%wide =l extuw %bits
%result =l xor %back, %wide
ret %result
}
'''
    declarations.update({
        'unsigned_sum':'extern uint32_t unsigned_conversion_sum(uint32_t);',
        'unsigned_pressure':'extern uint64_t unsigned_numeric_pressure(uint64_t,uint64_t,uint64_t,uint64_t,uint64_t,uint64_t,uint64_t,float,double,uint32_t);',
        'unsigned_wrapper':'extern uint64_t unsigned_numeric_wrapper(void);',
        'unsigned_literals':'extern uint64_t unsigned_numeric_literals(void);'})
    checks += [f'REQUIRE(unsigned_conversion_sum({n})=={n*(n-1)//2});' for n in (0,1,2,10,100)]
    expected=(1<<63)+2048+21+((1<<32)-1)
    checks += [f'REQUIRE(unsigned_numeric_pressure(UINT64_C(9223372036854777856),1,2,3,4,5,6,0.5f,-0.75,UINT32_C(4294967295))==UINT64_C({expected}));',
               f'REQUIRE(unsigned_numeric_wrapper()==UINT64_C({expected}));',
               'REQUIRE(zbe_check_preserved(unsigned_numeric_wrapper)==0);',
               f'REQUIRE(unsigned_numeric_literals()==UINT64_C({(1<<63)^0x5f800000}));']
    assert len(checks)==1554
    c='''#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <fenv.h>
static float from_s(uint64_t x) { uint32_t b=(uint32_t)x; float v; memcpy(&v,&b,4); return v; }
static double from_d(uint64_t x) { double v; memcpy(&v,&x,8); return v; }
static uint32_t bits_s(float v) { uint32_t x; memcpy(&x,&v,4); return x; }
static uint64_t bits_d(double v) { uint64_t x; memcpy(&x,&v,8); return x; }
#define REQUIRE(c) do { ++count; if (!(c)) { fprintf(stderr,"numeric check %zu failed\\n",count); return 1; } } while (0)
'''+'\n'.join(declarations.values())+'\nint main(void) { if (fesetround(FE_TONEAREST)) return 2; size_t count=0;\n'+'\n'.join(checks)+'\nprintf("%zu native signed/unsigned numeric-conversion checks passed\\n",count); return 0; }\n'
    with tempfile.TemporaryDirectory(prefix='zbe-numeric-') as directory:
        work=Path(directory)
        src,asm,driver,binary=[work/n for n in ('numeric.ssa','numeric.s','main.c','check')]
        src.write_text(il);driver.write_text(c)
        subprocess.run([str(args.compiler.resolve()),*flags,str(src),str(asm)],check=True,timeout=90)
        subprocess.run([args.cc,'-std=c11','-O2','-Wall','-Wextra','-Werror','-fPIE','-pie',str(driver),str(asm),str(root/'src/fixtures/check-preserved.s'),'-lm','-o',str(binary)],check=True,timeout=90)
        subprocess.run([str(binary)],check=True,timeout=30)
        for text in (
            'function w $f() {\n@e\n%r =w swtof 1\nret %r\n}',
            'function s $f() {\n@e\n%r =s stosi s_1\nret %r\n}',
            'function d $f(s %x) {\n@e\n%r =d swtof %x\nret %r\n}',
            'function l $f() {\n@e\n%r =l dtosi s_1\nret %r\n}',
            'function s $f() {\n@e\n%r =s stoui s_1\nret %r\n}',
            'function w $f() {\n@e\n%r =w uwtof 1\nret %r\n}',
            'function d $f(s %x) {\n@e\n%r =d uwtof %x\nret %r\n}',
            'function l $f() {\n@e\n%r =l dtoui s_1\nret %r\n}',
            'function s $f(w %x) {\n@e\n%r =s ultof %x\nret %r\n}',
            'function s $f() {\n@e\n%r =s truncd d_1\nret %r\n}',
        ):
            src.write_text(text);asm.unlink()
            for exists in (False,True):
                if exists: asm.write_text('preserve-numeric-output')
                result=subprocess.run([str(args.compiler.resolve()),*flags,str(src),str(asm)],capture_output=True,timeout=30)
                if result.returncode==0: raise SystemExit('Invalid/unsupported numeric conversion accepted')
                if (exists and asm.read_text()!='preserve-numeric-output') or (not exists and asm.exists()):
                    raise SystemExit('Invalid numeric conversion changed output')
        print('20 numeric rejection/output-preservation checks passed')


if __name__=='__main__': main()
