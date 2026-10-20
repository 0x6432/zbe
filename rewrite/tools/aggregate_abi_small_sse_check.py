#!/usr/bin/env python3
"""Bounded SSE/mixed record transport: independent C/ASM, guard and prior-ASM oracles."""
from pathlib import Path
import argparse
import hashlib
import json
import platform
import re
import resource
import subprocess
import tempfile


def digest(data):
    return hashlib.sha256(data).hexdigest()


def position(text, prefix):
    if not prefix:
        return text
    first = text.index('export function ')
    side = text.index('\nfunction ')+1
    return text[:first]+text[side:]+text[first:side]


def fragment(text, name):
    head = '.globl '+name+'\n.type '+name+', @function\n'
    tail = '.size '+name+', .-'+name+'\n'
    start = text.index(head)
    return text[start:text.index(tail, start)+len(tail)].encode()


def main():
    root = Path(__file__).resolve().parents[1]
    fixtures = root/'src/fixtures'
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--compiler', type=Path, default=root/'zig-out/bin/zbe-native')
    p.add_argument('--baseline-compiler', type=Path)
    p.add_argument('--cc', default='cc')
    p.add_argument('--check', action='store_true')
    p.add_argument('--mutation-controls', action='store_true')
    for flag in ('fold-integers', 'reuse-stack-homes', 'callee-saved-homes'):
        p.add_argument('--'+flag, action='store_true')
    a = p.parse_args()
    oracle = json.loads((fixtures/'aggregate_abi_small_sse_oracle.json').read_text())
    if oracle['baseline_commit'] != '4dac59b883395db6714e73f07ea618f5b4fe84d0':
        raise SystemExit('Wrong prior INTEGER compiler oracle provenance')
    for name, expected in oracle['fixture_sha256'].items():
        if digest((fixtures/name).read_bytes()) != expected:
            raise SystemExit('Changed reviewed SSE fixture: '+name)
    for name, expected in oracle['whole_record'].items():
        if digest((fixtures/name).read_bytes()) != expected['source_sha256'] or set(expected['assembly_sha256']) != {str(i) for i in range(8)}:
            raise SystemExit('Changed/incomplete immutable prior record fixture oracle: '+name)
    if a.check:
        print('Independent SSE/mixed C+ASM schemas/fixtures and prior4dac whole-record/matched-scalar oracles checked')
        return
    if platform.system() != 'Linux' or platform.machine() not in ('x86_64', 'amd64'):
        raise SystemExit('SSE/mixed execution requires Linux AMD64; no pass claimed')
    resource.setrlimit(resource.RLIMIT_CORE, (0, 0))
    mask = int(a.fold_integers)+2*int(a.reuse_stack_homes)+4*int(a.callee_saved_homes)
    flags = ['--'+f for f in ('fold-integers', 'reuse-stack-homes', 'callee-saved-homes') if getattr(a, f.replace('-', '_'))]
    compiler = [str(a.compiler.resolve()), *flags]
    with tempfile.TemporaryDirectory(prefix='aggregate_abi_small_sse_') as directory:
        path = Path(directory)
        il, asm, exe = path/'input.ssa', path/'output.s', path/'run'
        for name, expected in oracle['whole_record'].items():
            subprocess.run([*compiler, str(fixtures/name), str(asm)], check=True, timeout=90)
            actual = asm.read_bytes()
            if digest(actual) != expected['assembly_sha256'][str(mask)]:
                raise SystemExit('Whole prior INTEGER/MEMORY assembly changed: '+name)
            if a.baseline_compiler:
                prior = path/'prior.s'
                subprocess.run([str(a.baseline_compiler.resolve()), *flags, str(fixtures/name), str(prior)], check=True, timeout=90)
                if actual != prior.read_bytes():
                    raise SystemExit('Actual prior4dac whole-record bytes differ: '+name)
        print('2 exact whole prior4dac INTEGER/MEMORY fixture assemblies passed')
        for prefix in (False, True):
            key = 'prefix' if prefix else 'suffix'
            il.write_text(position((fixtures/'aggregate_abi_small_sse_mixed.ssa').read_text(), prefix))
            subprocess.run([*compiler, str(il), str(asm)], check=True, timeout=90)
            mixed = asm.read_text()
            if a.baseline_compiler:
                il.write_text(position((fixtures/'aggregate_abi_small_sse_scalar_reference.ssa').read_text(), prefix))
                prior = path/'prior.s'
                subprocess.run([str(a.baseline_compiler.resolve()), *flags, str(il), str(prior)], check=True, timeout=90)
            for symbol, expected in oracle['matched_fragments'][key][str(mask)].items():
                actual = fragment(mixed, symbol)
                if digest(actual) != expected:
                    raise SystemExit('Prior4dac SSE-module scalar fragment changed: '+key+' '+symbol)
                if a.baseline_compiler and actual != fragment(prior.read_text(), symbol):
                    raise SystemExit('Actual prior4dac matched scalar fragment differs: '+key+' '+symbol)
        print('8 exact prior4dac matched SSE-module scalar fragments passed (NOT whole mixed modules)')
        subprocess.run([*compiler, str(fixtures/'aggregate_abi_small_sse.ssa'), str(asm)], check=True, timeout=90)
        original = asm.read_text()

        def run_binary(assembly, output, link):
            subprocess.run([a.cc, '-std=c11', '-O2', '-Wall', '-Wextra', '-Werror', '-fPIE', link,
                            str(fixtures/'aggregate_abi_small_sse.c'), str(fixtures/'aggregate_abi_small_sse_shim.s'), str(assembly), '-o', str(output)], check=True, timeout=90)
            dynamic = subprocess.run(['readelf', '-d', str(output)], capture_output=True, check=True, timeout=30).stdout
            if b'TEXTREL' in dynamic:
                raise SystemExit('SSE binary has TEXTREL')
            return subprocess.run([str(output)], capture_output=True, timeout=30)

        for link in ('-pie', '-no-pie'):
            run = run_binary(asm, exe, link)
            if run.returncode:
                raise SystemExit(f'SSE/mixed ABI failure {link}: {run.returncode} {run.stderr.decode(errors="replace")}')
            if run.stdout.strip() != b'1414 independent small SSE checks passed':
                raise SystemExit('Incomplete independent checks: '+repr(run.stdout))
            print(link+': '+run.stdout.decode().strip())

        if a.mutation_controls:
            def body(name):
                start = original.index(name+':\n')
                end = original.index('.size '+name+',', start)
                return start, end, original[start:end]

            mutations = []
            start, end, f4 = body('aggregate_abi_small_sse_ret_F4')
            needle = '\tmovd 0(%r11), %xmm0\n'
            assert f4.count(needle) == 1
            mutations.append(('SSE4-rounded-read', start, end, f4.replace(needle, '\tmovq 0(%r11), %xmm0\n'), -11))
            mutations.append(('arithmetic-quiets-sNaN', start, end, f4.replace(needle, needle+'\taddss %xmm0, %xmm0\n'), None))
            start, end, f12 = body('aggregate_abi_small_sse_ret_F12')
            needle = '\tmovd 8(%r11), %xmm1\n'
            assert f12.count(needle) == 1
            mutations.append(('SSE12-rounded-tail', start, end, f12.replace(needle, '\tmovq 8(%r11), %xmm1\n'), -11))
            mutations.append(('lost-first-SSE-result', start, end, f12.replace(needle, '\tpxor %xmm0, %xmm0\n'+needle), None))
            start, end, f8 = body('aggregate_abi_small_sse_ret_F8')
            needle = '\tmovq 0(%r11), %xmm0\n'
            assert f8.count(needle) == 1
            mutations.append(('packed-floats-wrong-two-XMM', start, end, f8.replace(needle, '\tmovd 0(%r11), %xmm0\n\tmovd 4(%r11), %xmm1\n'), None))
            start, end, si = body('aggregate_abi_small_sse_ret_PSI12')
            needle = '\tmovq $0, %rax\n'
            assert si.count(needle) == 1
            changed = si.replace(needle, '\tmovq $0, %rdx\n').replace('\torq %r10, %rax\n', '\torq %r10, %rdx\n')
            mutations.append(('SI-wrong-RDX-not-RAX', start, end, changed, None))
            for name, pattern, injected, label in [
                ('aggregate_abi_small_sse_roundtrip_PSI12', r'(\tmovq %xmm0, -[0-9]+\(%rbp\)\n)', '\txorl %eax, %eax\n', 'SSE-capture-loses-GP-result'),
                ('aggregate_abi_small_sse_roundtrip_PIS12', r'(\tmovq %rax, -[0-9]+\(%rbp\)\n)', '\tpxor %xmm0, %xmm0\n', 'GP-capture-loses-SSE-result'),
                ('aggregate_abi_small_sse_mutate_F4', r'(\tmovd %xmm0, %r10d\n)', '\tpxor %xmm1, %xmm1\n', 'prologue-clobbers-later-parameter'),
            ]:
                start, end, text = body(name)
                changed, count = re.subn(pattern, lambda match: match[1]+injected, text, count=1)
                assert count == 1
                mutations.append((label, start, end, changed, None))
            for name, before, after, label in [
                ('aggregate_abi_small_sse_probe_sse', '\tmovq %rax, %r9\n', '\tmovq %rax, %r8\n', 'partial-GP-rollback'),
                ('aggregate_abi_small_sse_probe_gp', '\tmovq %rax, %xmm7\n', '\tmovq %rax, %xmm6\n', 'partial-SSE-rollback'),
            ]:
                start, end, text = body(name)
                assert text.count(before) == 1
                mutations.append((label, start, end, text.replace(before, after), None))
            for label, start, end, changed, signal in mutations:
                mutant = path/(label+'.s')
                mutant.write_text(original[:start]+changed+original[end:])
                run = run_binary(mutant, path/label, '-pie')
                if run.returncode == 0 or (signal is not None and run.returncode != signal):
                    raise SystemExit('Runtime mutation not caught: '+label+' '+str(run.returncode))
                print('Runtime mutation caught: '+label+' exit='+str(run.returncode))

        invalid = [
            'type :T=align 16 {s}\nfunction :T $f(l %p){\n@e\nret %p\n}',
            'type :T=align 16 {s 3}\nfunction :T $f(l %p){\n@e\nret %p\n}',
            'type :T=align 32 {d 3}\nfunction :T $f(l %p){\n@e\nret %p\n}',
            'type :T={s 1025}\nfunction :T $f(l %p){\n@e\nret %p\n}',
            'type :T={s}\nfunction :T $f(env %e,l %p){\n@e\nret %p\n}',
            'type :T={s}\nfunction :T $f(l %p,...){\n@e\nret %p\n}',
            'type :T={s}\nfunction w $f(l %p,l %fn){\n@e\n%r =:T call %fn(l %p)\nret 1\n}',
            'type :T={s}\nfunction w $f(l %p){\n@e\n%r =:T call $external(l %p,...)\nret 1\n}',
            'type :T={s}\nfunction w $f(l %p){\n@e\n%r =:T call $external(env %p)\nret 1\n}',
            'type :T=align 16 {s}\nfunction w $f(){\n@e\nret 1\n@dead\n%r =:T call $external()\nret 2\n}',
        ]
        # The three individually approved align16 cases now have independent
        # C/hand-ASM positive coverage. Other boundary expectations are unchanged.
        for index in (0, 1, 9):
            il.write_text(invalid[index])
            subprocess.run([*compiler, str(il), str(asm)], check=True, timeout=90)
        print('3 individually approved align16 native positive upgrades passed')
        invalid = [text for index, text in enumerate(invalid) if index not in (0, 1, 9)]
        for text in invalid:
            il.write_text(text)
            sentinel = b'preserve existing output\n'
            asm.write_bytes(sentinel)
            run = subprocess.run([*compiler, str(il), str(asm)], capture_output=True, timeout=90)
            if run.returncode == 0 or b'UnsupportedAggregateAbi' not in run.stderr or asm.read_bytes() != sentinel:
                raise SystemExit('SSE/mixed refusal or pre-write sentinel changed: '+repr(text)+' '+repr(run.stderr))
            asm.unlink()
            run = subprocess.run([*compiler, str(il), str(asm)], capture_output=True, timeout=90)
            if run.returncode == 0 or b'UnsupportedAggregateAbi' not in run.stderr or asm.exists():
                raise SystemExit('Refusal created output: '+repr(text))
        print(f'{len(invalid)*2} explicit SSE/mixed refusal/pre-write output checks passed')


if __name__ == '__main__':
    main()
