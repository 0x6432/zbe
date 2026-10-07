#!/bin/sh
# usage: tools/cmp.sh TARGET  -- compare asm output of zig qbe vs C qbe
t=$1; fail=0; n=0
for f in test/*.ssa; do
  n=$((n+1))
  /data/qbe-c/qbe -t $t $f > /tmp/c.s 2>/tmp/c.err; rc=$?
  ./zig-out/bin/qbe -t $t $f > /tmp/z.s 2>/tmp/z.err; rz=$?
  if [ $rc != $rz ] || ! cmp -s /tmp/c.s /tmp/z.s; then echo "DIFF $f ($rc/$rz)"; fail=$((fail+1)); fi
done
echo "$t: $fail/$n differ"
