#!/bin/sh
# usage: tools/dbgcmp.sh TARGET -- compare -d debug dumps (stderr) of zig qbe vs C qbe
t=$1; n=0; fail=0
for f in test/*.ssa; do
  n=$((n+1))
  ${QBEREF:-/data/qbe-cfix/qbe} -t $t -dPMNCGKAILSR $f >/dev/null 2>/tmp/c.err
  ./zig-out/bin/qbe -t $t -dPMNCGKAILSR $f >/dev/null 2>/tmp/z.err
  cmp -s /tmp/c.err /tmp/z.err || { echo "DIFF $f"; fail=$((fail+1)); }
done
echo "$t: $fail/$n debug dumps differ"
