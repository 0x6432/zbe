#!/usr/bin/env python3
"""Generate independent masked-shift and signed/unsigned comparison cases."""
from pathlib import Path
import argparse
import operator
import random


def generate() -> str:
    rng = random.Random(0x51424532)
    predicates = {
        "ceq": (operator.eq, False), "cne": (operator.ne, False),
        "cslt": (operator.lt, True), "csle": (operator.le, True),
        "csgt": (operator.gt, True), "csge": (operator.ge, True),
        "cult": (operator.lt, False), "cule": (operator.le, False),
        "cugt": (operator.gt, False), "cuge": (operator.ge, False),
    }
    lines = ["# result-type opcode lhs-decimal rhs-decimal expected-bits-decimal"]
    for width, spelling in ((32, "w"), (64, "l")):
        mask, sign = (1 << width) - 1, 1 << (width - 1)
        boundaries = [0, 1, 2, sign - 1, sign, mask, -1, 1 << width, (1 << width) + 1]
        counts = [0, 1, width - 1, width, width + 1, 255, 0xFFFFFFFF, 0x80000000, 1 << 64]
        for opcode in ("shl", "shr", "sar"):
            for index in range(32):
                lhs = boundaries[index % len(boundaries)] if index < 18 else rng.getrandbits(64)
                rhs = counts[index % len(counts)] if index < 18 else rng.getrandbits(64)
                bits, amount = lhs & mask, (rhs & 0xFFFFFFFF) & (width - 1)
                if opcode == "shl":
                    expected = (bits << amount) & mask
                elif opcode == "shr":
                    expected = bits >> amount
                else:
                    signed = bits if bits < sign else bits - (1 << width)
                    expected = (signed >> amount) & mask
                lines.append(f"{spelling}\t{opcode}\t{lhs}\t{rhs}\t{expected}")
        for prefix, (predicate, signed) in predicates.items():
            for index in range(32):
                if index < 18:
                    lhs = boundaries[index % len(boundaries)]
                    rhs = boundaries[(index // 2) % len(boundaries)]
                else:
                    lhs, rhs = rng.getrandbits(64), rng.getrandbits(64)
                a, b = lhs & mask, rhs & mask
                if signed:
                    a = a if a < sign else a - (1 << width)
                    b = b if b < sign else b - (1 << width)
                result_type = "w" if index % 2 == 0 else "l"
                lines.append(f"{result_type}\t{prefix}{spelling}\t{lhs}\t{rhs}\t{int(predicate(a, b))}")
    return "\n".join(lines) + "\n"


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    path = Path(__file__).resolve().parents[1] / "src/fixtures/scalar-extra-oracle.tsv"
    expected = generate()
    if args.check:
        if path.read_text(encoding="ascii") != expected:
            raise SystemExit("Scalar oracle fixture is stale")
        print("832 Python shift/comparison oracle cases verified.")
    else:
        path.write_text(expected, encoding="ascii")
        print("Wrote 832 Python shift/comparison oracle cases.")


if __name__ == "__main__":
    main()
