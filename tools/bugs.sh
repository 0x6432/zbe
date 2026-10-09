#!/bin/sh
# Regression checks for the upstream bugs fixed in stage 7 (see BUGS.md).
# These check *properties* of the Zig output, independent of any reference.
Z=${ZQBE:-$(dirname "$0")/../zig-out/bin/qbe}
W=$(mktemp -d)
pass=0; fail=0
T=$(printf '\t')
ok() { pass=$((pass+1)); }
ko() { fail=$((fail+1)); echo "FAIL: $1"; }

# 1. a shift must not be used as the flag source of a jnz (count 0 keeps flags)
for t in amd64_sysv amd64_apple amd64_win; do
  for op in shr sar shl; do
    for k in w l; do
      cat > $W/s.ssa <<EOF
export function w \$t($k %a, w %b) {
@start
	%n =w add %b, 32
	%x =$k $op %a, %n
	jnz %x, @nz, @z
@nz
	ret 1
@z
	ret 0
}
EOF
      $Z -t $t $W/s.ssa > $W/s.s 2>$W/e || { ko "shiftflags $t $op$k: qbe failed"; continue; }
      # the instruction right after the shift must not be a conditional jump
      if awk '/^\t(shr|sar|shl|sal)/{s=1;next} s&&/^\tj(z|nz|e|ne) /{bad=1} {s=0} END{exit !bad}' $W/s.s
      then ko "shiftflags $t $op$k: jcc right after shift"; else ok; fi
      grep -Eq "^$T(test|cmp)" $W/s.s && ok || ko "shiftflags $t $op$k: no test/cmp"
    done
  done
done

# 2. constant shift counts >= width are masked (must assemble on x86)
for t in amd64_sysv amd64_apple amd64_win; do
  for spec in 'l shr 1048576 0' 'l shl 64 0' 'l sar 65 1' 'w shr 32 0' 'w shl 33 1' 'w sar 4294967295 31' 'l shr 63 63' 'w shl 31 31'; do
    set -- $spec
    cat > $W/c.ssa <<EOF
export function $1 \$f($1 %a) {
@start
	%x =$1 $2 %a, $3
	ret %x
}
EOF
    $Z -t $t $W/c.ssa > $W/c.s 2>$W/e || { ko "shiftimm $t $spec: qbe failed"; continue; }
    if grep -Eq "^$T(shr|sar|shl|sal)[lq] \\\$$4, " $W/c.s || [ "$4" = 0 ]; then ok
    else ko "shiftimm $t $spec: count not masked to $4"; cat $W/c.s; fi
    if grep -Eq '\$([0-9]{3,})' $W/c.s && grep -E "^$T(shr|sar|shl|sal)" $W/c.s | grep -Eq '\$[0-9]{3,}'
    then ko "shiftimm $t $spec: huge immediate"; else ok; fi
  done
  # count produced by constant folding (C: sub 3, 32 -> 4294967267)
  cat > $W/f.ssa <<'EOF'
export function l $g(l %a) {
@start
	%c =w sub 3, 32
	%x =l shr %a, %c
	ret %x
}
EOF
  $Z -t $t $W/f.ssa > $W/f.s 2>$W/e || { ko "shiftfold $t: qbe failed"; continue; }
  if grep -E "^$T(shr|sar|shl|sal)" $W/f.s | grep -Eq '\$[0-9]{3,}'
  then ko "shiftfold $t: huge immediate"; else ok; fi
done

# 3. igroup() sel fix is covered by the unit test "igroup: sel1 run"

# if an assembler is around, make sure the outputs actually assemble
if command -v as >/dev/null 2>&1; then
  for f in $W/c.s $W/f.s; do as -o $W/o.o $f 2>/dev/null && ok || ko "assemble $f"; done
fi

rm -rf $W
printf 'bugs: %d passed, %d failed\n' $pass $fail
[ $fail -eq 0 ]
