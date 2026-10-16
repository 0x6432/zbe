#!/usr/bin/env python3
"""Generate scalar memory byte-order/extension expectations using Python bytes."""
from pathlib import Path
import argparse
import random


def generate() -> str:
    rng = random.Random(0x4d454d4f5259)
    patterns = [0, 1, (1 << 64)-1, 0x8000000000000000, 0x80000000,
                0x8000, 0x80, 0x7f, 0xff, 0xffff, 0xffffffff,
                0x7fc12345, 0xffc12345, 0x7ff8123456789abc, 0xfff8123456789abc,
                0x7f812345, 0x7ff0123456789abc]
    patterns += [rng.getrandbits(64) for _ in range(32-len(patterns))]
    loads = [(op, ty, width, signed) for op, width, signed in (
        ('loadsb',1,True),('loadub',1,False),('loadsh',2,True),('loaduh',2,False),
        ('loadsw',4,True),('loaduw',4,False),('loadw',4,True)) for ty in ('w','l')]
    loads += [('loadl','l',8,False),('loads','s',4,False),('loadd','d',8,False)]
    stores = [('storeb','w',1),('storeh','w',2),('storew','w',4),
              ('storel','l',8),('stores','s',4),('stored','d',8)]
    lines = ['# direction endian opcode type input-hex expected-hex-or-decimal']
    for endian in ('little','big'):
        for opcode, ty, width, signed in loads:
            for raw in patterns:
                # Same physical bytes in both endian images: interpretation differs.
                data = raw.to_bytes(8,'little')
                result_bits = 32 if ty in ('w','s') else 64
                expected = int.from_bytes(data[:width], endian, signed=signed) & ((1<<result_bits)-1)
                lines.append(f'L\t{endian}\t{opcode}\t{ty}\t{data.hex()}\t{expected}')
        for opcode, ty, width in stores:
            for raw in patterns:
                value = raw & ((1 << (32 if ty in ('w','s') else 64))-1)
                expected = (value & ((1 << (width*8))-1)).to_bytes(width,endian).hex()
                lines.append(f'S\t{endian}\t{opcode}\t{ty}\t{value:x}\t{expected}')
    return '\n'.join(lines)+'\n'


def main() -> None:
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--check',action='store_true')
    args=parser.parse_args()
    path=Path(__file__).resolve().parents[1]/'src/fixtures/memory-oracle.tsv'
    expected=generate()
    if args.check:
        if path.read_text(encoding='ascii') != expected:
            raise SystemExit('Memory oracle fixture is stale')
        print('1472 Python memory load/store byte-order cases verified.')
    else:
        path.write_text(expected,encoding='ascii')
        print('Wrote 1472 Python memory load/store byte-order cases.')


if __name__=='__main__':
    main()
