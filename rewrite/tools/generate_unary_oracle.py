#!/usr/bin/env python3
"""Generate bit-pattern expectations independently with Python integers."""
from pathlib import Path
import argparse
import random


def generate() -> str:
    rng = random.Random(0x554E415259)
    lines = ["# result-type opcode operand-type operand-decimal expected-bits-decimal"]
    for width, ty in ((32, "w"), (64, "l")):
        mask = (1 << width) - 1
        operations = ["neg", "extsb", "extub", "extsh", "extuh"]
        if width == 64:
            operations += ["extsw", "extuw"]
        for opcode in operations:
            operand_ty = ty if opcode == "neg" else "w"
            boundaries = [0, 1, -1, 127, 128, 255, 256, 32767, 32768,
                          65535, 65536, (1 << 31) - 1, 1 << 31, (1 << 32) - 1,
                          1 << 32, (1 << 63) - 1, 1 << 63, (1 << 64) - 1, 1 << 64]
            for index in range(32):
                raw = boundaries[index] if index < len(boundaries) else rng.getrandbits(64)
                if opcode == "neg":
                    expected = (-raw) & mask
                else:
                    bits = {"b": 8, "h": 16, "w": 32}[opcode[-1]]
                    value = raw & ((1 << bits) - 1)
                    if opcode[3] == "s" and value & (1 << (bits - 1)):
                        value -= 1 << bits
                    expected = value & mask
                lines.append(f"{ty}\t{opcode}\t{operand_ty}\t{raw}\t{expected}")
    return "\n".join(lines) + "\n"


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    path = Path(__file__).resolve().parents[1] / "src/fixtures/unary-oracle.tsv"
    expected = generate()
    if args.check:
        if path.read_text(encoding="ascii") != expected:
            raise SystemExit("Unary oracle fixture is stale")
        print("384 Python negation/extension oracle cases verified.")
    else:
        path.write_text(expected, encoding="ascii")
        print("Wrote 384 Python negation/extension oracle cases.")


if __name__ == "__main__":
    main()
