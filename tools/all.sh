#!/bin/sh
# run every regression check against the C reference; prints a summary
cd "$(dirname "$0")/.."
zig build || { echo "BUILD FAILED"; exit 1; }
# behaviour with all optimizations (programs are compiled and run)
bin=$PWD/zig-out/bin/qbe sh tools/test.sh all 2>&1 | tail -1 | sed 's/^/opt: /'
# byte-for-byte comparison with the (bug-fixed) C reference: compat mode
export QBE_COMPAT=1
bin=$PWD/zig-out/bin/qbe sh tools/test.sh all 2>&1 | tail -1
for t in amd64_sysv amd64_apple amd64_win arm64 arm64_apple rv64; do
  printf '%s | %s\n' "$(sh tools/cmp.sh $t 2>/dev/null | tail -1)" "$(sh tools/dbgcmp.sh $t 2>/dev/null | tail -1)"
done
zig build test >/dev/null 2>&1 && echo "unit: ok" || echo "unit: FAILED"
sh tools/edge.sh 2>&1 | tail -1
sh tools/bugs.sh 2>&1 | tail -1
( unset QBE_COMPAT; sh tools/opt.sh 2>&1 | tail -1 )
( unset QBE_COMPAT; timeout 200 python3 tools/opt2.py 2>&1 | tail -1 )
( unset QBE_COMPAT; timeout 300 sh tools/optsweep.sh test/*.ssa 2>&1 | tail -1 )
( unset QBE_COMPAT; timeout 200 sh tools/lib.sh 2>/dev/null | tail -1 )
( unset QBE_COMPAT; sh tools/cli.sh 2>&1 | tail -1 )
sh tools/corpus.sh /data/corpus/*.qbe /data/corpus/hare/*.ssa 2>/dev/null | tail -3
# behaviour fuzzing with all optimizations (native amd64 execution)
( unset QBE_COMPAT QBEREF; timeout 200 python3 tests/irfuzz.py -n 15 -s 9000 -k 20 2>&1 | tail -1 | sed 's/^/opt: /' )
if [ -n "$FUZZ" ]; then
  QBEREF=${QBEREF:-/data/qbe-cfix/qbe} python3 tests/abifuzz.py -n 15 -s 1000 -k 60 2>&1 | tail -1
  QBEREF=${QBEREF:-/data/qbe-cfix/qbe} python3 tests/irfuzz.py -n 15 -s 5000 -k 100 2>&1 | tail -1
fi
