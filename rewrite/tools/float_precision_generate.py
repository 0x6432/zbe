#!/usr/bin/env python3
"""Independent exact binary32 -> binary64 expectations using integer field mapping.

No host floating arithmetic, production Zig semantics, or existing float oracle.
Finite values are exact; NaNs deliberately excluded from exact payload promises.
"""
from pathlib import Path
import argparse
import random


def widen(bits):
    sign = (bits >> 31) << 63
    exponent, fraction = (bits >> 23) & 255, bits & 0x7fffff
    if exponent == 255:
        assert fraction == 0, 'NaN payload conversion is not an exact contract'
        return sign | (2047 << 52)
    if exponent:
        return sign | ((exponent + 896) << 52) | (fraction << 29)
    if fraction == 0:
        return sign
    # f * 2^-149: normalize directly into binary64's 53-bit significand.
    highest = fraction.bit_length() - 1
    return sign | ((highest + 874) << 52) | ((fraction - (1 << highest)) << (52 - highest))


def rows():
    values = {0, 0x80000000, 0x7f800000, 0xff800000}
    for exponent in range(1, 255):
        for fraction in (0, 1, 0x3fffff, 0x400000, 0x7ffffe, 0x7fffff):
            for sign in (0, 0x80000000):
                values.add(sign | (exponent << 23) | fraction)
    for position in range(23):
        for fraction in ((1 << position) - 1, 1 << position, (1 << position) + 1):
            for sign in (0, 0x80000000):
                values.add(sign | fraction)
    rng = random.Random(0x4558545350524543)
    for _ in range(512):
        bits = rng.getrandbits(32)
        if bits & 0x7f800000 != 0x7f800000:
            values.add(bits)
    return [(bits, widen(bits)) for bits in sorted(values)]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--check', action='store_true')
    args = parser.parse_args()
    # Independent known-value anchors protect bias/subnormal normalization errors.
    assert widen(1) == 0x36a0000000000000
    assert widen(0x7fffff) == 0x380fffffc0000000
    assert widen(0x800000) == 0x3810000000000000
    assert widen(0x3f800000) == 0x3ff0000000000000
    assert widen(0x7f7fffff) == 0x47efffffe0000000
    assert widen(0x80000000) == 0x8000000000000000
    content = '# binary32-bits binary64-bits (hex); exact exts, not NaN payloads\n'
    cases = rows()
    content += ''.join(f'{source:08x}\t{result:016x}\n' for source, result in cases)
    path = Path(__file__).resolve().parents[1] / 'src/fixtures/float_precision_oracle.tsv'
    if args.check:
        if path.read_text(encoding='ascii') != content:
            raise SystemExit('Float precision fixture is stale')
    else:
        path.write_text(content, encoding='ascii')
    print(f'{len(cases)} exact float precision cases ' + ('verified' if args.check else 'written'))


if __name__ == '__main__':
    main()
