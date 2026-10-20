#!/usr/bin/env python3
"""Ineligible record ABI metadata refuses; immutable scalar bytes stay exact."""
from pathlib import Path
import argparse
import hashlib
import json
import platform
import subprocess
import tempfile


def digest(data):
    return hashlib.sha256(data).hexdigest()


def main():
    root = Path(__file__).resolve().parents[1]
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--compiler', type=Path, default=root/'zig-out/bin/zbe-native')
    parser.add_argument('--baseline-compiler', type=Path)
    parser.add_argument('--check', action='store_true', help='Check immutable pre-change scalar oracle inputs only')
    for flag in ('fold-integers', 'reuse-stack-homes', 'callee-saved-homes'):
        parser.add_argument('--'+flag, action='store_true')
    args = parser.parse_args()
    oracle = json.loads((root/'src/fixtures/aggregate_abi_representation_scalar_oracle.json').read_text())
    if oracle['baseline_tree'] != '86799a806d58b871bcbb23e3a5b6a1bf46007b66':
        raise SystemExit('Wrong scalar byte-identity oracle provenance')
    for name, expected in oracle['fixtures'].items():
        if digest((root/'src/fixtures'/name).read_bytes()) != expected['source_sha256']:
            raise SystemExit('Scalar oracle source changed: '+name)
        if set(expected['assembly_sha256']) != {str(i) for i in range(8)} or any(len(x) != 64 for x in expected['assembly_sha256'].values()):
            raise SystemExit('Incomplete eight-mode scalar oracle')
    if args.check:
        print('2 immutable pre-change scalar oracle sources and 16 mode expectations verified')
        return
    if platform.system() != 'Linux' or platform.machine() not in ('x86_64', 'amd64'):
        raise SystemExit('Scalar assembly checks require Linux AMD64; no result claimed')
    flags = ['--'+f for f in ('fold-integers', 'reuse-stack-homes', 'callee-saved-homes') if getattr(args, f.replace('-', '_'))]
    mask = args.fold_integers + 2*args.reuse_stack_homes + 4*args.callee_saved_homes
    compiler = [str(args.compiler.resolve()), *flags]
    prefix = 'type :T = { b }\ntype :Normal = { w }\n'
    positive = [
        (root/'src/fixtures/aggregate_abi_representation_metadata.ssa').read_text(),
        prefix+'function $f(:T %p) {\n@e\nret\n}',
        prefix+'function :T $f() {\n@e\nret 0\n}',
        prefix+'function $f() {\n@e\n%p =:T call $external()\nret\n}',
        prefix+'function $f() {\n@e\ncall $external(:T 0)\nret\n}',
        prefix+'function $f() {\n@e\ncall $external(env 0, :T 0)\nret\n}',
        prefix+'function $f() {\n@e\ncall $external(..., :T 0)\nret\n}',
        prefix+'function $f(l %target) {\n@e\ncall %target(:T 0)\nret\n}',
        prefix+'function w $f() {\n@e\nret 42\n@dead\ncall $external(:T 0)\nret 0\n}',
        'type :Over = align 64 { l 3 }\nfunction $f(:Over %p, ...) {\n@e\nret\n}',
    ]
    negative = [prefix+text for text in (
        'function $f() {\n@e\n%p =:T copy 0\nret\n}',
        'function $f() {\n@e\n%p =:T add 0, 0\nret\n}',
        'function $f() {\n@e\njmp @n\n@n\n%p =:T phi @e 0\nret\n}',
        'data $x = { :T 0 }',
        'function :Missing $f() {\n@e\nret 0\n}',
        'function $f() {\n@e\ncall $external(env 0, ..., :T 0)\nret\n}',
    )]
    with tempfile.TemporaryDirectory(prefix='aggregate_abi_representation_') as directory:
        path = Path(directory)
        il, asm, before = path/'input.ssa', path/'output.s', path/'baseline.s'
        identity = 0
        for name, expected in oracle['fixtures'].items():
            source = (root/'src/fixtures'/name).read_text()
            baseline = None
            if args.baseline_compiler:
                il.write_text(source)
                subprocess.run([str(args.baseline_compiler.resolve()), *flags, str(il), str(before)], check=True, timeout=90)
                baseline = before.read_bytes()
                if digest(baseline) != expected['assembly_sha256'][str(mask)]:
                    raise SystemExit('Supplied prior compiler differs from immutable scalar oracle')
            for text in (source, prefix+source):
                il.write_text(text)
                subprocess.run([*compiler, str(il), str(asm)], check=True, timeout=90)
                result = asm.read_bytes()
                if digest(result) != expected['assembly_sha256'][str(mask)] or (baseline is not None and result != baseline):
                    raise SystemExit('Scalar assembly changed versus exact pre-change867 oracle: '+name)
                identity += 1
        # Individual plain Tiny signatures/calls (including unreachable calls)
        # become positive native cases. Combined vararg/overaligned
        # metadata and every malformed syntax case remain explicit refusals.
        eligible = [positive[i] for i in (1, 2, 3, 4, 5, 6, 7, 8)]
        unsupported = [positive[i] for i in (0, 9)]
        for text in eligible:
            il.write_text(text)
            subprocess.run([*compiler, str(il), str(asm)], check=True, timeout=45)
        print(f'{len(eligible)} newly eligible Tiny native cases emit; runtime checks live in small INTEGER and call-targets harnesses')
        refused = 0
        for aggregate, cases in ((True, unsupported), (False, negative)):
            for text in cases:
                il.write_text(text)
                for exists in (False, True):
                    asm.unlink(missing_ok=True)
                    if exists:
                        asm.write_text('preserve-aggregate-metadata-output')
                    run = subprocess.run([*compiler, str(il), str(asm)], capture_output=True, timeout=45)
                    if run.returncode == 0 or (aggregate and b'UnsupportedAggregateAbi' not in run.stderr):
                        raise SystemExit('Aggregate metadata executed or lacked explicit refusal: '+run.stderr.decode(errors='replace'))
                    if (exists and asm.read_text() != 'preserve-aggregate-metadata-output') or (not exists and asm.exists()):
                        raise SystemExit('Aggregate metadata/syntax refusal changed output')
                    refused += 1
        print(f'{identity} exact pre-change scalar assembly identities passed')
        print(f'{refused} aggregate ABI/syntax refusal output-preservation checks passed')
        print('Only deferred metadata/syntax refusals and scalar bytes are checked by this harness')


if __name__ == '__main__':
    main()
