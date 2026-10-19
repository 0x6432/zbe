#!/usr/bin/env python3
"""Independent literal encoding/object/runtime checks; no legacy compiler."""
import argparse
from pathlib import Path
import platform
import re
import subprocess
import tempfile


def main():
    root=Path(__file__).resolve().parents[1]
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--compiler',type=Path,default=root/'zig-out/bin/zbe-native');p.add_argument('--cc',default='cc')
    for f in ('fold-integers','reuse-stack-homes','callee-saved-homes'):p.add_argument('--'+f,action='store_true')
    args=p.parse_args()
    if platform.system()!='Linux' or platform.machine() not in ('x86_64','amd64'):raise SystemExit('Requires Linux AMD64; no passing result claimed')
    flags=['--'+f for f in ('fold-integers','reuse-stack-homes','callee-saved-homes') if getattr(args,f.replace('-','_'))]
    functions=[];declarations=[];checks=[];shapes={}
    rows=(root/'src/fixtures/immediate_selection_oracle.tsv').read_text().splitlines()
    for line in rows:
        if line.startswith('#'):continue
        ty,op,n,x,expected,eligible,encoding=line.split();key=(ty,op,n)
        if key not in shapes:
            name=f'immediate_{len(shapes)}';shapes[key]=(name,eligible=='1',int(encoding))
            functions.append(f'export function {ty} ${name}({ty} %x) {{\n@e\n%r ={ty} {op} %x, {n}\nret %r\n}}')
            ctype='uint32_t' if ty=='w' else 'uint64_t';declarations.append(f'extern {ctype} {name}({ctype});')
        name=shapes[key][0];checks.append(f'REQUIRE({name}(UINT64_C({x}))==UINT64_C({expected}));')
    functions += ['''export function l $immediate_context(l %x,l %y,w %n) {
@entry
jmp @loop
@loop
%i =w phi @entry 0, @body %nexti
%a =l phi @entry %x, @body %nexta
%done =w csgew %i, %n
jnz %done, @exit, @body
@body
%call =l call $immediate_callback(l %a,l %x,l %y)
%sum =l add %call, 127
%nexta =l xor %sum, 18446744071562067968
%nexti =w add %i, 1
jmp @loop
@exit
%r =l sub %a, %y
ret %r
}
export function w $immediate_projection(l %x) {
@entry
%r =w add %x, 4294967295
ret %r
}
export function l $immediate_symbol() {
@entry
%r =l add $"immediate slot\\\\"+3, 7
ret %r
}
export function l $immediate_subtract(l %x) {
@entry
%r =l sub 7, %x
ret %r
}
export function w $immediate_rhs_projection(l %x,l %y) {
@entry
%r =w and %x, %y
ret %r
}
export function l $immediate_preserved() {
@entry
%r =l call $immediate_context(l 81985529216486895,l 18364758544493064720,w 5)
ret %r
}''']
    declarations += ['extern uint64_t immediate_context(uint64_t,uint64_t,uint32_t);','extern uint32_t immediate_projection(uint64_t);','extern uintptr_t immediate_symbol(void);','extern uint64_t immediate_subtract(uint64_t);','extern uint32_t immediate_rhs_projection(uint64_t,uint64_t);','extern uint64_t immediate_preserved(void);','extern uint64_t zbe_check_preserved(uint64_t (*)(void));']
    mask=(1<<64)-1
    for n in (0,1,2,5,17):
        x=0x123456789abcdef;y=0xfedcba9876543210;a=x
        for _ in range(n):a=(((a+(x^y))&mask)+127)&mask;a^=0xffffffff80000000
        checks.append(f'REQUIRE(immediate_context(UINT64_C({x}),UINT64_C({y}),{n})==UINT64_C({(a-y)&mask}));')
    checks += ['REQUIRE(immediate_projection(UINT64_C(0xdeadbeef80000000))==UINT32_C(0x7fffffff));','REQUIRE(immediate_symbol()==(uintptr_t)&immediate_storage[10]);','REQUIRE(immediate_subtract(UINT64_C(0xffffffff80000000))==UINT64_C(0x80000007));','REQUIRE(zbe_check_preserved(immediate_preserved)==0);','REQUIRE(immediate_rhs_projection(UINT64_C(0xdeadbeef89abcdef),UINT64_C(0x12345678ff00ff00))==UINT32_C(0x8900cd00));']
    c='''#include <stdint.h>
#include <stdio.h>
unsigned char immediate_storage[32];
uint64_t immediate_callback(uint64_t a,uint64_t x,uint64_t y) { return a+(x^y); }
#define REQUIRE(c) do { ++count; if (!(c)) { fprintf(stderr,"immediate check %zu failed\\n",count); return 1; } } while(0)
'''+ '\n'.join(declarations)+'\nint main(void) { size_t count=0;\n'+ '\n'.join(checks)+'\nprintf("%zu native immediate selection assertions passed\\n",count); return 0; }\n'
    with tempfile.TemporaryDirectory(prefix='zbe-immediate-') as d:
        work=Path(d);src,asm,driver,aliases,obj,binary=[work/n for n in ('n.ssa','n.s','main.c','aliases.s','n.o','check')]
        src.write_text('\n'.join(functions));driver.write_text(c)
        subprocess.run([str(args.compiler.resolve()),*flags,str(src),str(asm)],check=True,timeout=90)
        # Defined ordinary quoted symbol, not COMMON; normal alias workaround remains.
        aliases.write_text('.data\n.globl "immediate slot\\\\"\n"immediate slot\\\\":\n.zero 32\n.globl immediate_storage\n.set immediate_storage,"immediate slot\\\\"\n.section .note.GNU-stack,"",@progbits\n')
        driver.write_text(c.replace('unsigned char immediate_storage[32];','extern unsigned char immediate_storage[32];'))
        subprocess.run([args.cc,'-c',str(asm),'-o',str(obj)],check=True,timeout=60)
        dis=subprocess.check_output(['objdump','-d',str(obj)],text=True,timeout=30)
        shape_count=0
        if not args.fold_integers:
            for (ty,op,_),(name,eligible,encoding) in shapes.items():
                body=dis.split('<'+name+'>:',1)[1].split('\n\n',1)[0]
                width=32 if ty=='w' else 64;register='eax' if ty=='w' else 'rax'
                pattern=rf'\b{op}\s+\$0x([0-9a-f]+),%{register}\b'
                immediate=re.search(pattern,body)
                if eligible:
                    if immediate is None or int(immediate[1],16)!=(encoding&((1<<width)-1)):raise SystemExit(f'Object immediate encoding wrong: {name}\n{body}')
                elif immediate is not None or not re.search(rf'\b{op}\s+%r10,%rax\b',body):raise SystemExit(f'Required fallback missing: {name}\n{body}')
                shape_count+=1
            print(f'{shape_count} independently checked object immediate/fallback encodings passed')
        for link in (['-fPIE','-pie'],['-fno-pie','-no-pie']):
            subprocess.run([args.cc,'-std=c11','-O2','-Wall','-Wextra','-Werror',*link,str(obj),str(aliases),str(driver),str(root/'src/fixtures/check-preserved.s'),'-o',str(binary)],check=True,timeout=90)
            subprocess.run([str(binary)],check=True,timeout=30)
        print('2 PIE/nonPIE immediate selection executions passed')
if __name__=='__main__':main()
