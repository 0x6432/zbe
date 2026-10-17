#!/usr/bin/env python3
"""Independent linked C address/byte/ABI expectations for checked scalar offsets."""
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
    options = ('fold-integers', 'reuse-stack-homes', 'callee-saved-homes')
    for flag in options:
        parser.add_argument('--'+flag, action='store_true')
    args = parser.parse_args()
    if platform.system() != 'Linux' or platform.machine() not in ('x86_64', 'amd64'):
        raise SystemExit('Scalar offset checks require Linux AMD64; no result claimed.')
    resource.setrlimit(resource.RLIMIT_CORE, (0, 0))
    flags = ['--'+f for f in options if getattr(args, f.replace('-', '_'))]
    c = r'''#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
unsigned char offset_external_bytes[64];
uint64_t offset_slots[3];
extern unsigned char offset_owned[64];
/* Alias and its storage are defined in this translation unit. Every negative
   address tested remains inside the same C-owned array; no before-object C pointer. */
__asm__(".globl offset_middle\n.set offset_middle,offset_external_bytes+32\n");
extern uint64_t offset_internal(void),offset_external(void),offset_negative(void),offset_zero(void);
extern uint64_t offset_load(void),offset_store(uint32_t),offset_slot(void),offset_phi(uint32_t),offset_swap(uint32_t);
extern uint64_t offset_arguments(void),offset_indirect(void),offset_difference(void),offset_preserved(void);
extern uint32_t offset_project(void),offset_branch(void);
extern void offset_blit(void);
extern uint64_t zbe_check_preserved(uint64_t (*)(void));
uint64_t offset_check_arguments(unsigned char *a,unsigned char *b,unsigned char *c,uint64_t *d,
                              unsigned char *e,unsigned char *f,unsigned char *g,unsigned char *h,double x,float y) {
 uint32_t bits;memcpy(&bits,&y,4);
 if(a!=offset_owned+1 || b!=offset_external_bytes+30 || c!=offset_external_bytes+3 || d!=offset_slots+1 ||
    e!=offset_owned+5 || f!=offset_external_bytes+26 || g!=offset_owned+7 || h!=offset_external_bytes+24 ||
    x!=1.5 || bits!=UINT32_C(0x80000000)) abort();
 return UINT64_C(0x59372);
}
@DECLARATIONS@
#define REQUIRE(c) do { ++count; if(!(c)) { fprintf(stderr,"offset check %zu failed\n",count);return 1; } } while(0)
int main(int argc,char **argv) {
 (void)argv;
 if(argc>1 && (((uintptr_t)offset_owned>>32)==0 || ((uintptr_t)offset_external_bytes>>32)==0 ||
                ((uintptr_t)offset_check_arguments>>32)==0)) {
  fprintf(stderr,"PIE high-address precondition failed\n");return 2;
 }
 size_t count=0;
 for(unsigned seed=0;seed<8;++seed) {
  unsigned char expected[64];
  for(size_t i=0;i<64;++i) {offset_owned[i]=(unsigned char)(seed*37+i*17);offset_external_bytes[i]=(unsigned char)(seed*43+i*29);}
  memcpy(expected,offset_owned,64);
  offset_slots[0]=UINT64_C(0x123456789abcdef0);offset_slots[1]=0;offset_slots[2]=UINT64_C(0xabcdef0198765432);
  REQUIRE(offset_internal()==(uintptr_t)(offset_owned+17));
  REQUIRE(offset_external()==(uintptr_t)(offset_external_bytes+63));
  REQUIRE(offset_negative()==(uintptr_t)(offset_external_bytes+1));
  REQUIRE(offset_zero()==(uintptr_t)offset_external_bytes);
  REQUIRE(offset_difference()==1);
  REQUIRE(offset_load()==offset_external_bytes[25]);
  uint32_t value=UINT32_C(0xabcde100)+seed;
  REQUIRE(offset_store(value)==(unsigned char)value);
  expected[19]=(unsigned char)value;
  REQUIRE(offset_owned[19]==(unsigned char)value);
  REQUIRE(memcmp(expected,offset_owned,64)==0);
  REQUIRE(offset_slot()==(uintptr_t)(offset_external_bytes+23));
  REQUIRE(offset_slots[1]==(uintptr_t)(offset_external_bytes+23));
  REQUIRE(offset_slots[0]==UINT64_C(0x123456789abcdef0));
  REQUIRE(offset_slots[2]==UINT64_C(0xabcdef0198765432));
  REQUIRE(offset_arguments()==UINT64_C(0x59372));
  REQUIRE(offset_indirect()==UINT64_C(0x59372));
  REQUIRE(offset_project()==(uint32_t)(uintptr_t)(offset_external_bytes+19));
  REQUIRE(offset_branch()==((uint32_t)(uintptr_t)(offset_owned+17)?11u:22u));
  uint64_t mixed=(uintptr_t)(offset_owned+1)^(uintptr_t)(offset_external_bytes+30)^
   (uintptr_t)(offset_external_bytes+3)^(uintptr_t)(offset_slots+1)^(uintptr_t)(offset_owned+5);
  REQUIRE(offset_preserved()==mixed);
  REQUIRE(zbe_check_preserved(offset_preserved)==0);
  for(unsigned take=0;take<2;++take) {
   uint64_t x=take?offset_owned[7]:offset_external_bytes[27];
   uint64_t y=take?offset_external_bytes[27]:offset_owned[7];
   REQUIRE(offset_phi(take)==x+257*y);
  }
  for(unsigned n=0;n<32;++n) {
   uint64_t x=n%2?offset_external_bytes[21]:offset_owned[11];
   uint64_t y=n%2?offset_owned[11]:offset_external_bytes[21];
   REQUIRE(offset_swap(n)==x+257*y);
  }
  for(unsigned i=0;i<64;++i) {
   REQUIRE(positive[i]()==(uintptr_t)(offset_external_bytes+i));
   REQUIRE(negative[i]()==(uintptr_t)(offset_external_bytes+i));
  }
  memcpy(expected+32,offset_external_bytes+16,16);
  offset_blit();REQUIRE(memcmp(expected,offset_owned,64)==0);
 }
 if(count!=1456) {fprintf(stderr,"offset check count %zu\n",count);return 3;}
 printf("%zu native scalar-symbol-offset checks passed\n",count);return 0;
}
'''
    # IL and C expressions are deliberately separate: runtime expectations use
    # C pointer arithmetic in defined extents, never emitted assembly text.
    source = (root/'src/fixtures/symbol-offsets.ssa').read_text()
    declarations = []
    for name, symbol, delta in (('positive', 'offset_external_bytes', 0), ('negative', 'offset_middle', -32)):
        for i in range(64):
            source += f'\nexport function l ${name}_{i}() {{\n@e\nret ${symbol}+{i+delta}\n}}\n'
            declarations.append(f'extern uint64_t {name}_{i}(void);')
        declarations.append(f'static uint64_t (*const {name}[64])(void)={{'+','.join(f'{name}_{i}' for i in range(64))+'};')
    c = c.replace('@DECLARATIONS@', '\n'.join(declarations))
    with tempfile.TemporaryDirectory(prefix='zbe-offsets-') as directory:
        work = Path(directory)
        src, asm, driver, binary = [work/n for n in ('offsets.ssa','offsets.s','main.c','check')]
        src.write_text(source)
        driver.write_text(c)
        subprocess.run([str(args.compiler.resolve()),*flags,str(src),str(asm)],check=True,timeout=120)
        for pie in (False,True):
            mode = ['-fPIE','-pie'] if pie else ['-fno-pie','-no-pie']
            subprocess.run([args.cc,'-std=c11','-O2','-Wall','-Wextra','-Werror',*mode,str(driver),str(asm),
                            str(root/'src/fixtures/check-preserved.s'),'-o',str(binary)],check=True,timeout=90)
            subprocess.run([str(binary),*(['high-address'] if pie else [])],check=True,timeout=30)
            dynamic = subprocess.run(['readelf','-d',str(binary)],capture_output=True,text=True,check=True,timeout=30).stdout
            if 'TEXTREL' in dynamic:
                raise SystemExit('Scalar offsets introduced a dynamic text relocation')
        print('2 scalar-offset executable no-TEXTREL checks passed')
        bad = (
            'function l $f() {\n@e\nret $target+2147483648\n}',
            'function l $f() {\n@e\nret $target+-2147483649\n}',
            'function l $f() {\n@e\nret $target+18446744073709551616\n}',
            'function l $f() {\n@e\nret $target+\n1\n}',
            'function l $f() {\n@e\nret $target-8\n}',
            'function l $f() {\n@e\nret $target++8\n}',
            'function l $f() {\n@e\nret $target+$other\n}',
            'function l $f() {\n@e\nret $target+d_1\n}',
            'function l $f() {\n@e\nret $target+1+2\n}',
            'function l $f() {\n@e\nret $""+1\n}',
            'function w $f() {\n@e\nret $target+0\n}',
            'function s $f() {\n@e\nret $target+0\n}',
            'function d $f() {\n@e\nret $target+0\n}',
            'function $f() {\n@e\ncall $target+0()\nret\n}',
            'function $f() {\n@e\ncall $target(w $other+0)\nret\n}',
            'function l $f() {\n@e\nret thread $target+1\n}',
        )
        for text in bad:
            src.write_text(text)
            if asm.exists(): asm.unlink()
            for exists in (False,True):
                if exists: asm.write_text('preserve-offset-output')
                result = subprocess.run([str(args.compiler.resolve()),*flags,str(src),str(asm)],capture_output=True,timeout=30)
                if result.returncode == 0: raise SystemExit('Invalid/unsupported scalar offset accepted')
                if (exists and asm.read_text()!='preserve-offset-output') or (not exists and asm.exists()):
                    raise SystemExit('Rejected scalar offset changed output')
        print('32 scalar-offset rejection/output-preservation checks passed')


if __name__ == '__main__': main()
