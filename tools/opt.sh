#!/bin/sh
# Stage 8 optimization tests: every case is compiled with the optimizing Zig
# qbe, linked with a C driver and RUN natively (amd64), and the result is
# checked against C semantics; some cases also check the asm shape.
Z=${ZQBE:-$(cd "$(dirname "$0")/.." && pwd)/zig-out/bin/qbe}
unset QBE_COMPAT
W=$(mktemp -d)
pass=0; fail=0
T=$(printf '\t')

# case NAME K OP CONST  -- builds  K f(K a) { return a OP CONST }
# and compares with the same expression evaluated by gcc
expr_case() {
  name=$1 k=$2 op=$3 c=$4 cop=$5
  if [ $k = w ]; then ct=uint32_t; else ct=uint64_t; fi
  cat > $W/f.ssa <<EOF
export function $k \$f($k %a) {
@start
	%x =$k $op %a, $c
	ret %x
}
EOF
  cat > $W/m.c <<EOF
#include <stdint.h>
#include <stdio.h>
$ct f($ct);
static $ct ref($ct a) { return $cop; }
int main(void) {
  $ct v[] = {0, 1, 2, 3, 7, 255, 0x80000000u, 0xffffffffu, ($ct)-1, ($ct)-2,
             ($ct)0x8000000000000000ull, ($ct)0x123456789abcdefull};
  for (unsigned i = 0; i < sizeof v / sizeof *v; i++)
    if (f(v[i]) != ref(v[i])) { printf("bad %u\n", i); return 1; }
  return 0;
}
EOF
  if $Z $W/f.ssa > $W/f.s 2>$W/e && gcc -o $W/t $W/m.c $W/f.s 2>>$W/e && $W/t >$W/o 2>&1
  then pass=$((pass+1)); else fail=$((fail+1)); echo "FAIL: $name"; cat $W/e $W/o; fi
}

for k in w l; do
  if [ $k = w ]; then M=31; else M=63; fi
  expr_case mul0_$k   $k mul 0  'a*0'
  expr_case mul1_$k   $k mul 1  'a*1'
  expr_case mul2_$k   $k mul 2  'a*2'
  expr_case mul8_$k   $k mul 8  'a*8'
  expr_case mul3_$k   $k mul 3  'a*3'
  expr_case mulm1_$k  $k mul -1 "a*($ct)-1"
  expr_case mulhi_$k  $k mul $((1<<M)) "a*(($ct)1<<$M)"
  expr_case add0_$k   $k add 0  'a+0'
  expr_case sub0_$k   $k sub 0  'a-0'
  expr_case or0_$k    $k or 0   'a|0'
  expr_case xor0_$k   $k xor 0  'a^0'
  expr_case and0_$k   $k and 0  'a&0'
  expr_case andm1_$k  $k and -1 "a&($ct)-1"
  expr_case andff_$k  $k and 4294967295 'a&0xffffffffu'
  expr_case div1_$k   $k div 1  'a'
  expr_case udiv1_$k  $k udiv 1 'a/1'
  expr_case shl0_$k   $k shl 0  'a'
  expr_case shr0_$k   $k shr 0  'a'
  expr_case sar0_$k   $k sar 0  'a'
  # counts are taken modulo the width (QBE/x86 semantics)
  expr_case shlW_$k   $k shl $((M+1)) 'a'
  expr_case shrW1_$k  $k shr $((M+2)) 'a>>1'
done

# asm shape: the identities really disappear / become shifts
shape() {
  printf 'export function l $f(l %%a) {\n@start\n\t%%x =l %s %%a, %s\n\tret %%x\n}\n' "$2" "$3" > $W/s.ssa
  $Z $W/s.ssa > $W/s.s
  if grep -Eq "$4" $W/s.s; then pass=$((pass+1)); else fail=$((fail+1)); echo "FAIL: shape $1"; cat $W/s.s; fi
}
shape mul8_is_shl mul 8 "^${T}shlq \\\$3,"
shape add0_gone add 0 "^${T}movq %rdi, %rax\$"
if ! grep -q imul $W/s.s; then pass=$((pass+1)); else fail=$((fail+1)); echo "FAIL: imul left"; fi

# QBE_COMPAT=1 keeps the upstream output
printf 'export function l $f(l %%a) {\n@start\n\t%%x =l mul %%a, 8\n\tret %%x\n}\n' > $W/c.ssa
if QBE_COMPAT=1 $Z $W/c.ssa | grep -q imul; then pass=$((pass+1)); else fail=$((fail+1)); echo "FAIL: compat"; fi

rm -rf $W
printf 'opt: %d passed, %d failed\n' $pass $fail
[ $fail -eq 0 ]
