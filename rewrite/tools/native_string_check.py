#!/usr/bin/env python3
"""Independent byte-string data, linker extent, mutation and injection checks."""
from pathlib import Path
import argparse
import platform
import resource
import subprocess
import tempfile


def run(command, **kwargs):
    return subprocess.run(command,check=True,timeout=90,**kwargs)


def main():
    root=Path(__file__).resolve().parents[1]
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--compiler',type=Path,default=root/'zig-out/bin/zbe-native')
    parser.add_argument('--cc',default='cc')
    for flag in ('fold-integers','reuse-stack-homes','callee-saved-homes'):parser.add_argument('--'+flag,action='store_true')
    args=parser.parse_args()
    if platform.system()!='Linux' or platform.machine() not in ('x86_64','amd64'):raise SystemExit('String checks require Linux AMD64; no result claimed.')
    resource.setrlimit(resource.RLIMIT_CORE,(0,0))
    flags=['--'+f for f in ('fold-integers','reuse-stack-homes','callee-saved-homes') if getattr(args,f.replace('-','_'))]
    compiler=str(args.compiler.resolve())
    objects=[]
    for line in (root/'src/fixtures/data-string-oracle.tsv').read_text().splitlines():
        if not line or line.startswith('#'):continue
        name,alignment,exported,hex_bytes=line.split('\t')
        objects.append((name,int(alignment),bool(int(exported)),b'' if hex_bytes=='-' else bytes.fromhex(hex_bytes)))
    assert len(objects)==8
    wrappers,declarations,checks=[],[],[]
    expected_count=0
    for name,alignment,exported,payload in objects:
        wrappers.append(f'export function l ${name}_address() {{\n@e\nret ${name}\n}}')
        declarations.append(f'extern uint64_t {name}_address(void);')
        if exported:declarations.append(f'extern unsigned char {name}[];')
        checks += [f'unsigned char *p_{name}=(unsigned char *)(uintptr_t){name}_address();',
                   f'REQUIRE((uintptr_t)p_{name}%{alignment}==0);',f'if(argc>1) REQUIRE(((uintptr_t)p_{name}>>32)!=0);']
        expected_count+=1
        if exported:
            checks.append(f'REQUIRE(p_{name}=={name});');expected_count+=1
        if not payload:continue
        n=len(payload)
        declarations.append(f'static const unsigned char expected_{name}[]={{'+','.join(map(str,payload))+'};')
        declarations.append(f'extern uint32_t {name}_read(uint64_t),{name}_write(uint64_t,uint32_t);')
        wrappers += [f'export function w ${name}_read(l %i) {{\n@e\n%p =l add ${name}, %i\n%x =w loadub %p\nret %x\n}}',
                     f'export function w ${name}_write(l %i,w %v) {{\n@e\n%p =l add ${name}, %i\nstoreb %v, %p\n%x =w loadub %p\nret %x\n}}']
        checks += ['{',f'unsigned char expected[{n}];memcpy(expected,expected_{name},{n});',
                   f'REQUIRE(memcmp(p_{name},expected,{n})==0);',f'for(size_t i=0;i<{n};++i) {{',
                   f' REQUIRE({name}_read(i)==expected[i]);',
                   ' uint32_t value=(uint32_t)(i*517+0xdead1200);expected[i]=(unsigned char)value;',
                   f' REQUIRE({name}_write(i,value)==expected[i]);REQUIRE(memcmp(p_{name},expected,{n})==0);',
                   f' p_{name}[i]^=0xa5;expected[i]^=0xa5;REQUIRE({name}_read(i)==expected[i]);',
                   '}',f'memcpy(p_{name},expected_{name},{n});','}']
        expected_count+=1+4*n
    observe=sum((i+1)*v for i,v in enumerate(b'hello world\0'))
    wrappers += ['''export function l $string_call() {
@e
%r =l call $string_external_observe(l $string_plain, l 12)
%after =l loadub $string_plain
%result =l add %r, %after
ret %result
}''']
    declarations += ['extern uint64_t string_call(void);',
                     'uint64_t string_external_observe(unsigned char *p,uint64_t n) { if(p!=string_plain || n!=12 || memcmp(p,expected_string_plain,12)) abort();uint64_t value=0;for(size_t i=0;i<12;++i)value+=(i+1)*p[i];p[0]=72;return value;}']
    checks += [f'REQUIRE(string_call()==UINT64_C({observe+72}));','REQUIRE(string_plain[0]==72);']
    expected_count+=2
    c='\n'.join(['#include <stdint.h>','#include <stdio.h>','#include <stdlib.h>','#include <string.h>',*declarations,
                  '#define REQUIRE(c) do {++count;if(!(c)){fprintf(stderr,"string check %zu failed at line %d\\n",count,__LINE__);return 1;}} while(0)',
                  'int main(int argc,char **argv){(void)argv;size_t count=0;',*checks,
                  f'if(count!={expected_count}+(argc>1?8:0)) {{fprintf(stderr,"wrong string completion count %zu\\n",count);return 3;}}',
                  'printf("%zu native byte-string data/mutation checks passed\\n",count);return 0;}'])
    with tempfile.TemporaryDirectory(prefix='zbe-strings-') as directory:
        work=Path(directory);source,assembly,driver,binary=[work/n for n in ('strings.ssa','strings.s','main.c','test')]
        source.write_text((root/'src/fixtures/data-string-oracle.ssa').read_text()+'\n'+'\n'.join(wrappers)+'\n');driver.write_text(c)
        run([compiler,*flags,str(source),str(assembly)])
        text=assembly.read_text()
        if '.ascii' in text or 'zbe_injected_symbol' in text:raise SystemExit('Raw string content escaped into assembly')
        metadata=0
        for pie in (False,True):
            mode=['-fPIE','-pie'] if pie else ['-fno-pie','-no-pie']
            run([args.cc,'-std=c11','-O2','-Wall','-Wextra','-Werror',*mode,str(driver),str(assembly),'-o',str(binary)])
            run([str(binary),*(['high-address'] if pie else [])])
            elf=run(['readelf','--wide','--symbols',str(binary)],capture_output=True,text=True).stdout
            table={f[7]:f for line in elf.splitlines() if len(f:=line.split())==8 and f[0].endswith(':')}
            if 'zbe_injected_symbol' in table:raise SystemExit('String injected an ELF symbol')
            for name,alignment,exported,payload in objects:
                fields=table.get(name)
                if fields is None or fields[3]!='OBJECT' or fields[4]!=('GLOBAL' if exported else 'LOCAL') or int(fields[2])!=len(payload) or int(fields[1],16)%alignment:
                    raise SystemExit(f'Wrong string object metadata for {name}: {fields}')
                metadata+=1
        assert metadata==16
        print('16 string ELF extent/binding/alignment checks passed')
        print('2 linked string-injection checks passed')
        source.write_text(r'export data $string_only = { b "A\000B" }'+'\n')
        run([compiler,*flags,str(source),str(assembly)])
        driver.write_text('#include <string.h>\nextern unsigned char string_only[];\nint main(void){const unsigned char expected[]={65,0,66};return memcmp(string_only,expected,3);}\n')
        for mode in (['-fno-pie','-no-pie'],['-fPIE','-pie']):
            run([args.cc,'-std=c11','-O2','-Wall','-Wextra','-Werror',*mode,str(driver),str(assembly),'-o',str(binary)]);run([str(binary)])
        print('2 string-data-only executable linking checks passed')
        bad=[f'data $x = {{ {k} "string" }}' for k in ('h','w','l','s','d','z')]
        bad += [r'data $x = { b "'+escape+r'" }' for escape in (r'\q',r'\8',r'\400',r'\777',r'\x',r'\x0',r'\xGG',r'\u0041')]
        bad += ['data $x = { b "a\nb" }','data $x = { b "a\rb" }','data $x = { b "a\\\nb" }',
                'data $x = { b "unterminated }',r'data $x = { b "trailing\" }',
                'function l $f() {\n@e\nret "string"\n}',r'data $"" = { b "str" }',
                'data $x = { b "a"+1 }','data $x = { z 16777216, b "a" }','data $x = { b "a" w 1 }']
        assert len(bad)==24,len(bad)
        for text in bad:
            source.write_text(text)
            if assembly.exists():assembly.unlink()
            for exists in (False,True):
                if exists:assembly.write_text('preserve-string-output')
                result=subprocess.run([compiler,*flags,str(source),str(assembly)],capture_output=True,timeout=30)
                if result.returncode==0:raise SystemExit('Invalid/unsupported string accepted')
                if (exists and assembly.read_text()!='preserve-string-output') or (not exists and assembly.exists()):raise SystemExit('Rejected string changed output')
        print('48 string rejection/output-preservation checks passed')


if __name__=='__main__':main()
