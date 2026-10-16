#!/usr/bin/env python3
"""Generate deterministic mixed-instruction/diamond/loop programs and Python results.

This is a bounded regression corpus, not a claim of exhaustive compiler fuzzing.
The oracle uses Python integer bit patterns, never the old/new compiler output.
"""
from pathlib import Path
import argparse
import random


def signed(value: int, width: int) -> int:
    return value if value < (1 << (width - 1)) else value - (1 << width)


def generate() -> dict[str, str]:
    rng = random.Random(0x5A424550524F47)
    functions, cases = [], ["# function-index type a-bits b-bits word-count expected-bits"]
    for index in range(32):
        width, ty = (32, "w") if index % 2 == 0 else (64, "l")
        mask = (1 << width) - 1
        names = ["a", "b"]
        operations = []
        body = []
        for ordinal in range(20):
            op = rng.choice(["add", "sub", "mul", "and", "or", "xor", "shl", "shr", "sar", "neg", "extsb", "extuh", "cslt", "cult", "ceq", "cne", "div", "udiv", "rem", "urem"])
            name = f"v{ordinal}"
            a, b = rng.choice(names), rng.choice(names)
            if op in ("shl", "shr", "sar"):
                text = f"{op} %{a}, %count"
            elif op == "neg":
                text = f"neg %{a}"
            elif op in ("extsb", "extuh"):
                if ty == "l":
                    a = "count"
                text = f"{op} %{a}"
            elif op in ("cslt", "cult", "ceq", "cne"):
                text = f"{op}{ty} %{a}, %{b}"
            elif op in ("div", "udiv", "rem", "urem"):
                # Positive, nonzero divisor excludes only exceptional pairs;
                # dedicated division fixtures cover all divisor signs/errors.
                body.extend([f"%small{ordinal} ={ty} and %{b}, 32767", f"%safe{ordinal} ={ty} or %small{ordinal}, 1"])
                text = f"{op} %{a}, %safe{ordinal}"
            else:
                text = f"{op} %{a}, %{b}"
            body.append(f"%{name} ={ty} {text}")
            operations.append((name, op, a, b))
            names.append(name)
        last = names[-1]
        functions.append(f"""export function {ty} $mixed_{index}({ty} %a, {ty} %b, w %count) {{
@entry
%limit =w and %count, 7
""" + "\n".join(body) + f"""
jnz %count, @left, @right
@left
%left ={ty} add %{last}, %a
jmp @join
@right
%right ={ty} xor %{last}, %b
jmp @join
@join
%base ={ty} phi @left %left, @right %right
jmp @loop
@loop
%i =w phi @join 0, @body %next
%acc ={ty} phi @join %base, @body %updated
%more =w cultw %i, %limit
jnz %more, @body, @done
@body
%mixed ={ty} xor %acc, %{last}
%updated ={ty} add %mixed, %a
%next =w add %i, 1
jmp @loop
@done
ret %acc
}}
""")
        for case in range(16):
            boundaries = [0, 1, mask, 1 << (width - 1), (1 << (width - 1)) - 1]
            a = boundaries[case] if case < len(boundaries) else rng.getrandbits(width)
            b = boundaries[-case - 1] if case < len(boundaries) else rng.getrandbits(width)
            count = [0, 1, 31, 32, 63, 64, 0xFFFFFFFF, 0x80000000][case % 8]
            values = {"a": a, "b": b, "count": count}
            for name, op, lhs_name, rhs_name in operations:
                lhs, rhs = values[lhs_name], values[rhs_name]
                if op == "add": result = lhs + rhs
                elif op == "sub": result = lhs - rhs
                elif op == "mul": result = lhs * rhs
                elif op == "and": result = lhs & rhs
                elif op == "or": result = lhs | rhs
                elif op == "xor": result = lhs ^ rhs
                elif op == "shl": result = lhs << (count % width)
                elif op == "shr": result = lhs >> (count % width)
                elif op == "sar": result = signed(lhs, width) >> (count % width)
                elif op == "neg": result = -lhs
                elif op == "extsb": result = signed(lhs & 255, 8)
                elif op == "extuh": result = lhs & 65535
                elif op == "cslt": result = int(signed(lhs, width) < signed(rhs, width))
                elif op == "cult": result = int(lhs < rhs)
                elif op == "ceq": result = int(lhs == rhs)
                elif op == "cne": result = int(lhs != rhs)
                else:
                    divisor = (rhs & 32767) | 1
                    dividend = signed(lhs, width) if op in ("div", "rem") else lhs
                    quotient = abs(dividend) // divisor
                    if dividend < 0: quotient = -quotient
                    result = quotient if op in ("div", "udiv") else dividend - quotient * divisor
                values[name] = result & mask
            result = (values[last] + a) & mask if count else values[last] ^ b
            for _ in range(count & 7):
                result = ((result ^ values[last]) + a) & mask
            cases.append(f"{index}\t{ty}\t{a}\t{b}\t{count}\t{result}")
    return {"mixed-programs.ssa": "\n".join(functions), "mixed-programs.tsv": "\n".join(cases) + "\n"}


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[1] / "src/fixtures"
    for name, content in generate().items():
        path = root / name
        if args.check:
            if path.read_text(encoding="ascii") != content:
                raise SystemExit(f"Mixed-program fixture is stale: {name}")
        else:
            path.write_text(content, encoding="ascii")
    print("32 mixed programs / 512 Python expected results " + ("verified." if args.check else "written."))


if __name__ == "__main__":
    main()
