#!/usr/bin/env python3
"""Generate valid division expectations without host floating-point division."""
from pathlib import Path
import argparse
import random


def generate() -> str:
    rng = random.Random(0x44495652454D)
    lines = ["# result-type opcode lhs-bits-decimal rhs-bits-decimal expected-bits-decimal"]
    for width, ty in ((32, "w"), (64, "l")):
        sign, mask = 1 << (width - 1), (1 << width) - 1
        boundaries = [0, 1, 2, 3, 7, sign - 1, sign, sign + 1, mask - 1, mask]
        for opcode in ("div", "udiv", "rem", "urem"):
            pairs = [(a, b) for a in boundaries for b in boundaries]
            pairs += [(rng.getrandbits(width), rng.getrandbits(width)) for _ in range(64)]
            for a, b in pairs:
                if b == 0:
                    continue
                if opcode in ("div", "rem"):
                    lhs = a if a < sign else a - (1 << width)
                    rhs = b if b < sign else b - (1 << width)
                    if lhs == -sign and rhs == -1:
                        continue
                    quotient = abs(lhs) // abs(rhs)
                    if (lhs < 0) != (rhs < 0):
                        quotient = -quotient
                    result = quotient if opcode == "div" else lhs - quotient * rhs
                else:
                    result = a // b if opcode == "udiv" else a % b
                lines.append(f"{ty}\t{opcode}\t{a}\t{b}\t{result & mask}")
    return "\n".join(lines) + "\n"


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    path = Path(__file__).resolve().parents[1] / "src/fixtures/division-oracle.tsv"
    expected = generate()
    count = len(expected.splitlines()) - 1
    if args.check:
        if path.read_text(encoding="ascii") != expected:
            raise SystemExit("Division oracle fixture is stale")
        print(f"{count} Python division/remainder oracle cases verified.")
    else:
        path.write_text(expected, encoding="ascii")
        print(f"Wrote {count} Python division/remainder oracle cases.")


if __name__ == "__main__":
    main()
