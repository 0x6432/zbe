#!/usr/bin/env python3
"""Bounded scalar memory checks for native Linux AMD64, not a memory sandbox."""
from pathlib import Path
import argparse
import platform
import resource
import signal
import subprocess
import tempfile


def main() -> None:
    root = Path(__file__).resolve().parents[1]
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--compiler', type=Path, default=root / 'zig-out/bin/zbe-native')
    parser.add_argument('--cc', default='cc')
    for flag in ('fold-integers', 'reuse-stack-homes', 'callee-saved-homes'):
        parser.add_argument('--' + flag, action='store_true')
    args = parser.parse_args()
    if platform.system() != 'Linux' or platform.machine() not in ('x86_64', 'amd64'):
        raise SystemExit('Native memory checks require Linux x86_64; no result claimed.')
    resource.setrlimit(resource.RLIMIT_CORE, (0, 0))
    flags = ['--' + f for f in ('fold-integers', 'reuse-stack-homes', 'callee-saved-homes') if getattr(args, f.replace('-', '_'))]
    il, declarations, cases, checks = [], [], [], []
    # Expected results use Python byte decoding and explicit modulo widths, never
    # generated code, host sign-extension casts or production semantic helpers.
    patterns = [0, (1 << 64) - 1, 0x8000000000000000, 0x7fffffffffffffff,
                0x80000000, 0xffffffff00000000, 0x7fc12345, 0x7ff8123456789abc,
                0xfff8123456789abc, 0x8000800080008000]
    patterns += [int.from_bytes(bytes((v + i * 37) & 255 for i in range(8)), 'little') for v in range(256)]
    loads = [(op, ty, size, signed) for op, size, signed in (
        ('loadsb', 1, True), ('loadub', 1, False), ('loadsh', 2, True), ('loaduh', 2, False),
        ('loadsw', 4, True), ('loaduw', 4, False), ('loadw', 4, True)) for ty in ('w', 'l')]
    loads += [('loadl', 'l', 8, False), ('loads', 's', 4, False), ('loadd', 'd', 8, False)]
    for n, (op, ty, size, signed) in enumerate(loads):
        cast = f'\n%bits ={ "w" if ty == "s" else "l"} cast %v' if ty in ('s', 'd') else ''
        result_type = 'w' if ty in ('w', 's') else 'l'
        il.append(f'export function {result_type} $mem_load_{n}(l %p) {{\n@e\n%v ={ty} {op} %p{cast}\nret %{ "bits" if cast else "v"}\n}}')
        ctype = 'uint32_t' if result_type == 'w' else 'uint64_t'
        declarations.append(f'extern {ctype} mem_load_{n}(uint64_t);')
        expected = [int.from_bytes(p.to_bytes(8, 'little')[:size], 'little', signed=signed) & ((1 << (32 if result_type == 'w' else 64)) - 1) for p in patterns]
        cases.append(f'static const uint64_t expected_{n}[] = {{' + ','.join(f'UINT64_C({v})' for v in expected) + '};')
        checks.append(f'''for (size_t i=0; i<N; ++i) for (size_t offset=0; offset<8; ++offset) {{
            memset(buffer, 0xa5, sizeof buffer); memcpy(buffer+offset, &patterns[i], 8);
            REQUIRE(mem_load_{n}((uint64_t)(uintptr_t)(buffer+offset)) == expected_{n}[i]);
        }}
        /* The exact access must not touch the following PROT_NONE page. */
        for (size_t i=0; i<N; ++i) {{
            memcpy(boundary-{size}, &patterns[i], {size});
            REQUIRE(mem_load_{n}((uint64_t)(uintptr_t)(boundary-{size})) == expected_{n}[i]);
        }}''')
    stores = [('storeb','w',1), ('storeh','w',2), ('storew','w',4), ('storel','l',8), ('stores','s',4), ('stored','d',8)]
    for n, (op, ty, size) in enumerate(stores):
        input_type = 'w' if ty in ('w','s') else 'l'
        cast = f'\n%v ={ty} cast %bits' if ty in ('s', 'd') else ''
        il.append(f'export function $mem_store_{n}(l %p, {input_type} %bits) {{\n@e{cast}\n{op} %{ "v" if cast else "bits"}, %p\nret\n}}')
        ctype = 'uint32_t' if input_type == 'w' else 'uint64_t'
        declarations.append(f'extern void mem_store_{n}(uint64_t, {ctype});')
        checks.append(f'''for (size_t i=0; i<N; ++i) for (size_t offset=0; offset<8; ++offset) {{
            memset(buffer, 0xa5, sizeof buffer); memset(expected_buffer, 0xa5, sizeof expected_buffer);
            memcpy(expected_buffer+offset, &patterns[i], {size});
            mem_store_{n}((uint64_t)(uintptr_t)(buffer+offset), ({ctype})patterns[i]);
            REQUIRE(memcmp(buffer, expected_buffer, sizeof buffer) == 0);
        }}
        for (size_t i=0; i<N; ++i) {{
            memset(boundary-16, 0xa5, 16); memset(expected_buffer, 0xa5, 16);
            memcpy(expected_buffer+16-{size}, &patterns[i], {size});
            mem_store_{n}((uint64_t)(uintptr_t)(boundary-{size}), ({ctype})patterns[i]);
            REQUIRE(memcmp(boundary-16, expected_buffer, 16) == 0);
        }}''')
    il.append('''export function l $mem_effects(l %p, l %q, w %count) {
@entry
storel 0, %p
jmp @loop
@loop
%i =w phi @entry %count, @body %next
jnz %i, @body, @done
@body
%v =l loadl %p
%n =l add %v, 1
storel %n, %p
%next =w sub %i, 1
jmp @loop
@done
%before =l loadl %p
call $memory_mutate(l %p)
%after =l loadl %p
%r =l add %before, %after
storel %r, %q
ret %r
}
export function l $mem_alias(l %p) {
@entry
storel %p, %p
%x =l loadl %p
ret %x
}
export function w $mem_dead_load(l %p) {
@entry
%dead =l loadl %p
ret 42
}
export function $mem_fault_store(l %p) {
@entry
storeb 7, %p
ret
}
export function w $mem_safe_branch(l %p, w %take) {
@entry
jnz %take, @read, @safe
@read
%x =w loadw %p
ret %x
@safe
ret 42
}
export function $mem_literal_store(l %p) {
@entry
storeb 511, %p
%q =l add %p, 1
storeh 305419896, %q
%r =l add %p, 3
storew 2882400001, %r
%s =l add %p, 7
storel 18364758544493064720, %s
ret
}''')
    declarations += ['extern uint64_t mem_effects(uint64_t,uint64_t,uint32_t);', 'extern uint64_t mem_alias(uint64_t);',
                     'extern uint32_t mem_dead_load(uint64_t);', 'extern void mem_fault_store(uint64_t);',
                     'extern uint32_t mem_safe_branch(uint64_t,uint32_t);', 'extern void mem_literal_store(uint64_t);']
    # More simultaneous pointer/value homes than the five preserved registers,
    # and pointer parameters beyond the six GP argument registers.
    il.append('export function l $mem_pressure(' + ', '.join(f'l %p{i}' for i in range(10)) + ') {\n@e\n' +
              '\n'.join(f'%v{i} =l loadl %p{i}' for i in range(10)) + '\n' +
              '\n'.join(f'storel %v{9-i}, %p{i}' for i in range(10)) + '\n' +
              '%sum0 =l add %v0, %v1\n' + '\n'.join(f'%sum{i-1} =l add %sum{i-2}, %v{i}' for i in range(2,10)) + '\nret %sum8\n}')
    declarations.append('extern uint64_t mem_pressure(' + ','.join(['uint64_t']*10) + ');')
    # Callee sees the actual valid buffer. memcpy avoids alignment/aliasing UB in C.
    helpers = '''void memory_mutate(uint64_t p) { uint64_t x; memcpy(&x,(void *)(uintptr_t)p,8); x += 17; memcpy((void *)(uintptr_t)p,&x,8); }
static uint64_t preserved_case(void) { unsigned char p[8], q[8]; return mem_effects((uint64_t)(uintptr_t)p,(uint64_t)(uintptr_t)q,3); }
extern uint64_t zbe_check_preserved(uint64_t (*)(void));'''
    checks.append('''unsigned char pressure[10][16];
    for (size_t i=0;i<10;++i) { uint64_t v=i+1; memcpy(pressure[i]+1,&v,8); }
    REQUIRE(mem_pressure(''' + ','.join(f'(uint64_t)(uintptr_t)(pressure[{i}]+1)' for i in range(10)) + ''') == 55);
    for (size_t i=0;i<10;++i) { uint64_t v; memcpy(&v,pressure[i]+1,8); REQUIRE(v == 10-i); }
    for (uint32_t n=0;n<40;++n) {
        uint64_t q=0, p=0;
        REQUIRE(mem_effects((uint64_t)(uintptr_t)&p,(uint64_t)(uintptr_t)&q,n) == (uint64_t)n*2+17);
        REQUIRE(q == (uint64_t)n*2+17); REQUIRE(p == (uint64_t)n+17);
    }
    REQUIRE(zbe_check_preserved(preserved_case) == 0);
    REQUIRE(mem_alias((uint64_t)(uintptr_t)buffer) == (uint64_t)(uintptr_t)buffer);
    REQUIRE(mem_safe_branch((uint64_t)(uintptr_t)boundary,0) == 42);
    REQUIRE(((uint64_t)(uintptr_t)boundary >> 32) != 0);
    memset(buffer,0xa5,sizeof buffer); memset(expected_buffer,0xa5,sizeof expected_buffer);
    mem_literal_store((uint64_t)(uintptr_t)buffer);
    { const unsigned char bytes[] = {255,120,86,1,239,205,171,16,50,84,118,152,186,220,254}; memcpy(expected_buffer,bytes,sizeof bytes); }
    REQUIRE(memcmp(buffer,expected_buffer,sizeof buffer) == 0);''')
    # 17 load variants + six stores, each 266 patterns * (8 offsets + boundary).
    expected_checks = (len(loads) + len(stores)) * len(patterns) * 9 + 40 * 3 + 5 + 11
    c = '''#define _GNU_SOURCE
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <unistd.h>
''' + '\n'.join(declarations) + '\n' + helpers + '\n' + '\n'.join(cases)
    c += '\nstatic const uint64_t patterns[] = {' + ','.join(f'UINT64_C({p})' for p in patterns) + '};\n'
    c += '''#define N (sizeof patterns / sizeof patterns[0])
#define REQUIRE(c) do { ++count; if (!(c)) { fprintf(stderr,"memory check %zu failed at line %d\\n",count,__LINE__); return 1; } } while (0)
int main(int argc, char **argv) {
    size_t count=0; long page = sysconf(_SC_PAGESIZE);
    if (page < 32) return 2;
    unsigned char *mapping = mmap(NULL,(size_t)page*2,PROT_READ|PROT_WRITE,MAP_PRIVATE|MAP_ANONYMOUS,-1,0);
    if (mapping == MAP_FAILED || mprotect(mapping+page,(size_t)page,PROT_NONE)) return 2;
    unsigned char *boundary=mapping+page;
    if (argc == 2) {
        if (!strcmp(argv[1],"load")) return (int)mem_dead_load((uint64_t)(uintptr_t)boundary);
        if (!strcmp(argv[1],"store")) { mem_fault_store((uint64_t)(uintptr_t)boundary); return 3; }
        return 2;
    }
    unsigned char buffer[32], expected_buffer[32];
''' + '\n'.join(checks) + f'\nif (count != {expected_checks}) return 2;\nprintf("%zu native scalar-memory checks passed\\n",count);\n'
    c += 'if (munmap(mapping,(size_t)page*2)) return 2;\nreturn 0;\n}\n'
    with tempfile.TemporaryDirectory(prefix='zbe-memory-') as directory:
        work = Path(directory)
        src, asm, driver, binary = [work / n for n in ('memory.ssa', 'memory.s', 'main.c', 'check')]
        src.write_text('\n'.join(il) + '\n')
        driver.write_text(c)
        subprocess.run([str(args.compiler.resolve()), *flags, str(src), str(asm)], check=True, timeout=90)
        subprocess.run([args.cc, '-std=c11', '-O2', '-Wall', '-Wextra', '-Werror', '-fPIE', '-pie', str(driver), str(asm), str(root / 'src/fixtures/check-preserved.s'), '-o', str(binary)], check=True, timeout=90)
        subprocess.run([str(binary)], check=True, timeout=30)
        for effect in ('load', 'store'):
            result = subprocess.run([str(binary), effect], capture_output=True, timeout=10)
            if result.returncode != -signal.SIGSEGV:
                raise SystemExit(f'{effect}: expected guard-page SIGSEGV, got {result.returncode}')
        print('2 memory fault-retention checks passed')
        # Parse/type failures must leave either absent or existing output alone.
        invalid = {
            'load-address': 'function w $f(w %p) {\n@e\n%x =w loadw %p\nret %x\n}',
            'store-value': 'function $f(s %v) {\n@e\nstoreb %v, 0\nret\n}',
            'load-result': 'function s $f(l %p) {\n@e\n%x =s loadub %p\nret %x\n}',
            'store-address': 'function $f(w %p) {\n@e\nstorew 1, %p\nret\n}',
        }
        for text in invalid.values():
            src.write_text(text)
            asm.unlink()
            for exists in (False, True):
                if exists:
                    asm.write_text('preserve-memory-output')
                result = subprocess.run([str(args.compiler.resolve()), *flags, str(src), str(asm)], capture_output=True, timeout=30)
                if result.returncode == 0:
                    raise SystemExit('Invalid memory form accepted')
                if (exists and asm.read_text() != 'preserve-memory-output') or (not exists and asm.exists()):
                    raise SystemExit('Invalid memory form changed output')
        print('8 memory rejection/output-preservation checks passed')


if __name__ == '__main__':
    main()
