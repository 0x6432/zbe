#!/usr/bin/env python3
"""Reproducible integer semantics oracle; not needed to run Zig tests."""
from pathlib import Path
import argparse
import operator
import random


def generate() -> str:
    rng = random.Random(0x5A42454E)
    boundaries = [
        0, 1, 2, 0x7FFFFFFF, 0x80000000, 0xFFFFFFFF,
        0x100000000, 0x100000001, 0x7FFFFFFFFFFFFFFF,
        0x8000000000000000, 0xFFFFFFFFFFFFFFFF,
    ]
    operations = {
        "add": operator.add, "sub": operator.sub, "mul": operator.mul,
        "bit_and": operator.and_, "bit_or": operator.or_, "bit_xor": operator.xor,
    }
    lines = ["# width opcode lhs-decimal rhs-decimal expected-bits-decimal"]
    for width, spelling in ((32, "w"), (64, "l")):
        mask = (1 << width) - 1
        for name, operation in operations.items():
            for index in range(32):
                if index < len(boundaries):
                    lhs = boundaries[index]
                    rhs = boundaries[(index * 3 + 1) % len(boundaries)]
                else:
                    lhs, rhs = rng.getrandbits(64), rng.getrandbits(64)
                result = operation(lhs & mask, rhs & mask) & mask
                lines.append(f"{spelling}\t{name}\t{lhs}\t{rhs}\t{result}")
    return "\n".join(lines) + "\n"


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    path = Path(__file__).resolve().parents[1] / "src/fixtures/integer-oracle.tsv"
    expected = generate()
    if args.check:
        if path.read_text(encoding="ascii") != expected:
            raise SystemExit("Integer oracle fixture is stale; regenerate it.")
        print("384 Python integer oracle cases verified.")
    else:
        path.write_text(expected, encoding="ascii")
        print("Wrote 384 Python integer oracle cases.")


if __name__ == "__main__":
    main()
