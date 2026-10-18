#!/usr/bin/env python3
"""Existing exts conformance: exact bits, phi cycles, internal/external calls and homes.

Expected numeric bits come only from the committed independent integer oracle.
NaN arithmetic tests assert classification, never payload/flags/trap equivalence.
"""
from pathlib import Path
import argparse
import platform
import resource
import subprocess
import tempfile


def run(command):
    subprocess.run([str(x) for x in command], check=True, timeout=90)


def main():
    root = Path(__file__).resolve().parents[1]
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--compiler', type=Path, default=root/'zig-out/bin/zbe-native')
    parser.add_argument('--cc', default='cc')
    for flag in ('fold-integers', 'reuse-stack-homes', 'callee-saved-homes'):
        parser.add_argument('--'+flag, action='store_true')
    args = parser.parse_args()
    if platform.system() != 'Linux' or platform.machine() not in ('x86_64', 'amd64'):
        raise SystemExit('Float precision checks require Linux AMD64; no result claimed')
    resource.setrlimit(resource.RLIMIT_CORE, (0, 0))
    flags = ['--'+f for f in ('fold-integers', 'reuse-stack-homes', 'callee-saved-homes') if getattr(args, f.replace('-', '_'))]
    rows = [tuple(int(x, 16) for x in line.split()) for line in (root/'src/fixtures/float_precision_oracle.tsv').read_text().splitlines() if line and not line.startswith('#')]
    assert len(rows) == 3693
    array = ',\n'.join(f'{{UINT32_C(0x{a:x}),UINT64_C(0x{b:x})}}' for a, b in rows)
    source = r'''
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <xmmintrin.h>
extern uint64_t float_precision_bits(uint32_t),float_precision_internal(uint32_t);
extern uint64_t float_precision_loop(uint32_t,uint32_t,uint32_t);
extern uint64_t float_precision_pressure(uint64_t,uint64_t,uint64_t,uint64_t,uint64_t,uint64_t,uint64_t,float,float,float,float,float,float,float,float,float,float,uint32_t);
extern uint64_t float_precision_preserved(void);
extern int zbe_check_preserved(uint64_t (*)(void));
static unsigned long checks;
#define REQUIRE(x) do {++checks;if(!(x)){fprintf(stderr,"Float precision failure line %d check %lu\n",__LINE__,checks);abort();}} while(0)
static const struct row {uint32_t input;uint64_t expected;} cases[]={
''' + array + r'''
};
static uint64_t expected_d[10],expected_g[7];
static unsigned observed;
static uint64_t dbits(double value){uint64_t bits;memcpy(&bits,&value,8);return bits;}
static float from_bits(uint32_t bits){float value;memcpy(&value,&bits,4);return value;}
uint64_t float_precision_observe(double a,double b,double c,double d,double e,double f,double g,double h,double i,double j,uint64_t q,uint64_t r,uint64_t s,uint64_t t,uint64_t u,uint64_t v,uint64_t w) {
    const double ds[]={a,b,c,d,e,f,g,h,i,j};
    const uint64_t gs[]={q,r,s,t,u,v,w};
    for(unsigned k=0;k<10;k++) REQUIRE(dbits(ds[k])==expected_d[k]);
    for(unsigned k=0;k<7;k++) REQUIRE(gs[k]==expected_g[k]);
    ++observed;
    /* Force live widened values to survive a genuinely clobbering host call. */
    __asm__ volatile(
      "xorps %%xmm0,%%xmm0\n\txorps %%xmm1,%%xmm1\n\txorps %%xmm2,%%xmm2\n\txorps %%xmm3,%%xmm3\n\t"
      "xorps %%xmm4,%%xmm4\n\txorps %%xmm5,%%xmm5\n\txorps %%xmm6,%%xmm6\n\txorps %%xmm7,%%xmm7\n\t"
      "xorps %%xmm8,%%xmm8\n\txorps %%xmm9,%%xmm9\n\txorps %%xmm10,%%xmm10\n\txorps %%xmm11,%%xmm11\n\t"
      "xorps %%xmm12,%%xmm12\n\txorps %%xmm13,%%xmm13\n\txorps %%xmm14,%%xmm14\n\txorps %%xmm15,%%xmm15\n\t"
      : : : "rax","rcx","rdx","rsi","rdi","r8","r9","r10","r11",
      "xmm0","xmm1","xmm2","xmm3","xmm4","xmm5","xmm6","xmm7","xmm8","xmm9","xmm10","xmm11","xmm12","xmm13","xmm14","xmm15","memory","cc");
    return UINT64_C(0xdad0123456789abc);
}
int main(void) {
    const unsigned saved=_mm_getcsr();
    const size_t count=sizeof(cases)/sizeof(cases[0]);
    /* All exact widening rows in all four rounding modes. DAZ/FTZ disabled;
       exceptions masked. This does not claim status-flag or trap equivalence. */
    for(unsigned mode=0;mode<4;mode++) {
        _mm_setcsr((saved & ~0xe07fu)|0x1f80u|(mode<<13));
        for(size_t k=0;k<count;k++) {
            REQUIRE(float_precision_bits(cases[k].input)==cases[k].expected);
            REQUIRE(float_precision_internal(cases[k].input)==cases[k].expected);
        }
    }
    _mm_setcsr((saved & ~0xe07fu)|0x1f80u);
    const unsigned ns[]={0,1,2,3,10,31};
    for(size_t k=0;k<128;k++) {
        const struct row a=cases[(k*29)%count],b=cases[(k*71+1)%count];
        for(unsigned m=0;m<6;m++) REQUIRE(float_precision_loop(ns[m],a.input,b.input)==(ns[m]%2?b.expected:a.expected));
    }
    for(unsigned seed=0;seed<64;seed++) {
        float fs[10];
        for(unsigned k=0;k<10;k++) {
            const struct row row=cases[(seed*53+k*367)%count];
            fs[k]=from_bits(row.input);expected_d[k]=row.expected;
        }
        for(unsigned k=0;k<7;k++)expected_g[k]=(UINT64_C(0x8172635445362718)*(k+1))^((uint64_t)seed<<37);
        for(unsigned select=0;select<2;select++) {
            uint64_t expected=UINT64_C(0xdad0123456789abc)^expected_d[select?8:9];
            for(unsigned k=0;k<10;k++)expected^=expected_d[k];
            for(unsigned k=0;k<7;k++)expected^=expected_g[k];
            REQUIRE(float_precision_pressure(expected_g[0],expected_g[1],expected_g[2],expected_g[3],expected_g[4],expected_g[5],expected_g[6],fs[0],fs[1],fs[2],fs[3],fs[4],fs[5],fs[6],fs[7],fs[8],fs[9],select)==expected);
        }
    }
    REQUIRE(observed==128);
    const uint32_t nans[]={0x7fc00001u,0xffc12345u,0x7fffffffu,0xffffffffu,0x7f800001u,0xff800001u};
    for(unsigned k=0;k<6;k++) {
        uint64_t bits=float_precision_bits(nans[k]);
        REQUIRE((bits & UINT64_C(0x7ff0000000000000))==UINT64_C(0x7ff0000000000000) && (bits & UINT64_C(0xfffffffffffff))!=0);
    }
    REQUIRE(zbe_check_preserved(float_precision_preserved)==0);
    REQUIRE(float_precision_preserved()==UINT64_C(0xb6a0000000000000));
    _mm_setcsr(saved);
    if(checks!=32625) {fprintf(stderr,"Unexpected check count %lu\n",checks);return 3;}
    printf("%lu float precision exact/classification/phi/call/home checks passed\n",checks);
    return 0;
}
'''
    # Expected check count: 3693*8 + 128*6 + 128*(17+1) + 1+6+2.
    assert 3693*8 + 128*6 + 128*18 + 1+6+2 == 32625
    with tempfile.TemporaryDirectory(prefix='float_precision_') as directory:
        work = Path(directory)
        il, assembly, driver, binary = [work/name for name in ('input.ssa', 'output.s', 'driver.c', 'run')]
        il.write_text((root/'src/fixtures/float_precision_program.ssa').read_text())
        driver.write_text(source)
        run([args.compiler.resolve(), *flags, il, assembly])
        for link in ('-pie', '-no-pie'):
            run([args.cc, '-std=c11', '-O2', '-Wall', '-Wextra', '-Werror', '-fPIE', link, driver, assembly, root/'src/fixtures/check-preserved.s', '-o', binary])
            run([binary])
        print('2 float precision link modes passed (PIE/non-PIE)')


if __name__ == '__main__':
    main()
