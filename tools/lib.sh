#!/bin/sh
# Library-mode tests: a C program linked with libqbe.a must produce exactly
# the same assembly as the qbe command for every test file, target and -O
# level; plus API edge cases (unknown target, target list, version, empty
# input, repeated calls).
D=$(cd "$(dirname "$0")/.." && pwd)
Z=$D/zig-out/bin/qbe
unset QBE_COMPAT
W=$(mktemp -d)
cat > $W/drv.c <<'EOF'
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "qbe.h"
int main(int argc, char **argv) {
  /* usage: drv file target opt  -> writes asm to stdout */
  if (argc == 2 && !strcmp(argv[1], "api")) {
    const char *n; char *out = 0; size_t len = 123; int i, bad = 0;
    for (i = 0; !qbe_target(i, &n); i++) printf("target %s\n", n);
    if (qbe_target(-1, &n) != 1) bad++;
    if (qbe_compile("", 0, "nope", 2, &out, &len) != 1 || out) bad++;
    if (qbe_compile("", 0, NULL, 2, &out, &len) != 0 || !out || len != strlen(out)) bad++;
    printf("empty [%s]\n", out); qbe_free(out);
    qbe_free(NULL);
    const char *f = "export function w $f(w %a) {\n@start\n\t%x =w udiv %a, 10\n\tret %x\n}\n";
    for (i = 0; i < 200; i++) {  /* repeated calls, alternating levels */
      if (qbe_compile(f, strlen(f), i & 1 ? "arm64" : NULL, i % 3, &out, NULL)) bad++;
      if (!strstr(out, "f:")) bad++;
      qbe_free(out);
    }
    printf("version %s\nbad %d\n", qbe_version(), bad);
    return bad != 0;
  }
  FILE *fp = fopen(argv[1], "rb");
  if (!fp) return 3;
  static char buf[1 << 22];
  size_t n = fread(buf, 1, sizeof buf, fp);
  fclose(fp);
  char *out; size_t len;
  int rc = qbe_compile(buf, n, argv[2], atoi(argv[3]), &out, &len);
  if (rc) return 10 + rc;
  fwrite(out, 1, len, stdout);
  qbe_free(out);
  return 0;
}
EOF
pass=0; fail=0
if ! cc -o $W/drv $W/drv.c -I$D/zig-out/include $D/zig-out/lib/libqbe.a 2>$W/e; then
  echo "lib: cannot link"; cat $W/e; exit 1; fi
$W/drv api > $W/api 2>&1
if [ $? -eq 0 ] && grep -q '^target amd64_sysv$' $W/api && grep -q '^target rv64$' $W/api \
   && [ "$(grep -c '^target' $W/api)" = 6 ] && grep -q '^empty \[' $W/api && grep -q '^bad 0' $W/api
then pass=$((pass+1)); else fail=$((fail+1)); echo "FAIL: api"; cat $W/api; fi
for t in amd64_sysv amd64_apple amd64_win arm64 arm64_apple rv64; do
  for o in 0 1 2; do
    for f in $D/test/*.ssa; do
      $Z -t $t -O$o $f > $W/a.s 2>/dev/null || continue
      if $W/drv $f $t $o > $W/b.s 2>/dev/null && cmp -s $W/a.s $W/b.s; then pass=$((pass+1))
      else fail=$((fail+1)); echo "FAIL: $t -O$o $(basename $f)"; fi
    done
  done
done
# -O0 through the library is byte-identical to the C reference as well
REF=${QBEREF:-/data/qbe-cfix/qbe}
if [ -x "$REF" ]; then
  for f in $D/test/*.ssa; do
    $REF $f > $W/a.s 2>/dev/null || continue
    if $W/drv $f amd64_sysv 0 > $W/b.s && cmp -s $W/a.s $W/b.s; then pass=$((pass+1))
    else fail=$((fail+1)); echo "FAIL: ref $(basename $f)"; fi
  done
fi
rm -rf $W
printf 'lib: %d passed, %d failed\n' $pass $fail
[ $fail -eq 0 ]
