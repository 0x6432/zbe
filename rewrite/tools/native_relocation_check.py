#!/usr/bin/env python3
"""Independent linked-address expectations for writable 64-bit data relocations."""
from pathlib import Path
import argparse
import platform
import resource
import subprocess
import tempfile


def run(command, **kwargs):
    return subprocess.run(command, check=True, timeout=90, **kwargs)


def main():
    root = Path(__file__).resolve().parents[1]
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--compiler', type=Path, default=root/'zig-out/bin/zbe-native')
    parser.add_argument('--cc', default='cc')
    for flag in ('fold-integers','reuse-stack-homes','callee-saved-homes'):
        parser.add_argument('--'+flag, action='store_true')
    args = parser.parse_args()
    if platform.system()!='Linux' or platform.machine() not in ('x86_64','amd64'):
        raise SystemExit('Relocation checks require Linux AMD64; no result claimed.')
    resource.setrlimit(resource.RLIMIT_CORE,(0,0))
    flags = ['--'+f for f in ('fold-integers','reuse-stack-homes','callee-saved-homes') if getattr(args,f.replace('-','_'))]
    compiler = str(args.compiler.resolve())
    c = r'''#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
unsigned char reloc_external_bytes[96];
__asm__(".globl reloc_external_middle\n.set reloc_external_middle,reloc_external_bytes+17");
uint64_t reloc_external_function(uint64_t x) { return (x^UINT64_C(0xa55a87654321))+19; }
extern uint64_t reloc_table[15],reloc_self,reloc_negative;
extern unsigned char reloc_unaligned[11];
extern uint64_t reloc_address(void),reloc_forward_address(void),reloc_internal_address(void),reloc_read(uint64_t),reloc_callback(uint64_t,uint64_t);
extern uint32_t reloc_load_byte(uint64_t);
extern void reloc_write_byte(uint64_t,uint32_t),reloc_replace(uint64_t,uint64_t);
#define REQUIRE(c) do {++count;if(!(c)){fprintf(stderr,"relocation check %zu failed at line %d\n",count,__LINE__);return 1;}} while(0)
int main(int argc,char **argv) {
 (void)argv;size_t count=0;
 unsigned char *internal=(unsigned char *)(uintptr_t)reloc_address();
 unsigned char *forward=(unsigned char *)(uintptr_t)reloc_forward_address();
 uint64_t function=reloc_internal_address();
 uint64_t expected[]={
  (uintptr_t)internal,(uintptr_t)(internal+1),(uintptr_t)(internal+63),
  (uintptr_t)(internal+32),(uintptr_t)(internal+32),
  (uintptr_t)reloc_external_bytes,(uintptr_t)(reloc_external_bytes+17),
  function,(uintptr_t)reloc_external_function,
  (uintptr_t)&reloc_self,(uintptr_t)forward,(uintptr_t)reloc_table,
  (uint64_t)(uintptr_t)internal+UINT64_C(9223372036854775807),
  (uint64_t)(uintptr_t)internal+UINT64_C(9223372036854775808),UINT64_C(81985529216486895)
 };
 for(size_t i=0;i<15;++i) { REQUIRE(reloc_table[i]==expected[i]);REQUIRE(reloc_read(i)==expected[i]); }
 REQUIRE((uintptr_t)internal%64==0);REQUIRE((uintptr_t)reloc_table%16==0);
 REQUIRE(reloc_negative==(uintptr_t)reloc_external_bytes);
 REQUIRE(reloc_self==(uintptr_t)&reloc_self);
 uint64_t bits;memcpy(&bits,forward,8);REQUIRE(bits==(uintptr_t)reloc_table);REQUIRE(forward[8]==51);
 REQUIRE(reloc_unaligned[0]==85);uint16_t half;memcpy(&half,reloc_unaligned+9,2);REQUIRE(half==8755);
 memcpy(&bits,reloc_unaligned+1,8);REQUIRE(bits==(uintptr_t)(reloc_external_bytes+1));
 if(argc>1) {REQUIRE(((uintptr_t)internal>>32)!=0);REQUIRE(((uintptr_t)reloc_external_bytes>>32)!=0);REQUIRE((function>>32)!=0);}
 unsigned char a[64]={0},b[96];a[0]=17;a[63]=165;REQUIRE(memcmp(internal,a,64)==0);
 const size_t offsets[]={0,1,63,32,32,0,17};
 for(unsigned seed=0;seed<8;++seed) {
  for(size_t i=0;i<64;++i) a[i]=(unsigned char)(seed*29+i*17);
  for(size_t i=0;i<96;++i) b[i]=(unsigned char)(seed*13+i*31);
  memcpy(internal,a,64);memcpy(reloc_external_bytes,b,96);
  for(size_t i=0;i<7;++i) {
   unsigned char *expected_bytes=i<5?a:b;
   REQUIRE(reloc_load_byte(i)==expected_bytes[offsets[i]]);
   uint32_t value=(uint32_t)(seed*257+i*513+0xdead1200);expected_bytes[offsets[i]]=(unsigned char)value;
   reloc_write_byte(i,value);
   REQUIRE(memcmp(internal,a,64)==0);REQUIRE(memcmp(reloc_external_bytes,b,96)==0);
   REQUIRE(reloc_load_byte(i)==(unsigned char)value);
  }
 }
 const uint64_t numbers[]={0,1,255,UINT64_C(0xffffffff),UINT64_C(0x100000000),UINT64_C(0x8000000000000000),UINT64_MAX-1,UINT64_MAX};
 for(size_t i=0;i<8;++i) {
  REQUIRE(reloc_callback(7,numbers[i])==numbers[i]+257);
  REQUIRE(reloc_callback(8,numbers[i])==(numbers[i]^UINT64_C(0xa55a87654321))+19);
 }
 for(size_t i=0;i<7;++i) {
  uint64_t address=(uintptr_t)(reloc_external_bytes+42);reloc_replace(i,address);
  REQUIRE(reloc_table[i]==address);REQUIRE(reloc_read(i)==address);REQUIRE(reloc_load_byte(i)==reloc_external_bytes[42]);
  reloc_table[i]=expected[i];REQUIRE(reloc_read(i)==expected[i]);REQUIRE(memcmp(reloc_table,expected,sizeof(expected))==0);
 }
 reloc_replace(7,(uintptr_t)reloc_external_function);
 for(size_t i=0;i<8;++i) REQUIRE(reloc_callback(7,numbers[i])==(numbers[i]^UINT64_C(0xa55a87654321))+19);
 reloc_table[7]=function;REQUIRE(memcmp(reloc_table,expected,sizeof(expected))==0);
 if(count!=(size_t)(324+(argc>1?3:0))) {fprintf(stderr,"relocation completion count %zu, expected %d\n",count,324+(argc>1?3:0));return 3;}
 printf("%zu native symbolic-data address/callback/mutation checks passed\n",count);return 0;
}
'''
    with tempfile.TemporaryDirectory(prefix='zbe-relocations-') as directory:
        work=Path(directory)
        source,assembly,driver,binary=[work/n for n in ('data.ssa','data.s','main.c','test')]
        source.write_text((root/'src/fixtures/data-relocations.ssa').read_text())
        driver.write_text(c)
        run([compiler,*flags,str(source),str(assembly)])
        metadata=0
        for pie in (False,True):
            mode=['-fPIE','-pie'] if pie else ['-fno-pie','-no-pie']
            run([args.cc,'-std=c11','-O2','-Wall','-Wextra','-Werror',*mode,str(driver),str(assembly),'-o',str(binary)])
            run([str(binary),*(['high-address'] if pie else [])])
            dynamic=run(['readelf','--dynamic',str(binary)],capture_output=True,text=True).stdout
            if 'TEXTREL' in dynamic: raise SystemExit('Unexpected text relocation')
            elf=run(['readelf','--wide','--symbols',str(binary)],capture_output=True,text=True).stdout
            table={f[7]:f for line in elf.splitlines() if len(f:=line.split())==8 and f[0].endswith(':')}
            for name,size,binding in [('reloc_table',120,'GLOBAL'),('reloc_bytes',64,'LOCAL'),('reloc_forward',9,'LOCAL'),('reloc_self',8,'GLOBAL'),('reloc_negative',8,'GLOBAL'),('reloc_unaligned',11,'GLOBAL')]:
                fields=table.get(name)
                if fields is None or fields[3]!='OBJECT' or fields[4]!=binding or int(fields[2])!=size:
                    raise SystemExit(f'Wrong relocated object metadata for {name}: {fields}')
                metadata+=1
        assert metadata==12
        print('12 relocated-object ELF metadata checks passed')
        print('2 executable no-text-relocation checks passed')
        source.write_text('export data $reloc_only = { l $reloc_only $reloc_external_function }\n')
        run([compiler,*flags,str(source),str(assembly)])
        driver.write_text('#include <stdint.h>\nextern uint64_t reloc_only[2];\nuint64_t reloc_external_function(uint64_t x){return x+5;}\nint main(void){return reloc_only[0]!=(uintptr_t)reloc_only || reloc_only[1]!=(uintptr_t)reloc_external_function;}\n')
        for mode in (['-fno-pie','-no-pie'],['-fPIE','-pie']):
            run([args.cc,'-std=c11','-O2','-Wall','-Wextra','-Werror',*mode,str(driver),str(assembly),'-o',str(binary)])
            run([str(binary)])
        print('2 symbolic-data-only executable linking checks passed')
        bad=[
            'data $x = { b $target }','data $x = { h $target }','data $x = { w $target }',
            'data $x = { s $target }','data $x = { d $target }','data $x = { z $target }',
            'data $x = { l $"quoted" }','data $x = { l thread $target }',
            'data $x = { l $target+9223372036854775808 }','data $x = { l $target+-9223372036854775809 }',
            'data $x = { l $target+18446744073709551616 }','data $x = { l $target+d_1 }',
            'data $x = { l $target+$other }','data $x = { l $target - 8 }','data $x = { l $target++8 }',
            'data $x = { l $target+ }','data $x = { l $target+1+2 }',
            'function l $f() {\n@e\nret $target+1\n}',
            'data $x = { l extern $target }','data $x = { l $target+nan }',
        ]
        assert len(bad)==20
        for text in bad:
            source.write_text(text)
            if assembly.exists():assembly.unlink()
            for exists in (False,True):
                if exists:assembly.write_text('preserve-relocation-output')
                result=subprocess.run([compiler,*flags,str(source),str(assembly)],capture_output=True,timeout=30)
                if result.returncode==0: raise SystemExit('Invalid/unsupported data reference accepted')
                if (exists and assembly.read_text()!='preserve-relocation-output') or (not exists and assembly.exists()):
                    raise SystemExit('Rejected data reference changed output')
        print('40 symbolic-data rejection/output-preservation checks passed')


if __name__=='__main__':main()
