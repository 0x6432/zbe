#!/usr/bin/env python3
"""Independent byte values and canonical escapes, never parser/assembler-derived."""
from pathlib import Path
import argparse


def quoted(payload):
    return '"'+''.join('\\%03o'%value for value in payload)+'"'


def generate():
    injection=b'.text\n.globl zbe_injected_symbol\n# $x, "quote" \\ end'
    cases=[
        ('string_plain',8,True,'b "hello world", b 0',b'hello world\0'),
        ('string_all',64,True,'b '+quoted(bytes(range(256))),bytes(range(256))),
        ('string_escapes',2,False,r'b "\"\\\n\r\t\a\b\f\v\101\7\00\x41"',bytes([34,92,10,13,9,7,8,12,11,65,7,0,65])),
        ('string_utf8',1,True,'b "λ🙂"','λ🙂'.encode()),
        ('string_injection',16,False,'b '+quoted(injection),injection),
        ('string_empty',8,True,'b ""',b''),
        ('string_mixed',4,True,r'b "A" 255 "B\000C", h 8755, z 3, b 0',b'A\xffB\0C\x33\x22\0\0\0\0'),
        ('string_escape_edges',32,True,r'b "\1" "\12" "\123" "\377" "\x00" "\xFf" "\x414"',bytes([1,10,83,255,0,255,65,52])),
    ]
    source=['# Independent bytes; explicit escapes and no automatic terminator.']
    rows=['# name alignment exported expected-byte-hex (dash means empty)']
    for name,alignment,exported,body,payload in cases:
        source.append(f'{"export " if exported else ""}data ${name} = align {alignment} {{ {body} }}')
        rows.append(f'{name}\t{alignment}\t{int(exported)}\t{payload.hex() or "-"}')
    return {'data-string-oracle.ssa':'\n'.join(source)+'\n','data-string-oracle.tsv':'\n'.join(rows)+'\n'}


def main():
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--check',action='store_true');args=parser.parse_args()
    root=Path(__file__).resolve().parents[1]/'src/fixtures'
    for name,text in generate().items():
        path=root/name
        if args.check:
            if not path.exists() or path.read_text()!=text:raise SystemExit(f'Stale data-string oracle: {name}')
        else:path.write_text(text)
    print('Independent data-string byte oracle reproducible' if args.check else 'Wrote independent data-string byte oracle')


if __name__=='__main__':main()
