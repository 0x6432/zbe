#!/usr/bin/env python3
"""Linux AMD64 extern/GOT aggregate boundary harness; not ABI certification.

Run only under the repository's shared verification lock and resource/CI
coordination policy. Each invocation exercises one compiler option combination.
Each source aggregate ends exactly at a readable page boundary followed by a
PROT_NONE page. The harness does not deliberately access the protected page.
"""
import argparse
import os
from pathlib import Path
import platform
import resource
import subprocess
import tempfile

from extern_got_record_smoke import ASM, IL, PROVIDER


MAIN = r'''#define _GNU_SOURCE
#include <stdint.h>
#include <stddef.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <unistd.h>

struct dd { double x,y; }; struct is { uint64_t x; double y; };
struct si { double x; uint64_t y; }; union u { struct si m; struct dd s; };
struct big { uint64_t x,y,z; };
_Static_assert(sizeof(struct dd)==16 && sizeof(struct is)==16 &&
 sizeof(struct si)==16 && sizeof(union u)==16 && sizeof(struct big)==24,
 "unexpected record sizes");
_Static_assert(offsetof(struct dd,y)==8 && offsetof(struct is,y)==8 &&
 offsetof(struct si,y)==8 && offsetof(struct big,y)==8 &&
 offsetof(struct big,z)==16, "unexpected record offsets");
extern struct dd call_dd(const struct dd *);
extern struct is call_is(const struct is *);
extern struct si call_si(const struct si *);
extern union u call_union(const union u *);
extern struct big call_pressure(const struct big *,const struct is *,uint64_t);
#define CHECK(c, code) do { if (!(c)) { fprintf(stderr,"assertion %d failed\n",code); return code; } } while (0)

enum { PREFIX = 16 };
struct guarded { unsigned char *mapping; void *value; size_t page; };
static struct guarded guard(const void *initial, size_t size, size_t alignment) {
 long page_long = sysconf(_SC_PAGESIZE);
 if (page_long <= 0 || (uintmax_t)page_long > SIZE_MAX/2) {
  fprintf(stderr,"invalid page size\n"); exit(90);
 }
 size_t page = (size_t)page_long;
 if (size > page || page - size < PREFIX) {
  fprintf(stderr,"record does not fit\n"); exit(90);
 }
 unsigned char *p = mmap(NULL, page*2, PROT_READ|PROT_WRITE,
                         MAP_PRIVATE|MAP_ANONYMOUS, -1, 0);
 if (p == MAP_FAILED) { perror("mmap"); exit(90); }
 if (mprotect(p+page, page, PROT_NONE) != 0) { perror("mprotect"); exit(90); }
 void *value = p+page-size;
 if ((uintptr_t)value % alignment != 0) {
  fprintf(stderr,"record boundary is not aligned\n"); exit(90);
 }
 memset(p+page-size-PREFIX, 0xa5, PREFIX);
 /* memcpy from the corresponding typed object establishes its effective type. */
 memcpy(value, initial, size);
 return (struct guarded){p,value,page};
}
static int prefix_intact(const struct guarded *g, size_t size) {
 const unsigned char *p = g->mapping+g->page-size-PREFIX;
 for (size_t i=0; i<PREFIX; ++i) if (p[i] != 0xa5) return 0;
 return 1;
}
int main(int argc, char **argv) {
 if (argc != 2 || (strcmp(argv[1],"normal") && strcmp(argv[1],"preload"))) return 90;
 unsigned base = !strcmp(argv[1],"normal") ? 10u : 200u;
 const struct dd dd0={1,2}; const struct is is0={17,3};
 const struct si si0={4,23}; const union u u0={.m={5,29}};
 const struct big big0={41,42,43};
 struct guarded dd=guard(&dd0,sizeof dd0,_Alignof(struct dd));
 struct guarded is=guard(&is0,sizeof is0,_Alignof(struct is));
 struct guarded si=guard(&si0,sizeof si0,_Alignof(struct si));
 struct guarded u=guard(&u0,sizeof u0,_Alignof(union u));
 struct guarded big=guard(&big0,sizeof big0,_Alignof(struct big));
 const struct dd *pd=dd.value; const struct is *pi=is.value;
 const struct si *ps=si.value; const union u *pu=u.value;
 const struct big *pb=big.value;
 struct dd rd=call_dd(pd);
 CHECK(rd.x==base+11.0 && rd.y==base+12.0,21);
 struct is ri=call_is(pi);
 CHECK(ri.x==base+21 && ri.y==base+22.0,22);
 struct si rs=call_si(ps);
 CHECK(rs.x==base+41.0 && rs.y==base+42,23);
 union u ru=call_union(pu);
 CHECK(ru.m.x==base+31.0 && ru.m.y==base+32,24);
 const uint64_t sizes[]={16,17,31,64,79};
 for (size_t i=0; i<sizeof sizes/sizeof sizes[0]; ++i) {
  struct big rb=call_pressure(pb,pi,sizes[i]);
  CHECK(rb.x==base+51 && rb.y==base+52 && rb.z==base+53,25);
 }
 CHECK(pd->x==1 && pd->y==2 && pi->x==17 && pi->y==3 &&
       ps->x==4 && ps->y==23 && pu->m.x==5 && pu->m.y==29 &&
       pb->x==41 && pb->y==42 && pb->z==43,26);
 CHECK(prefix_intact(&dd,sizeof dd0) && prefix_intact(&is,sizeof is0) &&
       prefix_intact(&si,sizeof si0) && prefix_intact(&u,sizeof u0) &&
       prefix_intact(&big,sizeof big0),27);
 struct guarded all[]={dd,is,si,u,big};
 for (size_t i=0; i<sizeof all/sizeof all[0]; ++i) {
  if (munmap(all[i].mapping, all[i].page*2) != 0) { perror("munmap"); return 90; }
 }
 return 0;
}
'''


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--compiler', type=Path, required=True)
    parser.add_argument('--cc', default='cc')
    for flag in ('fold-integers', 'reuse-stack-homes', 'callee-saved-homes'):
        parser.add_argument('--' + flag, action='store_true')
    args = parser.parse_args()
    if platform.system() != 'Linux' or platform.machine() not in ('x86_64', 'amd64'):
        raise SystemExit('Linux AMD64 required')
    resource.setrlimit(resource.RLIMIT_CORE, (0, 0))
    compiler = args.compiler.resolve(strict=True)
    flags = ['--' + f for f in ('fold-integers', 'reuse-stack-homes', 'callee-saved-homes')
             if getattr(args, f.replace('-', '_'))]
    with tempfile.TemporaryDirectory(prefix='zbe-got-record-guard-') as tmp:
        directory = Path(tmp)
        for name, text in (('input.ssa', IL), ('provider.c', PROVIDER),
                           ('provider.S', ASM), ('main.c', MAIN)):
            (directory / name).write_text(text)
        clean = {k: os.environ[k] for k in ('PATH', 'HOME', 'TMPDIR') if k in os.environ}
        clean['LC_ALL'] = 'C'

        def run(argv, env=None):
            proc = subprocess.run([str(x) for x in argv], cwd=directory,
                                  env=clean if env is None else env,
                                  capture_output=True, text=True, timeout=90)
            if proc.returncode != 0:
                raise RuntimeError(f'{argv!r}: exit {proc.returncode}; '
                                   f'stdout={proc.stdout!r} stderr={proc.stderr!r}')

        run([compiler, *flags, 'input.ssa', 'generated.s'])
        asm = (directory / 'generated.s').read_text()
        for sym in ('provider_dd', 'provider_is', 'provider_si', 'provider_union', 'provider_pressure'):
            if f'{sym}@GOTPCREL' not in asm:
                raise RuntimeError(f'missing dedicated extern GOT target {sym}')
        for base, bits, name in ((10, '0x4049800000000000', 'libprovider.so'),
                                 (200, '0x406e200000000000', 'liboverride.so')):
            run([args.cc, '-std=c11', '-O2', '-Wall', '-Wextra', '-Werror', '-fPIC',
                 '-shared', f'-DBASE={base}', f'-DRESULT_BITS={bits}',
                 f'-DRESULT_INTEGER={base+42}', 'provider.c', 'provider.S', '-o', name])
        run([args.cc, '-shared', '-fPIC', '-Wl,--no-relax', 'generated.s', '-L.',
             '-Wl,--no-as-needed', '-lprovider', '-Wl,-rpath,$ORIGIN', '-o', 'libsubject.so'])
        run([args.cc, '-std=c11', '-O2', '-Wall', '-Wextra', '-Werror', 'main.c',
             '-L.', '-Wl,--no-as-needed', '-lsubject', '-Wl,-rpath,$ORIGIN', '-o', 'check'])
        run(['./check', 'normal'])
        run(['./check', 'preload'], env=dict(clean, LD_PRELOAD=str(directory / 'liboverride.so')))
        print(f'Guard-page aggregate checks passed for normal and preload providers; '
              f'flags={flags!r}. Focused check only; not ABI certification.')


if __name__ == '__main__':
    main()
