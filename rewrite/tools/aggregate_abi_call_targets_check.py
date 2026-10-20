#!/usr/bin/env python3
"""Nonvariadic ENV/indirect aggregate ABI: independent C/ASM, guard and published-prior ASM oracles."""
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
    oracle = json.loads((fixtures/'aggregate_abi_call_targets_oracle.json').read_text())
    if oracle['baseline_commit'] != 'fb66417a0c6ace8383f360d5a6c0729bc3930805':
        raise SystemExit('Wrong prior SSE compiler oracle provenance')
    for name, expected in oracle['fixture_sha256'].items():
        if digest((fixtures/name).read_bytes()) != expected:
            raise SystemExit('Changed reviewed SSE fixture: '+name)
    for name, expected in oracle['whole_record'].items():
        if digest((fixtures/name).read_bytes()) != expected['source_sha256'] or set(expected['assembly_sha256']) != {str(i) for i in range(8)}:
            raise SystemExit('Changed/incomplete immutable prior record fixture oracle: '+name)
    if a.check:
        print('Independent call-target ENV/indirect C+ASM schemas/fixtures and priorfb66417 whole-record/matched-scalar oracles checked')
        return
    if platform.system() != 'Linux' or platform.machine() not in ('x86_64', 'amd64'):
        raise SystemExit('call-target ENV/indirect execution requires Linux AMD64; no pass claimed')
    resource.setrlimit(resource.RLIMIT_CORE, (0, 0))
    mask = int(a.fold_integers)+2*int(a.reuse_stack_homes)+4*int(a.callee_saved_homes)
    flags = ['--'+f for f in ('fold-integers', 'reuse-stack-homes', 'callee-saved-homes') if getattr(a, f.replace('-', '_'))]
    compiler = [str(a.compiler.resolve()), *flags]
    with tempfile.TemporaryDirectory(prefix='aggregate_abi_call_targets_') as directory:
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
                    raise SystemExit('Actual priorfb66417 whole-record bytes differ: '+name)
        print('4 exact whole priorfb66417 INTEGER/SSE/MEMORY fixture assemblies passed')
        for prefix in (False, True):
            key = 'prefix' if prefix else 'suffix'
            il.write_text(position((fixtures/'aggregate_abi_call_targets_mixed.ssa').read_text(), prefix))
            subprocess.run([*compiler, str(il), str(asm)], check=True, timeout=90)
            mixed = asm.read_text()
            if a.baseline_compiler:
                il.write_text(position((fixtures/'aggregate_abi_call_targets_scalar_reference.ssa').read_text(), prefix))
                prior = path/'prior.s'
                subprocess.run([str(a.baseline_compiler.resolve()), *flags, str(il), str(prior)], check=True, timeout=90)
            for symbol, expected in oracle['matched_fragments'][key][str(mask)].items():
                actual = fragment(mixed, symbol)
                if digest(actual) != expected:
                    raise SystemExit('Priorfb66417 align16-module scalar fragment changed: '+key+' '+symbol)
                if a.baseline_compiler and actual != fragment(prior.read_text(), symbol):
                    raise SystemExit('Actual priorfb66417 matched scalar fragment differs: '+key+' '+symbol)
        for prefix in (False, True):
            key = 'prefix' if prefix else 'suffix'
            il.write_text(position((fixtures/'aggregate_abi_call_targets_scalar_reference.ssa').read_text(), prefix))
            subprocess.run([*compiler, str(il), str(asm)], check=True, timeout=90)
            if digest(asm.read_bytes()) != oracle['whole_scalar_reference'][key][str(mask)]:
                raise SystemExit('Whole scalar-only module output changed')
            if a.baseline_compiler:
                subprocess.run([str(a.baseline_compiler.resolve()), *flags, str(il), str(path/'prior.s')], check=True, timeout=90)
                if asm.read_bytes() != (path/'prior.s').read_bytes():
                    raise SystemExit('Actual prior whole scalar module differs')
        print('2 whole scalar-only modules and8 exact priorfb66417 matched ENV/indirect-module scalar fragments passed (NOT whole mixed modules)')
        subprocess.run([*compiler, str(fixtures/'aggregate_abi_call_targets.ssa'), str(asm)], check=True, timeout=90)
        original = asm.read_text()

        def run_binary(assembly, output, link):
            subprocess.run([a.cc, '-std=c11', '-O2', '-Wall', '-Wextra', '-Werror', '-fPIE', link,
                            str(fixtures/'aggregate_abi_call_targets.c'), str(fixtures/'aggregate_abi_call_targets_shim.s'), str(assembly), '-o', str(output)], check=True, timeout=90)
            dynamic = subprocess.run(['readelf', '-d', str(output)], capture_output=True, check=True, timeout=30).stdout
            if b'TEXTREL' in dynamic:
                raise SystemExit('SSE binary has TEXTREL')
            return subprocess.run([str(output)], capture_output=True, timeout=30)

        for link in ('-pie', '-no-pie'):
            run = run_binary(asm, exe, link)
            if run.returncode:
                raise SystemExit(f'call-target ENV/indirect ABI failure {link}: {run.returncode} {run.stderr.decode(errors="replace")}')
            if run.stdout.strip() != b'aggregate call targets 2628 independent assertions passed':
                raise SystemExit('Incomplete independent checks: '+repr(run.stdout))
            print(link+': '+run.stdout.decode().strip())

        if a.mutation_controls:
            def body(symbol):
                start=original.index(symbol+':\n')
                end=original.index('.size '+symbol+',',start)
                return start,end,original[start:end]
            def mutated(symbol, transform):
                start,end,text=body(symbol)
                changed=transform(text)
                if changed==text:raise SystemExit('Inert runtime control: '+symbol)
                return original[:start]+changed+original[end:]
            def relocate_target(text):
                lines=text.splitlines(keepends=True)
                call=next(i for i,line in enumerate(lines) if line=='\tcall *%r11\n')
                group=lines[call-3:call-1]
                if 'movq %rax, %r11' not in group[1]:raise SystemExit('Unexpected late target sequence')
                del lines[call-3:call-1]
                label=next(i for i,line in enumerate(lines) if line.startswith('".Lzbe@'))
                lines[label+1:label+1]=group
                return ''.join(lines)
            def late_env_before_target(text):
                lines=text.splitlines(keepends=True);call=next(i for i,l in enumerate(lines) if l=='\tcall *%r11\n')
                lines[call-3:call]=[lines[call-1],lines[call-3],lines[call-2]]
                return ''.join(lines)
            def late_env_prologue(text):
                lines=text.splitlines(keepends=True)
                first=next(i for i,l in enumerate(lines) if l.startswith('\tmovq %rax, -'))
                save=lines.pop(first)
                lea=next(i for i,l in enumerate(lines) if l.startswith('\tleaq -'))
                lines.insert(lea+1,save)
                return ''.join(lines)
            controls=[
                ('target-parked-before-R11-pack','SS12_env_indirect',relocate_target),
                ('environment-before-target-RAX-load','SS12_env_indirect',late_env_before_target),
                ('environment-load-clobbers-target-R11','SS12_env_indirect',lambda t:t.replace('\tcall *%r11\n','\tmovq %rax, %r11\n\tcall *%r11\n',1)),
                ('environment-home-after-address-scratch','SI16_env',late_env_prologue),
                ('mixed-result-lost-GP-before-capture','SI16_env_indirect',lambda t:t.replace('\tcall *%r11\n','\tcall *%r11\n\txorq %rax, %rax\n',1)),
                ('mixed-result-lost-SSE-before-capture','IS16_env_indirect',lambda t:t.replace('\tcall *%r11\n','\tcall *%r11\n\tpxor %xmm0, %xmm0\n',1)),
                ('rounded-MEMORY-source-copy','M23_env_indirect',lambda t:t.replace('\tmovl $23, %ecx\n','\tmovl $24, %ecx\n',1)),
            ]
            for label,suffix,transform in controls:
                file=path/(label+'.s');file.write_text(mutated('aggregate_abi_call_targets_'+suffix,transform))
                run=run_binary(file,path/label,'-pie')
                if run.returncode==0:raise SystemExit('Runtime defect survived: '+label)
                if label=='rounded-MEMORY-source-copy' and run.returncode != -11:raise SystemExit('Expected guard fault, got '+str(run.returncode))
                print('Runtime defect caught: '+label+' exit='+str(run.returncode))

        invalid = [
            'type :T=align 32 {s}\nfunction :T $f(l %p){\n@e\nret %p\n}',
            'type :T={b 4097}\nfunction :T $f(l %p){\n@e\nret %p\n}',
            'type :T={s}\nfunction :T $f(env %e,l %p,...){\n@e\nret %p\n}',
            'type :T={s}\nfunction :T $f(l %p,...){\n@e\nret %p\n}',
            'type :T={s}\nfunction w $f(l %p,l %fn){\n@e\n%r =:T call %fn(l %p,...)\nret 1\n}',
            'type :T={s}\nfunction w $f(l %p){\n@e\n%r =:T call $external(env %p,...)\nret 1\n}',
        ]
        for text in invalid:
            expected_error = b'invalid_ir' if 'env %e,l %p,...' in text or 'env %p,...' in text else b'UnsupportedAggregateAbi'
            il.write_text(text)
            sentinel = b'preserve existing output\n'
            asm.write_bytes(sentinel)
            run = subprocess.run([*compiler, str(il), str(asm)], capture_output=True, timeout=90)
            if run.returncode == 0 or expected_error not in run.stderr or asm.read_bytes() != sentinel:
                raise SystemExit('call-target ENV/indirect refusal or pre-write sentinel changed: '+repr(text)+' '+repr(run.stderr))
            asm.unlink()
            run = subprocess.run([*compiler, str(il), str(asm)], capture_output=True, timeout=90)
            if run.returncode == 0 or expected_error not in run.stderr or asm.exists():
                raise SystemExit('Refusal created output: '+repr(text))
        print(f'{len(invalid)*2} explicit call-target ENV/indirect refusal/pre-write output checks passed')


if __name__ == '__main__':
    main()
