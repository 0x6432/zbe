#!/usr/bin/env python3
"""Synthetic path-substitution probe; NOT a Valgrind scan or a gate.

Runs the existing memcheck driver against a stub tool and fake client. The
stub keeps the original log open while the client replaces its pathname; then
it writes a fatal diagnostic and a clean summary to the original inode. The
client's replacement contains only the clean summary. A clean no-substitution
control must pass and a fatal no-substitution control must fail; substitution
demonstrates what the current path consumer accepts.
No real compiler, Valgrind, or reference implementation is invoked.
"""
import os
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
DRIVER = ROOT / 'tools' / 'memcheck.sh'

# This is a behavioral model, not a claim about Valgrind's call sequence or
# exit status in any particular failure. The stub always returns 0 so that the
# driver's independent fatal-diagnostic check can be tested in isolation.
STUB = r'''#!/bin/sh
log=
for arg do
  case "$arg" in --log-file=*) log=${arg#--log-file=};; esac
done
[ -n "$log" ] || exit 90
exec 3> "$log" || exit 91
shift 4
"$@" || exit 92
if [ "$PROBE_MODE" != clean ]; then
  printf '%s\n' 'valgrind: Fatal error at startup' >&3 || exit 95
fi
printf '%s\n' '==123== ERROR SUMMARY: 0 errors from 0 contexts (suppressed: 0 from 0)' >&3 || exit 95
exit 0
'''
CLIENT = r'''#!/usr/bin/env python3
import os
from pathlib import Path
import sys
if len(sys.argv) != 5 or sys.argv[1] != '-t' or sys.argv[3] not in ('-O0', '-O2'):
    sys.exit(93)
if os.environ['PROBE_MODE'] == 'substitute':
    roots = [p for p in Path(os.environ['TMPDIR']).iterdir()
             if p.is_dir() and (p / 'valgrind').is_file()]
    if len(roots) != 1:
        sys.exit(94)
    dest = roots[0] / 'valgrind'
    replacement = roots[0] / 'synthetic-replacement'
    replacement.write_text('==123== ERROR SUMMARY: 0 errors from 0 contexts (suppressed: 0 from 0)\n')
    os.replace(replacement, dest)
with open(os.environ['PROBE_CALLS'], 'a') as calls:
    calls.write(' '.join(sys.argv[1:]) + '\n')
'''


def executable(path, contents):
    path.write_text(contents)
    path.chmod(0o755)


def run_case(base, mode):
    case = base / mode
    case.mkdir()
    temp = case / 'tmp'
    temp.mkdir()
    executable(case / 'valgrind', STUB)
    executable(case / 'client', CLIENT)
    executable(case / 'reference', '#!/bin/sh\nexit 0\n')
    input_path = case / 'dummy.ssa'
    input_path.write_text('synthetic input; never compiled\n')
    calls = case / 'calls'
    env = os.environ.copy()
    env.update(PATH=str(case) + os.pathsep + os.defpath,
               TMPDIR=str(temp), ZQBE=str(case / 'client'),
               QBEREF=str(case / 'reference'), PROBE_MODE=mode,
               PROBE_CALLS=str(calls))
    result = subprocess.run(['sh', str(DRIVER), str(input_path)], env=env,
                            text=True, capture_output=True, timeout=30)
    rows = calls.read_text().splitlines() if calls.exists() else []
    expected = {f'-t {target} -O{opt} {input_path}'
                for target in ('amd64_sysv', 'amd64_apple', 'amd64_win',
                               'arm64', 'arm64_apple', 'rv64')
                for opt in (0, 2)}
    def require(condition, message):
        if not condition:
            raise RuntimeError(f'{mode}: {message}\n'
                               f'driver exit={result.returncode}\n'
                               f'stdout:\n{result.stdout}\nstderr:\n{result.stderr}')

    require(len(rows) == 12 and set(rows) == expected,
            f'wrong client calls: {rows!r}')
    leftovers = list(temp.iterdir())
    require(not leftovers, f'temporary files not cleaned: {leftovers!r}')
    lines = result.stdout.splitlines()
    summaries = [line for line in lines if line.startswith('memcheck: ')]
    expected_status = 1 if mode == 'control' else 0
    expected_summary = ('memcheck: 0 passed, 12 failed (0 reference-confirmed rejections)'
                        if mode == 'control' else
                        'memcheck: 12 passed, 0 failed (0 reference-confirmed rejections)')
    require(result.returncode == expected_status and summaries == [expected_summary],
            'unexpected status or summary')

    marker = 'valgrind: Fatal error at startup'
    marker_count = lines.count(marker)
    fail_indices = [i for i, line in enumerate(lines) if line.startswith('FAIL: ')]
    if mode == 'control':
        expected_failures = {f'FAIL: {target} -O{opt} {input_path} (exit 0)'
                             for target in ('amd64_sysv', 'amd64_apple', 'amd64_win',
                                            'arm64', 'arm64_apple', 'rv64')
                             for opt in (0, 2)}
        require(len(fail_indices) == 12 and
                {lines[i] for i in fail_indices} == expected_failures,
                'missing, duplicate, or unexpected failure rows')
        for n, start in enumerate(fail_indices):
            stop = fail_indices[n + 1] if n + 1 < len(fail_indices) else len(lines)
            require(lines[start + 1:stop].count(marker) == 1,
                    f'failure row lacks exactly one fatal marker: {lines[start]}')
        require(marker_count == 12, f'unexpected fatal marker count: {marker_count}')
    else:
        require(not fail_indices and marker_count == 0,
                f'unexpected failure rows or fatal markers: {len(fail_indices)}, {marker_count}')
    print(f'{mode}: driver exit={result.returncode}; {summaries[0]}; '
          f'synthetic client calls={len(rows)}; fatal markers={marker_count}')



def main():
    with tempfile.TemporaryDirectory(prefix='zbe-evidence-path-probe-') as tmp:
        base = Path(tmp)
        run_case(base, 'clean')
        run_case(base, 'control')
        run_case(base, 'substitute')
    print('BLOCKED: substitution was accepted by the current path consumer; '
          'this synthetic fixture is not Valgrind or gate evidence.')


if __name__ == '__main__':
    main()
