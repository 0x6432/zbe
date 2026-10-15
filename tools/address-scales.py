#!/usr/bin/env python3
"""AMD64 address scales: C memory oracle, shape checks and six-target -O0 identity.
Only valid addresses are dereferenced. High-bit and negative indexes exercise
64-bit shift wraparound; word shifts must wrap BEFORE zero extension.
"""
import os
from pathlib import Path
import random
import re
import shlex
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parent.parent
Z = os.environ.get('ZQBE', str(ROOT / 'zig-out/bin/qbe'))
REF = os.environ.get('QBEREF', '/data/qbe-cfix/qbe')
TARGETS = ['amd64_sysv', 'amd64_apple', 'amd64_win', 'arm64', 'arm64_apple', 'rv64']

def run(args, **kw):
    return subprocess.run(args, check=True, capture_output=True, text=True, timeout=120, **kw)

def main():
    env = dict(os.environ)
    env.pop('QBE_COMPAT', None)
    cases = [('shl', 'l', n, 0) for n in (0, 1, 2, 3, 4, 63, 64, 65)]
    cases += [('mul', 'l', n, 0) for n in (1, 2, 3)]
    cases += [('shl', 'w', n, 0) for n in (1, 2, 3)]
    # Displacements just inside/outside signed 32-bit encoding after scaling.
    for count in (1, 2, 3):
        bound = 1 << (31 - count)
        cases += [('shl', 'l', count, bias) for bias in
                  (bound - 1, bound, -bound, -bound - 1, 1073741824, -1073741824)]
    il, c, checks = [], ['#include <stdint.h>\n#include <stdio.h>'], []
    rng = random.Random(934701)
    indexes = [0, 1, 15, 127, 0xffffffffffffffff, 0xfffffffffffffff0,
               1 << 63, (1 << 63) + 1, 1 << 32, (1 << 32) + 1,
               0xffffffff, 0x80000000]
    indexes += [rng.getrandbits(64) for _ in range(512)]
    for number, (op, cls, count, bias) in enumerate(cases):
        name = f'scale{number}'
        operand = count if op == 'shl' else 1 << count
        value = '%biased' if bias else '%x'
        shift = (f'    %biased ={cls} add %x, {bias}\n' if bias else '')
        shift += f'    %s ={cls} {op} {value}, {operand}\n'
        widen = '    %wide =l extuw %s\n' if cls == 'w' else ''
        off = '%wide' if cls == 'w' else '%s'
        for store in (False, True):
            symbol = name + ('store' if store else 'load')
            il.append(f'export function l ${symbol}(l %base, {cls} %x) {{\n@start\n'
                      + shift + widen + f'    %p =l add %base, {off}\n'
                      + ('    storeb 173, %p\n' + f'    ret {off}\n' if store else
                         '    %v =w loadub %p\n    %ret =l extuw %v\n    ret %ret\n') + '}\n')
            c.append(f'extern uint64_t {symbol}(unsigned char *, uint{32 if cls == "w" else 64}_t);')
        valid = []
        width = 32 if cls == 'w' else 64
        case_indexes = list(indexes)
        if count in (1, 2, 3):
            # Random low addresses combined with high bits discarded by a
            # wrapping shift. Unlike arbitrary 64-bit indexes, all are safe.
            case_indexes += [(rng.getrandbits(count) << (width - count)) |
                             rng.randrange(128) for _ in range(64)]
        for index in case_indexes:
            x = (index - bias) & ((1 << width) - 1)
            offnum = (((x + bias) & ((1 << width) - 1)) << (count % width)) & ((1 << width) - 1)
            signed = offnum if offnum < (1 << 63) else offnum - (1 << 64)
            if -2048 <= signed <= 2048:
                valid.append((x, offnum, signed))
        assert valid
        for x, offset, signed in valid:
            checks.append(f'''{{ uint64_t x = UINT64_C({x});
  unsigned char *p = b + 4096; unsigned char *q = p + ({signed});
  *q = 91;
  if ({name}load(p, x) != 91) return puts("{name} load"), 1;
  if ({name}store(p, x) != UINT64_C({offset}) || *q != 173)
    return puts("{name} store"), 1;
}}''')
    c.append('int main(void) { unsigned char b[8192] = {0};\n' + '\n'.join(checks) + '\nreturn 0; }')
    passed = 0
    with tempfile.TemporaryDirectory(prefix='zbe-address-') as tmp:
        w = Path(tmp)
        src = w / 'f.ssa'; src.write_text('\n'.join(il))
        driver = w / 'main.c'; driver.write_text('\n'.join(c))
        native = ['-t', os.environ['QBET']] if os.environ.get('QBET') else []
        for level in (0, 1, 2):
            asm = w / 'native.s'
            run([Z, *native, f'-O{level}', '-o', str(asm), str(src)], env=env)
            exe = w / ('test.exe' if os.environ.get('QBET') == 'amd64_win' else 'test')
            try:
                run([*shlex.split(os.environ.get('CC', 'cc')), str(driver), str(asm), '-o', str(exe)])
            except subprocess.CalledProcessError as error:
                raise AssertionError('address assembly failure: ' + error.stdout + error.stderr) from error
            try:
                run([*shlex.split(os.environ.get('RUN', '')), str(exe)])
            except subprocess.CalledProcessError as error:
                raise AssertionError('memory oracle mismatch: ' + error.stdout + error.stderr) from error
            passed += 1
        for level in (1, 2):
            asm = run([Z, '-t', 'amd64_sysv', f'-O{level}', str(src)], env=env).stdout
            for number, (op, cls, count, bias) in enumerate(cases):
                if cls != 'l' or count not in (1, 2, 3) or bias:
                    continue
                for suffix in ('load', 'store'):
                    body = asm.split(f'scale{number}{suffix}:', 1)[1].split('.size', 1)[0]
                    assert re.search(r'\([^\n]*,[^\n]*,\s*' + str(1 << count) + r'\)', body), (level, number, suffix, body)
                    if suffix == 'load':
                        assert not re.search(r'\b(shl|sal|imul)', body), (level, number, body)
                    passed += 1
        # Require the reference; unavailable reference is NOT a successful check.
        for target in TARGETS:
            reference = run([REF, '-t', target, str(src)], env=env).stdout
            for flags in (['-O0'], ['-O2']):
                compat_env = dict(env)
                if flags == ['-O2']:
                    compat_env['QBE_COMPAT'] = '1'
                got = run([Z, '-t', target, *flags, str(src)], env=compat_env).stdout
                assert got == reference, ('compatibility', target, flags)
                passed += 1
    print(f'address scales: {passed} passed, 0 failed; {len(checks)} memory oracle cases per level')

if __name__ == '__main__':
    main()
