#!/bin/sh
# usage: tools/corpus.sh FILE...  -- compare zig qbe vs C qbe on IL files
# for all targets. env: QBEC (C reference), QBEZ (zig build)
QBEC=${QBEC:-/data/qbe-c/qbe}
QBEZ=${QBEZ:-$(dirname "$0")/../zig-out/bin/qbe}
targets=${TARGETS:-"amd64_sysv amd64_apple amd64_win arm64 arm64_apple rv64"}
n=0; fail=0; skip=0
for f in "$@"; do
  for t in $targets; do
    n=$((n+1))
    "$QBEC" -t $t "$f" > /tmp/corp.c.s 2>/tmp/corp.c.err; rc=$?
    "$QBEZ" -t $t "$f" > /tmp/corp.z.s 2>/tmp/corp.z.err; rz=$?
    if [ $rc != $rz ] || ! cmp -s /tmp/corp.c.s /tmp/corp.z.s; then
      echo "DIFF $t $f ($rc/$rz)"; fail=$((fail+1))
    elif [ $rc != 0 ]; then skip=$((skip+1)); fi
  done
done
echo "corpus: $n runs, $fail differ, $skip both-failed"
