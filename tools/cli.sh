#!/bin/sh
# CLI quality-of-life flags (non-compat mode) and their compat-mode behaviour.
Z=${ZQBE:-$(cd "$(dirname "$0")/.." && pwd)/zig-out/bin/qbe}
unset QBE_COMPAT
pass=0; fail=0
# default target follows the host (like upstream config.h)
case "$(uname -s)-$(uname -m)" in
Darwin-arm64) DEF=arm64_apple ;; Darwin-*) DEF=amd64_apple ;;
*-aarch64|*-arm64) DEF=arm64 ;; *-riscv64) DEF=rv64 ;; *) DEF=amd64_sysv ;;
esac
chk() { # name expected-rc grep-pattern command...
  n=$1 rc=$2 pat=$3; shift 3
  out=$("$@" 2>&1 < /dev/null); r=$?
  if [ $r -eq $rc ] && printf '%s\n' "$out" | grep -q -- "$pat"; then pass=$((pass+1))
  else fail=$((fail+1)); echo "FAIL: $n (rc $r)"; printf '%s\n' "$out" | head -3; fi
}
P='export function w $f(w %a) {
@start
	%x =w div %a, 4
	ret %x
}'
chk version 0 '^qbe (zig port) ' $Z --version
chk help_long 0 '^	-O<level>' $Z --help
chk help_short 0 'list-targets' $Z -h
chk list 0 "^$DEF (default)\$" $Z --list-targets
chk list_rv64 0 '^rv64$' $Z --list-targets
chk bad_long 1 "unrecognized option '--nope'" $Z --nope
chk bad_level 1 "invalid optimization level 'O7'" $Z -O7
chk t_query 0 "^$DEF\$" $Z -t '?'
chk O0_idiv 0 'idivl' sh -c "printf '%s\n' '$P' | $Z -O0 -t amd64_sysv"
chk O1_idiv 0 'idivl' sh -c "printf '%s\n' '$P' | $Z -O1 -t amd64_sysv"
chk O_is_O1 0 'idivl' sh -c "printf '%s\n' '$P' | $Z -O -t amd64_sysv"
chk O2_sar 0 'sarl \$2' sh -c "printf '%s\n' '$P' | $Z -O2 -t amd64_sysv"
chk O3_is_O2 0 'sarl \$2' sh -c "printf '%s\n' '$P' | $Z -O3 -t amd64_sysv"
chk Os_is_O2 0 'sarl \$2' sh -c "printf '%s\n' '$P' | $Z -Os -t amd64_sysv"
chk default_O2 0 'sarl \$2' sh -c "printf '%s\n' '$P' | $Z -t amd64_sysv"
chk last_wins 0 'idivl' sh -c "printf '%s\n' '$P' | $Z -O2 -O0 -t amd64_sysv"
chk mixed_flags 0 'asr' sh -c "printf '%s\n' '$P' | $Z -t arm64 -O2 -O2 - "
# compat mode: upstream CLI (long options rejected like getopt, -O ignored)
chk compat_long 1 "invalid option -- '-'" env QBE_COMPAT=1 $Z --version
chk compat_O2 0 'idivl' sh -c "printf '%s\n' '$P' | QBE_COMPAT=1 $Z -O2 -t amd64_sysv"
chk compat_help 0 'dump debug' env QBE_COMPAT=1 $Z -h
if QBE_COMPAT=1 $Z -h 2>&1 | grep -q -- '-O<level>'; then fail=$((fail+1)); echo 'FAIL: compat help shows -O'; else pass=$((pass+1)); fi
printf 'cli: %d passed, %d failed\n' $pass $fail
[ $fail -eq 0 ]
