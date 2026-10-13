#!/bin/sh
# usage: tools/corpus.sh FILE...  -- compare zig qbe vs C qbe on IL files
# for all targets. env: QBEC (C reference), QBEZ (zig build)
QBEC=${QBEC:-${QBEREF:-/data/qbe-cfix/qbe}}
QBEZ=${QBEZ:-$(dirname "$0")/../zig-out/bin/qbe}
targets=${TARGETS:-"amd64_sysv amd64_apple amd64_win arm64 arm64_apple rv64"}
n=0; fail=0; skip=0
work=$(mktemp -d) || exit 1
trap 'rm -rf "$work"' EXIT
. "$(dirname "$0")/input-error-compat.sh"
for f in "$@"; do
  for t in $targets; do
    n=$((n+1))
    "$QBEC" -t $t "$f" > "$work/c.s" 2>"$work/c.err"; rc=$?
    "$QBEZ" -t $t "$f" > "$work/z.s" 2>"$work/z.err"; rz=$?
    # when both fail (abort), stdout holds an arbitrary unflushed prefix:
    # compare the diagnostics instead
    if input_error_matches "$rc" "$rz" "$work/c.err" "$work/z.err"; then
      skip=$((skip+1)); continue
    fi
    if [ $rc != 0 ] && [ $rc = $rz ]; then
      # C prints __FILE__ before "dying:", zig prints "qbe"
      sed -i 's/^[^ ]*: dying:/dying:/' "$work/c.err" "$work/z.err"
      grep -q "Assertion" "$work/c.err" && grep -q "panic" "$work/z.err" && { skip=$((skip+1)); continue; }
      cmp -s "$work/c.err" "$work/z.err" && { skip=$((skip+1)); continue; }
      echo "DIFF(stderr) $t $f ($rc/$rz)"; fail=$((fail+1)); continue
    fi
    if [ $rc != $rz ] || ! cmp -s "$work/c.s" "$work/z.s"; then
      echo "DIFF $t $f ($rc/$rz)"; fail=$((fail+1))
    elif [ $rc != 0 ]; then skip=$((skip+1)); fi
  done
done
echo "corpus: $n runs, $fail differ, $skip both-failed"
