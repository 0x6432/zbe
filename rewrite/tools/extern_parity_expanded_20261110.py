#!/usr/bin/env python3
"""Bounded whole-file parity against a source-built predecessor, not published-oracle certification."""
import argparse
import fcntl
import hashlib
import json
import os
from pathlib import Path
import resource
import subprocess
import sys

FLAGS = ('--fold-integers', '--reuse-stack-homes', '--callee-saved-homes')
LIMIT = 4 * 1024**3

def digest(data):
    return hashlib.sha256(data).hexdigest()

def git(tree, *args):
    return subprocess.run(['git', '-C', str(tree), *args], check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE).stdout

def verify(trees, manifest):
    fixture_dir = Path('rewrite/src/fixtures')
    expected = set(manifest['fixtures']) | set(manifest['excluded'])
    for tree, key in zip(trees, ('baseline', 'draft')):
        if git(tree, 'rev-parse', 'HEAD').decode().strip() != manifest[key]:
            raise ValueError(f'{key} HEAD differs from manifest')
        if git(tree, 'status', '--porcelain', '--untracked-files=no'):
            raise ValueError(f'{key} tracked files are not clean')
        present = {p.name for p in (tree / fixture_dir).glob('*.ssa')}
        if present != expected:
            raise ValueError(f'{key} fixture inventory differs: {sorted(present ^ expected)}')
        for name, wanted in manifest['fixtures'].items():
            path = fixture_dir / name
            working = (tree / path).read_bytes()
            committed = git(tree, 'show', f'HEAD:{path.as_posix()}')
            if digest(working) != wanted or working != committed:
                raise ValueError(f'{key} fixture differs: {name}')

def compile_one(exe, flags, source, output, env):
    try:
        r = subprocess.run([str(exe), *flags, str(source), str(output)], cwd=output.parent,
                           env=env, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=90)
    except (OSError, subprocess.TimeoutExpired) as e:
        return {'error': str(e), 'ok': False}
    data = output.read_bytes() if output.is_file() else b''
    return {'ok': r.returncode == 0 and bool(data), 'exit': r.returncode,
            'bytes': len(data), 'sha256': digest(data) if data else None,
            'stdout': r.stdout[:1024].decode('utf-8', 'backslashreplace'),
            'stderr': r.stderr[:1024].decode('utf-8', 'backslashreplace')}

def main():
    ap = argparse.ArgumentParser(description=__doc__)
    for name in ('baseline-tree','draft-tree','baseline','draft','output-dir'):
        ap.add_argument('--'+name, type=Path, required=True)
    ap.add_argument('--only', choices=None, help='limit to one manifest fixture, for controls')
    args = ap.parse_args()
    oldtree, newtree = args.baseline_tree.resolve(strict=True), args.draft_tree.resolve(strict=True)
    baseline, draft = args.baseline.resolve(strict=True), args.draft.resolve(strict=True)
    if os.path.samefile(baseline, draft):
        ap.error('compiler paths must be distinct')
    manifest_path = newtree / 'rewrite/continuation/u16-expanded-manifest-20261110.json'
    manifest_bytes = manifest_path.read_bytes()
    manifest = json.loads(manifest_bytes)
    if args.only and args.only not in manifest['fixtures']:
        ap.error('--only must name a manifest fixture')
    args.output_dir.mkdir(parents=True, exist_ok=False)
    out = args.output_dir.resolve()
    lock = open('/data/zbe-coordination/full-verification.lock', 'a')
    try:
        fcntl.flock(lock, fcntl.LOCK_EX)
    except BlockingIOError:
        ap.exit(2, 'verification lock busy\n')
    affinity = sorted(os.sched_getaffinity(0))[:2]
    os.sched_setaffinity(0, affinity)
    old_soft, old_hard = resource.getrlimit(resource.RLIMIT_AS)
    cap = LIMIT if old_hard == resource.RLIM_INFINITY else min(LIMIT, old_hard)
    resource.setrlimit(resource.RLIMIT_AS, (cap, cap))
    resource.setrlimit(resource.RLIMIT_CORE, (0, 0))
    verify((oldtree, newtree), manifest)
    tmp = out / 'tmp'; tmp.mkdir()
    env = {'PATH': os.defpath, 'LC_ALL': 'C', 'TMPDIR': str(tmp)}
    results = []
    names = [args.only] if args.only else list(manifest['fixtures'])
    for name in names:
        for mask in range(8):
            flags = [f for bit, f in enumerate(FLAGS) if mask & (1 << bit)]
            case = out / f'{name}-{mask}'; case.mkdir()
            src = newtree / 'rewrite/src/fixtures' / name
            a = compile_one(baseline, flags, src, case/'old.s', env)
            b = compile_one(draft, flags, src, case/'new.s', env)
            equal = a['ok'] and b['ok'] and (case/'old.s').read_bytes() == (case/'new.s').read_bytes()
            results.append({'fixture': name, 'mask': mask, 'flags': flags, 'baseline': a, 'draft': b, 'equal': equal})
            if not equal:
                print('FAIL', name, mask, json.dumps({'baseline':a, 'draft':b}), flush=True)
    verify((oldtree, newtree), manifest)
    obj = {'manifest_sha256':digest(manifest_bytes), 'baseline_commit':manifest['baseline'],
           'draft_commit':manifest['draft'], 'baseline_binary':str(baseline), 'baseline_binary_sha256':digest(baseline.read_bytes()),
           'draft_binary':str(draft), 'draft_binary_sha256':digest(draft.read_bytes()),
           'affinity':affinity, 'address_space_limit':cap, 'fixture_count':len(names),
           'excluded':manifest['excluded'], 'cases':results}
    (out/'results.json').write_text(json.dumps(obj, indent=2)+'\n')
    count = sum(r['equal'] for r in results)
    print(f'Result: {count}/{len(results)} byte comparisons; {len(results)-count} failures; results={out}/results.json', flush=True)
    return 0 if count == len(results) else 1

if __name__ == '__main__':
    sys.exit(main())
