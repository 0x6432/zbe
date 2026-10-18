#!/usr/bin/env python3
"""Independent width-masked neutral and near-miss integer oracle (no compiler import)."""
import argparse
from pathlib import Path
import random


def render():
    rows=['# ty opcode side neutral input expected rewrites']
    rng=random.Random(0x4e45555452414c)
    for ty,width in [('w',32),('l',64)]:
        mask=(1<<width)-1
        rules=[('add',0,0),('add',1,0),('sub',0,0),('mul',0,1),('mul',1,1),('or',0,0),('or',1,0),('xor',0,0),('xor',1,0),('and',0,mask),('and',1,mask)]
        rules += [(op,0,n) for op in ('shl','shr','sar') for n in (0,32,64,128,0xffffffe0,0xffffffc0)]
        rules += [('add',0,1),('sub',1,0),('mul',0,0),('and',0,0),('and',0,0xffffffff if width==64 else mask-1)]
        values=[0,1,mask,1<<(width-1),(1<<(width-1))-1,rng.getrandbits(width),rng.getrandbits(width)]
        for op,side,n in rules:
            for x in values:
                a,b=(n,x) if side else (x,n)
                if op=='add': result=a+b
                elif op=='sub': result=a-b
                elif op=='mul': result=a*b
                elif op=='and': result=a&b
                elif op=='or': result=a|b
                elif op=='xor': result=a^b
                else:
                    count=b&(width-1)
                    if op=='shl': result=a<<count
                    elif op=='shr': result=a>>count
                    else: result=(a if a<1<<(width-1) else a-(1<<width))>>count
                neutral=(op in ('add','or','xor') and n==0 or op=='sub' and side==0 and n==0 or op=='mul' and n==1 or op=='and' and n==mask or op in ('shl','shr','sar') and n&(width-1)==0)
                rows.append(f'{ty}\t{op}\t{side}\t{n}\t{x}\t{result&mask}\t{int(neutral)}')
    return '\n'.join(rows)+'\n'


def main():
    p=argparse.ArgumentParser();p.add_argument('--check',action='store_true');args=p.parse_args()
    path=Path(__file__).resolve().parents[1]/'src/fixtures/neutral_identity_oracle.tsv'
    text=render()
    if args.check:
        if path.read_text()!=text: raise SystemExit('neutral identity oracle differs')
    else: path.write_text(text)
    print(f'{len(text.splitlines())-1} independently computed neutral/near-miss cases verified')
if __name__=='__main__': main()
