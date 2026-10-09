#!/bin/sh
# Real-program tests: build Lua 5.4 (+ its official test suite) and SQLite
# (smoke test vs a gcc build) with cproc using zbe as the backend.
# Usage: programs.sh WORKDIR   (needs cproc on PATH or $CPROC, and qbe=zbe on PATH)
# Prints one summary line: "programs: N passed, M failed".
set -u
W=${1:-/tmp/zbe-programs}; mkdir -p "$W"; cd "$W" || exit 2
CPROC=${CPROC:-cproc}
LUA=5.4.7 SQL=3460100 SQLY=2024
pass=0; fail=0
# gcc's limits.h relies on gcc-predefined macros that cproc does not define
gcc -dM -E - </dev/null | grep -E '#define __(CHAR_BIT|SCHAR_MAX|SHRT_MAX|INT_MAX|LONG_MAX|WCHAR_MAX|WCHAR_MIN|SIZE_MAX|PTRDIFF_MAX|FLT_RADIX|FLT_[A-Z0-9_]+|DBL_[A-Z0-9_]+)__ ' |
  grep -v FLT_EVAL_METHOD > "$W/gccdefs.h"
LIM="-include $W/gccdefs.h"
ok() { pass=$((pass+1)); echo "PASS: $1"; }
ko() { fail=$((fail+1)); echo "FAIL: $1"; }
get() { [ -f "$2" ] || curl -sSfL -o "$2" "$1"; }

# --- Lua: interpreter + official test suite (portable subset) ---
get https://www.lua.org/ftp/lua-$LUA.tar.gz lua.tgz &&
get https://www.lua.org/tests/lua-$LUA-tests.tar.gz luatests.tgz &&
tar xzf lua.tgz && tar xzf luatests.tgz || ko "lua download"
if [ -d lua-$LUA ]; then
  if (cd lua-$LUA/src && make -s CC="$CPROC" CFLAGS="-std=c99 -DLUA_USE_POSIX $LIM -Dvolatile=" MYLDFLAGS= MYLIBS='-lm' \
        AR='ar rcu' lua >../../lua-build.log 2>&1); then ok "lua build"
    if (cd lua-$LUA-tests && timeout 900 ../lua-$LUA/src/lua -e'_port=true; _soft=true' all.lua) >lua-tests.log 2>&1 \
       && grep -q 'final OK' lua-tests.log; then ok "lua test suite"
    else ko "lua test suite"; tail -20 lua-tests.log; fi
  else ko "lua build"; tail -20 lua-build.log; fi
fi

# --- SQLite: same SQL script through a cproc+zbe build and a gcc build ---
# Off by default: cproc still rejects something long-double related in
# sqlite3.c ("cproc-qbe: long double is not yet supported"); set SQLITE=1 to try.
if [ "${SQLITE:-0}" = 1 ]; then
get https://www.sqlite.org/$SQLY/sqlite-amalgamation-$SQL.zip sqlite.zip &&
unzip -qo sqlite.zip || ko "sqlite download"
S=sqlite-amalgamation-$SQL
if [ -d $S ]; then
  F='-DLONGDOUBLE_TYPE=double -DSQLITE_THREADSAFE=0 -DSQLITE_OMIT_LOAD_EXTENSION -DSQLITE_DISABLE_INTRINSIC -DSQLITE_OMIT_WAL'
  # the library (sqlite3.c, ~250k lines) is compiled by cproc+zbe; the shell
  # front-end by gcc (its top-level 'SQLITE_EXTENSION_INIT1;' is not C99)
  gcc -O1 $F -c -o shell-gcc.o $S/shell.c
  if timeout 1800 $CPROC -std=c99 $F $LIM -Dvolatile= -c -o sqlite3-zbe.o $S/sqlite3.c >sqlite-build.log 2>&1 &&
     gcc -o sqlite-zbe shell-gcc.o sqlite3-zbe.o -lm >>sqlite-build.log 2>&1; then ok "sqlite build"
    gcc -O1 $F -o sqlite-gcc $S/shell.c $S/sqlite3.c -lm
    cat > q.sql <<'EOF'
CREATE TABLE t(a INTEGER PRIMARY KEY, b TEXT, c REAL);
WITH RECURSIVE n(x) AS (SELECT 1 UNION ALL SELECT x+1 FROM n WHERE x<20000)
INSERT INTO t SELECT x, printf('row%05d', x*7919 % 20000), x*1.5/7 FROM n;
CREATE INDEX tb ON t(b);
SELECT count(*), sum(a), round(avg(c),6), min(b), max(b) FROM t;
SELECT b, a FROM t WHERE b BETWEEN 'row10000' AND 'row10050' ORDER BY b;
SELECT a % 13 AS k, count(*), group_concat(a % 7, '') FROM t GROUP BY k ORDER BY k;
UPDATE t SET c = c * 2 WHERE a % 3 = 0; DELETE FROM t WHERE a % 5 = 0;
SELECT count(*), round(sum(c), 4), hex(randomblob(0)) FROM t;
SELECT json_object('n', count(*), 'm', max(a)) FROM t;
SELECT upper(b), length(b), substr(b, 2, 3) FROM t ORDER BY a DESC LIMIT 5;
PRAGMA integrity_check;
EOF
    ./sqlite-zbe :memory: < q.sql > out-zbe.txt 2>&1; ./sqlite-gcc :memory: < q.sql > out-gcc.txt 2>&1
    if cmp -s out-zbe.txt out-gcc.txt && grep -q '^ok$' out-zbe.txt; then ok "sqlite smoke (== gcc build)"
    else ko "sqlite smoke (== gcc build)"; diff out-gcc.txt out-zbe.txt | head -20; fi
  else ko "sqlite build"; tail -20 sqlite-build.log; fi
fi
fi
echo "programs: $pass passed, $fail failed"
[ $fail -eq 0 ]
