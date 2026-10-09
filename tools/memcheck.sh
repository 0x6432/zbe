#!/bin/sh
# Run every test/*.ssa through zbe (Debug build) under valgrind memcheck on
# all 6 targets and -O0/-O2. Fails on any invalid read/write/uninitialised
# use. Leaks are not reported: qbe frees per-function arenas wholesale.
# Usage: memcheck.sh [files...]
Z=${ZQBE:-$(cd "$(dirname "$0")/.." && pwd)/zig-out/bin/qbe}
cd "$(dirname "$0")/.."
[ $# -gt 0 ] || set -- test/*.ssa
unset QBE_COMPAT
pass=0; fail=0
for f; do
  for t in amd64_sysv amd64_win arm64 arm64_apple rv64; do
    for o in 0 2; do
      valgrind -q --error-exitcode=99 --leak-check=no --track-origins=no \
        $Z -t $t -O$o "$f" > /dev/null 2> /tmp/memcheck.err
      if [ $? -eq 99 ]; then fail=$((fail+1)); echo "FAIL: $t -O$o $f"; head -30 /tmp/memcheck.err
      else pass=$((pass+1)); fi
    done
  done
done
echo "memcheck: $pass passed, $fail failed"
[ $fail -eq 0 ]
