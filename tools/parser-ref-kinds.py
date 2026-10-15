#!/usr/bin/env python3
"""Non-temporary reference IDs must not index the parser's temporary table."""
import os
from pathlib import Path
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parent.parent
ZBE = os.environ.get('ZQBE', str(ROOT / 'zig-out/bin/qbe'))
REF = os.environ.get('QBEREF', '/data/qbe-cfix/qbe')
TARGETS = ('amd64_sysv', 'amd64_apple', 'amd64_win', 'arm64', 'arm64_apple', 'rv64')


def main():
    # A high type reference with only one temporary recreates Hare's failure.
    text = ''.join(f'type :t{n} = {{ w }}\n' for n in range(300))
    text += ('export function w $type_ref(:t299 %arg) {\n@start\n'
             ' %value =w loadw %arg\n ret %value\n}\n')
    # Two distinct constants per instruction outgrow the temporary table too.
    text += 'export function w $constant_refs() {\n@start\n'
    for n in range(192):
        text += f' %v{n} =w add {1000 + 2*n}, {1001 + 2*n}\n'
    text += ' ret %v191\n}\n'
    passed = failed = 0
    with tempfile.TemporaryDirectory(prefix='zbe-ref-kinds-') as directory:
        source = Path(directory) / 'ref-kinds.ssa'
        source.write_text(text)
        for target in TARGETS:
            for debug in (False, True):
                args = ['-t', target] + (['-dP'] if debug else []) + [str(source)]
                results = [subprocess.run([exe] + args, env=dict(os.environ, QBE_COMPAT='1'),
                                          capture_output=True, timeout=120)
                           for exe in (ZBE, REF)]
                z, c = results
                if z.returncode == c.returncode == 0 and z.stdout == c.stdout and z.stderr == c.stderr:
                    passed += 1
                else:
                    failed += 1
                    print(f'FAIL: {target} {"parse dump" if debug else "assembly"} '
                          f'(zbe={z.returncode}, C={c.returncode}; '
                          f'stdout equal={z.stdout == c.stdout}, stderr equal={z.stderr == c.stderr})')
    print(f'parser-ref-kinds: {passed} passed, {failed} failed')
    return 1 if failed else 0


if __name__ == '__main__':
    sys.exit(main())
