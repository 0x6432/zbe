#!/bin/sh
# run every regression check against the C reference; prints a summary
cd "$(dirname "$0")/.."
bin=$PWD/zig-out/bin/qbe sh tools/test.sh all 2>&1 | tail -1
for t in amd64_sysv amd64_apple amd64_win arm64 arm64_apple rv64; do
  printf '%s | %s\n' "$(sh tools/cmp.sh $t 2>/dev/null | tail -1)" "$(sh tools/dbgcmp.sh $t 2>/dev/null | tail -1)"
done
sh tools/corpus.sh /data/corpus/*.qbe /data/corpus/hare/*.ssa 2>/dev/null | tail -3
if [ -n "$FUZZ" ]; then
  QBEREF=/data/qbe-c/qbe python3 tests/abifuzz.py -n 15 -s 1000 -k 60 2>&1 | tail -1
  QBEREF=/data/qbe-c/qbe python3 tests/irfuzz.py -n 15 -s 5000 -k 100 2>&1 | tail -1
fi
