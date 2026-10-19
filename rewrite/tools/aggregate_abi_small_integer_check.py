#!/usr/bin/env python3
"""Independent C/hand-ASM INTEGER1..16 interoperability and exact-span controls."""
from pathlib import Path
import argparse
import hashlib
import json
import platform
import re
import resource
import subprocess
import tempfile


def main():
    root = Path(__file__).resolve().parents[1]
    fixtures = root/'src/fixtures'
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--compiler', type=Path, default=root/'zig-out/bin/zbe-native')
    p.add_argument('--cc', default='cc')
    p.add_argument('--baseline-compiler', type=Path)
    p.add_argument('--check', action='store_true')
    p.add_argument('--mutation-controls', action='store_true')
    for flag in ('fold-integers', 'reuse-stack-homes', 'callee-saved-homes'):
        p.add_argument('--'+flag, action='store_true')
    a = p.parse_args()
    oracle = json.loads((fixtures/'aggregate_abi_small_integer_oracle.json').read_text())
    if oracle['sizes'] != list(range(1, 17)) or oracle['pattern'] != '(37 + 13*i + n) modulo 256':
        raise SystemExit('Changed independent size/pattern oracle')
    for name, expected in oracle['fixture_sha256'].items():
        if hashlib.sha256((fixtures/name).read_bytes()).hexdigest() != expected:
            raise SystemExit('Changed reviewed INTEGER fixture: '+name)
    if a.check:
        print('Independent1..16 C layouts, two literal32byte stack/GP/SSE oracles and fixture hashes checked')
        return
    if platform.system() != 'Linux' or platform.machine() not in ('x86_64', 'amd64'):
        raise SystemExit('INTEGER ABI execution requires Linux AMD64; no pass claimed')
    resource.setrlimit(resource.RLIMIT_CORE, (0, 0))
    mask = int(a.fold_integers)+2*int(a.reuse_stack_homes)+4*int(a.callee_saved_homes)
    flags = ['--'+f for f in ('fold-integers', 'reuse-stack-homes', 'callee-saved-homes') if getattr(a, f.replace('-', '_'))]
    compiler = [str(a.compiler.resolve()), *flags]
    with tempfile.TemporaryDirectory(prefix='aggregate_abi_small_integer_') as directory:
        path = Path(directory)
        asm, exe, il = path/'output.s', path/'run', path/'input.ssa'
        # The old compiler refuses small-record uses. Compare ONLY the four
        # unaffected functions with a separately generated prior2c scalar
        # reference that has identical symbol IDs/order and function ordinals.
        # The unit test establishes those identities for prefix AND suffix.
        def fragment(text, name):
            head = '.globl '+name+'\n.type '+name+', @function\n'
            tail = '.size '+name+', .-'+name+'\n'
            begin = text.index(head)
            return text[begin:text.index(tail, begin)+len(tail)].encode()

        def position(text, prefix):
            if not prefix:
                return text
            # Unique final side function, after all four exported scalars.
            cut = text.index('function ', text.index('export function l $T()')+len('export function l $T()'))
            return text[:text.index('export function ')]+text[cut:]+text[text.index('export function '):cut]

        for prefix in (False, True):
            key = 'prefix' if prefix else 'suffix'
            source = position((fixtures/'aggregate_abi_small_integer_mixed.ssa').read_text(), prefix)
            il.write_text(source)
            subprocess.run([*compiler, str(il), str(asm)], check=True, timeout=90)
            mixed = asm.read_text()
            reference = position((fixtures/'aggregate_abi_small_integer_scalar_reference.ssa').read_text(), prefix)
            if a.baseline_compiler:
                il.write_text(reference)
                prior = path/'prior.s'
                subprocess.run([str(a.baseline_compiler.resolve()), *flags, str(il), str(prior)], check=True, timeout=90)
            for symbol, expected in oracle['matched_fragments'][key][str(mask)].items():
                actual = fragment(mixed, symbol)
                if hashlib.sha256(actual).hexdigest() != expected:
                    raise SystemExit('Prior2c INTEGER mixed fragment changed: '+key+' '+symbol)
                if a.baseline_compiler and fragment(prior.read_text(), symbol) != actual:
                    raise SystemExit('Actual prior2c INTEGER mixed fragment differs: '+key+' '+symbol)
        print('8 exact prior2c matched INTEGER-module scalar fragments passed (not whole mixed modules)')
        subprocess.run([*compiler, str(fixtures/'aggregate_abi_small_integer.ssa'), str(asm)], check=True, timeout=90)
        original = asm.read_text()

        def run_binary(assembly, output, link):
            subprocess.run([a.cc, '-std=c11', '-O2', '-Wall', '-Wextra', '-Werror', '-fPIE', link,
                            str(fixtures/'aggregate_abi_small_integer.c'), str(fixtures/'aggregate_abi_small_integer_shim.s'), str(assembly), '-o', str(output)], check=True, timeout=90)
            dynamic = subprocess.run(['readelf', '-d', str(output)], capture_output=True, check=True, timeout=30).stdout
            if b'TEXTREL' in dynamic:
                raise SystemExit('INTEGER binary has TEXTREL')
            return subprocess.run([str(output)], capture_output=True, timeout=30)

        for link in ('-pie', '-no-pie'):
            run = run_binary(asm, exe, link)
            if run.returncode:
                raise SystemExit(f'INTEGER ABI runtime failure {link}: {run.returncode} {run.stderr.decode(errors="replace")}')
            if run.stdout.strip() != b'275 independent small INTEGER checks passed':
                raise SystemExit('Incomplete independent runtime checks: '+repr(run.stdout))
            print(link+': '+run.stdout.decode().strip())

        if a.mutation_controls:
            def body(name):
                start = original.index(name+':\n')
                end = original.index('.size '+name+',', start)
                return start, end, original[start:end]

            name = 'aggregate_abi_small_integer_ret9'
            start, end, ret = body(name)
            needle = '\tmovzbl 8(%r11), %r10d\n'
            assert ret.count(needle) == 1
            mutations = [
                ('rounded-tail-read', start, end, ret.replace(needle, '\tmovq 8(%r11), %r10\n'), -11),
                ('lost-RAX-during-second-pack', start, end, ret.replace(needle, '\txorl %eax, %eax\n'+needle), None),
                ('swapped-return-lanes', start, end, ret.replace('\tleave\n', '\txchgq %rax, %rdx\n\tleave\n'), None),
                ('omitted-ninth-byte', start, end, ret.replace(needle, '\txorl %r10d, %r10d\n'), None),
            ]
            start, end, capture = body('aggregate_abi_small_integer_roundtrip9')
            capture, count = re.subn(r'(\tcall aggregate_abi_small_integer_cmake9\n\tmovq %rax, -[0-9]+\(%rbp\)\n)', r'\1\txorl %edx, %edx\n', capture)
            assert count == 1
            mutations.append(('lost-RDX-during-first-unpack', start, end, capture, None))
            start, end, outgoing = body('aggregate_abi_small_integer_call_memory_probe')
            # The whole two-lane arg has fallen back to stack. The following
            # scalar must still use R9; consuming its bank slot breaks ASM oracle.
            outgoing, count = re.subn(r'\tmovq %rax, %r9\n', '\tmovq %rax, %r8\n', outgoing)
            assert count == 1
            mutations.append(('partial-bank-consumption', start, end, outgoing, None))
            for label, start, end, changed, signal in mutations:
                mutant = path/(label+'.s')
                mutant.write_text(original[:start]+changed+original[end:])
                run = run_binary(mutant, path/label, '-pie')
                if run.returncode == 0 or (signal is not None and run.returncode != signal):
                    raise SystemExit('Runtime mutation was not caught: '+label+' '+str(run.returncode))
                print('Runtime mutation caught: '+label+' exit='+str(run.returncode))

        invalid = [
            'type :T = { s }\nexport function :T $f(l %p) { @start ret %p }\n',
            'type :T = { d 2 }\nexport function :T $f(l %p) { @start ret %p }\n',
            'type :T = { w, s }\nexport function :T $f(l %p) { @start ret %p }\n',
            'type :T = align 16 { b }\nexport function :T $f(l %p) { @start ret %p }\n',
            'type :T = align 32 { b 32 }\nexport function :T $f(l %p) { @start ret %p }\n',
            'type :T = { b 4097 }\nexport function :T $f(l %p) { @start ret %p }\n',
            'type :T = { b }\nexport function :T $f(env %e, l %p) { @start ret %p }\n',
            'type :T = { b }\nexport function :T $f(l %p, ...) { @start ret %p }\n',
            'type :T = { b }\nexport function w $f(l %p, l %fn) { @start %r =:T call %fn(l %p) ret 1 }\n',
            'type :T = { b }\nexport function w $f(l %p) { @start %r =:T call $g(l %p, ...) ret 1 }\n',
            'type :T = { b }\nexport function w $f(l %p) { @start %r =:T call $g(env %p) ret 1 }\n',
            'type :T = { s }\nexport function w $f() { @start ret 1 @dead %r =:T call $g() ret 2 }\n',
        ]
        def normalized(source):
            return source.replace("{ @start ", "{\n@start\n").replace(" @dead ", "\n@dead\n").replace(" ret ", "\nret ").replace(" }\n", "\n}\n")

        # Only these four approved SSE/native cases change expectation; all
        # remaining env/vararg/indirect/alignment/size boundaries stay negative.
        for index in (0, 1, 2, 11):
            il.write_text(normalized(invalid[index]))
            subprocess.run([*compiler, str(il), str(asm)], check=True, timeout=90)
        print('4 individually approved SSE/dominance/unreachable native positive upgrades passed')
        invalid = [source for index, source in enumerate(invalid) if index not in (0, 1, 2, 11)]
        refusals = 0
        for source in invalid:
            source = normalized(source)
            il.write_text(source)
            sentinel = b'preserve existing output\n'
            asm.write_bytes(sentinel)
            run = subprocess.run([*compiler, str(il), str(asm)], capture_output=True, timeout=90)
            if run.returncode == 0 or b'UnsupportedAggregateAbi' not in run.stderr or asm.read_bytes() != sentinel:
                raise SystemExit('Unsupported INTEGER boundary or output preservation changed: '+repr(source)+' '+repr(run.stderr))
            asm.unlink()
            run = subprocess.run([*compiler, str(il), str(asm)], capture_output=True, timeout=90)
            if run.returncode == 0 or b'UnsupportedAggregateAbi' not in run.stderr or asm.exists():
                raise SystemExit('Refusal created output: '+repr(source))
            refusals += 2
        print(f'{refusals} explicit refusal/pre-write output checks passed')


if __name__ == '__main__':
    main()
