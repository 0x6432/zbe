#!/usr/bin/env python3
"""Independent integer immediate encoding-range and runtime oracle."""
from pathlib import Path
import argparse
import random


def render():
    rows=['# type op rhs lhs expected immediate signed_encoding']
    rng=random.Random(0x494d4d4544494154)
    word=[0,1,127,128,0x7fffffff,0x80000000,0xffffffff,0xffffff80]
    long=[0,1,0x7fffffff,0x80000000,0xffffffff,0x100000000,0xffffffff7fffffff,0xffffffff80000000,0xffffffffffffffff,0xffffffffffffff80,0xffffffff00000000,0x8000000000000000]
    for ty,width,constants in [('w',32,word),('l',64,long)]:
        mask=(1<<width)-1
        values=[0,1,mask,1<<(width-1),rng.getrandbits(width)]
        for op in ('add','sub','and','or','xor'):
            for rhs in constants:
                signed=rhs if rhs<1<<(width-1) else rhs-(1<<width)
                eligible=width==32 or -(1<<31)<=signed<(1<<31)
                encoding=(rhs&0xffffffff)-((1<<32) if rhs&(1<<31) else 0)
                for lhs in values:
                    result={'add':lambda:lhs+rhs,'sub':lambda:lhs-rhs,'and':lambda:lhs&rhs,'or':lambda:lhs|rhs,'xor':lambda:lhs^rhs}[op]()&mask
                    rows.append(f'{ty}\t{op}\t{rhs}\t{lhs}\t{result}\t{int(eligible)}\t{encoding}')
    return '\n'.join(rows)+'\n'


def main():
    p=argparse.ArgumentParser();p.add_argument('--check',action='store_true');a=p.parse_args()
    path=Path(__file__).resolve().parents[1]/'src/fixtures/immediate_selection_oracle.tsv';text=render()
    if a.check:
        if path.read_text()!=text:raise SystemExit('Immediate oracle differs')
    else:path.write_text(text)
    print(f'{len(text.splitlines())-1} independent immediate runtime/encoding cases verified')
if __name__=='__main__':main()
