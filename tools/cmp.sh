#!/bin/sh
# usage: tools/cmp.sh TARGET  -- compare asm output of zig qbe vs C qbe
t=$1; fail=0; n=0
work=$(mktemp -d) || exit 1
trap 'rm -rf "$work"' EXIT
. "$(dirname "$0")/input-error-compat.sh"
for f in test/*.ssa; do
  n=$((n+1))
  ${QBEREF:-/data/qbe-cfix/qbe} -t $t $f > "$work/c.s" 2>"$work/c.err"; rc=$?
  ./zig-out/bin/qbe -t $t $f > "$work/z.s" 2>"$work/z.err"; rz=$?
  if input_error_matches "$rc" "$rz" "$work/c.err" "$work/z.err"; then continue; fi
  if [ $rc != $rz ] || ! cmp -s "$work/c.s" "$work/z.s"; then echo "DIFF $f ($rc/$rz)"; fail=$((fail+1)); fi
done
echo "$t: $fail/$n differ"
