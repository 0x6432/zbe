#!/usr/bin/env python3
"""Focused predecessor-vs-extern-draft whole-output byte comparison.

After hosted CI is finished, supply already-built Linux AMD64 zbe-native binaries:
  python3 rewrite/tools/extern_old_output_parity.py \
    --baseline /path/to/predecessor/zbe-native --draft /path/to/draft/zbe-native

The intended predecessor is 3890562118b85be550dcc19f6c400414d3f8672a,
whose fixture bytes are pinned below. The draft is based on 9cced46f5d58d3849bdb64575a2a6053dc44070f. Binary provenance must be established by the caller;
paths and SHA-256 digests are reported, but binaries cannot prove their commits.
The shared lock serializes local verification, not hosted CI: wait for hosted CI
separately. No building, linking, fixture generation, or CI is performed.

Inventory: scalar calls, symbol addresses/offsets/quoted names, relocations,
subword, ENV, variadic/vaarg, and INTEGER/SSE/MEMORY/union/opaque record cases.
These 21 unchanged whole modules cover only selected old syntax. This is neither
an exhaustive U16 ledger nor extern/GOT semantics, ABI, or full compatibility.
"""
import argparse
import fcntl
import hashlib
import os
from pathlib import Path
import platform
import resource
import shlex
import subprocess
import sys
import tempfile

# Each SHA-256 is the unchanged file from both 3890562 and 9cced46.
FIXTURES = {
    'record_declaration_scalar.ssa': '34cc1dc0d7a2b4e26fd24e55416b12869384aaeae7e7c72f99dd1fc16df38654',
    'record_declaration_symbol_identity.ssa': '7cc54fe2c9a20616a1ba7ce5353d7aa6a0453956247b21540775b61eb27ef36f',
    'aggregate_abi_native.ssa': 'b2152654e6fef9d33c55a724a627c1223d66a1a2180f979a41a5dad7bd10d57a',
    'aggregate_abi_small_integer.ssa': 'd6285f3a8ea40c213a64c4d23a44c41173bfb7cf4f0d74ea79c6d2c53a1a8a3e',
    'aggregate_abi_small_sse.ssa': '4f17966330717ed86638159ad1c2c104a84fb56e49f2a0290b0ecb29e8658313',
    'aggregate_abi_align16.ssa': 'e5de81cbecc3edb1b9197655e578dc9a3d856c7ce6a01bc1d117807512c0d3f2',
    'aggregate_abi_call_targets.ssa': 'b441027b3a7a75159d9ae51833914e879704e83563a92c62af9d24bdde305d76',
    'aggregate_abi_variadic.ssa': '530a9b187e7a22e572a8b596a57c86a80a8939e5478d78097ad0891ace253256',
    'aggregate_abi_union.ssa': '34f7619143be1a6ccfceea59ed9ee20ba57d96ea429619ca54f08180426632e6',
    'aggregate_abi_opaque.ssa': 'a88fd2de52045496a750621b122c4081b5936a961b0196ad7fa80611c534353f',
    'environment-calls.ssa': 'd155b614f9ec4160562d34c932c9e42b8b74712b0f6c91a5577644cca0b71e63',
    'variadic-calls.ssa': '708c029586982aa6120059d54f8dfb51fa0d8ebe35a2a97695f800924b96340b',
    'variadic-functions.ssa': 'eeb333d6764d88418752ca7d28d0e5d5ae7ec17fa81e1cf910655e08f7fb0910',
    'vaarg-consumers.ssa': '9542f0fc2ec5e8d2ca2213257dbb86fa22b7345ed5345340b86fe648dc250d20',
    'symbol-addresses.ssa': '96270ddc6b6cda41f79e9bee706126356ad847ad39678f2e77eed276b2ee5982',
    'symbol-offsets.ssa': '5dd1d1170e5d09bc2fa83131a0ebdadf00a7d4f7bb00d1321affbc746a69e043',
    'quoted-globals.ssa': 'fe48608f05f617e66630431db15da49ffd6628c4382c9396031f24790984ec71',
    'data-relocations.ssa': 'c21548140c7e951ccaf6d297390b82e889ad1568c119fec8f51d8427a1f0316c',
    'direct-calls.ssa': '79d6befb0d2fe4afa5d9b06c11e909944d6bc334f5b69f7e4dbeeb168f5e1406',
    'indirect-calls.ssa': 'aaac117bf8892d2ee1212a4009a1d964c1dbe6fae7f9405c7a5214cb2a870715',
    'subword-abi.ssa': 'a4a1fb571b160c6363c98c4f21b801ba4020ecf8e26033b44377265d9338c0a2',
}
FLAGS = ('--fold-integers', '--reuse-stack-homes', '--callee-saved-homes')
TIMEOUT = 90


def sha(data):
    return hashlib.sha256(data).hexdigest()


def diagnostics(data):
    # Limit noise without decoding assembly or allowing arbitrary terminal controls.
    data = data or b''
    return repr(data[:4096]) + (' ... [truncated]' if len(data) > 4096 else '')


