#!/usr/bin/env python3
"""Input-driven failures must return, preserve C diagnostics, and allow reuse.
Run after zig build. QBEREF optionally enables comparison to the C reference.
"""
import os
from pathlib import Path
import re
import shlex
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parent.parent
ZIG = ROOT / 'zig-out/bin/qbe'
REF = Path(os.environ.get('QBEREF', '/data/qbe-cfix/qbe'))
TARGETS = ('amd64_sysv', 'amd64_apple', 'amd64_win', 'arm64', 'arm64_apple', 'rv64')
VALID = 'function w $ok() {\n@s\n ret 7\n}\n'
CASES = []

def case(name, targets, source, message):
    for target in targets:
        CASES.append((name, target, source, 'dying: ' + message + '\n'))

case('extern-thread', ('arm64', 'rv64'),
     'function l $f() {\n@s\n ret extern thread $g\n}\n',
     'extern thread unavailable on {target}')
# The two targets have different (but otherwise identical) diagnostics.
CASES = [(n, t, s, m.format(target=t)) for n, t, s, m in CASES]
for linkage in ('extern', 'thread', 'extern thread'):
    case('win-' + linkage.replace(' ', '-'), ('amd64_win',),
         f'function l $f() {{\n@s\n ret {linkage} $g\n}}\n',
         'extern/thread unsupported on amd64_win')
case('extern-offset', ('rv64',),
     'function l $f() {\n@s\n %p =l add extern $g, 4\n ret %p\n}\n',
     'extern with offset is not supported')
case('env-varargs', ('amd64_win',),
     'function $f() {\n@s\n call $g(env 0, ...)\n ret\n}\n',
     "can't use env with varargs")
case('common-initializer', TARGETS, 'common data $d = { w 1 }\n',
     'invalid common data definition')
alloc = ('function $f() {\n@s\n' +
         ''.join(f' %p{i} =l alloc16 2147483600\n' for i in range(5)) +
         ' call $g(' + ', '.join(f'l %p{i}' for i in range(5)) + ')\n ret\n}\n')
case('alloc-overflow', ('amd64_sysv', 'amd64_apple', 'amd64_win', 'rv64'),
     alloc, 'alloc too large')

# Repeated bad->good compilations in ONE process verify library error propagation
# and continued usability, rather than merely testing an isolated subprocess.
DRIVER = r'''
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "qbe.h"
int main(int argc, char **argv) {
    if (argc != 4) return 90;
    FILE *fp = fopen(argv[1], "rb");
    if (!fp) return 91;
    char src[8192];
    size_t n = fread(src, 1, sizeof(src), fp);
    fclose(fp);
    const char *good = "function w $ok() {\n@s\n ret 7\n}\n";
    for (int i = 0; i < 3; ++i) {
        char *out = NULL;
        size_t len = 0;
        int rc = qbe_compile(src, n, argv[2], atoi(argv[3]), &out, &len);
        if (rc != 3) { fprintf(stderr, "bad return %d\n", rc); return 92; }
        if (out) { qbe_free(out); return 93; }
        rc = qbe_compile(good, strlen(good), argv[2], atoi(argv[3]), &out, &len);
        if (rc || !out || len != strlen(out) || !strstr(out, "ok:")) return 94;
        qbe_free(out);
    }
    return 0;
}
'''

def diagnostic(raw):
    # The only allowed difference is the binary/source-file prefix.
    return re.sub(rb'^[^\s]+: dying:', b'dying:', raw).decode()

passed = failed = 0
with tempfile.TemporaryDirectory() as tmp:
    work = Path(tmp)
    (work / 'driver.c').write_text(DRIVER)
    subprocess.run(shlex.split(os.environ.get('CC', 'cc')) + [
        '-o', str(work / 'driver'), str(work / 'driver.c'),
        '-I' + str(ROOT / 'zig-out/include'), str(ROOT / 'zig-out/lib/libqbe.a')], check=True)
    for name, target, source, expected in CASES:
        file = work / 'input.ssa'
        file.write_text(source)
        if REF.is_file():
            ref = subprocess.run([str(REF), '-t', target, str(file)], capture_output=True)
            assert ref.returncode != 0 and diagnostic(ref.stderr) == expected, (name, target, ref.stderr)
        for opt in range(3):
            cli = subprocess.run([str(ZIG), '-t', target, f'-O{opt}', str(file)], capture_output=True)
            lib = subprocess.run([str(work / 'driver'), str(file), target, str(opt)], capture_output=True)
            if (cli.returncode == 1 and diagnostic(cli.stderr) == expected and
                    lib.returncode == 0 and diagnostic(lib.stderr).count(expected) == 3):
                passed += 1
            else:
                failed += 1
                print(f'FAIL: {name}[{target}] -O{opt} cli={cli.returncode} lib={lib.returncode}')
                print(cli.stderr.decode(), lib.stderr.decode())
print(f'input-errors: {passed} passed, {failed} failed')
raise SystemExit(failed != 0)
