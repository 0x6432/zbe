#!/usr/bin/env python3
"""Independent low-word projection checks on Linux AMD64, including retained long uses."""
from pathlib import Path
import argparse
import platform
import random
import resource
import signal
import subprocess
import tempfile


def main() -> None:
    root=Path(__file__).resolve().parents[1]
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--compiler',type=Path,default=root/'zig-out/bin/zbe-native')
    parser.add_argument('--cc',default='cc')
    for flag in ('fold-integers','reuse-stack-homes','callee-saved-homes'): parser.add_argument('--'+flag,action='store_true')
    args=parser.parse_args()
    if platform.system()!='Linux' or platform.machine() not in ('x86_64','amd64'): raise SystemExit('Low-word native checks require Linux x86_64; no result claimed.')
    resource.setrlimit(resource.RLIMIT_CORE,(0,0))
    flags=['--'+f for f in ('fold-integers','reuse-stack-homes','callee-saved-homes') if getattr(args,f.replace('-','_'))]
    operations=('add','sub','mul','and','or','xor','shl','shr','sar','div','rem','udiv','urem','neg','extub','extsb')
    declarations=[f'extern uint32_t low_word_{op}(uint64_t,uint64_t);' for op in operations]
    checks=[]
    for line in (root/'src/fixtures/low-word-oracle.tsv').read_text().splitlines():
        if not line or line.startswith('#'): continue
        index,x,y,expected=map(int,line.split())
        checks.append(f'REQUIRE(low_word_{operations[index]}(UINT64_C({x}),UINT64_C({y}))==UINT32_C({expected}));')
    assert len(checks)==1024
    declarations += ['extern uint32_t low_word_return(uint64_t);','extern uint32_t low_word_phi(uint64_t,uint64_t,uint32_t);',
                     'extern uint64_t low_word_keep(uint64_t);','extern uint64_t low_word_call(uint64_t,uint64_t,uint64_t,uint64_t,uint64_t,uint64_t,uint64_t);',
                     'extern uint32_t low_word_indirect(uint32_t (*)(uint32_t),uint64_t);','extern uint32_t low_word_store(void *,uint64_t);',
                     'extern double low_word_swtof(uint64_t);','extern double low_word_uwtof(uint64_t);','extern uint64_t low_word_count(uint64_t);',
                     'extern uint64_t low_word_compare(uint64_t,uint64_t);','extern uint32_t low_word_loop(uint64_t,uint32_t);',
                     'extern float low_word_cast(uint64_t);','extern uint64_t low_word_extend(uint64_t);','extern uint64_t low_word_fold(void);',
                     'extern uint64_t zbe_check_preserved(uint64_t (*)(void));','extern uint32_t low_word_fault(uint64_t,uint64_t);']
    rng=random.Random(0x50524f4a454354)
    edges=(0,1,0xffffffff,0x80000000,0x7fffffff,31,32,63,64,0x7fc12345,0x800000ff)
    for i in range(64):
        lo=edges[i%len(edges)] if i<32 else rng.getrandbits(32)
        ly=edges[(i*3+1)%len(edges)] if i<32 else rng.getrandbits(32)
        x=(rng.randrange(1,1<<32)<<32)|lo;y=(rng.randrange(1,1<<32)<<32)|ly
        sx=lo if lo<(1<<31) else lo-(1<<32)
        sy=ly if ly<(1<<31) else ly-(1<<32)
        call_sum=(2*lo+21)&0xffffffff
        byte=lo&255;signed_byte=byte-(256 if byte&128 else 0)
        checks += [f'REQUIRE(low_word_return(UINT64_C({x}))==UINT32_C({lo}));',
                   f'REQUIRE(low_word_phi(UINT64_C({x}),UINT64_C({y}),0)==UINT32_C({ly}));',
                   f'REQUIRE(low_word_phi(UINT64_C({x}),UINT64_C({y}),1)==UINT32_C({lo}));',
                   f'REQUIRE(low_word_keep(UINT64_C({x}))==UINT64_C({x&0xffffffff00000000}));',
                   f'REQUIRE(low_word_call(UINT64_C({x}),1,2,3,4,5,6)==UINT64_C({x^call_sum}));',
                   f'REQUIRE(low_word_indirect(callback,UINT64_C({x}))==UINT32_C({lo^0xabcdef01}));',
                   f'REQUIRE(low_word_store(&storage[4],UINT64_C({x}))==UINT32_C({lo}));',
                   'REQUIRE(storage[0]==0xa5 && storage[3]==0xa5 && storage[8]==0xa5 && storage[11]==0xa5);',
                   f'REQUIRE(low_word_swtof(UINT64_C({x}))=={sx}.0);',
                   f'REQUIRE(low_word_uwtof(UINT64_C({x}))=={lo}.0);',
                   f'REQUIRE(low_word_count(UINT64_C({x}))==UINT64_C({1<<(lo&63)}));',
                   f'REQUIRE(low_word_compare(UINT64_C({x}),UINT64_C({y}))=={int(sx<sy)});',
                   f'REQUIRE(bits_s(low_word_cast(UINT64_C({x})))==UINT32_C({lo}));',
                   f'REQUIRE(low_word_extend(UINT64_C({x}))==UINT64_C({signed_byte&((1<<64)-1)}));']
        checks += [f'REQUIRE(low_word_loop(UINT64_C({x}),{n})==UINT32_C({(lo+n)&0xffffffff}));' for n in (0,1,10)]
    checks += ['REQUIRE(low_word_fold()==UINT64_C(0xdeadbeef00000001));','REQUIRE(zbe_check_preserved(low_word_fold)==0);']
    assert len(checks)==2114
    c='''#include <stdint.h>
#include <stdio.h>
#include <string.h>
static uint32_t bits_s(float v) { uint32_t x; memcpy(&x,&v,4); return x; }
static uint32_t callback(uint32_t x) { return x^UINT32_C(0xabcdef01); }
#define REQUIRE(c) do { ++count; if (!(c)) { fprintf(stderr,"low-word check %zu failed\\n",count); return 1; } } while (0)
'''+ '\n'.join(declarations)+'''
int main(int argc,char **argv) {
 (void)argv;
 if (argc>1) return (int)low_word_fault(UINT64_C(0xdeadbeef80000000),argc==2?UINT64_C(0xffffffff00000000):UINT64_C(0xdeadbeefffffffff));
 unsigned char storage[12]; memset(storage,0xa5,sizeof storage); size_t count=0;
'''+ '\n'.join(checks)+ '\nprintf("%zu native low-word projection checks passed\\n",count); return 0; }\n'
    il=(root/'src/fixtures/low-word-operations.ssa').read_text()+(root/'src/fixtures/low-word-contexts.ssa').read_text()+'''
export function w $low_word_fault(l %x,l %y) {
@entry
%r =w div %x, %y
ret %r
}
'''
    with tempfile.TemporaryDirectory(prefix='zbe-low-word-') as directory:
        work=Path(directory);src,asm,driver,binary=[work/n for n in ('low-word.ssa','low-word.s','main.c','check')]
        src.write_text(il);driver.write_text(c)
        subprocess.run([str(args.compiler.resolve()),*flags,str(src),str(asm)],check=True,timeout=90)
        subprocess.run([args.cc,'-std=c11','-O2','-Wall','-Wextra','-Werror','-fPIE','-pie',str(driver),str(asm),str(root/'src/fixtures/check-preserved.s'),'-o',str(binary)],check=True,timeout=90)
        subprocess.run([str(binary)],check=True,timeout=30)
        for parameters in (['zero'],['min','minus-one']):
            result=subprocess.run([str(binary),*parameters],capture_output=True,timeout=30)
            if result.returncode!=-signal.SIGFPE: raise SystemExit('Projected integer fault was not retained')
        print('2 projected integer arithmetic-fault checks passed')
        for text in (
            'function l $f(w %v) {\n@e\nret %v\n}',
            'function l $f(w %v) {\n@e\n%r =l add %v, 1\nret %r\n}',
            'function l $f(w %v) {\n@e\n%r =l copy %v\nret %r\n}',
            'function w $f(d %v) {\n@e\n%r =w copy %v\nret %r\n}',
        ):
            src.write_text(text);asm.unlink()
            for exists in (False,True):
                if exists: asm.write_text('preserve-low-word-output')
                result=subprocess.run([str(args.compiler.resolve()),*flags,str(src),str(asm)],capture_output=True,timeout=30)
                if result.returncode==0: raise SystemExit('Invalid implicit widening/class accepted')
                if (exists and asm.read_text()!='preserve-low-word-output') or (not exists and asm.exists()): raise SystemExit('Invalid projection input changed output')
        print('8 low-word rejection/output-preservation checks passed')


if __name__=='__main__': main()
