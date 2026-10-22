#!/usr/bin/env python3
"""Bounded unused record metadata emits no code; ineligible aggregate uses refuse."""
from pathlib import Path
import argparse
import platform
import resource
import subprocess
import tempfile


def main():
    root=Path(__file__).resolve().parents[1]
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--compiler',type=Path,default=root/'zig-out/bin/zbe-native')
    parser.add_argument('--cc',default='cc')
    for flag in ('fold-integers','reuse-stack-homes','callee-saved-homes'):parser.add_argument('--'+flag,action='store_true')
    args=parser.parse_args()
    if platform.system()!='Linux' or platform.machine() not in ('x86_64','amd64'):
        raise SystemExit('Record declaration native checks require Linux AMD64; no result claimed')
    resource.setrlimit(resource.RLIMIT_CORE,(0,0))
    flags=['--'+f for f in ('fold-integers','reuse-stack-homes','callee-saved-homes') if getattr(args,f.replace('-','_'))]
    compiler=[str(args.compiler.resolve()),*flags]
    records=(root/'src/fixtures/record_declaration_layouts.ssa').read_text()
    scalar=(root/'src/fixtures/record_declaration_scalar.ssa').read_text()
    checks=[]
    for bits in (0,1,0x8000000000000000,(1<<64)-1,0x12345678abcdef01):
        for n in (0,1,2,10,31,100):
            for value,double_bits in (('0.0f',0),('-0.0f',1<<63),('1.5f',0x3ff8000000000000),('-2.0f',0xc000000000000000)):
                expected=bits^(n*(n-1)//2)^double_bits
                checks.append(f'REQUIRE(record_declaration_scalar(UINT64_C({bits}),{n},{value})==UINT64_C({expected}));')
    checks += [f'REQUIRE(record_declaration_wrapper()==UINT64_C({(1<<63)^123456789^45}));','REQUIRE(zbe_check_preserved(record_declaration_wrapper)==0);']
    assert len(checks)==122
    c='''#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
extern uint64_t record_declaration_scalar(uint64_t,uint32_t,float),record_declaration_wrapper(void);
extern int zbe_check_preserved(uint64_t (*)(void));
static unsigned count;
#define REQUIRE(x) do {++count;if(!(x)){fprintf(stderr,"record declaration native check %u failed\\n",count);abort();}}while(0)
int main(void) {
'''+ '\n'.join(checks)+ '\nif(count!=122) {return 3;} printf("%u record declaration scalar checks passed\\n",count);return 0;}\n'
    declarations=['type :E = {}','type :T = { b 0 }','type :T = { b -1 }','type :T = { b 2147483648 }','type :T = { b 18446744073709551616 }','type :T = align 0 { b }','type :T = align 3 { b }','type :T = align 128 { b }','type :T = { sb }','type :T = { :T }','type :T = { :Later }\ntype :Later = { w }','type :A = { :B }\ntype :B = { :A }','type :T = { w }\ntype :T = { b }','export type :T = { b }']
    uses=[
        'function :T $f() {\n@e\nret\n}',
        'function $f(:T %x) {\n@e\nret\n}',
        'function $f() {\n@e\n%x =:T copy 0\nret\n}',
        'function $f() {\n@e\n%x =:T call $g()\nret\n}',
        'function $f() {\n@e\ncall $g(:T 0)\nret\n}',
        'function l $f() {\n@e\n%x =l copy :T\nret %x\n}',
        'function l $f() {\n@e\nret :T\n}',
        'function l $f() {\n@e\njmp @b\n@b\n%x =l phi @e :T\nret %x\n}',
        'data $x = { :T 0 }',
    ]
    # Parameter and call annotations for INTEGER word records are now positive;
    # malformed missing-value return and first-class aggregate syntax still fail.
    eligible=['type :T = { w }\n'+uses[i] for i in (1,3,4)]
    invalid=declarations+['type :T = { w }\n'+uses[i] for i in (0,2,5,6,7,8)]
    assert len(invalid)==20
    with tempfile.TemporaryDirectory(prefix='record_declaration_') as directory:
        path=Path(directory)
        il,asm,baseline,driver,exe=[path/name for name in ('input.ssa','output.s','baseline.s','driver.c','run')]
        il.write_text(scalar)
        subprocess.run([*compiler,str(il),str(baseline)],check=True,timeout=90)
        il.write_text(records+scalar)
        subprocess.run([*compiler,str(il),str(asm)],check=True,timeout=90)
        if asm.read_bytes()!=baseline.read_bytes():raise SystemExit('Unused record declarations changed scalar assembly')
        print('1 byte-identical scalar assembly check passed')
        # Precisely upgrade only the newly supported declaration, without removing
        # other historical refusal positions or changing any fixture expectations.
        for text in ('type :U = { { b } { w } }\n'+scalar, scalar+'\ntype :U = { { b } { w } }\n'):
            il.write_text(text)
            subprocess.run([*compiler,str(il),str(asm)],check=True,timeout=90)
            if asm.read_bytes()!=baseline.read_bytes():raise SystemExit('Unused union changed scalar assembly')
        print('2 former-union-refusal positive byte-identical scalar assemblies passed')

        for text in ('type :O = align 16 { 32 }\n'+scalar, scalar+'\ntype :O = align 16 { 32 }\n'):
            il.write_text(text)
            subprocess.run([*compiler,str(il),str(asm)],check=True,timeout=90)
            if asm.read_bytes()!=baseline.read_bytes():raise SystemExit('Unused opaque changed scalar assembly')
        print('2 former-opaque-refusal positive byte-identical scalar assemblies passed')
        driver.write_text(c)
        for link in ('-pie','-no-pie'):
            subprocess.run([args.cc,'-std=c11','-O2','-Wall','-Wextra','-Werror','-fPIE',link,str(driver),str(asm),str(root/'src/fixtures/check-preserved.s'),'-o',str(exe)],check=True,timeout=90)
            subprocess.run([str(exe)],check=True,timeout=30)
        il.write_text('')
        subprocess.run([*compiler,str(il),str(baseline)],check=True,timeout=90)
        il.write_text(records)
        subprocess.run([*compiler,str(il),str(asm)],check=True,timeout=90)
        if asm.read_bytes()!=baseline.read_bytes():raise SystemExit('Type-only declarations emitted code or symbols')
        print('1 type-only empty-module assembly check passed')
        aliases=(root/'src/fixtures/record_declaration_symbol_identity.ssa').read_text()
        il.write_text(aliases)
        subprocess.run([*compiler,str(il),str(baseline)],check=True,timeout=90)
        expected=baseline.read_bytes()
        if b'.Lzbe@common' not in expected or b'.set \".Lzbe@s' not in expected:
            raise SystemExit('Record alias regression did not exercise COMMON/.set lowering')
        declarations='type :Unused = { b }\n'+'type :T = { w }\n'+'type :Normal = { :Unused 3 }\n'
        for source in (declarations+aliases,aliases+declarations):
            il.write_text(source)
            subprocess.run([*compiler,str(il),str(asm)],check=True,timeout=90)
            if asm.read_bytes()!=expected:raise SystemExit('Unused record names changed COMMON/ordinary/external/normal scalar aliases')
            subprocess.run([args.cc,'-c',str(asm),'-o',str(path/'aliases.o')],check=True,timeout=30)
        print('2 complete COMMON/ordinary/external/normal namespace assembly identity checks passed')
        for text in eligible:
            il.write_text(text)
            subprocess.run([*compiler,str(il),str(asm)],check=True,timeout=45)
        print('3 newly eligible INTEGER-word parameter/call forms emit; independent runtime coverage is separate')
        rejected=0
        for text in invalid:
            il.write_text(text)
            for exists in (False,True):
                asm.unlink(missing_ok=True)
                if exists:asm.write_text('preserve-record-output')
                run=subprocess.run([*compiler,str(il),str(asm)],capture_output=True,timeout=30)
                if run.returncode==0 or (exists and asm.read_text()!='preserve-record-output') or (not exists and asm.exists()):raise SystemExit('Unsupported/invalid record or aggregate use accepted or changed output')
                rejected+=1
        print(f'{rejected} record/aggregate refusal output-preservation checks passed')
        print('2 record declaration scalar link modes passed')


if __name__=='__main__':main()
