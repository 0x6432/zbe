#!/usr/bin/env python3
"""Generate floating comparison truth values from integer classification/fractions."""
from pathlib import Path
import argparse
import operator
import random
from generate_float_oracle import decode


def classification(bits: int, p: int, e: int):
    exponent = (bits >> p) & ((1 << e) - 1)
    fraction = bits & ((1 << p) - 1)
    if exponent == (1 << e) - 1:
        if fraction:
            return None
        return (-1 if bits >> (p + e) else 1, 0)
    return (0, decode(bits, p, e))


def generate() -> str:
    rng = random.Random(0x46434D504F524143)
    lines = ["# result-type opcode operand-type lhs-bits rhs-bits expected"]
    comparisons = {"ceq": operator.eq, "cne": operator.ne, "clt": operator.lt, "cle": operator.le, "cgt": operator.gt, "cge": operator.ge}
    for ty, p, e in (("s", 23, 8), ("d", 52, 11)):
        sign = 1 << (p + e)
        inf = ((1 << e) - 1) << p
        one = ((1 << (e - 1)) - 1) << p
        boundaries = [0, sign, 1, sign | 1, one, one | sign, inf, inf | sign, inf | (1 << (p - 1)), inf | 1, inf | sign | 0x1234, inf - 1]
        pairs = [(a, b) for a in boundaries for b in boundaries]
        pairs += [(rng.getrandbits(p + e + 1), rng.getrandbits(p + e + 1)) for _ in range(16)]
        for prefix in (*comparisons, "co", "cuo"):
            for index, (a, b) in enumerate(pairs):
                lhs, rhs = classification(a, p, e), classification(b, p, e)
                unordered = lhs is None or rhs is None
                if prefix == "co": result = not unordered
                elif prefix == "cuo": result = unordered
                elif unordered: result = prefix == "cne"
                else: result = comparisons[prefix](lhs, rhs)
                result_type = "w" if index % 2 == 0 else "l"
                lines.append(f"{result_type}\t{prefix}{ty}\t{ty}\t{a}\t{b}\t{int(result)}")
    return "\n".join(lines) + "\n"


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    path = Path(__file__).resolve().parents[1] / "src/fixtures/float-comparison-oracle.tsv"
    content = generate()
    if args.check:
        if path.read_text(encoding="ascii") != content:
            raise SystemExit("Floating comparison fixture is stale")
    else:
        path.write_text(content, encoding="ascii")
    print("2560 floating comparison oracle cases " + ("verified." if args.check else "written."))


if __name__ == "__main__":
    main()
