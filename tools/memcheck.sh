#!/bin/sh
# Run every test/*.ssa through zbe (Debug build) under valgrind memcheck on
# all 6 targets and -O0/-O2. Memory errors and unexpected compiler exits fail.
# Documented input rejections must match the patched C reference exactly.
# Leaks are not reported: qbe frees per-function arenas wholesale.
# Usage: memcheck.sh [files...]
Z=${ZQBE:-$(cd "$(dirname "$0")/.." && pwd)/zig-out/bin/qbe}
R=${QBEREF:-/data/qbe-cfix/qbe}
cd "$(dirname "$0")/.." || exit 1
command -v valgrind >/dev/null 2>&1 || { echo 'memcheck: valgrind unavailable' >&2; exit 1; }
[ -f "$R" ] && [ -x "$R" ] || { echo 'memcheck: executable patched C reference required (QBEREF)' >&2; exit 1; }
. ./tools/input-error-compat.sh
W=$(mktemp -d) || exit 1
trap 'rm -rf "$W"' EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM
[ $# -gt 0 ] || set -- test/*.ssa
unset QBE_COMPAT
pass=0; fail=0; rejected=0
for f; do
  for t in amd64_sysv amd64_apple amd64_win arm64 arm64_apple rv64; do
    for o in 0 2; do
      # Separate Valgrind diagnostics from compiler stderr so neither can hide
      # an error in the other. Require a completed, zero-error memory scan even
      # when the compiler correctly rejects an unsupported target/input pair.
      : > "$W/valgrind"; : > "$W/reference-error"
      LC_ALL=C valgrind --error-exitcode=99 --leak-check=no --track-origins=no \
        --log-file="$W/valgrind" "$Z" -t "$t" -O"$o" "$f" \
        > /dev/null 2> "$W/error"
      rc=$?
      ok=0
      if [ "$rc" -ne 99 ] &&
         [ "$(grep -c 'ERROR SUMMARY:' "$W/valgrind")" = 1 ] &&
         [ "$(tail -c 1 "$W/valgrind" | wc -l)" -eq 1 ] &&
         grep -Eq '^==[0-9]+== ERROR SUMMARY: 0 errors from 0 contexts [(]suppressed: [0-9,]+ from [0-9,]+[)]$' "$W/valgrind" &&
         ! grep -Eiq "valgrind:|vex:|the 'impossible' happened|Process terminating with default action|fatal signal" "$W/valgrind"; then
        if [ "$rc" -eq 0 ]; then ok=1
        elif [ "$rc" -eq 1 ]; then
          "$R" -t "$t" "$f" > /dev/null 2> "$W/reference-error"
          ref_rc=$?
          if input_error_matches "$ref_rc" "$rc" "$W/reference-error" "$W/error"; then
            ok=1; rejected=$((rejected+1))
          fi
        fi
      fi
      if [ "$ok" -eq 1 ]; then
        pass=$((pass+1))
        if grep -Eq 'Serious error when reading debug info|DWARF2 reader:|unhandled DW_FORM' "$W/valgrind"; then
          echo "WARN: $t -O$o $f: Valgrind debug info degraded; zero-error memory scan completed, source locations may be unavailable"
        fi
      else
        fail=$((fail+1)); echo "FAIL: $t -O$o $f (exit $rc)"
        head -30 "$W/error"
        head -30 "$W/valgrind"
        head -30 "$W/reference-error"
      fi
    done
  done
done
echo "memcheck: $pass passed, $fail failed ($rejected reference-confirmed rejections)"
[ "$fail" -eq 0 ]
