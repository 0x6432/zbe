#!/usr/bin/env python3
"""Focused Linux AMD64 extern-target record smoke, not the full N06/N13/N15 ledger.

Run under the shared verification lock and resource/CI coordination policy.
One invocation tests one explicit compiler option combination.  The C and ASM
providers are independent of the compiler under test; exact integer-valued
doubles avoid tolerance or NaN/unspecified-padding oracles.
"""
import argparse
import os
from pathlib import Path
import platform
import resource
import subprocess
import tempfile

IL = '''type :DD = { d 2 }
type :IS = { l, d }
type :SI = { d, l }
type :U = { { d, l } { d 2 } }
type :Big = { l 3 }
export function :DD $call_dd(l %p) {
@entry
%r =:DD call extern $provider_dd(:DD %p)
ret %r
}
export function :IS $call_is(l %p) {
@entry
%r =:IS call extern $provider_is(:IS %p)
ret %r
}
export function :SI $call_si(l %p) {
@entry
%r =:SI call extern $provider_si(:SI %p)
ret %r
}
export function :U $call_union(l %p) {
@entry
%r =:U call extern $provider_union(:U %p)
ret %r
}
export function :Big $call_pressure(l %big, l %mix, l %size) {
@entry
%space =l alloc16 %size
storel 123456, %space
%r =:Big call extern $provider_pressure(l 1, l 2, l 3, l 4, l 5, l 6, l 7, d d_1, d d_2, d d_3, d d_4, d d_5, d d_6, d d_7, d d_8, d d_9, :Big %big, :IS %mix)
%v =l loadl %space
%ok =w ceql %v, 123456
jnz %ok, @good, @bad
@good
ret %r
@bad
ret %big
}
'''
PROVIDER = r'''#include <stdint.h>
#include <stddef.h>
struct dd { double x,y; };
struct is { uint64_t x; double y; };
struct si { double x; uint64_t y; };
union u { struct si m; struct dd s; };
struct big { uint64_t x,y,z; };
_Static_assert(sizeof(struct dd)==16 && sizeof(struct is)==16 && sizeof(struct si)==16 && sizeof(union u)==16 && sizeof(struct big)==24, "layout");
_Static_assert(offsetof(struct is,y)==8 && offsetof(struct si,y)==8, "offsets");
struct dd provider_dd(struct dd v) {
 if(v.x!=1.0 || v.y!=2.0) return (struct dd){-1,-2};
 return (struct dd){BASE+11.0, BASE+12.0};
}
struct is provider_is(struct is v) {
 if(v.x!=17 || v.y!=3.0) return (struct is){0, -3};
 return (struct is){BASE+21, BASE+22.0};
}
union u provider_union(union u v) {
 if(v.m.x!=5.0 || v.m.y!=29) return (union u){.m={-5,0}};
 return (union u){.m={BASE+31.0, BASE+32}};
}
struct big provider_pressure(uint64_t a,uint64_t b,uint64_t c,uint64_t d,uint64_t e,uint64_t f,uint64_t g,
 double h,double i,double j,double k,double l,double m,double n,double o,double p, struct big q,struct is r) {
 if(a!=1 || b!=2 || c!=3 || d!=4 || e!=5 || f!=6 || g!=7 ||
    h!=1 || i!=2 || j!=3 || k!=4 || l!=5 || m!=6 || n!=7 || o!=8 || p!=9 ||
    q.x!=41 || q.y!=42 || q.z!=43 || r.x!=17 || r.y!=3) return (struct big){0,0,0};
 return (struct big){BASE+51, BASE+52, BASE+53};
}
'''
# SysV :SI argument and result: first lane xmm0, second lane rdi/rax.
# No stack access or callee-saved register clobber; both lanes are checked.
ASM = r''' .text
.globl provider_si
.type provider_si,@function
provider_si:
 movabsq $0x4010000000000000, %r10
 movq %xmm0, %r11
 cmpq %r10, %r11
 jne .Lbad
 cmpq $23, %rdi
 jne .Lbad
 movabsq $RESULT_BITS, %r10
 movq %r10, %xmm0
 movq $RESULT_INTEGER, %rax
 ret
.Lbad:
 pxor %xmm0, %xmm0
 xorl %eax, %eax
 ret
.size provider_si,.-provider_si
.section .note.GNU-stack,"",@progbits
'''
MAIN = r'''#include <stdint.h>
#include <stdlib.h>
#include <stdio.h>
struct dd { double x,y; }; struct is { uint64_t x; double y; };
struct si { double x; uint64_t y; }; union u { struct si m; struct dd s; };
struct big { uint64_t x,y,z; };
extern struct dd call_dd(const struct dd *);
extern struct is call_is(const struct is *);
extern struct si call_si(const struct si *);
extern union u call_union(const union u *);
extern struct big call_pressure(const struct big *,const struct is *,uint64_t);
#define CHECK(c, code) do { if (!(c)) { fprintf(stderr,"assertion %d failed\n",code); return code; } } while(0)
int main(int argc,char **argv) {
 if (argc!=2) return 90;
 unsigned base=(unsigned)strtoul(argv[1],0,10);
 struct { uint64_t pre; struct dd value; uint64_t post; } dd={101,{1,2},102};
 struct { uint64_t pre; struct is value; uint64_t post; } is={103,{17,3},104};
 struct { uint64_t pre; struct si value; uint64_t post; } si={105,{4,23},106};
 struct { uint64_t pre; union u value; uint64_t post; } u={107,{.m={5,29}},108};
 struct { uint64_t pre; struct big value; uint64_t post; } big={109,{41,42,43},110};
 struct dd rd=call_dd(&dd.value);
 CHECK(rd.x==base+11.0 && rd.y==base+12.0,21);
 struct is ri=call_is(&is.value);
 CHECK(ri.x==base+21 && ri.y==base+22.0,22);
 struct si rs=call_si(&si.value);
 CHECK(rs.x==base+41.0 && rs.y==base+42,23);
 union u ru=call_union(&u.value);
 CHECK(ru.m.x==base+31.0 && ru.m.y==base+32,24);
 const uint64_t sizes[]={16,17,31,64,79};
 for (unsigned index=0;index<sizeof sizes/sizeof sizes[0];++index) {
  struct big rb=call_pressure(&big.value,&is.value,sizes[index]);
  CHECK(rb.x==base+51 && rb.y==base+52 && rb.z==base+53,25);
 }
 CHECK(dd.pre==101 && dd.post==102 && dd.value.x==1 && dd.value.y==2 &&
       is.pre==103 && is.post==104 && is.value.x==17 && is.value.y==3 &&
       si.pre==105 && si.post==106 && si.value.x==4 && si.value.y==23 &&
       u.pre==107 && u.post==108 && u.value.m.x==5 && u.value.m.y==29 &&
       big.pre==109 && big.post==110 && big.value.x==41 && big.value.y==42 && big.value.z==43,26);
 return 0;
}
'''


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--compiler', type=Path, required=True)
    p.add_argument('--cc', default='cc')
    for flag in ('fold-integers', 'reuse-stack-homes', 'callee-saved-homes'):
        p.add_argument('--'+flag, action='store_true')
    a = p.parse_args()
    if platform.system() != 'Linux' or platform.machine() not in ('x86_64', 'amd64'):
        raise SystemExit('Linux AMD64 required')
    resource.setrlimit(resource.RLIMIT_CORE, (0, 0))
    compiler = a.compiler.resolve(strict=True)
    flags = ['--'+f for f in ('fold-integers', 'reuse-stack-homes', 'callee-saved-homes') if getattr(a, f.replace('-', '_'))]
    with tempfile.TemporaryDirectory(prefix='zbe-got-record-') as tmp:
        d = Path(tmp)
        for name, text in (('input.ssa',IL), ('provider.c',PROVIDER), ('provider.S',ASM), ('main.c',MAIN)):
            (d/name).write_text(text)
        def run(argv, env=None, expected=0):
            proc = subprocess.run([str(x) for x in argv], cwd=d, env=env, capture_output=True, text=True, timeout=90)
            if proc.returncode != expected:
                raise RuntimeError(f'{argv!r}: expected {expected}, got {proc.returncode}; stdout={proc.stdout!r} stderr={proc.stderr!r}')
            return proc.stdout
        run([compiler, *flags, 'input.ssa', 'generated.s'])
        asm = (d/'generated.s').read_text()
        for sym in ('provider_dd','provider_is','provider_si','provider_union','provider_pressure'):
            if f'{sym}@GOTPCREL' not in asm:
                raise RuntimeError(f'missing dedicated extern GOT target {sym}')
        # Assembly constants correspond to exact 51.0 and 241.0; both normal doubles.
        for base, bits, name in ((10,'0x4049800000000000','libprovider.so'), (200,'0x406e200000000000','liboverride.so')):
            run([a.cc,'-std=c11','-O2','-Wall','-Wextra','-Werror','-fPIC','-shared',f'-DBASE={base}',f'-DRESULT_BITS={bits}',f'-DRESULT_INTEGER={base+42}','provider.c','provider.S','-o',name])
        def link_subject(source):
            run([a.cc,'-shared','-fPIC','-Wl,--no-relax',source,'-L.','-Wl,--no-as-needed','-lprovider','-Wl,-rpath,$ORIGIN','-o','libsubject.so'])
        link_subject('generated.s')
        run([a.cc,'-std=c11','-O2','-Wall','-Wextra','-Werror','main.c','-L.','-Wl,--no-as-needed','-lsubject','-Wl,-rpath,$ORIGIN','-o','check'])
        clean = {k:v for k,v in os.environ.items() if k not in ('LD_PRELOAD','LD_LIBRARY_PATH','LD_AUDIT')}
        run(['./check','10'],env=clean)
        run(['./check','200'],env=dict(clean,LD_PRELOAD=str(d/'liboverride.so')))
        # Corrupt only the first SSE result lane *after* the real call, so the
        # target and argument ABI stay valid. Require the specific DD assertion.
        start = asm.index('call_dd:\n')
        end = asm.index('.size call_dd,', start)
        body = asm[start:end]
        needle = '\tcall *%r11\n'
        if body.count(needle) != 1:
            raise RuntimeError('DD result-lane control did not match exactly once')
        mutated = asm[:start] + body.replace(needle, needle+'\tpxor %xmm0, %xmm0\n') + asm[end:]
        (d/'mutant.s').write_text(mutated)
        link_subject('mutant.s')
        run(['./check','10'],env=clean,expected=21)
        print(f'GOT record smoke passed provider and preload; SSE result-lane control rejected at assertion 21; flags={flags!r}')

if __name__ == '__main__':
    main()
