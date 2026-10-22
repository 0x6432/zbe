#!/usr/bin/env python3
"""Opaque MEMORY ABI: independent ASM/real C, byte guards, actual union identity.
Caller must serialize compiler/native execution with the shared verification lock.
"""
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


def main():
    root = Path(__file__).resolve().parents[1]
    fixtures = root/'src/fixtures'
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--compiler', type=Path, default=root/'zig-out/bin/zbe-native')
    p.add_argument('--baseline-compiler', type=Path)
    p.add_argument('--cc', default='cc')
    p.add_argument('--check', action='store_true')
    p.add_argument('--mutation-controls', action='store_true')
    for f in ('fold-integers', 'reuse-stack-homes', 'callee-saved-homes'):
        p.add_argument('--'+f, action='store_true')
    a = p.parse_args()
    oracle = json.loads((fixtures/'aggregate_abi_opaque_oracle.json').read_text())
    assert oracle['base_commit'] == 'c09b74646b04e0ade3d84aebdcdda59fef56819e'
    assert oracle['base_tree'] == '2b68fd71e05b74d116e8a65bb02d7c6e4d345222'
    assert len(oracle['whole_modules']) == 12
    for name, row in oracle['whole_modules'].items():
        assert digest((fixtures/name).read_bytes()) == row['source_sha256'], name
        assert set(row['assembly_sha256']) == set(map(str, range(8))), name
    for name, expected in oracle['fixture_sha256'].items():
        assert digest((fixtures/name).read_bytes()) == expected, name
    if a.check:
        print('Opaque independent ASM/real-C/guard fixture hashes and12 actual published union all8-option oracles checked')
        return
    if platform.system() != 'Linux' or platform.machine() not in ('x86_64', 'amd64'):
        raise SystemExit('Opaque native probes require Linux AMD64; no pass claimed')
    resource.setrlimit(resource.RLIMIT_CORE, (0, 0))
    flags = ['--'+f for f in ('fold-integers', 'reuse-stack-homes', 'callee-saved-homes') if getattr(a, f.replace('-', '_'))]
    mask = int(a.fold_integers)+2*int(a.reuse_stack_homes)+4*int(a.callee_saved_homes)
    compiler = [str(a.compiler.resolve()), *flags]
    with tempfile.TemporaryDirectory(prefix='aggregate_opaque_') as d:
        path = Path(d)
        il, asm, exe = path/'input.ssa', path/'output.s', path/'run'
        unused = 'type :UnusedOpaque=align 64 {18446744073709551615}\n'
        for name, row in oracle['whole_modules'].items():
            source = (fixtures/name).read_text()
            for text in (source, unused+source, source+'\n'+unused):
                il.write_text(text)
                subprocess.run([*compiler, str(il), str(asm)], check=True, timeout=90)
                assert digest(asm.read_bytes()) == row['assembly_sha256'][str(mask)], name
            if a.baseline_compiler:
                il.write_text(source)
                subprocess.run([str(a.baseline_compiler.resolve()), *flags, str(il), str(path/'prior.s')], check=True, timeout=90)
                assert digest((path/'prior.s').read_bytes()) == row['assembly_sha256'][str(mask)], name
        print('12 exact whole union-baseline modules +24 unused opaque prefix/suffix identities passed; no used-opaque whole-module parity claimed')
        subprocess.run([*compiler, str(fixtures/'aggregate_abi_opaque.ssa'), str(asm)], check=True, timeout=90)
        original = asm.read_text()

        def run(assembly, output, link):
            subprocess.run([a.cc, '-std=c11', '-O2', '-Wall', '-Wextra', '-Werror', '-fPIE', link,
                            str(fixtures/'aggregate_abi_opaque.c'), str(fixtures/'aggregate_abi_opaque_shim.s'), str(assembly), '-o', str(output)], check=True, timeout=90)
            dyn = subprocess.run(['readelf', '-d', str(output)], check=True, capture_output=True, timeout=30).stdout
            assert b'TEXTREL' not in dyn
            return subprocess.run([str(output)], capture_output=True, timeout=90)

        for link in ('-pie', '-no-pie'):
            result = run(asm, exe, link)
            if result.returncode:
                raise SystemExit('Opaque native failed '+link+': '+str(result.returncode)+' '+result.stderr.decode(errors='replace'))
            print(result.stdout.decode(), end='')
        print('2 opaque PIE/non-PIE independent ASM/packed C pressure/continuation/readonly-byte-guard link modes passed')
        invalid = [
            'type :O={1}', 'type :O=align 8 {0}', 'type :O=align 8 {-1}',
            'type :O=align 8 {18446744073709551616}', 'type :O=align 8 {1,}',
            'type :O=align 8 {1 b}', 'type :O=align 8 {1 2}',
            'type :O=align 3 {1}', 'type :O=align 8 {}',
            'export type :O=align 8 {1}', 'type :"O"=align 8 {1}',
            'type :O=align 8 {1}\ntype :O=align 8 {1}',
            'type :O=align 8 {1}\nfunction $f(){\n@e\n%x =:O vaarg 0\nret\n}',
            'type :O=align 8 {1}\nfunction $f(env %e,...){\n@e\ncall $ext(:O 0)\nret\n}',
        ]
        sites = [
            'function :S $f(:S %p){\n@e\nret %p\n}',
            'function $f(:S %p){\n@e\nret\n}',
            'function $f(){\n@e\ncall $ext(:S 0)\nret\n}',
            'function $f(){\n@e\ncall 0(:S 0)\nret\n}',
            'function $f(){\n@e\nret\n@dead\n%r =:S call $ext()\nret\n}',
        ]
        for definition in ('type :S={:O}', 'type :T={:O}\ntype :S={{w}{:T}}', 'type :S=align 32 {1}', 'type :S=align 8 {4097}'):
            invalid.extend('type :O=align 16 {1}\n'+definition+'\n'+site for site in sites)
        for text in invalid:
            il.write_text(text)
            for exists in (False, True):
                asm.unlink(missing_ok=True)
                if exists:
                    asm.write_text('opaque-output-sentinel')
                result = subprocess.run([*compiler, str(il), str(asm)], capture_output=True, timeout=30)
                assert result.returncode != 0, text
                assert (asm.read_text() == 'opaque-output-sentinel') if exists else not asm.exists(), text
        print(str(2*len(invalid))+' malformed/unsupported opaque output-preservation checks passed')
        if a.mutation_controls:
            # Deliberate machine-code defects, never weakened input/expected values.
            # Every control must assemble/link and then fail at runtime.
            controls = [
                ('missing-hidden-RDI-save', 'opaque_A1_id', '\tmovq %rdi, -', 'hidden'),
                ('wrong-AL', 'opaque_A1_var', '\tmovb $1, %al', '\tmovb $0, %al'),
                ('advanced-result-RAX', 'opaque_A1_id', '\tret\n', '\taddq $1, %rax\n\tret\n'),
                ('lost-private-argument-copy', 'opaque_A1_private', '\tmovq %rax, %rdi\n', 'alias'),
                ('private-result-pad-aliases-source', 'opaque_A1_direct', '', 'padalias'),
                ('late-ENV-load', 'opaque_A1_indirect', '\tcall *%r11\n', '\txorq %rax, %rax\n\tcall *%r11\n'),
                ('late-indirect-target', 'opaque_A1_indirect', '\tcall *%r11\n', '\txorq %r11, %r11\n\tcall *%r11\n'),
            ]
            for name, symbol, old, new in controls:
                start = original.index(symbol+':\n')
                end = original.index('.size '+symbol+',', start)
                body = original[start:end]
                if new == 'hidden':
                    import re
                    body, count = re.subn(r'\tmovq %rdi, -\d+\(%rbp\)\n', '\txorq %rdi, %rdi\n', body, count=1)
                    assert count == 1
                elif new == 'padalias':
                    import re
                    body, count = re.subn(r'\tleaq -\d+\(%rbp\), %rdi\n', '\tmovq opaque_source(%rip), %rdi\n', body, count=1)
                    assert count == 1
                elif new == 'alias':
                    # Mutation uses original source rather than private incoming object.
                    # The original source is read-only, so the first store must fault.
                    import re
                    # Replace the actual store destination, not a padding-only byte.
                    needle = '\tmovb %al, (%r10)'
                    assert needle in body
                    body = body.replace(needle, '\tmovq opaque_source(%rip), %r10\n'+needle, 1)
                else:
                    assert old in body, (name, body)
                    body = body.replace(old, new, 1)
                bad = path/(name+'.s')
                bad.write_text(original[:start]+body+original[end:])
                result = run(bad, path/name, '-pie')
                assert result.returncode != 0, 'Ineffective runtime control: '+name
                print('Real compiled runtime defect caught: '+name+' exit='+str(result.returncode))


if __name__ == '__main__':
    main()
