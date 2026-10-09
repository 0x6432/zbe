#!/usr/bin/env python3
"""Stage 8c division tests: for many constant divisors generate QBE functions
for div/rem/udiv/urem (w and l), compile them with the optimizing Zig qbe at
every -O level, link with a C driver that checks each against C on ~200k
inputs per function (boundaries, multiples of the divisor +-1, random)."""
import os, random, subprocess, sys, tempfile

Z = os.environ.get('ZQBE') or os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'zig-out', 'bin', 'qbe')
rnd = random.Random(8)

w_div = [2**n for n in range(1, 32)] + [-(2**n) for n in range(0, 31)] + \
        [3, 5, 6, 7, 9, 10, 11, 12, 13, 25, 100, 641, 1000, 65535, 65537, 6700417,
         0x7fffffff, -3, -7, -1000] + [rnd.randrange(2, 2**31) for _ in range(25)]
l_div = [2**n for n in range(1, 64)] + [-(2**n) for n in range(0, 63)] + \
        [3, 7, 10, 1000, 2**32 + 1, -3] + [rnd.randrange(2, 2**63) for _ in range(10)]
uw_div = [1, 2, 3, 5, 6, 7, 9, 10, 11, 12, 13, 14, 15, 17, 19, 25, 60, 100, 255, 641,
          1000, 3600, 65535, 65537, 6700417, 0x7fffffff, 0x80000000, 0x80000001,
          0xfffffffe, 0xffffffff, 0xdeadbeef] + list(range(3, 300)) + \
         [rnd.randrange(3, 2**32) for _ in range(60)] + [rnd.randrange(3, 2**16) for _ in range(30)]
ul_div = [3, 7, 10, 1000, 2**32, 2**63, 2**64 - 1]

cases = []  # (name, cls, op, divisor)
for d in w_div:
    for op in ('div', 'rem'): cases.append(('w', op, d))
for d in l_div:
    for op in ('div', 'rem'): cases.append(('l', op, d))
for d in uw_div:
    for op in ('udiv', 'urem'): cases.append(('w', op, d))
for d in ul_div:
    for op in ('udiv', 'urem'): cases.append(('l', op, d))

ssa, decl, checks = [], [], []
for n, (k, op, d) in enumerate(cases):
    ssa.append(f'export function {k} $f{n}({k} %a) {{\n@start\n\t%x ={k} {op} %a, {d}\n\tret %x\n}}\n')
    sgn = op in ('div', 'rem')
    ct = ('int32_t' if sgn else 'uint32_t') if k == 'w' else ('int64_t' if sgn else 'uint64_t')
    cop = '/' if op in ('div', 'udiv') else '%'
    bits = 32 if k == 'w' else 64
    dv = d % (1 << bits)
    decl.append(f'{ct} f{n}({ct});')
    # avoid C UB: INT_MIN / -1
    guard = f'if (!({ct})({ct})~0 || 1) ' if False else ''
    lit = f'(({ct}){dv}ull)'
    if sgn:
        ub = f'(x == ({ct})((uint64_t)1 << {bits - 1}) && {lit} == -1)'
    else:
        ub = '0'
    checks.append(f'  {{ {ct} dd = {lit}; for (i = 0; i < NV; i++) {{ {ct} x = ({ct})v[i];'
                  f' if ({ub}) continue; if (f{n}(x) != ({ct})(x {cop} dd)) {{ printf("f{n} {k} {op} {d} x=%lld got %lld want %lld\\n",'
                  f' (long long)x, (long long)f{n}(x), (long long)(x {cop} dd)); return 1; }}'
                  f' if (dd && dd != ({ct})-1) for (int m = -1; m <= 1; m++) {{ {ct} y = ({ct})(v[i] % 100000) * dd + m;'
                  f' if ((x == y) || 0) continue; if (f{n}(y) != ({ct})(y {cop} dd)) {{ printf("f{n} y=%lld\\n", (long long)y); return 1; }} }} }} }}')

driver = '''#include <stdint.h>
#include <stdio.h>
#define NV 4000
%s
static uint64_t v[NV];
int main(void) {
  int i = 0; uint64_t s = 88172645463325252ull;
  uint64_t fix[] = {0, 1, 2, 3, 4, 5, 7, 8, 9, 15, 16, 17, 31, 32, 33, 63, 64, 65,
    0x7fffffffull, 0x80000000ull, 0x80000001ull, 0xfffffffeull, 0xffffffffull,
    0x100000000ull, 0x7fffffffffffffffull, 0x8000000000000000ull,
    0x8000000000000001ull, 0xfffffffffffffffeull, 0xffffffffffffffffull};
  for (; i < (int)(sizeof fix / sizeof *fix); i++) v[i] = fix[i];
  for (; i < NV; i++) { s ^= s << 13; s ^= s >> 7; s ^= s << 17;
    v[i] = (i & 3) == 0 ? s : (i & 3) == 1 ? (uint32_t)s : (i & 3) == 2 ? -(s & 0xffff) : (s & 0xff); }
%s
  return 0;
}
''' % ('\n'.join(decl), '\n'.join(checks))

W = tempfile.mkdtemp()
open(f'{W}/f.ssa', 'w').write(''.join(ssa))
open(f'{W}/m.c', 'w').write(driver)
ok = 0
for lvl in ('-O0', '-O1', '-O2'):
    env = dict(os.environ); env.pop('QBE_COMPAT', None)
    r = subprocess.run([Z, lvl, '-o', f'{W}/f.s', f'{W}/f.ssa'], env=env, capture_output=True, text=True)
    if r.returncode: print('qbe failed', lvl, r.stderr[:500]); sys.exit(1)
    r = subprocess.run(['gcc', '-O1', '-o', f'{W}/t', f'{W}/m.c', f'{W}/f.s'], capture_output=True, text=True)
    if r.returncode: print('cc failed', r.stderr[:2000]); sys.exit(1)
    r = subprocess.run([f'{W}/t'], capture_output=True, text=True)
    if r.returncode: print('FAIL', lvl, r.stdout[:500]); sys.exit(1)
    ok += 1
asm = open(f'{W}/f.s').read()
print(f'opt2: {len(cases)} division functions x 3 levels ok '
      f'(-O2 asm: {asm.count("idiv")} idiv, {asm.count("div") - asm.count("idiv")} div left)')
