#!/usr/bin/env python3
"""Aligned regular record transport and padding-only NO_CLASS: independent C/ASM, guard and prior-ASM oracles."""
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
    oracle = json.loads((fixtures/'aggregate_abi_align16_oracle.json').read_text())
    if oracle['baseline_commit'] != '8b1a0444ba4bbfd6d92951b633c04d746f630457':
        raise SystemExit('Wrong prior SSE compiler oracle provenance')
    for name, expected in oracle['fixture_sha256'].items():
        if digest((fixtures/name).read_bytes()) != expected:
            raise SystemExit('Changed reviewed SSE fixture: '+name)
    for name, expected in oracle['whole_record'].items():
        if digest((fixtures/name).read_bytes()) != expected['source_sha256'] or set(expected['assembly_sha256']) != {str(i) for i in range(8)}:
            raise SystemExit('Changed/incomplete immutable prior record fixture oracle: '+name)
    if a.check:
        print('Independent align16/NO_CLASS C+ASM schemas/fixtures and prior8b1a whole-record/matched-scalar oracles checked')
        return
    if platform.system() != 'Linux' or platform.machine() not in ('x86_64', 'amd64'):
        raise SystemExit('align16/NO_CLASS execution requires Linux AMD64; no pass claimed')
    resource.setrlimit(resource.RLIMIT_CORE, (0, 0))
    mask = int(a.fold_integers)+2*int(a.reuse_stack_homes)+4*int(a.callee_saved_homes)
    flags = ['--'+f for f in ('fold-integers', 'reuse-stack-homes', 'callee-saved-homes') if getattr(a, f.replace('-', '_'))]
    compiler = [str(a.compiler.resolve()), *flags]
    with tempfile.TemporaryDirectory(prefix='aggregate_abi_align16_') as directory:
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
                    raise SystemExit('Actual prior8b1a whole-record bytes differ: '+name)
        print('3 exact whole prior8b1a INTEGER/SSE/MEMORY fixture assemblies passed')
        for prefix in (False, True):
            key = 'prefix' if prefix else 'suffix'
            il.write_text(position((fixtures/'aggregate_abi_align16_mixed.ssa').read_text(), prefix))
            subprocess.run([*compiler, str(il), str(asm)], check=True, timeout=90)
            mixed = asm.read_text()
            if a.baseline_compiler:
                il.write_text(position((fixtures/'aggregate_abi_align16_scalar_reference.ssa').read_text(), prefix))
                prior = path/'prior.s'
                subprocess.run([str(a.baseline_compiler.resolve()), *flags, str(il), str(prior)], check=True, timeout=90)
            for symbol, expected in oracle['matched_fragments'][key][str(mask)].items():
                actual = fragment(mixed, symbol)
                if digest(actual) != expected:
                    raise SystemExit('Prior8b1a align16-module scalar fragment changed: '+key+' '+symbol)
                if a.baseline_compiler and actual != fragment(prior.read_text(), symbol):
                    raise SystemExit('Actual prior8b1a matched scalar fragment differs: '+key+' '+symbol)
        for prefix in (False, True):
            key = 'prefix' if prefix else 'suffix'
            il.write_text(position((fixtures/'aggregate_abi_align16_scalar_reference.ssa').read_text(), prefix))
            subprocess.run([*compiler, str(il), str(asm)], check=True, timeout=90)
            if digest(asm.read_bytes()) != oracle['whole_scalar_reference'][key][str(mask)]:
                raise SystemExit('Whole scalar-only module output changed')
            if a.baseline_compiler:
                subprocess.run([str(a.baseline_compiler.resolve()), *flags, str(il), str(path/'prior.s')], check=True, timeout=90)
                if asm.read_bytes() != (path/'prior.s').read_bytes():
                    raise SystemExit('Actual prior whole scalar module differs')
        print('2 whole scalar-only modules and8 exact prior8b1a matched align16-module scalar fragments passed (NOT whole mixed modules)')
        subprocess.run([*compiler, str(fixtures/'aggregate_abi_align16.ssa'), str(asm)], check=True, timeout=90)
        original = asm.read_text()

        def run_binary(assembly, output, link):
            subprocess.run([a.cc, '-std=c11', '-O2', '-Wall', '-Wextra', '-Werror', '-fPIE', link,
                            str(fixtures/'aggregate_abi_align16.c'), str(fixtures/'aggregate_abi_align16_shim.s'), str(assembly), '-o', str(output)], check=True, timeout=90)
            dynamic = subprocess.run(['readelf', '-d', str(output)], capture_output=True, check=True, timeout=30).stdout
            if b'TEXTREL' in dynamic:
                raise SystemExit('SSE binary has TEXTREL')
            return subprocess.run([str(output)], capture_output=True, timeout=30)

        for link in ('-pie', '-no-pie'):
            run = run_binary(asm, exe, link)
            if run.returncode:
                raise SystemExit(f'align16/NO_CLASS ABI failure {link}: {run.returncode} {run.stderr.decode(errors="replace")}')
            if run.stdout.strip() != b'align16 2034 independent assertions passed':
                raise SystemExit('Incomplete independent checks: '+repr(run.stdout))
            print(link+': '+run.stdout.decode().strip())

        if a.mutation_controls:
            def change_body(symbol, old, new):
                head = original.index(symbol+':\n')
                tail = original.index('.size '+symbol+',', head)
                body = original[head:tail]
                if body.count(old) != 1:
                    raise SystemExit('Missing/ambiguous runtime control site: '+symbol+' '+repr(old))
                return original[:head]+body.replace(old, new)+original[tail:]
            controls = [
                ('padding-consumes-SSE-shifts-real-double', 'aggregate_abi_align16_pressure_ione', '\tmovq %rax, %xmm0\n', '\tpxor %xmm0, %xmm0\n\tmovq %rax, %xmm1\n'),
                ('padding-consumes-GP-shifts-real-long', 'aggregate_abi_align16_pressure_sone', '\tmovq %rax, %rdi\n', '\txorq %rdi, %rdi\n\tmovq %rax, %rsi\n'),
                ('lost16-stack-alignment', 'aggregate_abi_align16_pressure_gp', '\tleaq 16(%rsp), %rdi\n', '\tleaq 8(%rsp), %rdi\n'),
                ('wrong-full-object-stack-extent', 'aggregate_abi_align16_pressure_gp', '\tmovq %rax, 32(%rsp)\n', '\tmovq %rax, 24(%rsp)\n'),
                ('short-fallback-loses-initialized-second-lane', 'aggregate_abi_align16_pressure_gpfail', '\tmovl $16, %ecx\n', '\tmovl $8, %ecx\n'),
                ('mixed-return-loses-GP', 'aggregate_abi_align16_IS_ret', '\tmovq 8(%r11), %xmm0\n', '\txorq %rax, %rax\n\tmovq 8(%r11), %xmm0\n'),
                ('mixed-return-loses-SSE', 'aggregate_abi_align16_SI_ret', '\tmovq 8(%r11), %rax\n', '\tpxor %xmm0, %xmm0\n\tmovq 8(%r11), %rax\n'),
            ]
            for label, symbol, old, new in controls:
                mutant = path/(label+'.s');mutant.write_text(change_body(symbol,old,new))
                run = run_binary(mutant,path/label,'-pie')
                if run.returncode == 0:
                    raise SystemExit('Runtime control not caught: '+label)
                print('Runtime mutation caught: '+label+' exit='+str(run.returncode))
            # A real guard-page read fault, using a valid FULL16-readable-byte
            # align16 object and initialized two-word II fields, not padding.
            symbol = 'aggregate_abi_align16_II_ret'
            head = original.index('.globl '+symbol+'\n');tail=original.index('.size '+symbol+',',head)
            tail=original.index('\n',tail)+1
            body=original[head:tail]
            needle='\tmovq 8(%r11), %rdx\n'
            if body.count(needle)!=1:raise SystemExit('Missing second initialized II lane')
            guard=path/'guard.c'
            guard.write_text('#define _GNU_SOURCE\n#include <sys/mman.h>\n#include <unistd.h>\n#include <stdint.h>\n#include <string.h>\n#include <stdlib.h>\ntypedef struct{_Alignas(16) uint64_t u[2];}T;\nextern T aggregate_abi_align16_II_ret(const void*);\nint main(void){long p=sysconf(_SC_PAGESIZE);if(p<4096)return 2;char*m=mmap(0,p*2,PROT_READ|PROT_WRITE,MAP_PRIVATE|MAP_ANONYMOUS,-1,0);if(m==MAP_FAILED||mprotect(m+p,p,PROT_NONE))return 3;T v={{0x1122334455667788,0x8877665544332211}};memcpy(m+p-16,&v,16);T r=aggregate_abi_align16_II_ret(m+p-16);if(r.u[0]!=v.u[0]||r.u[1]!=v.u[1])return 4;return munmap(m,p*2)!=0;}\n')
            for defect in (False, True):
                file=path/('guard-mutant.s' if defect else 'guard-valid.s')
                file.write_text('.text\n'+(body.replace(needle,'\tmovq 16(%r11), %rdx\n') if defect else body)+'\n.section .note.GNU-stack,"",@progbits\n')
                output=path/('guard-mutant' if defect else 'guard-valid')
                subprocess.run([a.cc,'-std=c11','-O2','-fPIE','-pie',str(guard),str(file),'-o',str(output)],check=True,timeout=90)
                rc=subprocess.run([str(output)],capture_output=True,timeout=20).returncode
                if rc != (-11 if defect else 0):raise SystemExit('Guard positive/control failed: '+str(rc))
            print('Runtime mutation caught: full16-declared-guard-overread exit=-11; valid initialized-lane guard oracle passed')

        invalid = [
            'type :T=align 32 {s}\nfunction :T $f(l %p){\n@e\nret %p\n}',
            'type :T=align 64 {l 2}\nfunction :T $f(l %p){\n@e\nret %p\n}',
            'type :T={b 4097}\nfunction :T $f(l %p){\n@e\nret %p\n}',
            'type :T=align 16 {s}\nfunction :T $f(env %e,l %p){\n@e\nret %p\n}',
            'type :T=align 16 {s}\nfunction :T $f(l %p,...){\n@e\nret %p\n}',
            'type :T=align 16 {s}\nfunction w $f(l %p,l %fn){\n@e\n%r =:T call %fn(l %p)\nret 1\n}',
            'type :T=align 16 {s}\nfunction w $f(l %p){\n@e\n%r =:T call $external(l %p,...)\nret 1\n}',
            'type :T=align 16 {s}\nfunction w $f(l %p){\n@e\n%r =:T call $external(env %p)\nret 1\n}',
            'type :T=align 32 {s}\nfunction w $f(){\n@e\nret 1\n@dead\n%r =:T call $external()\nret 2\n}',
        ]
        # Exactly these two formerly refused cases are approved by the variadic
        # endpoint. Their execution oracle is aggregate_abi_variadic_check.py.
        approved_variadic = [invalid[i] for i in (4, 6)]
        for text in approved_variadic:
            text = text.replace("{ @start ", "{\n@start\n").replace(" ret ", "\nret ").replace(" }\n", "\n}\n")
            il.write_text(text)
            subprocess.run([*compiler, str(il), str(asm)], check=True, timeout=90)
            if not asm.read_bytes().startswith(b'.text'): raise SystemExit('Approved variadic case emitted no code')

        # Precisely the newly approved nonvariadic ENV/indirect cases are
        # positive compilation checks, not silently dropped refusals. Their
        # execution is independently covered by aggregate_abi_call_targets_check.
        eligible_call_targets = [source for source in invalid
                                 if '...' not in source and
                                 ('env ' in source or 'call %' in source or 'call 0(' in source)]
        for source in eligible_call_targets:
            il.write_text(source)
            subprocess.run([*compiler, str(il), str(asm)], check=True, timeout=90)
            if not asm.read_bytes().startswith(b'.text'):
                raise SystemExit('Eligible call target did not emit native code')
        invalid = [source for source in invalid if source not in eligible_call_targets]
        invalid = [source for source in invalid if source not in approved_variadic]
        for text in invalid:
            il.write_text(text)
            sentinel = b'preserve existing output\n'
            asm.write_bytes(sentinel)
            run = subprocess.run([*compiler, str(il), str(asm)], capture_output=True, timeout=90)
            if run.returncode == 0 or b'UnsupportedAggregateAbi' not in run.stderr or asm.read_bytes() != sentinel:
                raise SystemExit('align16/NO_CLASS refusal or pre-write sentinel changed: '+repr(text)+' '+repr(run.stderr))
            asm.unlink()
            run = subprocess.run([*compiler, str(il), str(asm)], capture_output=True, timeout=90)
            if run.returncode == 0 or b'UnsupportedAggregateAbi' not in run.stderr or asm.exists():
                raise SystemExit('Refusal created output: '+repr(text))
        print(f'{len(invalid)*2} explicit align16/NO_CLASS refusal/pre-write output checks passed')


if __name__ == '__main__':
    main()
