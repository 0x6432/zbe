#!/usr/bin/env python3
"""Independent linked C expectations for long symbol-address operands (Linux AMD64)."""
from pathlib import Path
import argparse
import platform
import resource
import subprocess
import tempfile


def main():
    root = Path(__file__).resolve().parents[1]
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--compiler', type=Path, default=root/'zig-out/bin/zbe-native')
    parser.add_argument('--cc', default='cc')
    for flag in ('fold-integers', 'reuse-stack-homes', 'callee-saved-homes'):
        parser.add_argument('--'+flag, action='store_true')
    args = parser.parse_args()
    if platform.system() != 'Linux' or platform.machine() not in ('x86_64', 'amd64'):
        raise SystemExit('Symbol checks require Linux AMD64; no result claimed.')
    resource.setrlimit(resource.RLIMIT_CORE, (0, 0))
    flags = ['--'+f for f in ('fold-integers', 'reuse-stack-homes', 'callee-saved-homes') if getattr(args, f.replace('-', '_'))]
    c = r'''#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
unsigned char zbe_symbol_bytes[64],zbe_symbol_other[64];
uint64_t zbe_symbol_slot;
extern uint64_t symbol_address(void),symbol_function_address(void),symbol_external_address(void);
extern uint64_t symbol_load(uint64_t),symbol_store(uint64_t,uint32_t),symbol_phi(uint32_t),symbol_swap(uint32_t);
extern uint64_t symbol_target(unsigned char *,uint64_t),symbol_callback(uint64_t),symbol_external_callback(uint64_t);
extern uint64_t symbol_many_arguments(void),symbol_slot_roundtrip(void),symbol_difference(void),symbol_preserved(void);
extern uint32_t symbol_low_word(void),symbol_branch(void);
extern void symbol_blit(void);
extern uint64_t zbe_check_preserved(uint64_t (*)(void));
uint64_t zbe_symbol_transform(unsigned char *p,uint64_t n) {
 if(p!=zbe_symbol_bytes) abort();
 return (n^((uint64_t)p[0]<<40))+123;
}
uint64_t zbe_symbol_arguments(uint64_t a,uint64_t b,uint64_t c,uint64_t d,uint64_t e,uint64_t f,uint64_t g,uint64_t h,double x,float y) {
 uint32_t bits;memcpy(&bits,&y,4);
 if(a!=(uintptr_t)zbe_symbol_bytes || b!=(uintptr_t)zbe_symbol_other || c!=(uintptr_t)&zbe_symbol_slot ||
    d!=(uintptr_t)zbe_symbol_transform || e!=(uintptr_t)symbol_target || f!=a || g!=b || h!=c || x!=1.5 || bits!=UINT32_C(0x80000000)) abort();
 return UINT64_C(0x6234);
}
#define REQUIRE(c) do { ++count; if(!(c)) { fprintf(stderr,"symbol check %zu failed\n",count);return 1; } } while(0)
int main(int argc,char **argv) {
 (void)argv;
 if(argc>1 && (((uintptr_t)zbe_symbol_bytes>>32)==0 || ((uintptr_t)symbol_target>>32)==0 || ((uintptr_t)zbe_symbol_transform>>32)==0)) {
  fprintf(stderr,"PIE high-address precondition failed\n");return 2;
 }
 const uint64_t seeds[]={0,1,17,127,128,255,UINT64_C(0xdeadbeef),UINT64_C(0xffffffff)};
 const uint64_t numbers[]={0,1,127,255,UINT64_C(0x100000000),UINT64_C(0x8000000000000000),UINT64_MAX-1,UINT64_MAX};
 size_t count=0;
 for(size_t s=0;s<sizeof(seeds)/sizeof(seeds[0]);++s) {
  uint64_t seed=seeds[s];
  for(size_t i=0;i<64;++i) {zbe_symbol_bytes[i]=(unsigned char)(seed+i*17);zbe_symbol_other[i]=(unsigned char)((seed^0xa5)+i*29);}
  REQUIRE(symbol_address()==(uintptr_t)zbe_symbol_bytes);
  REQUIRE(symbol_function_address()==(uintptr_t)symbol_target);
  REQUIRE(symbol_external_address()==(uintptr_t)zbe_symbol_transform);
  REQUIRE(symbol_low_word()==(uint32_t)(uintptr_t)zbe_symbol_bytes);
  REQUIRE(symbol_branch()==((uint32_t)(uintptr_t)zbe_symbol_bytes?11u:22u));
  REQUIRE(symbol_difference()==(uint64_t)(uintptr_t)zbe_symbol_bytes-(uint64_t)(uintptr_t)zbe_symbol_other);
  REQUIRE(symbol_many_arguments()==UINT64_C(0x6234));
  REQUIRE(symbol_slot_roundtrip()==(uintptr_t)zbe_symbol_bytes);
  REQUIRE(zbe_symbol_slot==(uintptr_t)zbe_symbol_bytes);
  uint64_t mixed=(uintptr_t)zbe_symbol_bytes^(uintptr_t)zbe_symbol_other^(uintptr_t)&zbe_symbol_slot^(uintptr_t)zbe_symbol_transform^(uintptr_t)symbol_target;
  REQUIRE(symbol_preserved()==mixed);
  REQUIRE(zbe_check_preserved(symbol_preserved)==0);
  for(unsigned select=0;select<2;++select) {
   uint64_t x=select?zbe_symbol_bytes[0]:zbe_symbol_other[0];
   uint64_t y=select?zbe_symbol_other[0]:zbe_symbol_bytes[0];
   REQUIRE(symbol_phi(select)==x+257*y);
  }
  for(unsigned n=0;n<32;++n) {
   uint64_t x=n%2?zbe_symbol_other[0]:zbe_symbol_bytes[0];
   uint64_t y=n%2?zbe_symbol_bytes[0]:zbe_symbol_other[0];
   REQUIRE(symbol_swap(n)==x+257*y);
  }
  for(size_t n=0;n<sizeof(numbers)/sizeof(numbers[0]);++n) {
   REQUIRE(symbol_callback(numbers[n])==numbers[n]+zbe_symbol_bytes[0]);
   REQUIRE(symbol_external_callback(numbers[n])==(numbers[n]^((uint64_t)zbe_symbol_bytes[0]<<40))+123);
  }
  for(size_t i=0;i<64;++i) {
   unsigned char expected[64];memcpy(expected,zbe_symbol_bytes,64);
   REQUIRE(symbol_load(i)==expected[i]);
   uint32_t value=(uint32_t)(seed^(i*257));expected[i]=(unsigned char)value;
   REQUIRE(symbol_store(i,value)==expected[i]);
   REQUIRE(memcmp(zbe_symbol_bytes,expected,64)==0);
  }
  unsigned char expected[64];memcpy(expected,zbe_symbol_other,64);memcpy(expected,zbe_symbol_bytes,16);
  symbol_blit();REQUIRE(memcmp(zbe_symbol_other,expected,64)==0);
 }
 if(count!=2032) return 3;
 printf("%zu native linked-symbol checks passed\n",count);return 0;
}
'''
    with tempfile.TemporaryDirectory(prefix='zbe-symbols-') as directory:
        work=Path(directory)
        src, asm, driver, binary=[work/n for n in ('symbols.ssa','symbols.s','main.c','check')]
        src.write_text((root/'src/fixtures/symbol-addresses.ssa').read_text())
        driver.write_text(c)
        subprocess.run([str(args.compiler.resolve()),*flags,str(src),str(asm)],check=True,timeout=120)
        for position_independent in (False,True):
            mode=['-fPIE','-pie'] if position_independent else ['-fno-pie','-no-pie']
            subprocess.run([args.cc,'-std=c11','-O2','-Wall','-Wextra','-Werror',*mode,str(driver),str(asm),str(root/'src/fixtures/check-preserved.s'),'-o',str(binary)],check=True,timeout=90)
            subprocess.run([str(binary),*(['high-address'] if position_independent else [])],check=True,timeout=30)
        print('2 executable linking modes including PIE high-address checks passed')
        bad_inputs=(
            'function w $f() {\n@e\nret $target\n}',
            'function s $f() {\n@e\n%r =s copy $target\nret %r\n}',
            'function l $f() {\n@e\nret $target+8\n}',
            'function l $f() {\n@e\nret $"quoted"\n}',
            'function l $f() {\n@e\nret thread $target\n}',
            'function l $f() {\n@e\nret extern $target\n}',
            'data $target = { l 1 }',
            'function $f() {\n@e\ncall $callee(w $target)\nret\n}',
        )
        for text in bad_inputs:
            src.write_text(text)
            if asm.exists():asm.unlink()
            for exists in (False,True):
                if exists:asm.write_text('preserve-symbol-output')
                result=subprocess.run([str(args.compiler.resolve()),*flags,str(src),str(asm)],capture_output=True,timeout=30)
                if result.returncode==0:raise SystemExit('Invalid/unsupported symbolic input accepted')
                if (exists and asm.read_text()!='preserve-symbol-output') or (not exists and asm.exists()):raise SystemExit('Rejected symbolic input changed output')
        print('16 symbol rejection/output-preservation checks passed')


if __name__=='__main__':main()
