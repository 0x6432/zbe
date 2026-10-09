#!/bin/sh
# jnz semantics (IL spec): only the low 32 bits of the argument are tested,
# even for a long. Run natively at every -O level, plus byte comparison with
# the C reference in compat mode. Regression test for BUGS.md #4.
D=$(cd "$(dirname "$0")/.." && pwd)
Z=${ZQBE:-$D/zig-out/bin/qbe}
REF=${QBEREF:-/data/qbe-cfix/qbe}
unset QBE_COMPAT
W=$(mktemp -d)
cat > $W/f.ssa <<'EOF'
export function w $jl(l %a) {
@start
	jnz %a, @T, @F
@T
	ret 1
@F
	ret 0
}
export function w $jw(w %a) {
@start
	jnz %a, @T, @F
@T
	ret 1
@F
	ret 0
}
export function w $jshl(l %a, l %n) {
@start
	%x =l shl %a, %n
	jnz %x, @T, @F
@T
	ret 1
@F
	ret 0
}
export function w $jphi(l %a, w %c) {
@start
	jnz %c, @A, @B
@A
	%y =l mul %a, 4294967296
	jmp @J
@B
	%z =l add %a, 0
	jmp @J
@J
	%p =l phi @A %y, @B %z
	jnz %p, @T, @F
@T
	ret 1
@F
	ret 0
}
EOF
cat > $W/m.c <<'EOF'
#include <stdint.h>
#include <stdio.h>
int jl(int64_t), jw(int32_t), jshl(int64_t, int64_t), jphi(int64_t, int32_t);
#define LO(v) ((uint32_t)(uint64_t)(v) != 0)
int main(void) {
  int64_t v[] = {0, 1, -1, 0x100000000ll, 0xaf25000000000000ll, (int64_t)0x8000000000000000ull,
                 0xffffffff00000000ll, 0x100000001ll, 0x80000000ll, 0x7fffffffll, -4294967296ll};
  int bad = 0;
  for (unsigned i = 0; i < sizeof v / sizeof *v; i++) {
    if (jl(v[i]) != LO(v[i])) { printf("jl %u\n", i); bad++; }
    if (jw((int32_t)v[i]) != LO(v[i])) { printf("jw %u\n", i); bad++; }
    for (int n = 0; n < 64; n += 7)
      if (jshl(v[i], n) != LO((uint64_t)v[i] << n)) { printf("jshl %u %d\n", i, n); bad++; }
    if (jphi(v[i], 1) != LO((uint64_t)v[i] * 4294967296ull)) { printf("jphi1 %u\n", i); bad++; }
    if (jphi(v[i], 0) != LO(v[i])) { printf("jphi0 %u\n", i); bad++; }
  }
  return bad != 0;
}
EOF
pass=0; fail=0
for o in 0 1 2; do
  if $Z ${QBET:+-t $QBET} -O$o $W/f.ssa > $W/f.s && ${CC:-gcc} -o $W/t $W/m.c $W/f.s && $RUN $W/t; then pass=$((pass+1))
  else fail=$((fail+1)); echo "FAIL: run -O$o"; fi
done
for t in amd64_sysv amd64_apple amd64_win arm64 arm64_apple rv64; do
  if [ -x "$REF" ]; then
    $REF -t $t $W/f.ssa > $W/a.s; QBE_COMPAT=1 $Z -t $t $W/f.ssa > $W/b.s
    if cmp -s $W/a.s $W/b.s; then pass=$((pass+1)); else fail=$((fail+1)); echo "FAIL: ref $t"; fi
  fi
  for o in 1 2; do
    if $Z -t $t -O$o $W/f.ssa > /dev/null; then pass=$((pass+1)); else fail=$((fail+1)); echo "FAIL: $t -O$o"; fi
  done
done
rm -rf $W
printf 'jnz: %d passed, %d failed\n' $pass $fail
[ $fail -eq 0 ]
