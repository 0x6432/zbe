#!/usr/bin/env python3
"""Independent Linux ELF common metadata, coalescing, strong override and execution."""
from pathlib import Path
import argparse
from collections import Counter
import platform
import re
import resource
import subprocess
import sys
import tempfile


def run(command, **kwargs):
    try:
        return subprocess.run(command, check=True, timeout=90, **kwargs)
    except subprocess.CalledProcessError as error:
        if error.stderr:
            print(error.stderr, file=sys.stderr)
        raise


def symbols(path):
    text = run(['readelf', '--wide', '--symbols', str(path)], capture_output=True, text=True).stdout
    return {f[7]: f for line in text.splitlines()
            if len(f := line.split(None, 7)) == 8 and f[0].endswith(':')}


def accessors(prefix):
    return f'''export function l ${prefix}_address() {{
@e
ret $shared
}}
export function w ${prefix}_read(l %i) {{
@e
%p =l add $shared, %i
%x =w loadub %p
ret %x
}}
export function w ${prefix}_write(l %i, w %v) {{
@e
%p =l add $shared, %i
storeb %v, %p
%x =w loadub %p
ret %x
}}
'''


def main():
    root = Path(__file__).resolve().parents[1]
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--compiler', type=Path, default=root / 'zig-out/bin/zbe-native')
    parser.add_argument('--cc', default='cc')
    for flag in ('fold-integers', 'reuse-stack-homes', 'callee-saved-homes'):
        parser.add_argument('--' + flag, action='store_true')
    args = parser.parse_args()
    if platform.system() != 'Linux' or platform.machine() not in ('x86_64', 'amd64'):
        raise SystemExit('Common checks require Linux AMD64; no success claimed.')
    resource.setrlimit(resource.RLIMIT_CORE, (0, 0))
    flags = ['--' + f for f in ('fold-integers', 'reuse-stack-homes', 'callee-saved-homes')
             if getattr(args, f.replace('-', '_'))]
    compiler = str(args.compiler.resolve())
    with tempfile.TemporaryDirectory(prefix='zbe-common-') as directory:
        work = Path(directory)

        def compile_il(name, text):
            source, assembly, obj = [work / (name + ext) for ext in ('.ssa', '.s', '.o')]
            source.write_text(text)
            run([compiler, *flags, str(source), str(assembly)])
            # Pin GNU-compatible default ELF OBJECT common policy, not --elf-stt-common.
            run([args.cc, '-c', str(assembly), '-o', str(obj)])
            return obj

        a = compile_il('a', 'common data $shared = { z 0, z 17, z 0 }\n'
                       'common data $empty = align 64 {}\ncommon data $emptyrun = { z 0 }\n'
                       'common data $"quoted common" = align 32 { z 17 }\n'
                       + ''.join(f'common data $align{n} = align {n} {{ z 1 }}\n'
                                 for n in (1, 2, 4, 8, 16, 32, 64))
                       + 'export data $ordinary = { b 7 }\n' + accessors('a'))
        b = compile_il('b', 'export\ncommon\ndata $shared = align 64 { z 33 }\n' + accessors('b'))
        metadata = 0
        expected_a = [('shared', 17, 8), ('empty', 0, 64), ('emptyrun', 0, 8), ('quoted common', 17, 32)]
        expected_a += [(f'align{n}', 1, n) for n in (1, 2, 4, 8, 16, 32, 64)]
        for obj, expected in ((a, expected_a), (b, [('shared', 33, 64)])):
            table = symbols(obj)
            for name, size, alignment in expected:
                f = table.get(name)
                if f is None or (int(f[1], 16), int(f[2], 0), f[3:7]) != (alignment, size, ['OBJECT', 'GLOBAL', 'DEFAULT', 'COM']):
                    raise SystemExit(f'Wrong common ELF metadata {name}: {f}')
                metadata += 1
        ordinary = symbols(a)['ordinary']
        if ordinary[3:6] != ['OBJECT', 'GLOBAL', 'DEFAULT'] or ordinary[6] == 'COM' or int(ordinary[2]) != 1:
            raise SystemExit('Ordinary data changed by common linkage')
        metadata += 1
        assert metadata == 13
        print('13 common relocatable ELF size/alignment/binding checks passed')
        initialized = compile_il('strong', 'export data $shared = align 8 { b 1 2 3 4 5 6 7 8 9 }\n')
        zero = compile_il('strongzero', 'export data $shared = align 8 { z 9 }\n')
        for obj, section, kind in ((initialized, '.data', 'PROGBITS'), (zero, '.bss', 'NOBITS')):
            headers = run(['readelf', '--wide', '--section-headers', str(obj)], capture_output=True, text=True).stdout
            sections = {m[1]: (m[2], m[3]) for line in headers.splitlines()
                        if (m := re.match(r'\s*\[\s*(\d+)\]\s+(\S+)\s+(\S+)', line))}
            f = symbols(obj)['shared']
            if int(f[2]) != 9 or sections.get(f[6]) != (section, kind):
                raise SystemExit('Strong definition is not the expected initialized/BSS object')
        print('2 strong-definition PROGBITS/NOBITS metadata checks passed')
        c = work / 'main.c'
        binary = work / 'test'
        configurations = 0
        for kind, strong, size, alignment, initial in (
                ('coalesced', None, 33, 64, [0] * 33),
                ('strongdata', initialized, 9, 8, list(range(1, 10))),
                ('strongbss', zero, 9, 8, [0] * 9)):
            # Strong size9 intentionally smaller and less aligned than common33/64:
            # only these9 winning bytes are ever accessed, never common's extent.
            c.write_text('''#include <stdint.h>
#include <stdio.h>
#include <string.h>
extern unsigned char shared[], ordinary[];
extern uint64_t a_address(void),b_address(void);
extern uint32_t a_read(uint64_t),b_read(uint64_t),a_write(uint64_t,uint32_t),b_write(uint64_t,uint32_t);
#define REQUIRE(c) do {++count;if(!(c)){fprintf(stderr,"common check %zu failed at line %d\\n",count,__LINE__);return 1;}}while(0)
int main(int argc,char **argv){(void)argv;size_t count=0;
unsigned char *a=(unsigned char *)(uintptr_t)a_address(),*b=(unsigned char *)(uintptr_t)b_address();
''' + f'unsigned char expected[{size}]={{' + ','.join(map(str, initial)) + '};\n'
                         + f'REQUIRE(a==b);REQUIRE(a==shared);REQUIRE((uintptr_t)a%{alignment}==0);REQUIRE(ordinary[0]==7);\n'
                         + 'if(argc>1) REQUIRE(((uintptr_t)a>>32)!=0);\n'
                         + f'for(size_t i=0;i<{size};++i){{REQUIRE(a_read(i)==expected[i]);REQUIRE(b_read(i)==expected[i]);\n'
                         + 'expected[i]=(unsigned char)(i*13+99);REQUIRE(a_write(i,expected[i])==expected[i]);REQUIRE(b_read(i)==expected[i]);\n'
                         + 'expected[i]^=0xa5;REQUIRE(b_write(i,expected[i])==expected[i]);REQUIRE(a_read(i)==expected[i]);}\n'
                         + f'REQUIRE(memcmp(a,expected,{size})==0);if(count!=(size_t)({5+6*size}+(argc>1)))return 3;return 0;}}\n')
            for reverse in (False, True):
                objects = [a, b] + ([strong] if strong else [])
                if reverse:
                    objects.reverse()
                for pie in (False, True):
                    mode = ['-fPIE', '-pie'] if pie else ['-fno-pie', '-no-pie']
                    # ld may warn about deliberate strong/common alignment/size mismatch.
                    run([args.cc, '-std=c11', '-O2', '-Wall', '-Wextra', '-Werror', *mode,
                         str(c), *map(str, objects), '-o', str(binary)], capture_output=True, text=True)
                    run([str(binary), *(['high-address'] if pie else [])])
                    f = symbols(binary)['shared']
                    if f[3:6] != ['OBJECT', 'GLOBAL', 'DEFAULT'] or f[6] == 'COM' or int(f[2]) != size or int(f[1], 16) % alignment:
                        raise SystemExit(f'Wrong linked {kind} symbol: {f}')
                    configurations += 1
        assert configurations == 12
        print('12 common coalescing/strong/BSS-override link-order PIE/non-PIE runtime checks passed')
        quoted_name = 'adversarial slot\\\\'
        quoted_token = '$"' + quoted_name + '"'
        qsource = ('common data ' + quoted_token + ' = align 64 { z 17 }\n'
                   + 'data $"ordinary\\\\" = { b 9 }\n'
                   + 'data $qtable = { l ' + quoted_token + ', l ' + quoted_token + '+16, l ' + quoted_token + '+-1 }\n')
        for suffix, operand in [('address', quoted_token), ('offset', quoted_token + '+16'),
                                ('before', quoted_token + '+-1'), ('max', quoted_token + '+2147483647'),
                                ('min', quoted_token + '+-2147483648'), ('ordinary', '$"ordinary\\\\"')]:
            qsource += f'export function l $q_{suffix}() {{\n@e\nret {operand}\n}}\n'
        qsource += ('export function l $q_table(l %i) {\n@e\n%p =l add $qtable, %i\n%x =l loadl %p\nret %x\n}\n'
                    + 'export function w $q_read(l %i) {\n@e\n%p =l add ' + quoted_token + ', %i\n%x =w loadub %p\nret %x\n}\n'
                    + 'export function w $q_write(l %i, w %v) {\n@e\n%p =l add ' + quoted_token + ', %i\nstoreb %v, %p\n%x =w loadub %p\nret %x\n}\n')
        q = compile_il('quoted', qsource)
        qfields = symbols(q).get('adversarial slot\\')
        if qfields is None or (int(qfields[1], 16), int(qfields[2]), qfields[3:7]) != (64, 17, ['OBJECT', 'GLOBAL', 'DEFAULT', 'COM']):
            raise SystemExit('Quoted COMMON identity/metadata changed')
        relocations = run(['readelf', '--wide', '--relocs', str(q)], capture_output=True, text=True).stdout
        common_relocs = Counter(line.rsplit('adversarial slot\\', 1)[1].strip()
                                for line in relocations.splitlines()
                                if 'R_X86_64_64' in line and 'adversarial slot\\' in line)
        if common_relocs != {'+ 0': 2, '+ 10': 1, '- 1': 1}:
            raise SystemExit(f'Wrong quoted common full-width relocation/addends: {common_relocs}')
        print('4 quoted common full-width pointer-cell/data relocation metadata checks passed')
        qstrong = compile_il('quotedstrong', 'export data ' + quoted_token + ' = align 8 { b 1 2 3 4 5 6 7 8 9 }\n')
        qconfigurations = 0
        for strong in (None, qstrong):
            size, alignment = (9, 8) if strong else (17, 64)
            initial = list(range(1, 10)) if strong else [0] * 17
            c.write_text('#include <stdint.h>\n#include <stdio.h>\n'
                         'extern uint64_t q_address(void),q_offset(void),q_before(void),q_max(void),q_min(void),q_ordinary(void),q_table(uint64_t);\n'
                         'extern uint32_t q_read(uint64_t),q_write(uint64_t,uint32_t);\n'
                         '#define REQUIRE(c) do {++count;if(!(c)){fprintf(stderr,"quoted common check %zu failed\\n",count);return 1;}}while(0)\n'
                         'int main(int argc,char **argv){(void)argv;size_t count=0;uint64_t p=q_address();\n'
                         + f'unsigned char expected[{size}]={{' + ','.join(map(str, initial)) + '};\n'
                         + f'REQUIRE(p%{alignment}==0);REQUIRE(q_offset()==p+16);REQUIRE(q_before()==p-1);\n'
                         + 'REQUIRE(q_max()==p+UINT64_C(2147483647));REQUIRE(q_min()==p-UINT64_C(2147483648));\n'
                         + 'REQUIRE(q_table(0)==p);REQUIRE(q_table(8)==p+16);REQUIRE(q_table(16)==p-1);\n'
                         + 'REQUIRE(*(unsigned char *)(uintptr_t)q_ordinary()==9);if(argc>1)REQUIRE((p>>32)!=0);\n'
                         + f'for(size_t i=0;i<{size};++i){{REQUIRE(q_read(i)==expected[i]);expected[i]^=0xa5;REQUIRE(q_write(i,expected[i])==expected[i]);REQUIRE(q_read(i)==expected[i]);}}\n'
                         + f'if(count!=(size_t)({9+3*size}+(argc>1))){{return 3;}}\nreturn 0;}}\n')
            for reverse in ((False, True) if strong else (False,)):
                objects = [q, strong] if strong else [q]
                if reverse:
                    objects.reverse()
                for pie in (False, True):
                    mode = ['-fPIE', '-pie'] if pie else ['-fno-pie', '-no-pie']
                    run([args.cc, '-std=c11', '-O2', '-Wall', '-Wextra', '-Werror', *mode,
                         str(c), *map(str, objects), '-o', str(binary)], capture_output=True, text=True)
                    run([str(binary), *(['high-address'] if pie else [])])
                    dynamic = run(['readelf', '--wide', '--dynamic', str(binary)], capture_output=True, text=True).stdout
                    if 'TEXTREL' in dynamic:
                        raise SystemExit('Quoted COMMON address cells introduced text relocations')
                    qconfigurations += 1
        assert qconfigurations == 6
        print('6 quoted trailing-backslash COMMON address/offset/relocation/override no-TEXTREL runtime checks passed')
        invalid = ['common common data $x = {}', 'common function $x() {\n@e\nret\n}',
                   'common thread data $x = {}', 'common section ".data" data $x = {}',
                   'common data $x = align 3 {}', 'common data $x = { z 16777217 }']
        invalid += [f'common data $x = {{ {body} }}' for body in
                    ('b 0', 'h 0', 'w 0', 'l 0', 's s_0', 'd d_0', 'b ""', 'l $other+0', 'z 0, b 0')]
        for text in invalid:
            source, output = work / 'bad.ssa', work / 'bad.s'
            source.write_text(text)
            for existing in (False, True):
                if output.exists():
                    output.unlink()
                if existing:
                    output.write_bytes(b'preserved common rejection\n')
                result = subprocess.run([compiler, *flags, str(source), str(output)], capture_output=True, timeout=30)
                if result.returncode == 0 or (output.read_bytes() if output.exists() else None) != (b'preserved common rejection\n' if existing else None):
                    raise SystemExit('Common rejection/output preservation failed: ' + text)
        assert len(invalid) == 15
        print('30 common invalid-initializer/linkage/output-preservation checks passed')


if __name__ == '__main__':
    main()
