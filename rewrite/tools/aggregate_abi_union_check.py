#!/usr/bin/env python3
"""Named union ABI: independent C/ASM, guard and published-prior ASM oracles."""
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
    oracle = json.loads((fixtures/'aggregate_abi_union_oracle.json').read_text())
    if oracle['baseline_commit'] != '203886b271c92ef98b96a1cd518dbf8ab423ac00':
        raise SystemExit('Wrong prior published compiler oracle provenance')
    for name, expected in oracle['fixture_sha256'].items():
        if digest((fixtures/name).read_bytes()) != expected:
            raise SystemExit('Changed reviewed union fixture: '+name)
    for name, expected in oracle['whole_record'].items():
        if digest((fixtures/name).read_bytes()) != expected['source_sha256'] or set(expected['assembly_sha256']) != {str(i) for i in range(8)}:
            raise SystemExit('Changed/incomplete immutable prior record fixture oracle: '+name)
    if a.check:
        print('Independent union C/ASM literal layouts, fixtures and actual prior203886 compatibility oracles checked')
        return
    if platform.system() != 'Linux' or platform.machine() not in ('x86_64', 'amd64'):
        raise SystemExit('aggregate union execution requires Linux AMD64; no pass claimed')
    resource.setrlimit(resource.RLIMIT_CORE, (0, 0))
    mask = int(a.fold_integers)+2*int(a.reuse_stack_homes)+4*int(a.callee_saved_homes)
    flags = ['--'+f for f in ('fold-integers', 'reuse-stack-homes', 'callee-saved-homes') if getattr(a, f.replace('-', '_'))]
    compiler = [str(a.compiler.resolve()), *flags]
    with tempfile.TemporaryDirectory(prefix='aggregate_abi_union_') as directory:
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
                    raise SystemExit('Actual prior203886 whole-record bytes differ: '+name)
        print('6 exact whole prior203886 INTEGER/SSE/MEMORY fixture assemblies passed')
        for name, expected in oracle['whole_record'].items():
            for prefix in (False, True):
                base=(fixtures/name).read_text()
                unused='type :UnusedUnion=align 64 {{b 3}{d,w}}\n'
                il.write_text(unused+base if prefix else base+'\n'+unused)
                subprocess.run([*compiler,str(il),str(asm)],check=True,timeout=90)
                if digest(asm.read_bytes())!=expected['assembly_sha256'][str(mask)]:
                    raise SystemExit('Unused union changed whole prior ASM: '+name)
        print('12 unused-union prefix/suffix whole prior modules remain byte-identical')

        for prefix in (False, True):
            key = 'prefix' if prefix else 'suffix'
            il.write_text(position((fixtures/'aggregate_abi_union_mixed.ssa').read_text(), prefix))
            subprocess.run([*compiler, str(il), str(asm)], check=True, timeout=90)
            mixed = asm.read_text()
            if a.baseline_compiler:
                il.write_text(position((fixtures/'aggregate_abi_union_scalar_reference.ssa').read_text(), prefix))
                prior = path/'prior.s'
                subprocess.run([str(a.baseline_compiler.resolve()), *flags, str(il), str(prior)], check=True, timeout=90)
            for symbol, expected in oracle['matched_fragments'][key][str(mask)].items():
                actual = fragment(mixed, symbol)
                if digest(actual) != expected:
                    raise SystemExit('Prior203886 align16-module scalar fragment changed: '+key+' '+symbol)
                if a.baseline_compiler and actual != fragment(prior.read_text(), symbol):
                    raise SystemExit('Actual prior203886 matched scalar fragment differs: '+key+' '+symbol)
        for prefix in (False, True):
            key = 'prefix' if prefix else 'suffix'
            il.write_text(position((fixtures/'aggregate_abi_union_scalar_reference.ssa').read_text(), prefix))
            subprocess.run([*compiler, str(il), str(asm)], check=True, timeout=90)
            if digest(asm.read_bytes()) != oracle['whole_scalar_reference'][key][str(mask)]:
                raise SystemExit('Whole scalar-only module output changed')
            if a.baseline_compiler:
                subprocess.run([str(a.baseline_compiler.resolve()), *flags, str(il), str(path/'prior.s')], check=True, timeout=90)
                if asm.read_bytes() != (path/'prior.s').read_bytes():
                    raise SystemExit('Actual prior whole scalar module differs')
        print('2 whole scalar-only modules and8 exact prior203886 matched ENV/indirect-module scalar fragments passed (NOT whole mixed modules)')
        subprocess.run([*compiler, str(fixtures/'aggregate_abi_union.ssa'), str(asm)], check=True, timeout=90)
        original = asm.read_text()

        def run_binary(assembly, output, link):
            subprocess.run([a.cc, '-std=c11', '-O2', '-Wall', '-Wextra', '-Werror', '-fPIE', link,
                            str(fixtures/'aggregate_abi_union.c'), str(fixtures/'aggregate_abi_union_shim.s'), str(assembly), '-o', str(output)], check=True, timeout=90)
            dynamic = subprocess.run(['readelf', '-d', str(output)], capture_output=True, check=True, timeout=30).stdout
            if b'TEXTREL' in dynamic:
                raise SystemExit('Union binary has TEXTREL')
            return subprocess.run([str(output)], capture_output=True, timeout=30)

        for link in ('-pie', '-no-pie'):
            run = run_binary(asm, exe, link)
            if run.returncode:
                raise SystemExit(f'aggregate union ABI failure {link}: {run.returncode} {run.stderr.decode(errors="replace")}')
            if run.stdout.strip() != b'aggregate union 4384 independent assertions passed':
                raise SystemExit('Incomplete independent checks: '+repr(run.stdout))
            print(link+': '+run.stdout.decode().strip())


        if a.mutation_controls:
            def mutated(suffix, transform):
                symbol='aggregate_abi_union_'+suffix
                start=original.index(symbol+':\n');end=original.index('.size '+symbol+',',start)
                before=original[start:end];after=transform(before)
                if before==after:raise SystemExit('Inert runtime control: '+suffix)
                return original[:start]+after+original[end:]
            controls=[
                ('only-float-first-arm-not-INTEGER-merge','U4_direct',lambda t:t.replace('\torq %r10, %rdi\n','\tmovd %r10d, %xmm0\n',1)),
                ('only-last-float-arm-not-INTEGER-merge','U4R_direct',lambda t:t.replace('\torq %r10, %rdi\n','\tmovd %r10d, %xmm0\n',1)),
                ('shifted-child-lost-INTEGER-tail','PS_indirect',lambda t:t.replace('\torq %r10, %rdi\n','\txorq %rdi, %rdi\n',1)),
                ('reverse-shifted-child-lost-SSE-tail','PR_indirect',lambda t:t.replace('\tmovd 8(%r11), %xmm0\n','\tpxor %xmm0, %xmm0\n',1)),
                ('NO_CLASS-phantom-GP-shifts-real-tail','UN_variadic',lambda t:t.replace('\tmovq %rax, %rdx\n','\tmovq %rax, %rcx\n',1)),
                ('SSE-failed-mixed-tuple-consumes-GP','pressure_B',lambda t:t.replace('\tmovabsq $0x4d, %rax\n\tmovq %rax, %rsi\n','\tmovabsq $0x4d, %rax\n\tmovq %rax, %rdx\n',1)),
                ('private-result-pad-aliases-input','U17_indirect',lambda t:t.replace('\tleaq -64(%rbp), %rdi\n','\tmovq -16(%rbp), %rdi\n',1)),
                ('two-INTEGER-return-lost-RDX','U16_identity',lambda t:t.replace('\tmovq 8(%r11), %rdx\n','\txorq %rdx, %rdx\n',1)),
                ('two-INTEGER-return-lost-RAX','U16_identity',lambda t:t.replace('\tmovq 8(%r11), %rdx\n','\tmovq 8(%r11), %rdx\n\txorq %rax, %rax\n',1)),
                ('two-SSE-return-lost-XMM1','UDD_identity',lambda t:t.replace('\tmovq 8(%r11), %xmm1\n','\tpxor %xmm1, %xmm1\n',1)),
                ('whole-tuple-rollback-consumed-SSE','pressure',lambda t:t.replace('\tmovb $1, %al\n','\tmovb $2, %al\n',1)),
                ('AL-before-indirect-RAX-target','pressure',lambda t:t.replace('\tmovq %rax, %r11\n\tmovb $1, %al\n\tcall *%r11\n','\tmovb $1, %al\n\tmovq %rax, %r11\n\tcall *%r11\n',1)),
                ('rounded-not-raw-named-stack24','definition_pressure',lambda t:t.replace('\tleaq 40(%rbp), %rax\n','\tleaq 48(%rbp), %rax\n',1)),
                ('hidden-result-GP-not-counted','definition_pressure',lambda t:t.replace('\tmovl $48, 0(%r10)\n','\tmovl $40, 0(%r10)\n',1)),
                ('named-union-fallback-consumed-SSE','definition_pressure',lambda t:t.replace('\tmovl $48, 4(%r10)\n','\tmovl $64, 4(%r10)\n',1)),
                ('rounded-source-copy17-to24','U17_indirect',lambda t:t.replace('\tmovl $17, %ecx\n','\tmovl $24, %ecx\n',1)),
                ('rounded-destination-copy17-to24','U17_indirect',lambda t:t.replace('\tmovl $17, %ecx\n\trep movsb\n\tmovq -40(%rbp), %rax\n','\tmovl $24, %ecx\n\trep movsb\n\tmovq -40(%rbp), %rax\n',1)),
                ('advance-hidden-result-RAX','U17_indirect',lambda t:t.replace('\tleave\n','\taddq $17, %rax\n\tleave\n',1)),
                ('unexpected-FP-exceptions-on-rawbits','U8_direct',lambda t:t.replace('\tcall aggregate_abi_union_U8_echo\n','\tpxor %xmm15, %xmm15\n\tdivss %xmm15, %xmm15\n\tcall aggregate_abi_union_U8_echo\n',1)),
            ]
            for label,suffix,transform in controls:
                assembly=path/(label+'.s');assembly.write_text(mutated(suffix,transform))
                run=run_binary(assembly,path/label,'-pie')
                if run.returncode==0:raise SystemExit('Runtime defect survived: '+label)
                if label.startswith('rounded-source') or label.startswith('rounded-destination'):
                    if run.returncode!=-11:raise SystemExit('Expected exact guard SIGSEGV: '+label+' '+str(run.returncode))
                print('Runtime defect caught: '+label+' exit='+str(run.returncode))

        invalid=[
            ('type :U={{b}{}}','unsupported_construct'),
            ('type :U={{b},{w}}','unexpected_token'),
            ('type :U={{b}{:Missing}}','unknown_type'),
            ('type :U={{b}{w 0}}','invalid_record_count'),
            ('type :U={{b}{w}}\ntype :U={d}','duplicate_type'),
            ('type :U=align 3 {{b}{w}}','invalid_alignment'),
            ('type :U={{:U}{b}}','unknown_type'),
            ('type :U=align 32 {{s}{w}}\nfunction :U $f(l %p){\n@e\nret %p\n}','UnsupportedAggregateAbi'),
            ('type :U={{b 4097}{d}}\nfunction :U $f(l %p){\n@e\nret %p\n}','UnsupportedAggregateAbi'),
            ('type :U={{s}{w}}\nfunction :U $f(env %e,l %p,...){\n@e\nret %p\n}','invalid_ir'),
            ('type :U={{s}{w}}\nfunction w $f(l %p){\n@e\n%r =:U call %p(env %p,...)\nret 0\n}','invalid_ir'),
            ('type :U={{s}{w}}\nfunction :U $f(l %list,...){\n@e\n%r =:U vaarg %list\nret %r\n}','unsupported_construct'),
            ('type :U={{s}{w}}\nfunction $f(){\n@e\n%x =:U copy 0\nret\n}','unsupported_construct'),
            ('type :A={{s}{w}}\ntype :B={{s}{w}}\nfunction $f(){\n@e\ncall $g(:B 0)\nret\n}\nfunction $g(:A %p){\n@e\nret\n}','CallSignatureMismatch'),
            ('type :U={{b}{w}}\ndata $g={:U 0}','unexpected_token'),
            ('type :U={{b}{w}}\nfunction $f(){\n@e\nret\n@dead\ncall $g(:Unknown 0)\nret\n}','unknown_type'),
        ]
        for text,error in invalid:
            for exists in (True,False):
                il.write_text(text);sentinel=b'existing output must survive union refusal\n'
                if exists:asm.write_bytes(sentinel)
                elif asm.exists():asm.unlink()
                run=subprocess.run([*compiler,str(il),str(asm)],capture_output=True,timeout=90)
                if run.returncode==0 or error.encode() not in run.stderr or (asm.read_bytes()!=sentinel if exists else asm.exists()):
                    raise SystemExit('Union refusal or pre-write preservation failed: '+repr(text)+' '+repr(run.stderr))
        print(str(len(invalid)*2)+' union refusal/pre-write sentinel checks passed')

if __name__=='__main__':
    main()
