#!/usr/bin/env python3
"""Bounded native SysV MEMORY interoperability, guards and prior scalar oracles."""
from pathlib import Path
import argparse
import hashlib
import json
import platform
import resource
import subprocess
import tempfile


def digest(data):
    return hashlib.sha256(data).hexdigest()


def fragment(text, name):
    head = ('.globl '+name+'\n.type '+name+', @function\n').encode()
    tail = ('.size '+name+', .-'+name+'\n').encode()
    start = text.index(head)
    end = text.index(tail, start)+len(tail)
    return text[start:end]


def main():
    root = Path(__file__).resolve().parents[1]
    fixtures = root/'src/fixtures'
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--compiler', type=Path, default=root/'zig-out/bin/zbe-native')
    p.add_argument('--baseline-compiler', type=Path)
    p.add_argument('--cc', default='cc')
    p.add_argument('--check', action='store_true')
    p.add_argument('--mutation-controls', action='store_true', help='Actually link/run assembly-level copy/return defects; never edits compiler sources')
    for flag in ('fold-integers', 'reuse-stack-homes', 'callee-saved-homes'):
        p.add_argument('--'+flag, action='store_true')
    a = p.parse_args()
    oracle = json.loads((fixtures/'aggregate_abi_native_scalar_oracle.json').read_text())
    if oracle['baseline_commit'] != '45ec2c9c025c7d5ae6346cb641d99767b8f930cc':
        raise SystemExit('Incorrect prior scalar oracle provenance')
    for name, expected in oracle['whole_scalar'].items():
        if digest((fixtures/name).read_bytes()) != expected['source_sha256'] or set(expected['assembly_sha256']) != {str(i) for i in range(8)}:
            raise SystemExit('Changed/incomplete prior scalar oracle: '+name)
    for name, key in (('aggregate_abi_native_mixed.ssa', 'mixed_source_sha256'), ('aggregate_abi_native_scalar_reference.ssa', 'mixed_reference_sha256')):
        if digest((fixtures/name).read_bytes()) != oracle[key]:
            raise SystemExit('Changed explicit mixed/reference source')
    if a.check:
        print('8 prior45ec scalar sources/64 whole-assembly +32 matched-fragment expectations checked')
        return
    if platform.system() != 'Linux' or platform.machine() not in ('x86_64', 'amd64'):
        raise SystemExit('Native MEMORY tests require Linux AMD64; no pass claimed')
    resource.setrlimit(resource.RLIMIT_CORE, (0, 0))
    flags = ['--'+f for f in ('fold-integers', 'reuse-stack-homes', 'callee-saved-homes') if getattr(a, f.replace('-', '_'))]
    mask = int(a.fold_integers)+2*int(a.reuse_stack_homes)+4*int(a.callee_saved_homes)
    compiler = [str(a.compiler.resolve()), *flags]
    with tempfile.TemporaryDirectory(prefix='aggregate_abi_native_') as directory:
        path = Path(directory)
        asm, exe, il = path/'output.s', path/'run', path/'input.ssa'
        identities = 0
        for name, expected in oracle['whole_scalar'].items():
            subprocess.run([*compiler, str(fixtures/name), str(asm)], check=True, timeout=90)
            actual = asm.read_bytes()
            if digest(actual) != expected['assembly_sha256'][str(mask)]:
                raise SystemExit('Whole scalar assembly changed: '+name)
            if a.baseline_compiler:
                prior = path/'prior.s'
                subprocess.run([str(a.baseline_compiler.resolve()), *flags, str(fixtures/name), str(prior)], check=True, timeout=90)
                if prior.read_bytes() != actual:
                    raise SystemExit('Actual prior45ec whole scalar comparison failed: '+name)
            identities += 1
        subprocess.run([*compiler, str(fixtures/'aggregate_abi_native_mixed.ssa'), str(asm)], check=True, timeout=90)
        mixed = asm.read_bytes()
        for symbol in oracle['symbols']:
            if digest(fragment(mixed, symbol)) != oracle['mixed_fragments'][str(mask)][symbol]:
                raise SystemExit('Matched unaffected scalar function changed: '+symbol)
        # NOT a whole mixed-module differential: the prior compiler refuses it.
        # Unit tests assert exact symbol IDs/string order + function ordinals.
        print(f'{identities} exact prior whole scalar assemblies and4 precise matched mixed fragments passed')
        subprocess.run([*compiler, str(fixtures/'aggregate_abi_native.ssa'), str(asm)], check=True, timeout=90)
        original = asm.read_bytes()

        def link_run(assembly, output, link):
            subprocess.run([a.cc, '-std=c11', '-O2', '-Wall', '-Wextra', '-Werror', '-fPIE', link,
                            str(fixtures/'aggregate_abi_native.c'), str(fixtures/'aggregate_abi_native_shim.s'), str(assembly), '-o', str(output)], check=True, timeout=90)
            dynamic = subprocess.run(['readelf', '-d', str(output)], capture_output=True, check=True, timeout=30).stdout
            if b'TEXTREL' in dynamic:
                raise SystemExit('Native MEMORY binary has TEXTREL')
            return subprocess.run([str(output)], capture_output=True, timeout=30)

        for link in ('-pie', '-no-pie'):
            run = link_run(asm, exe, link)
            if run.returncode != 0:
                raise SystemExit('Native C/ASM/guard-page checks failed '+str(run.returncode)+' '+run.stderr.decode(errors='replace'))
            print(link+': '+run.stdout.decode().strip())
        if a.mutation_controls:
            # Compiled machine-code defects, including real guard faults. Each
            # control must fail runtime checks, not compilation or link checks.
            text = original.decode()
            start = text.index('aggregate_abi_native_send17:')
            end = text.index('.size aggregate_abi_native_send17,', start)
            body = text[start:end]
            needle = '\tmovl $17, %ecx\n\trep movsb\n'
            if body.count(needle) != 1:
                raise SystemExit('Copy controls did not locate exact production17-byte copy')
            controls = {
                'rounded-argument-copy': text[:start]+body.replace(needle, '\tmovl $24, %ecx\n\trep movsb\n')+text[end:],
                'omitted-argument-copy': text[:start]+body.replace(needle, '\tmovb $0, (%rdi)\n\tmovl $0, %ecx\n\trep movsb\n')+text[end:],
            }
            start = text.index('aggregate_abi_native_ret17:')
            end = text.index('.size aggregate_abi_native_ret17,', start)
            body = text[start:end]
            if body.count(needle) != 1:
                raise SystemExit('Return control missing exact production17-byte copy')
            controls['rounded-return-copy'] = text[:start]+body.replace(needle, '\tmovl $24, %ecx\n\trep movsb\n')+text[end:]
            # Wrong advancedRDI return is an ABI defect, not a memory-copy test.
            line = [x for x in body.splitlines() if x.startswith('\tmovq -') and x.endswith(', %rax')][-1]
            controls['advanced-rdi-return'] = text[:start]+body.replace(line, '\tmovq %rdi, %rax')+text[end:]
            for name, mutant in controls.items():
                broken = path/(name+'.s')
                broken.write_text(mutant)
                run = link_run(broken, exe, '-pie')
                if run.returncode == 0:
                    raise SystemExit('Runtime mutation control survived: '+name)
                if name.startswith('rounded-') and run.returncode != -11:
                    raise SystemExit('Rounded-copy control did not produce the expected real guard-page fault: '+name)
                print('Runtime defect caught: '+name+' exit='+str(run.returncode))
        # Approved INTEGER16 upgrade: its runtime path is independently checked
        # by aggregate_abi_small_integer_check.py, not a blanket allowed exit.
        il.write_text('type :T={b 16}\nfunction $f(:T %p){\n@e\nret\n}')
        subprocess.run([*compiler, str(il), str(asm)], check=True, timeout=45)
        print('1 newly eligible INTEGER16 signature emits successfully')
        cases = [
            'type :T={b 4097}\nfunction $f(:T %p){\n@e\nret\n}',
            'type :T=align 32 {b 17}\nfunction $f(:T %p){\n@e\nret\n}',
            'type :T=align 64 {b 17}\nfunction $f(:T %p){\n@e\nret\n}',
        ]
        prefix = 'type :T={b 17}\n'
        cases += [prefix+source for source in (
            'function $f(env %e,:T %p){\n@e\nret\n}',
            'function :T $f(...){\n@e\nret 0\n}',
            'function $f(){\n@e\ncall $ext(env 0,:T 0)\nret\n}',
            'function $f(){\n@e\ncall $ext(...,:T 0)\nret\n}',
            'function $f(){\n@e\ncall 0(:T 0)\nret\n}',
            'function $f(){\n@e\n%x =:T copy 0\nret\n}',
            'function $f(){\n@e\n%x =:T add 0,0\nret\n}',
            'function $f(){\n@e\njmp @b\n@b\n%x =:T phi @e 0\nret\n}',
        )]
        cases += ['type :A={b 17}\ntype :B={b 17}\nfunction $f(){\n@e\ncall $g(:A 0)\nret\n}\nfunction $g(:B %p){\n@e\nret\n}',
                  'function w $f(){\n@e\nret 1\n@dead\ncall $bad(:Missing 0)\nret 0\n}']
        # Precisely the newly approved nonvariadic ENV/indirect cases are
        # positive compilation checks, not silently dropped refusals. Their
        # execution is independently covered by aggregate_abi_call_targets_check.
        eligible_call_targets = [source for source in cases
                                 if '...' not in source and
                                 ('env ' in source or 'call %' in source or 'call 0(' in source)]
        for source in eligible_call_targets:
            il.write_text(source)
            subprocess.run([*compiler, str(il), str(asm)], check=True, timeout=90)
            if not asm.read_bytes().startswith(b'.text'):
                raise SystemExit('Eligible call target did not emit native code')
        cases = [source for source in cases if source not in eligible_call_targets]
        for source in cases:
            il.write_text(source)
            for exists in (False, True):
                asm.unlink(missing_ok=True)
                if exists:
                    asm.write_text('preserve-native-ABI-output')
                run = subprocess.run([*compiler, str(il), str(asm)], capture_output=True, timeout=45)
                if run.returncode == 0 or (exists and asm.read_text() != 'preserve-native-ABI-output') or (not exists and asm.exists()):
                    raise SystemExit('Native ABI boundary refusal changed output or succeeded')
        print(str(2*len(cases))+' unsupported/malformed native refusal output checks passed')


if __name__ == '__main__':
    main()
