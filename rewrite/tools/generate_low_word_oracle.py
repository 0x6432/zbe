#!/usr/bin/env python3
"""Exact integer oracle for explicit long-to-word operand projections."""
from pathlib import Path
import random
import argparse


def generate() -> dict[str,str]:
    rng=random.Random(0x4c4f57574f5244)
    mask=(1<<32)-1
    operations=('add','sub','mul','and','or','xor','shl','shr','sar','div','rem','udiv','urem','neg','extub','extsb')
    rows=['# function-index long-x long-y expected-word']
    functions=[]
    for index,op in enumerate(operations):
        arguments='%x' if op in ('neg','extub','extsb') else '%x, %y'
        functions.append(f'export function w $low_word_{op}(l %x,l %y) {{\n@entry\n%r =w {op} {arguments}\nret %r\n}}')
        for i in range(64):
            edges=(0,1,mask,1<<31,(1<<31)-1,0x80000001,31,32,63,64)
            x=edges[i%len(edges)] if i<32 else rng.getrandbits(32)
            y=edges[(i*3+1)%len(edges)] if i<32 else rng.getrandbits(32)
            sx=x if x<(1<<31) else x-(1<<32)
            sy=y if y<(1<<31) else y-(1<<32)
            if op in ('div','rem') and (sy==0 or (sx==-(1<<31) and sy==-1)):
                y=3;sy=3
            if op in ('udiv','urem') and y==0: y=3;sy=3
            if op=='add': result=x+y
            elif op=='sub': result=x-y
            elif op=='mul': result=x*y
            elif op=='and': result=x&y
            elif op=='or': result=x|y
            elif op=='xor': result=x^y
            elif op=='shl': result=x<<(y&31)
            elif op=='shr': result=x>>(y&31)
            elif op=='sar': result=sx>>(y&31)
            elif op in ('div','rem'):
                q=(abs(sx)//abs(sy))*(-1 if (sx<0)!=(sy<0) else 1)
                result=q if op=='div' else sx-q*sy
            elif op=='udiv': result=x//y
            elif op=='urem': result=x%y
            elif op=='neg': result=-x
            elif op=='extub': result=x&255
            else: result=(x&255)-(256 if x&128 else 0)
            long_x=(rng.randrange(1,1<<32)<<32)|x
            long_y=(rng.randrange(1,1<<32)<<32)|y
            rows.append(f'{index}\t{long_x}\t{long_y}\t{result&mask}')
    assert len(rows)==1025
    return {'low-word-oracle.tsv':'\n'.join(rows)+'\n','low-word-operations.ssa':'\n'.join(functions)+'\n'}


def main() -> None:
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--check',action='store_true');args=parser.parse_args()
    root=Path(__file__).resolve().parents[1]/'src/fixtures'
    for name,text in generate().items():
        path=root/name
        if args.check:
            if path.read_text(encoding='ascii')!=text: raise SystemExit('Low-word fixture is stale: '+name)
        else: path.write_text(text,encoding='ascii')
    print('1024 Python low-word projection cases '+('verified.' if args.check else 'written.'))


if __name__=='__main__':main()
