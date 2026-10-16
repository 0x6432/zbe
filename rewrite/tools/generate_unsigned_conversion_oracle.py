#!/usr/bin/env python3
"""Exact Fraction expectations for defined unsigned conversions, nearest-even."""
from pathlib import Path
from fractions import Fraction
import argparse
import random
from generate_float_oracle import decode, rounded


def generate() -> dict[str, str]:
    rng = random.Random(0x554e5349474e4544)
    rows = ['# result-type opcode source-type source-bits expected-bits']
    functions = []
    for integer_ty, width in (('w', 32), ('l', 64)):
        maximum = (1 << width) - 1
        for float_ty, p, e in (('s', 23, 8), ('d', 52, 11)):
            to_float = 'uwtof' if integer_ty == 'w' else 'ultof'
            to_integer = 'stoui' if float_ty == 's' else 'dtoui'
            functions += [f'export function {float_ty} $unsigned_{to_float}_{float_ty}({integer_ty} %v) {{\n@e\n%r ={float_ty} {to_float} %v\nret %r\n}}',
                          f'export function {integer_ty} $unsigned_{to_integer}_{integer_ty}({float_ty} %v) {{\n@e\n%r ={integer_ty} {to_integer} %v\nret %r\n}}']
            # High-half sticky-halving must preserve ties and either side of them.
            integers = [0, 1, 2, maximum, maximum-1, maximum-2]
            for power in (p, p+1, p+2, 31, 32, 63, 64):
                if power > width: continue
                center = 1 << power
                step = 1 << max(0, power-p)
                for v in (center-2, center-1, center, center+1, center+2,
                          center+step//2-1, center+step//2, center+step//2+1,
                          center+3*step//2-1, center+3*step//2, center+3*step//2+1):
                    if 0 <= v <= maximum: integers.append(v)
            while len(integers) < 128: integers.append(rng.randrange(maximum+1))
            assert len(integers) <= 128
            for value in integers:
                rows.append(f'{float_ty}\t{to_float}\t{integer_ty}\t{value}\t{rounded(Fraction(value),p,e)}')
            sign = 1 << (p+e)
            candidates = [0, sign, 1, sign|1]
            for value in (Fraction(1,2), Fraction(-1,2), Fraction(-3,4), Fraction(3,2),
                          Fraction((1 << 31)), Fraction((1 << 32)),
                          Fraction(1 << 63), Fraction(1 << 64), Fraction(maximum),
                          Fraction(maximum)+Fraction(1,2)):
                bits = rounded(value,p,e)
                candidates += [bits, bits-1 if bits else 0, bits+1]
            selected = []
            while len(selected) < 128:
                bits = candidates.pop(0) if candidates else rng.getrandbits(p+e+1)
                if ((bits >> p) & ((1 << e)-1)) == (1 << e)-1: continue
                truncated = int(decode(bits,p,e))
                if 0 <= truncated <= maximum: selected.append((bits,truncated))
            for bits, expected in selected:
                rows.append(f'{integer_ty}\t{to_integer}\t{float_ty}\t{bits}\t{expected}')
    assert len(rows) == 1025
    return {'unsigned-conversion-oracle.tsv':'\n'.join(rows)+'\n', 'unsigned-conversions.ssa':'\n'.join(functions)+'\n'}


def main() -> None:
    parser=argparse.ArgumentParser(description=__doc__); parser.add_argument('--check', action='store_true'); args=parser.parse_args()
    root=Path(__file__).resolve().parents[1]/'src/fixtures'
    for name,text in generate().items():
        path=root/name
        if args.check:
            if path.read_text(encoding='ascii') != text: raise SystemExit('Unsigned conversion fixture is stale: '+name)
        else: path.write_text(text,encoding='ascii')
    print('1024 exact unsigned numeric-conversion cases '+('verified.' if args.check else 'written.'))


if __name__ == '__main__': main()
