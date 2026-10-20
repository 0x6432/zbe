#!/usr/bin/env python3
"""Aggregate variadic ABI: independent C/ASM, guard and published-prior ASM oracles."""
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
    oracle = json.loads((fixtures/'aggregate_abi_variadic_oracle.json').read_text())
    if oracle['baseline_commit'] != 'b3fec4ae1ad65c6f8ef5e9d6b0620463bad6d0c8':
        raise SystemExit('Wrong prior SSE compiler oracle provenance')
    for name, expected in oracle['fixture_sha256'].items():
        if digest((fixtures/name).read_bytes()) != expected:
            raise SystemExit('Changed reviewed SSE fixture: '+name)
    for name, expected in oracle['whole_record'].items():
        if digest((fixtures/name).read_bytes()) != expected['source_sha256'] or set(expected['assembly_sha256']) != {str(i) for i in range(8)}:
            raise SystemExit('Changed/incomplete immutable prior record fixture oracle: '+name)
    if a.check:
        print('Independent aggregate variadic C+ASM schemas/fixtures and priorb3fec4 whole-record/matched-scalar oracles checked')
        return
    if platform.system() != 'Linux' or platform.machine() not in ('x86_64', 'amd64'):
        raise SystemExit('aggregate variadic execution requires Linux AMD64; no pass claimed')
    resource.setrlimit(resource.RLIMIT_CORE, (0, 0))
    mask = int(a.fold_integers)+2*int(a.reuse_stack_homes)+4*int(a.callee_saved_homes)
    flags = ['--'+f for f in ('fold-integers', 'reuse-stack-homes', 'callee-saved-homes') if getattr(a, f.replace('-', '_'))]
    compiler = [str(a.compiler.resolve()), *flags]
    with tempfile.TemporaryDirectory(prefix='aggregate_abi_variadic_') as directory:
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
                    raise SystemExit('Actual priorb3fec4 whole-record bytes differ: '+name)
        print('5 exact whole priorb3fec4 INTEGER/SSE/MEMORY fixture assemblies passed')
        for prefix in (False, True):
            key = 'prefix' if prefix else 'suffix'
            il.write_text(position((fixtures/'aggregate_abi_variadic_mixed.ssa').read_text(), prefix))
            subprocess.run([*compiler, str(il), str(asm)], check=True, timeout=90)
            mixed = asm.read_text()
            if a.baseline_compiler:
                il.write_text(position((fixtures/'aggregate_abi_variadic_scalar_reference.ssa').read_text(), prefix))
                prior = path/'prior.s'
                subprocess.run([str(a.baseline_compiler.resolve()), *flags, str(il), str(prior)], check=True, timeout=90)
            for symbol, expected in oracle['matched_fragments'][key][str(mask)].items():
                actual = fragment(mixed, symbol)
                if digest(actual) != expected:
                    raise SystemExit('Priorb3fec4 align16-module scalar fragment changed: '+key+' '+symbol)
                if a.baseline_compiler and actual != fragment(prior.read_text(), symbol):
                    raise SystemExit('Actual priorb3fec4 matched scalar fragment differs: '+key+' '+symbol)
        for prefix in (False, True):
            key = 'prefix' if prefix else 'suffix'
            il.write_text(position((fixtures/'aggregate_abi_variadic_scalar_reference.ssa').read_text(), prefix))
            subprocess.run([*compiler, str(il), str(asm)], check=True, timeout=90)
            if digest(asm.read_bytes()) != oracle['whole_scalar_reference'][key][str(mask)]:
                raise SystemExit('Whole scalar-only module output changed')
            if a.baseline_compiler:
                subprocess.run([str(a.baseline_compiler.resolve()), *flags, str(il), str(path/'prior.s')], check=True, timeout=90)
                if asm.read_bytes() != (path/'prior.s').read_bytes():
                    raise SystemExit('Actual prior whole scalar module differs')
        print('2 whole scalar-only modules and8 exact priorb3fec4 matched ENV/indirect-module scalar fragments passed (NOT whole mixed modules)')
        subprocess.run([*compiler, str(fixtures/'aggregate_abi_variadic.ssa'), str(asm)], check=True, timeout=90)
        original = asm.read_text()

        def run_binary(assembly, output, link):
            subprocess.run([a.cc, '-std=c11', '-O2', '-Wall', '-Wextra', '-Werror', '-fPIE', link,
                            str(fixtures/'aggregate_abi_variadic.c'), str(fixtures/'aggregate_abi_variadic_shim.s'), str(assembly), '-o', str(output)], check=True, timeout=90)
            dynamic = subprocess.run(['readelf', '-d', str(output)], capture_output=True, check=True, timeout=30).stdout
            if b'TEXTREL' in dynamic:
                raise SystemExit('SSE binary has TEXTREL')
            return subprocess.run([str(output)], capture_output=True, timeout=30)

        for link in ('-pie', '-no-pie'):
            run = run_binary(asm, exe, link)
            if run.returncode:
                raise SystemExit(f'aggregate variadic ABI failure {link}: {run.returncode} {run.stderr.decode(errors="replace")}')
            if run.stdout.strip() != b'aggregate variadic 5005 independent assertions passed':
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
            def before_target(text):
                lines=text.splitlines(keepends=True)
                al=next(i for i,l in enumerate(lines) if l.startswith('\tmovb $') and l.endswith(', %al\n'))
                value=lines.pop(al)
                if 'movq %rax, %r11' not in lines[al-1]:raise SystemExit('Unexpected indirect target/AL order')
                lines.insert(al-2,value)
                return ''.join(lines)
            def delayed_sse_save(text):
                lines=text.splitlines(keepends=True)
                banks=[l for l in lines if l.startswith('\tmovdqu %xmm')]
                if len(banks)!=8:raise SystemExit('Expected eight save-area SSE saves')
                lines=[l for l in lines if l not in banks]
                call=next(i for i,l in enumerate(lines) if l=='\tcall aggregate_abi_variadic_copy_list\n')
                lines[call+1:call+1]=banks
                return ''.join(lines)
            controls=[
                ('missing-zero-AL','zero',lambda t:t.replace('\tmovb $0, %al\n','',1)),
                ('missing-occupied-SSE-count','SS12_indirect',lambda t:t.replace('\tmovb $3, %al\n','\tmovb $0, %al\n',1)),
                ('AL-before-RAX-target-load','SS12_indirect',before_target),
                ('SSE-full-tuple-consumes-GP','pressure_C',lambda t:t.replace('\tmovabsq $0x63, %rax\n\tmovq %rax, %rsi\n','\tmovabsq $0x63, %rax\n\tmovq %rax, %rdx\n',1)),
                ('unexpected-FP-exception-status','zero',lambda t:t.replace('\tmovb $0, %al\n','\tpxor %xmm15, %xmm15\n\tdivss %xmm15, %xmm15\n\tmovb $0, %al\n',1)),
                ('failed-whole-tuple-consumes-SSE','pressure_A',lambda t:t.replace('\tmovb $5, %al\n','\tmovb $6, %al\n',1)),
                ('rounded-not-raw40-overflow','definition_A',lambda t:t.replace('\tleaq 56(%rbp), %rax\n','\tleaq 64(%rbp), %rax\n',1)),
                ('rounded-not-raw56-overflow','definition_B1',lambda t:t.replace('\tleaq 72(%rbp), %rax\n','\tleaq 80(%rbp), %rax\n',1)),
                ('hidden-MEMORY-GP-not-counted','definition_A',lambda t:t.replace('\tmovl $48, 0(%r10)\n','\tmovl $40, 0(%r10)\n',1)),
                ('named-SSE-carrier-erasure','SS12_definition',lambda t:t.replace('\tmovl $80, 4(%r10)\n','\tmovl $48, 4(%r10)\n',1)),
                ('rounded-MEMORY-source-copy','M23_indirect',lambda t:t.replace('\tmovl $23, %ecx\n','\tmovl $24, %ecx\n',1)),
                ('save-after-first-caller-clobber','definition_count',delayed_sse_save),
            ]
            for label,suffix,transform in controls:
                file=path/(label+'.s');file.write_text(mutated('aggregate_abi_variadic_'+suffix,transform))
                run=run_binary(file,path/label,'-pie')
                if run.returncode==0:raise SystemExit('Runtime defect survived: '+label)
                if label=='rounded-MEMORY-source-copy' and run.returncode != -11:raise SystemExit('Expected guard fault, got '+str(run.returncode))
                print('Runtime defect caught: '+label+' exit='+str(run.returncode))

        invalid = [
            'type :T=align 32 {s}\nfunction :T $f(l %p,...){\n@e\nret %p\n}',
            'type :T={b 4097}\nfunction :T $f(l %p,...){\n@e\nret %p\n}',
            'type :T={s}\nfunction :T $f(env %e,l %p,...){\n@e\nret %p\n}',
            'type :T={s}\nfunction w $f(l %p){\n@e\n%r =:T call $external(env %p,...)\nret 1\n}',
            'type :T={s}\nfunction :T $f(l %list,...){\n@e\n%r =:T vaarg %list\nret %r\n}',
            'type :A={s}\ntype :B={s}\nfunction $f(){\n@e\ncall $g(:B 0,...)\nret\n}\nfunction $g(:A %p,...){\n@e\nret\n}',
            'type :T={s}\nfunction $f(){\n@e\ncall $g(:T 0,...)\nret\n}\nfunction $g(:T %p){\n@e\nret\n}',
            'function $f(){\n@e\nret\n@dead\ncall $g(...,:Missing 0)\nret\n}',
        ]

        for text in invalid:
            expected_error = b'UnsupportedAggregateAbi' if 'align 32' in text or '4097' in text else (b'unsupported_construct' if 'vaarg' in text else (b'CallSignatureMismatch' if 'function $g(' in text else (b'unknown' if ':Missing' in text else b'invalid_ir')))
            il.write_text(text)
            sentinel = b'preserve existing output\n'
            asm.write_bytes(sentinel)
            run = subprocess.run([*compiler, str(il), str(asm)], capture_output=True, timeout=90)
            if run.returncode == 0 or expected_error not in run.stderr or asm.read_bytes() != sentinel:
                raise SystemExit('aggregate variadic refusal or pre-write sentinel changed: '+repr(text)+' '+repr(run.stderr))
            asm.unlink()
            run = subprocess.run([*compiler, str(il), str(asm)], capture_output=True, timeout=90)
            if run.returncode == 0 or expected_error not in run.stderr or asm.exists():
                raise SystemExit('Refusal created output: '+repr(text))
        print(f'{len(invalid)*2} explicit aggregate variadic refusal/pre-write output checks passed')


if __name__ == '__main__':
    main()
