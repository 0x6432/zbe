#!/usr/bin/env python3
"""Generate same-width casts and exact single-to-double widening expectations."""
from pathlib import Path
import argparse
import random
from generate_float_oracle import decode, rounded


def generate() -> str:
    rng = random.Random(0x43415354455854)
    lines = ["# result-type opcode operand-type operand-bits expected-bits"]
    for result, source, width in (("w", "s", 32), ("s", "w", 32), ("l", "d", 64), ("d", "l", 64)):
        sign = 1 << (width - 1)
        inf = 0x7F800000 if width == 32 else 0x7FF0000000000000
        boundaries = [0, sign, 1, sign | 1, inf, inf | sign, inf | 1, inf | sign | 0x1234, inf | (1 << (22 if width == 32 else 51)), (1 << width) - 1]
        for i in range(64):
            bits = boundaries[i] if i < len(boundaries) else rng.getrandbits(width)
            lines.append(f"{result}\tcast\t{source}\t{bits}\t{bits}")
    boundaries = [0, 0x80000000, 1, 0x80000001, 0x7FFFFF, 0x800000,
                  0x3F800000, 0xBF800000, 0x7F7FFFFF, 0xFF7FFFFF, 0x7F800000, 0xFF800000]
    for i in range(128):
        bits = boundaries[i] if i < len(boundaries) else rng.getrandbits(32)
        if i >= len(boundaries) and bits & 0x7F800000 == 0x7F800000:
            bits ^= 1 << 23
        if bits & 0x7FFFFFFF == 0x7F800000:
            expected = (int(bool(bits >> 31)) << 63) | 0x7FF0000000000000
        else:
            expected = rounded(decode(bits, 23, 8), 52, 11, bool(bits >> 31))
        lines.append(f"d\texts\ts\t{bits}\t{expected}")
    return "\n".join(lines) + "\n"


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    path = Path(__file__).resolve().parents[1] / "src/fixtures/conversion-oracle.tsv"
    content = generate()
    if args.check:
        if path.read_text(encoding="ascii") != content:
            raise SystemExit("Conversion oracle fixture is stale")
    else:
        path.write_text(content, encoding="ascii")
    print("384 cast/widening oracle cases " + ("verified." if args.check else "written."))


if __name__ == "__main__":
    main()
