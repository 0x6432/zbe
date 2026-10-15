#!/usr/bin/env python3
"""Exercise real parser hash growth/reuse and debug-file vector growth vs C."""
import os
from pathlib import Path
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parent.parent
ZBE = os.environ.get('ZQBE', str(ROOT / 'zig-out/bin/qbe'))
REF = os.environ.get('QBEREF', '/data/qbe-cfix/qbe')
TARGETS = ('amd64_sysv', 'amd64_apple', 'amd64_win', 'arm64', 'arm64_apple', 'rv64')


def function(name, count):
    lines = [f'function w ${name}(w %arg) {{', '@start', '\tdbgloc 10, 2']
    previous = '%arg'
    for n in range(count):
        lines.append(f'\t%t{n} =w add {previous}, 1')
        previous = f'%t{n}'
    return '\n'.join(lines + [f'\tret {previous}', '}'])


def main():
    # 8300 temporaries cross the initial hash table's 8192-entry growth
    # threshold. A small function followed by another large one checks clear
    # and reuse with the same names but different function-local references.
    text = '\n'.join(f'dbgfile "source{n}.ssa"' for n in range(9)) + '\n'
    text += function('large0', 8300) + '\ndbgfile "source2.ssa"\n'
    text += function('small', 1) + '\ndbgfile "source8.ssa"\n'
    text += function('large1', 8300) + '\n'
    env = dict(os.environ, QBE_COMPAT='1')
    passed = failed = 0
    with tempfile.TemporaryDirectory(prefix='zbe-parser-caches-') as directory:
        source = Path(directory) / 'growth.ssa'
        source.write_text(text)
        for target in TARGETS:
            for debug in (False, True):
                args = ['-t', target] + (['-dP'] if debug else []) + [str(source)]
                results = [subprocess.run([exe] + args, env=env, capture_output=True,
                                          timeout=120) for exe in (ZBE, REF)]
                z, c = results
                if z.returncode == c.returncode == 0 and z.stdout == c.stdout and z.stderr == c.stderr:
                    passed += 1
                else:
                    failed += 1
                    print(f'FAIL: {target} {"parse dump" if debug else "assembly"} '
                          f'(status zbe={z.returncode}, C={c.returncode}; '
                          f'stdout equal={z.stdout == c.stdout}, stderr equal={z.stderr == c.stderr})')
    print(f'parser-caches: {passed} passed, {failed} failed')
    return 1 if failed else 0


if __name__ == '__main__':
    sys.exit(main())