def compile_one(label, compiler, flags, fixture, output, env):
    command = [str(compiler), *flags, str(fixture), str(output)]
    try:
        result = subprocess.run(command, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                timeout=TIMEOUT, env=env, cwd=output.parent)
    except (OSError, subprocess.TimeoutExpired) as exc:
        print(f'  {label}: launch/timeout error: {exc}\n  command: {shlex.join(command)}', file=sys.stderr)
        if isinstance(exc, subprocess.TimeoutExpired):
            print(f'  stdout: {diagnostics(exc.stdout)}\n  stderr: {diagnostics(exc.stderr)}', file=sys.stderr)
        return None
    if result.returncode != 0:
        print(f'  {label}: exit {result.returncode}\n  command: {shlex.join(command)}'
              f'\n  stdout: {diagnostics(result.stdout)}\n  stderr: {diagnostics(result.stderr)}', file=sys.stderr)
        return None
    try:
        data = output.read_bytes()
        if not data:
            raise ValueError('empty output')
        return data
    except (OSError, ValueError) as exc:
        print(f'  {label}: successful exit but missing/unreadable/empty output: {exc}'
              f'\n  command: {shlex.join(command)}\n  stdout: {diagnostics(result.stdout)}'
              f'\n  stderr: {diagnostics(result.stderr)}', file=sys.stderr)
        return None


def report_difference(old, new):
    offset = next((i for i, (a, b) in enumerate(zip(old, new)) if a != b), min(len(old), len(new)))
    start = max(0, offset - 16)
    end = offset + 17
    print(f'  first differing byte offset: {offset} (zero-based; may be EOF)', file=sys.stderr)
    for label, data in (('baseline', old), ('draft', new)):
        print(f'  {label}: length={len(data)} sha256={sha(data)}'
              f' bytes[{start}:{end}]={data[start:end].hex(" ")}', file=sys.stderr)


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('--baseline', type=Path, required=True, help='already-built predecessor zbe-native')
    parser.add_argument('--draft', type=Path, required=True, help='already-built draft zbe-native')
    parser.add_argument('--lock', type=Path, default=Path('/data/zbe-coordination/full-verification.lock'),
                        help='shared local verification lock (default: %(default)s)')
    args = parser.parse_args()
    if platform.system() != 'Linux' or platform.machine() not in ('x86_64', 'amd64'):
        parser.error('requires Linux AMD64')
    try:
        baseline = args.baseline.resolve(strict=True)
        draft = args.draft.resolve(strict=True)
        for path in (baseline, draft):
            if not path.is_file() or not os.access(path, os.X_OK):
                raise ValueError(f'not an executable file: {path}')
        if os.path.samefile(baseline, draft):
            raise ValueError('baseline and draft must be distinct files')
        fixture_dir = Path(__file__).resolve().parents[1] / 'src/fixtures'
        for name, expected in FIXTURES.items():
            actual = sha((fixture_dir / name).read_bytes())
            if actual != expected:
                raise ValueError(f'fixture {name}: SHA-256 {actual}, expected {expected}')
        binary_hashes = [sha(path.read_bytes()) for path in (baseline, draft)]
        lock = open(args.lock, 'a')
    except (OSError, ValueError) as exc:
        parser.exit(2, f'preflight failed: {exc}\n')

    with lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            parser.exit(2, 'shared verification lock is busy; retry after other work ends\n')
        resource.setrlimit(resource.RLIMIT_CORE, (0, 0))
        print('Focused old-output parity; caller must verify compiler provenance and hosted CI completion.', flush=True)
        print(f'baseline {baseline} sha256={binary_hashes[0]}\ndraft    {draft} sha256={binary_hashes[1]}')
        print(f'Inventory: {len(FIXTURES)} unchanged fixtures, 8 masks; fold=1 reuse=2 callee-save=4')
        for name, digest in FIXTURES.items():
            print(f'  {name} sha256={digest}')
        print('Scope: selected whole modules only; not exhaustive U16, extern/GOT semantics, or full compatibility.', flush=True)
        failures = 0
        passed = 0
        with tempfile.TemporaryDirectory(prefix='extern-old-parity-') as temp:
            temp = Path(temp)
            # No inherited credentials, loader overrides, or user configuration.
            env = {'PATH': os.defpath, 'LC_ALL': 'C', 'TMPDIR': str(temp)}
            for name in FIXTURES:
                fixture = fixture_dir / name
                for mask in range(8):
                    flags = [flag for bit, flag in enumerate(FLAGS) if mask & (1 << bit)]
                    case = temp / f'{name}-{mask}'
                    case.mkdir()
                    old = compile_one('baseline', baseline, flags, fixture, case / 'baseline.s', env)
                    new = compile_one('draft', draft, flags, fixture, case / 'draft.s', env)
                    if old is None or new is None or old != new:
                        failures += 1
                        print(f'FAIL fixture={name} mask={mask} flags={shlex.join(flags) or "(none)"}', file=sys.stderr)
                        if old is not None and new is not None:
                            report_difference(old, new)
                    else:
                        passed += 1
        # Detect source changes during the run as well as before it.
        for name, expected in FIXTURES.items():
            try:
                actual = sha((fixture_dir / name).read_bytes())
            except OSError as exc:
                print(f'FAIL fixture changed or vanished: {name}: {exc}', file=sys.stderr)
                failures += 1
                continue
            if actual != expected:
                print(f'FAIL fixture changed during run: {name}: {actual}', file=sys.stderr)
                failures += 1
        print(f'Result: {passed}/{len(FIXTURES) * 8} comparisons passed; {failures} failures')
        return 1 if failures or passed != len(FIXTURES) * 8 else 0


if __name__ == '__main__':
    sys.exit(main())
