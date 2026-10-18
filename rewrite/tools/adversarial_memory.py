#!/usr/bin/env python3
"""Run isolated memory tests against an immutable COPY of any rewrite worktree.
Never writes the candidate. Each run gets a new snapshot and local build cache;
`zig test`, not a compile-only build, must run and report all three tests passed.
Mutation controls alter only disposable copies, never production source.
"""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import tempfile
import time

HERE = Path(__file__).resolve()
OWNER = HERE.parents[2]
TEST = HERE.parents[1] / 'src/adversarial_memory_test.zig'
FIXTURE = HERE.parents[1] / 'src/fixtures/adversarial_escaped_stack.ssa'
MUTATIONS = {
    'undefined_source_accepted': ('try source.requireInitialized();', '// mutation: skip source initialization check'),
    'partial_overlap_accepted': ('if (src != dst and distance < count) return error.PartialMemoryOverlap;', '_ = distance; // mutation: allow partial overlap'),
    'destination_not_defined': ('destination.define();', '// mutation: omit destination initialization'),
    'dead_objects_retained': ('while (self.objects.items.len > object_count) self.objects.pop().?.deinit(self.allocator);', 'if (false) while (self.objects.items.len > object_count) self.objects.pop().?.deinit(self.allocator);'),
}


def digest_tree(root):
    return {str(p.relative_to(root)): hashlib.sha256(p.read_bytes()).hexdigest()
            for p in sorted(root.rglob('*')) if p.is_file()}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source', type=Path, default=OWNER)
    parser.add_argument('--zig', required=True)
    parser.add_argument('--optimize', choices=['Debug', 'ReleaseSafe', 'ReleaseFast'], default='Debug')
    parser.add_argument('--mutations', action='store_true')
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    source = args.source.resolve() / 'rewrite/src'
    before = digest_tree(source)
    workspace = OWNER / '.zig-cache'
    workspace.mkdir(exist_ok=True)
    snapshot = Path(tempfile.mkdtemp(prefix='adversarial_memory-', dir=workspace))
    clean = snapshot / 'clean'
    shutil.copytree(source, clean)
    copied = digest_tree(clean)
    if before != copied or before != digest_tree(source):
        raise SystemExit('Source changed during snapshot; no test claim made. Retry when stable.')
    shutil.copy2(TEST, clean / TEST.name)
    shutil.copy2(FIXTURE, clean / 'fixtures' / FIXTURE.name)
    args.output.mkdir(parents=True, exist_ok=True)
    revision = subprocess.run(['git', '-C', str(args.source), 'rev-parse', 'HEAD'], text=True, capture_output=True, check=True).stdout.strip()
    status = subprocess.run(['git', '-C', str(args.source), 'status', '--short'], text=True, capture_output=True, check=True).stdout
    results = []
    for name in ['baseline'] + (list(MUTATIONS) if args.mutations else []):
        tree = clean
        if name != 'baseline':
            tree = snapshot / name
            shutil.copytree(clean, tree, ignore=shutil.ignore_patterns('.local-cache'))
            file = tree / 'evaluation_memory.zig'
            old, new = MUTATIONS[name]
            text = file.read_text()
            if text.count(old) != 1:
                raise SystemExit(f'Mutation {name} no longer matches exactly once; no mutation claim made.')
            file.write_text(text.replace(old, new))
        command = [args.zig, 'test', str(tree / TEST.name), '--test-filter', 'adversarial_', '-O', args.optimize,
                   '--cache-dir', str(tree / '.local-cache')]
        start = time.monotonic()
        run = subprocess.run(command, text=True, capture_output=True)
        output = run.stdout + run.stderr
        (args.output / f'{name}.log').write_text(output)
        compiled_and_ran = ('1/3 adversarial_memory_test.test.adversarial_memory' in output
                            and '3/3 adversarial_memory_test.test.adversarial_memory' in output)
        passed = run.returncode == 0 and compiled_and_ran and 'All 3 tests passed.' in output
        # A compiler error is NOT an effective mutation control.
        killed = run.returncode != 0 and compiled_and_ran and 'FAIL (' in output
        accepted = passed if name == 'baseline' else killed
        result = dict(name=name, command=command, returncode=run.returncode,
                      compiled_and_ran=compiled_and_ran, passed=passed, killed=killed,
                      accepted=accepted, elapsed_seconds=round(time.monotonic() - start, 3))
        results.append(result)
        print(f'{name}: {"PASS" if accepted else "FAIL"} ({result["elapsed_seconds"]}s)', flush=True)
    unchanged = before == digest_tree(source)
    report = dict(source=str(args.source.resolve()), revision=revision, git_status=status,
                  optimize=args.optimize, source_sha256=before,
                  test_sha256=hashlib.sha256(TEST.read_bytes()).hexdigest(),
                  fixture_sha256=hashlib.sha256(FIXTURE.read_bytes()).hexdigest(),
                  snapshot=str(snapshot), source_unchanged=unchanged, results=results)
    (args.output / 'result.json').write_text(json.dumps(report, indent=2) + '\n')
    if not unchanged:
        print('Candidate changed during run: results identify only the recorded snapshot.', flush=True)
    return 0 if unchanged and all(r['accepted'] for r in results) else 1


if __name__ == '__main__':
    raise SystemExit(main())
