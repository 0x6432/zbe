#!/usr/bin/env python3
"""Independent packed-data byte, ELF symbol, and writable-global execution checks."""
from pathlib import Path
import argparse
import platform
import resource
import subprocess
import tempfile


def run(command, **kwargs):
    return subprocess.run(command, check=True, timeout=90, **kwargs)


def main():
    root = Path(__file__).resolve().parents[1]
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--compiler', type=Path, default=root/'zig-out/bin/zbe-native')
    parser.add_argument('--cc', default='cc')
    for flag in ('fold-integers', 'reuse-stack-homes', 'callee-saved-homes'):
        parser.add_argument('--'+flag, action='store_true')
    args = parser.parse_args()
    if platform.system() != 'Linux' or platform.machine() not in ('x86_64', 'amd64'):
        raise SystemExit('Data execution checks require Linux AMD64; no result claimed.')
    resource.setrlimit(resource.RLIMIT_CORE, (0, 0))
    flags = ['--'+f for f in ('fold-integers', 'reuse-stack-homes', 'callee-saved-homes') if getattr(args, f.replace('-', '_'))]
    compiler = str(args.compiler.resolve())
    objects = []
    for line in (root/'src/fixtures/data-oracle.tsv').read_text().splitlines():
        if not line or line.startswith('#'):
            continue
        name, alignment, exported, payload = line.split('\t')
        objects.append((name, int(alignment), bool(int(exported)), b'' if payload == '-' else bytes.fromhex(payload)))
    assert len(objects) == 10 and sum(len(x[3]) for x in objects) == 1896
    wrappers, declarations, checks = [], [], []
    expected_count = 0
    for name, alignment, exported, payload in objects:
        wrappers.append(f'export function l ${name}_address() {{\n@e\nret ${name}\n}}')
        declarations.append(f'extern uint64_t {name}_address(void);')
        if exported:
            declarations.append(f'extern unsigned char {name}[];')
        checks += [f'unsigned char *p_{name}=(unsigned char *)(uintptr_t){name}_address();',
                   f'REQUIRE((uintptr_t)p_{name}%{alignment}==0);',
                   f'if(argc>1) REQUIRE(((uintptr_t)p_{name}>>32)!=0);']
        expected_count += 1
        if exported:
            checks.append(f'REQUIRE(p_{name}=={name});')
            expected_count += 1
        if not payload:
            continue  # Empty object has no readable extent or uniqueness promise.
        wrappers += [f'''export function w ${name}_read(l %i) {{
@e
%p =l add ${name}, %i
%x =w loadub %p
ret %x
}}''', f'''export function w ${name}_write(l %i, w %v) {{
@e
%p =l add ${name}, %i
storeb %v, %p
%x =w loadub %p
ret %x
}}''']
        declarations += [f'extern uint32_t {name}_read(uint64_t),{name}_write(uint64_t,uint32_t);',
                         f'static const unsigned char expected_{name}[]={{'+','.join(map(str,payload))+'};']
        n = len(payload)
        checks += ['{', f'unsigned char expected[{n}];memcpy(expected,expected_{name},{n});',
                   f'REQUIRE(memcmp(p_{name},expected,{n})==0);',
                   f'for(size_t i=0;i<{n};++i) {{',
                   f' REQUIRE({name}_read(i)==expected[i]);',
                   ' uint32_t value=(uint32_t)(i*513+0xdead1200);expected[i]=(unsigned char)value;',
                   f' REQUIRE({name}_write(i,value)==expected[i]);',
                   f' REQUIRE(memcmp(p_{name},expected,{n})==0);',
                   f' p_{name}[i]^=0xa5;expected[i]^=0xa5;REQUIRE({name}_read(i)==expected[i]);',
                   '}', f'memcpy(p_{name},expected_{name},{n});', '}']
        expected_count += 1+4*n
    wrappers += ['''export function l $data_unaligned_long() {
@e
%p =l add $data_default, 7
%x =l loadl %p
ret %x
}''', '''export function l $data_call_probe() {
@e
%p =l copy $data_default
%before =l loadub %p
call $data_external_mutate(l %p)
%after =l loadub %p
%scaled =l mul %before, 257
%r =l add %scaled, %after
ret %r
}''', '''export function $data_global_blit() {
@e
blit $data_default, $data_zero, 15
ret
}''']
    declarations += ['extern uint64_t data_unaligned_long(void),data_call_probe(void);',
                     'extern void data_global_blit(void);',
                     'void data_external_mutate(unsigned char *p) { if(p!=data_default) abort();p[0]^=0x5a; }']
    checks += ['REQUIRE(data_unaligned_long()==UINT64_C(81985529216486895));',
               'REQUIRE(data_call_probe()==UINT64_C(17)*257+(17^0x5a));',
               'REQUIRE(data_default[0]==(17^0x5a));',
               'data_global_blit();REQUIRE(memcmp(data_zero,data_default,15)==0);',
               'for(size_t i=15;i<257;++i) REQUIRE(data_zero[i]==0);']
    expected_count += 4+242
    # Count the PIE-only high-address precondition for every object separately.
    c = '\n'.join(['#include <stdint.h>', '#include <stdio.h>', '#include <stdlib.h>', '#include <string.h>',
                   *declarations,
                   '#define REQUIRE(c) do {++count;if(!(c)){fprintf(stderr,"data check %zu failed at line %d\\n",count,__LINE__);return 1;}} while(0)',
                   'int main(int argc,char **argv) { (void)argv;size_t count=0;', *checks,
                   f'if(count!={expected_count}+(argc>1?{len(objects)}:0)) return 3;',
                   'printf("%zu native packed-data byte/address/mutation checks passed\\n",count);return 0;}'])
    with tempfile.TemporaryDirectory(prefix='zbe-data-') as directory:
        work = Path(directory)
        source, assembly, driver, binary = [work/n for n in ('data.ssa','data.s','driver.c','test')]
        source.write_text((root/'src/fixtures/data-oracle.ssa').read_text()+'\n'+'\n'.join(wrappers)+'\n')
        driver.write_text(c)
        run([compiler,*flags,str(source),str(assembly)])
        symbol_count = 0
        for pie in (False,True):
            mode = ['-fPIE','-pie'] if pie else ['-fno-pie','-no-pie']
            run([args.cc,'-std=c11','-O2','-Wall','-Wextra','-Werror',*mode,str(driver),str(assembly),'-o',str(binary)])
            run([str(binary),*(['high-address'] if pie else [])])
            # Parse independent ELF metadata, not assembly spelling alone.
            elf = run(['readelf','--wide','--symbols',str(binary)],capture_output=True,text=True).stdout
            table = {}
            for line in elf.splitlines():
                fields = line.split()
                if len(fields) == 8 and fields[0].endswith(':'):
                    table[fields[7]] = fields
            for name, alignment, exported, payload in objects:
                fields = table.get(name)
                if fields is None or fields[3] != 'OBJECT' or fields[4] != ('GLOBAL' if exported else 'LOCAL') or int(fields[2]) != len(payload) or int(fields[1],16)%alignment:
                    raise SystemExit(f'Wrong linked object metadata for {name}: {fields}')
                symbol_count += 1
        assert symbol_count == 20
        print('20 ELF data size/binding/alignment checks passed')
        # A module containing no functions must still be a usable compilation unit.
        source.write_text('export data $data_only = align 64 { b 17, h 8755, z 3, l -1 }\n')
        run([compiler,*flags,str(source),str(assembly)])
        driver.write_text('#include <stdint.h>\n#include <string.h>\nextern unsigned char data_only[];\nint main(void) { const unsigned char expected[]={17,51,34,0,0,0,255,255,255,255,255,255,255,255}; return (uintptr_t)data_only%64 || memcmp(data_only,expected,14); }\n')
        for mode in (['-fno-pie','-no-pie'],['-fPIE','-pie']):
            run([args.cc,'-std=c11','-O2','-Wall','-Wextra','-Werror',*mode,str(driver),str(assembly),'-o',str(binary)])
            run([str(binary)])
        print('2 data-only executable linking checks passed')
        bad = [
            'data $x = align 0 {}','data $x = align 3 {}','data $x = align 128 {}',
            'data $x = { z -1 }','data $x = { z 4294967296 }','data $x = { z 16777217 }',
            'data $x = { z 1 2 }','data $x = { b }','data $x = { b 1 h 2 }','data $x = { b 1,, }',
            'data $x = { l $other }','data $x = { l $other+8 }','data $x = { b "string" }',
            'data $"quoted" = {}','thread data $x = {}','section "custom" data $x = {}',
            'data $x = { s d_1 }','data $x = { s 1 }','data $x = { d d_nan(payload) }',
            'data $x = {}\ndata $x = {}',
            'data $x = {}\nfunction $x() {\n@e\nret\n}',
            'function $x() {\n@e\nret\n}\ndata $x = {}',
            'data $x = {}\nfunction $f() {\n@e\ncall $x()\nret\n}',
            '\n'.join(f'data $x{i} = {{ z 16777216 }}' for i in range(5)),
        ]
        assert len(bad) == 24
        for text in bad:
            source.write_text(text)
            if assembly.exists(): assembly.unlink()
            for exists in (False,True):
                if exists: assembly.write_text('preserve-data-output')
                result = subprocess.run([compiler,*flags,str(source),str(assembly)],capture_output=True,timeout=30)
                if result.returncode == 0:
                    raise SystemExit('Invalid/unsupported data input accepted')
                if (exists and assembly.read_text()!='preserve-data-output') or (not exists and assembly.exists()):
                    raise SystemExit('Rejected data input changed output')
        print('48 data rejection/output-preservation checks passed')


if __name__ == '__main__':
    main()
