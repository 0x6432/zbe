#!/bin/sh
# Optimization robustness sweep: every target x -O1/-O2 over the test suite
# and the corpus. The optimized compiler must never crash or fail where the
# C reference succeeds (non-amd64 code cannot be executed here, so this is
# the guard against e.g. rewrites that break register allocation).
# Usage: optsweep.sh [files...]   (default: test/*.ssa + /data/corpus)
D=$(cd "$(dirname "$0")/.." && pwd)
Z=${ZQBE:-$D/zig-out/bin/qbe}
REF=${QBEREF:-/data/qbe-cfix/qbe}
unset QBE_COMPAT
[ $# -eq 0 ] && set -- $D/test/*.ssa $(ls /data/corpus/*.qbe /data/corpus/hare/*.ssa 2>/dev/null)
pass=0; fail=0
for t in amd64_sysv amd64_apple amd64_win arm64 arm64_apple rv64; do
  for f in "$@"; do
    $REF -t $t "$f" > /dev/null 2>&1 || continue
    for o in 1 2; do
      if $Z -t $t -O$o "$f" > /dev/null 2>/tmp/optsweep.err; then pass=$((pass+1))
      else fail=$((fail+1)); echo "FAIL: $t -O$o $f: $(head -c 200 /tmp/optsweep.err | head -1)"; fi
    done
  done
done
printf 'optsweep: %d passed, %d failed\n' $pass $fail
[ $fail -eq 0 ]
