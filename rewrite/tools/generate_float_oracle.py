#!/usr/bin/env python3
"""Generate finite-input IEEE binary32/64 arithmetic expectations with exact fractions.

Round to nearest, ties to even; no host float arithmetic supplies expected bits.
NaN payload arithmetic and non-default rounding modes are outside this fixture.
"""
from pathlib import Path
from fractions import Fraction
import argparse
import random


def decode(bits: int, fraction_bits: int, exponent_bits: int) -> Fraction:
    bias = (1 << (exponent_bits - 1)) - 1
    exponent = (bits >> fraction_bits) & ((1 << exponent_bits) - 1)
    assert exponent != (1 << exponent_bits) - 1
    significand = bits & ((1 << fraction_bits) - 1)
    if exponent:
        significand |= 1 << fraction_bits
    power = (exponent - bias if exponent else 1 - bias) - fraction_bits
    value = Fraction(significand << power) if power >= 0 else Fraction(significand, 1 << -power)
    return -value if bits >> (fraction_bits + exponent_bits) else value


def rounded(value: Fraction, fraction_bits: int, exponent_bits: int, negative_zero: bool = False) -> int:
    sign = int(value < 0 or (value == 0 and negative_zero)) << (fraction_bits + exponent_bits)
    if value == 0:
        return sign
    n, d = abs(value.numerator), value.denominator
    bias = (1 << (exponent_bits - 1)) - 1
    exponent = n.bit_length() - d.bit_length()
    if (n < d << exponent) if exponent >= 0 else (n << -exponent < d):
        exponent -= 1
    exponent = max(exponent, 1 - bias)
    scale = fraction_bits - exponent
    if scale >= 0:
        n <<= scale
    else:
        d <<= -scale
    q, r = divmod(n, d)
    if r * 2 > d or (r * 2 == d and q & 1):
        q += 1
    if q >= 1 << (fraction_bits + 1):
        q >>= 1
        exponent += 1
    if exponent > bias:
        return sign | (((1 << exponent_bits) - 1) << fraction_bits)
    if q < 1 << fraction_bits:
        return sign | q
    return sign | ((exponent + bias) << fraction_bits) | (q - (1 << fraction_bits))


def generate() -> dict[str, str]:
    rng = random.Random(0x46504F5241434C45)
    rows = ["# type opcode lhs-bits-decimal rhs-bits-decimal expected-bits-decimal"]
    functions = []
    for ty, p, e in (("s", 23, 8), ("d", 52, 11)):
        sign = 1 << (p + e)
        exponent_mask = ((1 << e) - 1) << p
        one = ((1 << (e - 1)) - 1) << p
        bounds = [0, sign, 1, sign | 1, (1 << p) - 1, 1 << p,
                  one, one | sign, one + 1, one - 1, exponent_mask - 1,
                  (exponent_mask - 1) | sign, (1 << p) + 1]
        for bits in bounds:
            assert rounded(decode(bits, p, e), p, e, bool(bits & sign)) == bits
        assert rounded(Fraction(1, 3), p, e) == (0x3EAAAAAB if ty == "s" else 0x3FD5555555555555)
        for op in ("add", "sub", "mul", "div"):
            functions.append(f"export function {ty} $fp_{op}_{ty}({ty} %a, {ty} %b) {{\n@entry\n%r ={ty} {op} %a, %b\nret %r\n}}")
            for index in range(64):
                if index < 26:
                    a, b = bounds[index % len(bounds)], bounds[(index * 3 + 1) % len(bounds)]
                else:
                    a, b = rng.getrandbits(p + e + 1), rng.getrandbits(p + e + 1)
                    if a & exponent_mask == exponent_mask: a ^= 1 << p
                    if b & exponent_mask == exponent_mask: b ^= 1 << p
                x, y = decode(a, p, e), decode(b, p, e)
                if op == "div" and not y:
                    b, y = one, Fraction(1)
                if op == "add": value, neg_zero = x + y, bool(a & sign and b & sign)
                elif op == "sub": value, neg_zero = x - y, bool(a & sign and not b & sign)
                elif op == "mul": value, neg_zero = x * y, bool((a ^ b) & sign)
                else: value, neg_zero = x / y, bool((a ^ b) & sign)
                rows.append(f"{ty}\t{op}\t{a}\t{b}\t{rounded(value, p, e, neg_zero)}")
        for name, instruction in (("copy", "copy"), ("neg", "neg")):
            functions.append(f"export function {ty} $fp_{name}_{ty}({ty} %a) {{\n@entry\n%r ={ty} {instruction} %a\nret %r\n}}")
        functions.append(f"""export function {ty} $fp_swap_{ty}(w %n, {ty} %a0, {ty} %b0) {{
@entry
jmp @loop
@loop
%i =w phi @entry 0, @body %next
%a ={ty} phi @entry %a0, @body %b
%b ={ty} phi @entry %b0, @body %a
%more =w cultw %i, %n
jnz %more, @body, @done
@body
%next =w add %i, 1
jmp @loop
@done
ret %a
}}""")
    return {"float-oracle.tsv": "\n".join(rows) + "\n", "float-operations.ssa": "\n".join(functions) + "\n"}


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[1] / "src/fixtures"
    for name, content in generate().items():
        path = root / name
        if args.check:
            if path.read_text(encoding="ascii") != content:
                raise SystemExit(f"Floating fixture is stale: {name}")
        else:
            path.write_text(content, encoding="ascii")
    print("512 exact-rational floating oracle cases " + ("verified." if args.check else "written."))


if __name__ == "__main__":
    main()
