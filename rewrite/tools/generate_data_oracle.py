#!/usr/bin/env python3
"""Independent int/struct byte expectations for numeric/zero-fill data definitions."""
from pathlib import Path
import argparse
import random
import struct


def generate():
    rng = random.Random(0x4441544142595445)
    source = ['# Independent packed numeric objects; no compiler-derived expectations.']
    rows = ['# name alignment exported little-endian-hex (dash means empty)']
    objects = []
    for index, alignment in enumerate((1, 2, 4, 8, 16, 32, 64)):
        groups, payload = [], bytearray()
        for kind, width in (('b', 1), ('h', 2), ('w', 4), ('l', 8)):
            values = [0, 1, -1, 1 << (8*width-1), (1 << (8*width))+17,
                      -(1 << 70)-129, (1 << 80)+0x123456789abcdef, rng.getrandbits(64)]
            groups.append(kind + ' ' + ' '.join(map(str, values)))
            for value in values:
                payload += (value % (1 << (width*8))).to_bytes(width, 'little')
        for kind, code in (('s', 'f'), ('d', 'd')):
            spellings = ['0', '-0', '1.5', '-2.25', '0x1.8p+3', 'inf', '-inf', '0x1p-126' if kind == 's' else '0x1p-1022']
            groups.append(kind + ' ' + ' '.join(kind+'_'+v for v in spellings))
            for text in spellings:
                value = float.fromhex(text) if '0x' in text else float(text)
                payload += struct.pack('<'+code, value)
        groups += ['z 0', f'z {index+1}', 'b 165', 'z 3', 'l -1']
        payload += bytes(index+1) + bytes([165]) + bytes(3) + bytes([255])*8
        name = f'data_oracle_{index}'
        objects.append((name, alignment, index % 2 == 0, groups, payload))
    objects += [('data_default', 8, True, ['b 17', 'h 8755', 'w 1146447479', 'l 81985529216486895'],
                 bytes.fromhex('11332277665544efcdab8967452301')),
                ('data_empty', 8, True, [], b''),
                ('data_zero', 16, True, ['z 257'], bytes(257))]
    for name, alignment, exported, groups, payload in objects:
        prefix = 'export ' if exported else ''
        align = '' if name in ('data_default', 'data_empty') else f'align {alignment} '
        source.append(f'{prefix}data ${name} = {align}{{\n ' + ',\n '.join(groups) + (',\n' if groups else '') + '}')
        rows.append(f'{name}\t{alignment}\t{int(exported)}\t{payload.hex() or "-"}')
    assert len(objects) == 10
    return {'data-oracle.ssa': '\n'.join(source)+'\n', 'data-oracle.tsv': '\n'.join(rows)+'\n'}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--check', action='store_true')
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[1]/'src/fixtures'
    for name, text in generate().items():
        path = root/name
        if args.check:
            if not path.exists() or path.read_text() != text:
                raise SystemExit(f'Data oracle is stale: {path.name}')
        else:
            path.write_text(text)
    print('Independent data-byte oracle reproducible' if args.check else 'Wrote independent data-byte oracle')


if __name__ == '__main__':
    main()
