#!/bin/sh
# Native LP64 benchmark inputs must be valid C before their timings are useful.
# A sanitizer failure is a failing check, never a timing or a skipped fixture.
set -eu
cd "$(dirname "$0")/.."
W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT HUP INT TERM
pass=0
for source in bench/*.c; do
  "${CC:-cc}" -std=c99 -O1 -fsanitize=undefined \
    -fno-sanitize-recover=undefined "$source" -o "$W/program"
  "$W/program" > /dev/null
  pass=$((pass+1))
done
echo "benchmark fixtures: $pass passed, 0 failed"