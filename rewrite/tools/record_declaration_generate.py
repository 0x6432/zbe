#!/usr/bin/env python3
"""Independent mathematical record-layout expectations; no host/compiler layout.
Uses division/remainders, arbitrary-precision integers and compact field runs.
"""
from pathlib import Path
import argparse
import random


def generate():
    layouts={}
    source=[]
    rows=['# T name explicit-or-0 alignment size run-count; R name index member count offset stride']
    sizes={'b':1,'h':2,'w':4,'l':8,'s':4,'d':8}
    def add(name,fields,explicit=0):
        cursor=0;align=explicit or 1;runs=[]
        for member,count in fields:
            if member.startswith(':'):
                size,natural=layouts[member[1:]][:2]
            else:size=natural=sizes[member]
            offset=cursor+(-cursor % natural)
            cursor=offset+size*count
            align=max(align,natural)
            runs.append((member,count,offset,size))
        total=((cursor+align-1)//align)*align
        assert 0<total<1<<64
        layouts[name]=(total,align,runs)
        source.append('type :'+name+' = '+(f'align {explicit} ' if explicit else '')+'{ '+', '.join(member+(f' {count}' if count!=1 else '') for member,count in fields)+' }')
        rows.append(f'T\t{name}\t{explicit}\t{align}\t{total}\t{len(runs)}')
        rows.extend(f'R\t{name}\t{i}\t{member}\t{count}\t{offset}\t{stride}' for i,(member,count,offset,stride) in enumerate(runs))
    add('Pair',[('b',1),('w',1)])
    add('Packet',[(':Pair',2),('h',1)])
    add('Explicit16',[('b',1),('w',2)],16)
    add('Minimum2',[('d',1),('b',1)],2)
    add('Mixed',[(x,1) for x in 'bhwsld'])
    assert layouts['Pair'][:2]==(8,4)
    assert layouts['Packet'][:2]==(20,4)
    assert layouts['Explicit16'][:2]==(16,16)
    assert layouts['Minimum2'][:2]==(16,8)
    assert layouts['Mixed'][:2]==(32,8)
    for alignment in (1,2,4,8,16,32,64):
        add('Aligned'+str(alignment),[('b',3),('h',2),('s',3),('l',2)],alignment)
    rng=random.Random(0x5245434f524453)
    for index in range(256):
        fields=[]
        for _ in range(rng.randrange(1,9)):
            # A bounded earlier DAG, not recursive expansion of nested records.
            member=':'+rng.choice(list(layouts)) if rng.randrange(3)==0 else rng.choice(list(sizes))
            fields.append((member,rng.choice((1,2,3,7,16,31))))
        add('Generated'+str(index),fields,rng.choice((0,0,1,2,4,8,16,32,64)))
    a=(1<<31)-1
    add('ExtremeA',[('b',a)])
    add('ExtremeB',[(':ExtremeA',a)])
    add('ExtremeC',[(':ExtremeB',4),(':ExtremeA',8),('b',3)])
    assert layouts['ExtremeB'][0]==4611686014132420609
    assert layouts['ExtremeC'][0]==(1<<64)-1
    return '\n'.join(source)+'\n','\n'.join(rows)+'\n',len(layouts)


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--check',action='store_true')
    args=parser.parse_args()
    source,oracle,count=generate()
    directory=Path(__file__).resolve().parents[1]/'src/fixtures'
    for name,content in [('record_declaration_layouts.ssa',source),('record_declaration_oracle.tsv',oracle)]:
        path=directory/name
        if args.check:
            if path.read_text(encoding='ascii')!=content:raise SystemExit('Record fixture stale: '+name)
        else:path.write_text(content,encoding='ascii')
    print(f'{count} independent compact record layouts '+('verified' if args.check else 'written'))


if __name__=='__main__':main()
