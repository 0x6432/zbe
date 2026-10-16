#!/usr/bin/env python3
"""Assemble/link/run base-scalar SSE and mixed SysV argument regressions."""
from pathlib import Path
import argparse
import platform
import subprocess
import tempfile


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    root = Path(__file__).resolve().parents[1]
    parser.add_argument("--compiler", type=Path, default=root / "zig-out/bin/zbe-native")
    parser.add_argument("--cc", default="cc")
    args = parser.parse_args()
    if platform.system() != "Linux" or platform.machine() not in ("x86_64", "amd64"):
        raise SystemExit("Native execution requires Linux x86_64; no result claimed.")
    declarations = ["#include <stdint.h>", "#include <stdio.h>", "#include <string.h>", "#include <fenv.h>",
                    "static float f32(uint32_t v) { float f; memcpy(&f, &v, 4); return f; }",
                    "static double f64(uint64_t v) { double f; memcpy(&f, &v, 8); return f; }",
                    "static uint32_t b32(float f) { uint32_t v; memcpy(&v, &f, 4); return v; }",
                    "static uint64_t b64(double f) { uint64_t v; memcpy(&v, &f, 8); return v; }"]
    functions = [(root / "src/fixtures/float-operations.ssa").read_text()]
    checks = []

    def check(expression: str, expected: int) -> None:
        index = len(checks)
        checks.append(f'if ((uint64_t)({expression}) != UINT64_C({expected})) {{ fprintf(stderr, "floating check {index} failed\\n"); return 1; }}')

    for ty, width, ctype in (("s", 32, "float"), ("d", 64, "double")):
        for op in ("add", "sub", "mul", "div"):
            declarations.append(f"extern {ctype} fp_{op}_{ty}({ctype}, {ctype});")
        for op in ("copy", "neg"):
            declarations.append(f"extern {ctype} fp_{op}_{ty}({ctype});")
        declarations.append(f"extern {ctype} fp_swap_{ty}(uint32_t, {ctype}, {ctype});")
        sign = 1 << (width - 1)
        inf = 0x7F800000 if width == 32 else 0x7FF0000000000000
        for bits in (0, sign, 1, sign | 1, inf, inf | sign, inf | 0x1234, inf | (1 << (22 if width == 32 else 51)) | 0x1234):
            for op in ("copy", "neg"):
                check(f"b{width}(fp_{op}_{ty}(f{width}(UINT{width}_C({bits}))))", bits if op == "copy" else bits ^ sign)
            for n in range(4):
                other = bits ^ sign
                check(f"b{width}(fp_swap_{ty}({n}, f{width}(UINT{width}_C({bits})), f{width}(UINT{width}_C({other}))))", bits if n % 2 == 0 else other)
    for line in (root / "src/fixtures/float-oracle.tsv").read_text().splitlines():
        if not line or line.startswith("#"):
            continue
        ty, op, a, b, expected = line.split()
        width = 32 if ty == "s" else 64
        check(f"b{width}(fp_{op}_{ty}(f{width}(UINT{width}_C({a})), f{width}(UINT{width}_C({b}))))", int(expected))
    conversion_functions = set()
    conversion_cases = 0
    ctypes = {"w": "uint32_t", "l": "uint64_t", "s": "float", "d": "double"}
    for line in (root / "src/fixtures/conversion-oracle.tsv").read_text().splitlines():
        if not line or line.startswith("#"):
            continue
        result_ty, opcode, source_ty, bits, expected = line.split()
        name = f"convert_{opcode}_{result_ty}"
        if name not in conversion_functions:
            functions.append(f"export function {result_ty} ${name}({source_ty} %v) {{\n@b\n%r ={result_ty} {opcode} %v\nret %r\n}}")
            declarations.append(f"extern {ctypes[result_ty]} {name}({ctypes[source_ty]});")
            conversion_functions.add(name)
        width = 32 if source_ty in ("w", "s") else 64
        argument = f"UINT{width}_C({bits})"
        if source_ty in ("s", "d"):
            argument = f"f{width}({argument})"
        expression = f"{name}({argument})"
        if result_ty in ("s", "d"):
            expression = f"b{32 if result_ty == 's' else 64}({expression})"
        check(expression, int(expected))
        conversion_cases += 1
    assert conversion_cases == 384 and len(conversion_functions) == 5
    comparison_functions = set()
    comparison_cases = 0
    for line in (root / "src/fixtures/float-comparison-oracle.tsv").read_text().splitlines():
        if not line or line.startswith("#"):
            continue
        result_ty, opcode, operand_ty, a, b, expected = line.split()
        name = f"compare_{opcode}_{result_ty}"
        ctype = "float" if operand_ty == "s" else "double"
        if name not in comparison_functions:
            functions.append(f"export function {result_ty} ${name}({operand_ty} %a, {operand_ty} %b) {{\n@entry\n%r ={result_ty} {opcode} %a, %b\nret %r\n}}")
            declarations.append(f"extern {ctypes[result_ty]} {name}({ctype}, {ctype});")
            comparison_functions.add(name)
        width = 32 if operand_ty == "s" else 64
        check(f"{name}(f{width}(UINT{width}_C({a})), f{width}(UINT{width}_C({b})))", int(expected))
        comparison_cases += 1
    assert comparison_cases == 2560 and len(comparison_functions) == 32
    # Exercise both register banks and their independent exhaustion. Stack slots
    # retain declaration order across floating and integer overflow arguments.
    for ty, ctype in (("s", "float"), ("d", "double")):
        for order in ("interleaved", "floats_first"):
            fp = [(ty, f"f{i}", ctype, i + 1) for i in range(10)]
            gp = [("w" if i % 2 == 0 else "l", f"g{i}", "uint32_t" if i % 2 == 0 else "uint64_t", 20 + i) for i in range(8)]
            parameters = [item for i in range(10) for item in ([fp[i], gp[i]] if i < 8 else [fp[i]])] if order == "interleaved" else fp + gp
            for result_kind in ("fp", "gp"):
                name = f"mixed_{ty}_{order}_{result_kind}"
                result_ty, result_ctype = (ty, ctype) if result_kind == "fp" else ("l", "uint64_t")
                body, terms = [], []
                for i, (arg_ty, arg_name, _, _) in enumerate(fp if result_kind == "fp" else gp):
                    source = f"%{arg_name}"
                    if result_kind == "gp" and arg_ty == "w":
                        body.append(f"%e{i} =l extuw {source}")
                        source = f"%e{i}"
                    factor = f"{ty}_{i + 2}" if result_kind == "fp" else str(i + 2)
                    body.append(f"%m{i} ={result_ty} mul {source}, {factor}")
                    terms.append(f"%m{i}")
                body.append(f"%sum0 ={result_ty} copy {terms[0]}")
                for i, term in enumerate(terms[1:], 1):
                    body.append(f"%sum{i} ={result_ty} add %sum{i - 1}, {term}")
                params = ", ".join(f"{p_ty} %{n}" for p_ty, n, _, _ in parameters)
                functions.append(f"export function {result_ty} ${name}({params}) {{\n@entry\n" + "\n".join(body) + f"\nret %sum{len(terms) - 1}\n}}")
                declarations.append(f"extern {result_ctype} {name}(" + ", ".join(p_c for _, _, p_c, _ in parameters) + ");")
                expression = name + "(" + ", ".join(str(v) for _, _, _, v in parameters) + ")"
                expected = sum(v * (i + 2) for i, (_, _, _, v) in enumerate(fp if result_kind == "fp" else gp))
                # These small positive integers are exact in both IEEE formats.
                if result_kind == "fp":
                    check(f"{expression} == {expected}", 1)
                else:
                    check(expression, expected)
    with tempfile.TemporaryDirectory(prefix="zbe-float-check-") as directory:
        work = Path(directory)
        source, output, driver, executable = (work / n for n in ("input.ssa", "output.s", "driver.c", "test"))
        source.write_text("\n".join(functions) + "\n")
        driver.write_text("\n".join(declarations) + "\nint main(void) {\nif (fesetround(FE_TONEAREST)) return 2;\n" + "\n".join(checks) + f'\nputs("{len(checks)} native floating/bit-pattern/mixed-ABI checks passed");\nreturn 0;\n}}\n')
        for command in ([str(args.compiler.resolve()), str(source), str(output)], [args.cc, "-std=c11", "-O2", "-Wall", "-Wextra", "-Werror", "-no-pie", str(driver), str(output), "-lm", "-o", str(executable)], [str(executable)]):
            subprocess.run(command, check=True, timeout=90)


if __name__ == "__main__":
    main()
