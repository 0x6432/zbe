#!/usr/bin/env python3
"""Strict tests for C-abort versus zbe-input-error diagnostic comparisons.
TEST_SHELL overrides /bin/sh to reproduce a specific shell (e.g. dash).
"""
import os
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parent.parent
SHELL = os.environ.get('TEST_SHELL', '/bin/sh')
MESSAGES = (
    'extern thread unavailable on arm64',
    'extern thread unavailable on rv64',
    'extern/thread unsupported on amd64_win',
    'extern with offset is not supported',
    'alloc too large',
    'invalid constant',
    "can't use env with varargs",
    'invalid common data definition',
)
passed = failed = 0
with tempfile.TemporaryDirectory() as tmp:
    cfile, zfile = Path(tmp) / 'c.err', Path(tmp) / 'z.err'

    def check(name, crc, zrc, cerr, zerr, expected):
        global passed, failed
        cfile.write_text(cerr)
        zfile.write_text(zerr)
        result = subprocess.run([
            SHELL, '-c', '. tools/input-error-compat.sh; input_error_matches "$@"',
            'compat-test', str(crc), str(zrc), str(cfile), str(zfile)], cwd=ROOT)
        if (result.returncode == 0) == expected:
            passed += 1
        else:
            failed += 1
            print(f'FAIL: {name}: exit {result.returncode}')

    for message in MESSAGES:
        c = 'backend/emit.c: dying: ' + message + '\n'
        z = 'qbe: dying: ' + message + '\n'
        for trailer in ('', 'Aborted\n', 'Aborted (core dumped)\n'):
            check(message + repr(trailer), 134, 1, c + trailer, z, True)

    c = 'backend/emit.c: dying: alloc too large\n'
    z = 'qbe: dying: alloc too large\n'
    for crc, zrc in ((0, 1), (1, 1), (139, 1), (134, 0), (134, 134), (134, 3)):
        check(f'wrong-status-{crc}-{zrc}', crc, zrc, c, z, False)
    for name, cerr, zerr in (
        ('internal-invariant', 'x.c: dying: unreachable\n', 'qbe: dying: unreachable\n'),
        ('wrong-message', c, 'qbe: dying: invalid constant\n'),
        ('extra-C-diagnostic', c + 'extra\n', z),
        ('extra-Z-diagnostic', c, z + 'extra\n'),
        ('extra-C-newline', c + '\n', z),
        ('extra-Z-newline', c, z + '\n'),
        ('missing-C-newline', c.rstrip('\n'), z),
        ('missing-Z-newline', c, z.rstrip('\n')),
        ('midstream-abort', c + 'Aborted\nextra\n', z),
        ('duplicate-abort', c + 'Aborted\nAborted\n', z),
        ('unrecognized-abort', c + 'Aborted unexpectedly\n', z),
        ('Z-abort-trailer', c, z + 'Aborted\n'),
    ):
        check(name, 134, 1, cerr, zerr, False)

print(f'input-error-compat: {passed} passed, {failed} failed')
raise SystemExit(failed != 0)
