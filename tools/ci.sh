#!/bin/sh
# CI driver. Usage: ci.sh <suite> [target]
#   core          everything on x86_64 linux (compat cmp, opt behaviour, fuzzers, ...)
#   native        behaviour + oracle tests on the host (linux arm64, macOS)
#   cross <tgt>   behaviour via cross gcc + qemu-user (arm64, rv64) or wine (amd64_win)
#   corpus DIR    compat comparison of a generated IL corpus vs the C reference
# Env: QBEREF (C reference qbe), ZQBE. Exits 1 if any check fails; writes a
# Markdown table to $GITHUB_STEP_SUMMARY when set.
cd "$(dirname "$0")/.."
D=$PWD
export ZQBE=${ZQBE:-$D/zig-out/bin/qbe}
export QBEREF=${QBEREF:-/data/qbe-cfix/qbe}
unset QBE_COMPAT
fail=0
SUM=$(mktemp)
printf '| check | result | summary |\n|---|---|---|\n' > $SUM

# chk NAME PATTERN cmd...   (passes if exit 0 and output matches PATTERN)
chk() {
  name=$1; pat=$2; shift 2
  out=$("$@" 2>&1); rc=$?
  last=$(printf '%s\n' "$out" | grep -v '^\s*$' | tail -1)
  if [ $rc -eq 0 ] && printf '%s\n' "$out" | grep -Eq "$pat"; then st=PASS
  else st=FAIL; fail=$((fail+1)); echo "::group::$name output (rc=$rc)"; printf '%s\n' "$out" | tail -80; echo "::endgroup::"
  fi
  echo "[$st] $name: $last"
  printf '| %s | %s | %s |\n' "$name" "$st" "$(printf '%s' "$last" | tr '|' '/')" >> $SUM
}
C() { env QBE_COMPAT=1 "$@"; }
OK0='(, 0 failed|0 failures| 0/[0-9]+ (debug dumps )?differ| 0 differ|iterations ok|All is fine!|ok)'

suite=$1; shift
case "$suite" in
core)
  chk unit 'All [0-9]+ tests passed|^$|.' zig build test
  chk "behaviour -O2 (test.sh)" 'All is fine!' env bin=$ZQBE sh tools/test.sh all
  chk "behaviour compat (test.sh)" 'All is fine!' C env bin=$ZQBE sh tools/test.sh all
  for t in amd64_sysv amd64_apple amd64_win arm64 arm64_apple rv64; do
    chk "compat asm $t" ' 0/[0-9]+ differ' C sh tools/cmp.sh $t
    chk "compat debug $t" ' 0/[0-9]+ debug dumps differ' C sh tools/dbgcmp.sh $t
  done
  chk edge ', 0 failed' C sh tools/edge.sh
  chk bugs ', 0 failed' C sh tools/bugs.sh
  chk opt ', 0 failed' sh tools/opt.sh
  chk opt2 'ok' python3 tools/opt2.py
  chk optsweep ', 0 failed' sh tools/optsweep.sh test/*.ssa
  chk lib ', 0 failed' sh tools/lib.sh
  chk cli ', 0 failed' sh tools/cli.sh
  chk jnz ', 0 failed' sh tools/jnz.sh
  chk opttable '0 failures' python3 tests/opttable.py
  chk optfuzz 'iterations ok' python3 tests/optfuzz.py -n 20 -s 1 -k 40
  chk "irfuzz -O2" 'iterations ok' env -u QBEREF python3 tests/irfuzz.py -n 15 -s 9000 -k 60
  chk "irfuzz compat" 'iterations ok' python3 tests/irfuzz.py -n 15 -s 5000 -k 60
  chk abifuzz 'iterations ok' python3 tests/abifuzz.py -n 15 -s 1000 -k 60
  chk mutation 'mutate: [0-9]+ killed, 0 survived' python3 tools/mutate.py
  chk "zig package" 'amd64_sysv: [0-9]+ bytes' sh -c 'cd tests/pkg && zig build && ./zig-out/bin/cons'
  ;;
native)
  chk unit '.' zig build test
  chk "behaviour -O2 (test.sh)" 'All is fine!' env bin=$ZQBE sh tools/test.sh all
  chk "behaviour compat (test.sh)" 'All is fine!' C env bin=$ZQBE sh tools/test.sh all
  chk "compat asm vs C (default target)" ' 0/[0-9]+ differ' C sh tools/cmp.sh "$($ZQBE -t?)"
  chk jnz ', 0 failed' sh tools/jnz.sh
  chk opttable '0 failures' python3 tests/opttable.py
  chk optfuzz 'iterations ok' python3 tests/optfuzz.py -n 20 -s 1 -k 20
  chk lib ', 0 failed' sh tools/lib.sh
  chk cli ', 0 failed' sh tools/cli.sh
  chk "zig package" 'bytes' sh -c 'cd tests/pkg && zig build && ./zig-out/bin/cons'
  ;;
cross)
  t=$1
  case $t in
  arm64) export CC="aarch64-linux-gnu-gcc -static" RUN=qemu-aarch64 QBET=arm64 ;;
  rv64) export CC="riscv64-linux-gnu-gcc -static" RUN=qemu-riscv64 QBET=rv64 ;;
  amd64_win) export CC="x86_64-w64-mingw32-gcc -static" RUN=wine QBET=amd64_win WINEDEBUG=-all ;;
  esac
  if [ $t != amd64_win ]; then
    chk "behaviour -O2 $t (test.sh)" 'All is fine!' env bin=$ZQBE sh tools/test.sh $t all
    chk "behaviour compat $t (test.sh)" 'All is fine!' C env bin=$ZQBE sh tools/test.sh $t all
  fi
  chk "jnz $t" ', 0 failed' sh tools/jnz.sh
  chk "opttable $t" '0 failures' python3 tests/opttable.py
  chk "optfuzz $t" 'iterations ok' python3 tests/optfuzz.py -n 20 -s 1 -k 10
  ;;
corpus)
  dir=$1
  chk "corpus compat vs C ($(ls $dir | wc -l) files)" ' 0 differ' sh tools/corpus.sh $(find $dir -name '*.qbe' -o -name '*.ssa')
  chk "corpus optsweep" ', 0 failed' sh tools/optsweep.sh $(find $dir -name '*.qbe' -o -name '*.ssa')
  ;;
*) echo "unknown suite $suite"; exit 2 ;;
esac
[ -n "$GITHUB_STEP_SUMMARY" ] && { echo "### $suite $*"; cat $SUM; } >> "$GITHUB_STEP_SUMMARY"
mkdir -p ci-out && cp $SUM "ci-out/$suite${1:+-$1}.md"
echo "failed checks: $fail"
[ $fail -eq 0 ]
