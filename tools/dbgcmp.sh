#!/bin/sh
# usage: tools/dbgcmp.sh TARGET -- compare -d debug dumps (stderr) of zig qbe vs C qbe
t=$1; n=0; fail=0
work=$(mktemp -d) || exit 1
trap 'rm -rf "$work"' EXIT
for f in test/*.ssa; do
  n=$((n+1))
  ${QBEREF:-/data/qbe-cfix/qbe} -t $t -dPMNCGKAILSR $f >/dev/null 2>"$work/c.err"
  ./zig-out/bin/qbe -t $t -dPMNCGKAILSR $f >/dev/null 2>"$work/z.err"
  cmp -s "$work/c.err" "$work/z.err" || { echo "DIFF $f"; fail=$((fail+1)); }
done
echo "$t: $fail/$n debug dumps differ"
