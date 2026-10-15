#!/bin/sh
# Run every test/*.ssa through zbe (Debug build) under valgrind memcheck on
# all 6 targets and -O0/-O2. Any nonzero compiler/valgrind exit fails the check.
# Leaks are not reported: qbe frees per-function arenas wholesale.
# Usage: memcheck.sh [files...] (supply valid compiler inputs)
Z=${ZQBE:-$(cd "$(dirname "$0")/.." && pwd)/zig-out/bin/qbe}
cd "$(dirname "$0")/.." || exit 1
command -v valgrind >/dev/null 2>&1 || { echo 'memcheck: valgrind unavailable' >&2; exit 1; }
W=$(mktemp -d) || exit 1
trap 'rm -rf "$W"' EXIT HUP INT TERM
[ $# -gt 0 ] || set -- test/*.ssa
unset QBE_COMPAT
pass=0; fail=0
for f; do
  for t in amd64_sysv amd64_apple amd64_win arm64 arm64_apple rv64; do
    for o in 0 2; do
      valgrind -q --error-exitcode=99 --leak-check=no --track-origins=no \
        "$Z" -t "$t" -O"$o" "$f" > /dev/null 2> "$W/error"
      rc=$?
      if [ "$rc" -eq 0 ]; then pass=$((pass+1))
      else
        fail=$((fail+1)); echo "FAIL: $t -O$o $f (exit $rc)"
        head -30 "$W/error"
      fi
    done
  done
done
echo "memcheck: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
