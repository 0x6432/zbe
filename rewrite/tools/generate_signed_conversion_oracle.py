#!/usr/bin/env python3
"""Exact Fraction expectations for defined signed numeric conversions, nearest-even."""
from pathlib import Path
from fractions import Fraction
import argparse
import random
from generate_float_oracle import decode, rounded


def generate() -> dict[str, str]:
    rng=random.Random(0x5349474e4544)
    rows=['# result-type opcode source-type source-bits expected-bits']
    functions=[]
    for integer_ty,width in (('w',32),('l',64)):
        lo,hi=-(1<<(width-1)),(1<<(width-1))-1
        for float_ty,p,e in (('s',23,8),('d',52,11)):
            to_float='swtof' if integer_ty=='w' else 'sltof'
            to_integer='stosi' if float_ty=='s' else 'dtosi'
            functions += [f'export function {float_ty} $signed_{to_float}_{float_ty}({integer_ty} %v) {{\n@e\n%r ={float_ty} {to_float} %v\nret %r\n}}',
                          f'export function {integer_ty} $signed_{to_integer}_{integer_ty}({float_ty} %v) {{\n@e\n%r ={integer_ty} {to_integer} %v\nret %r\n}}']
            integers=[0,1,-1,lo,hi,lo+1,hi-1]
            for power in (23,24,25,52,53,54):
                integers += [v for v in ((1<<power)-1,1<<power,(1<<power)+1,-(1<<power)-1) if lo<=v<=hi]
            while len(integers)<64:
                integers.append(rng.randrange(lo,hi+1))
            for value in integers[:64]:
                rows.append(f'{float_ty}\t{to_float}\t{integer_ty}\t{value & ((1<<width)-1)}\t{rounded(Fraction(value),p,e)}')
            sign=1<<(p+e)
            candidates=[0,sign,1,sign|1]
            for value in (Fraction(lo),Fraction(hi),Fraction(lo)-Fraction(1,2),Fraction(hi)+Fraction(1,2),
                          Fraction(-3,2),Fraction(3,2),Fraction(-1,2),Fraction(1,2),Fraction(-7),Fraction(7)):
                bits=rounded(value,p,e)
                candidates += [bits,bits-1 if bits else 0,bits+1]
            selected=[]
            while len(selected)<64:
                bits=candidates.pop(0) if candidates else rng.getrandbits(p+e+1)
                if ((bits>>p)&((1<<e)-1))==((1<<e)-1): continue
                exact=decode(bits,p,e)
                truncated=int(exact)
                if lo<=truncated<=hi:
                    selected.append((bits,truncated & ((1<<width)-1)))
            for bits,expected in selected:
                rows.append(f'{integer_ty}\t{to_integer}\t{float_ty}\t{bits}\t{expected}')
    assert len(rows)==513
    return {'signed-conversion-oracle.tsv':'\n'.join(rows)+'\n','signed-conversions.ssa':'\n'.join(functions)+'\n'}


def main() -> None:
    parser=argparse.ArgumentParser(description=__doc__); parser.add_argument('--check',action='store_true'); args=parser.parse_args()
    root=Path(__file__).resolve().parents[1]/'src/fixtures'
    for name,text in generate().items():
        path=root/name
        if args.check:
            if path.read_text(encoding='ascii')!=text: raise SystemExit('Signed conversion fixture is stale: '+name)
        else: path.write_text(text,encoding='ascii')
    print('512 exact signed numeric-conversion cases '+('verified.' if args.check else 'written.'))


if __name__=='__main__': main()
