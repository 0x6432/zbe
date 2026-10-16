#!/usr/bin/env python3
"""Independent raw bytes, ELF section kinds, and cap-sized sparse BSS checks."""
from pathlib import Path
import argparse
import platform
import re
import resource
import subprocess
import tempfile


def run(command,**kwargs):
    return subprocess.run(command,check=True,timeout=90,**kwargs)


def elf_tables(binary):
    sections=run(['readelf','--wide','--section-headers',str(binary)],capture_output=True,text=True).stdout
    section_map={int(m[1]):(m[2],m[3]) for line in sections.splitlines() if (m:=re.match(r'\s*\[\s*(\d+)\]\s+(\S+)\s+(\S+)',line))}
    symbols=run(['readelf','--wide','--symbols',str(binary)],capture_output=True,text=True).stdout
    table={f[7]:f for line in symbols.splitlines() if len(f:=line.split())==8 and f[0].endswith(':')}
    return section_map,table


def main():
    root=Path(__file__).resolve().parents[1]
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--compiler',type=Path,default=root/'zig-out/bin/zbe-native');parser.add_argument('--cc',default='cc')
    for f in ('fold-integers','reuse-stack-homes','callee-saved-homes'):parser.add_argument('--'+f,action='store_true')
    args=parser.parse_args()
    if platform.system()!='Linux' or platform.machine() not in ('x86_64','amd64'):raise SystemExit('BSS checks require Linux AMD64; no result claimed.')
    resource.setrlimit(resource.RLIMIT_CORE,(0,0))
    flags=['--'+f for f in ('fold-integers','reuse-stack-homes','callee-saved-homes') if getattr(args,f.replace('-','_'))]
    compiler=str(args.compiler.resolve())
    # Explicit expected bytes/section kinds, not source-parser/emitter outputs.
    records=[('bss_numbers',64,True,bytes(15),'NOBITS'),('bss_bytes',32,True,bytes(3),'NOBITS'),
             ('bss_empty',16,False,b'','NOBITS'),('bss_positive',8,True,bytes(12),'NOBITS'),
             ('bss_negative',8,True,bytes.fromhex('000000800000000000000080'),'PROGBITS'),
             ('bss_nonzero',8,True,bytes(63)+b'\1'+bytes(65),'PROGBITS'),
             ('bss_pointer',8,True,bytes(8),'PROGBITS'),('bss_mixed',8,False,bytes(35),'NOBITS')]
    wrappers=[];decl=[];checks=[];expected_count=0
    for name,alignment,exported,payload,kind in records:
        if name not in ('bss_empty','bss_mixed'):wrappers.append(f'export function l ${name}_address() {{\n@e\nret ${name}\n}}')
        decl.append(f'extern uint64_t {name}_address(void);')
        if exported:decl.append(f'extern unsigned char {name}[];')
        checks += [f'unsigned char *p_{name}=(unsigned char *)(uintptr_t){name}_address();',f'REQUIRE((uintptr_t)p_{name}%{alignment}==0);',f'if(argc>1) REQUIRE(((uintptr_t)p_{name}>>32)!=0);']
        expected_count+=1
        if exported:checks.append(f'REQUIRE(p_{name}=={name});');expected_count+=1
        if not payload:continue
        n=len(payload)
        decl += [f'static const unsigned char initial_{name}[]={{'+','.join(map(str,payload))+'};',f'extern uint32_t {name}_read(uint64_t),{name}_write(uint64_t,uint32_t);']
        wrappers += [f'export function w ${name}_read(l %i) {{\n@e\n%p =l add ${name}, %i\n%x =w loadub %p\nret %x\n}}',f'export function w ${name}_write(l %i,w %v) {{\n@e\n%p =l add ${name}, %i\nstoreb %v, %p\n%x =w loadub %p\nret %x\n}}']
        checks += ['{',f'unsigned char expected[{n}];memcpy(expected,initial_{name},{n});']
        if name=='bss_pointer':checks.append('uint64_t address=(uintptr_t)bss_bytes;memcpy(expected,&address,8);')
        checks += [f'REQUIRE(memcmp(p_{name},expected,{n})==0);',f'for(size_t i=0;i<{n};++i) {{',f'REQUIRE({name}_read(i)==expected[i]);',
                   'uint32_t value=(uint32_t)(i*517+0xdead1200);expected[i]=(unsigned char)value;',f'REQUIRE({name}_write(i,value)==expected[i]);REQUIRE(memcmp(p_{name},expected,{n})==0);',
                   f'p_{name}[i]^=0xa5;expected[i]^=0xa5;REQUIRE({name}_read(i)==expected[i]);','}','}']
        expected_count+=1+4*n
    assert expected_count==877
    c='\n'.join(['#include <stdint.h>','#include <stdio.h>','#include <string.h>',*decl,
                  '#define REQUIRE(c) do {++count;if(!(c)){fprintf(stderr,"BSS check %zu failed at line %d\\n",count,__LINE__);return 1;}} while(0)',
                  'int main(int argc,char **argv){(void)argv;size_t count=0;',*checks,
                  'if(count!=(size_t)(877+(argc>1?8:0))) return 3;',
                  'printf("%zu native zero-data bit-pattern/mutation checks passed\\n",count);return 0;}'])
    with tempfile.TemporaryDirectory(prefix='zbe-bss-') as directory:
        work=Path(directory);source,assembly,driver,binary=[work/n for n in ('bss.ssa','bss.s','main.c','test')]
        source.write_text((root/'src/fixtures/data-bss.ssa').read_text()+'\n'+'\n'.join(wrappers)+'\n');driver.write_text(c)
        run([compiler,*flags,str(source),str(assembly)])
        metadata=0
        for pie in (False,True):
            mode=['-fPIE','-pie'] if pie else ['-fno-pie','-no-pie']
            run([args.cc,'-std=c11','-O2','-Wall','-Wextra','-Werror',*mode,str(driver),str(assembly),'-o',str(binary)])
            run([str(binary),*(['high-address'] if pie else [])])
            sections,symbols=elf_tables(binary)
            for name,alignment,exported,payload,kind in records:
                fields=symbols.get(name)
                if fields is None or fields[3]!='OBJECT' or fields[4]!=('GLOBAL' if exported else 'LOCAL') or int(fields[2],0)!=len(payload) or int(fields[1],16)%alignment or sections.get(int(fields[6]))!=(('.bss' if kind=='NOBITS' else '.data'),kind):
                    raise SystemExit(f'Wrong data section/metadata for {name}: {fields}')
                metadata+=1
        assert metadata==16
        print('16 zero-data ELF section/size/binding checks passed')
        cap=16*1024*1024
        source.write_text('\n'.join(f'export data $bss_cap_{i} = align 64 {{ z {cap} }}' for i in range(4))+'\n')
        run([compiler,*flags,str(source),str(assembly)])
        driver.write_text('''#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
extern unsigned char bss_cap_0[],bss_cap_1[],bss_cap_2[],bss_cap_3[];
int main(void) {
 unsigned char *objects[]={bss_cap_0,bss_cap_1,bss_cap_2,bss_cap_3};
 const size_t size=16*1024*1024;
 for(size_t o=0;o<4;++o) {
  if((uintptr_t)objects[o]%64) return 1;
  for(size_t i=0;i<size;++i) if(objects[o][i]!=0) return 2;
  objects[o][0]=(unsigned char)(17+o);objects[o][size-1]=(unsigned char)(201+o);
  for(size_t i=0;i<size;++i) if(objects[o][i]!=(i==0?17+o:i==size-1?201+o:0)) return 3;
 }
 return 0;
}
''')
        for mode in (['-fno-pie','-no-pie'],['-fPIE','-pie']):
            run([args.cc,'-std=c11','-O2','-Wall','-Wextra','-Werror',*mode,str(driver),str(assembly),'-o',str(binary)])
            if binary.stat().st_size>128*1024:raise SystemExit('64MiB zero module unexpectedly inflated ELF file')
            sections,symbols=elf_tables(binary)
            for i in range(4):
                fields=symbols.get(f'bss_cap_{i}')
                if fields is None or int(fields[2],0)!=cap or sections.get(int(fields[6]))!=('.bss','NOBITS'):
                    raise SystemExit('Cap-sized object lost BSS extent')
            run([str(binary)])
        print('2 cap-sized BSS sparse-file/runtime checks passed')


if __name__=='__main__':main()
