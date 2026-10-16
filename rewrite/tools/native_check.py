#!/usr/bin/env python3
"""Assemble/link/execute the experimental Linux AMD64 integer slice."""
from pathlib import Path
import argparse
import platform
import itertools
import re
import resource
import signal
import subprocess
import tempfile


def run(args: list[str], **kwargs) -> subprocess.CompletedProcess:
    return subprocess.run(args, check=True, timeout=90, **kwargs)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    root = Path(__file__).resolve().parents[1]
    parser.add_argument("--compiler", type=Path, default=root / "zig-out/bin/zbe-native")
    parser.add_argument("--cc", default="cc")
    parser.add_argument("--fold-integers", action="store_true")
    parser.add_argument("--reuse-stack-homes", action="store_true")
    parser.add_argument("--callee-saved-homes", action="store_true")
    args = parser.parse_args()
    if platform.system() != "Linux" or platform.machine() not in ("x86_64", "amd64"):
        raise SystemExit("Native execution requires Linux x86_64; no result claimed.")
    resource.setrlimit(resource.RLIMIT_CORE, (0, 0))
    compiler = str(args.compiler.resolve())
    compiler_flags = (["--fold-integers"] if args.fold_integers else []) + (["--reuse-stack-homes"] if args.reuse_stack_homes else []) + (["--callee-saved-homes"] if args.callee_saved_homes else [])
    declarations = ["#include <stdint.h>", "#include <stdio.h>", "#include <string.h>"]
    checks = []
    functions = []
    traps = []

    def check(expression: str, expected: int) -> None:
        index = len(checks)
        checks.append(f'if ((uint64_t)({expression}) != UINT64_C({expected})) {{ fprintf(stderr, "native check {index} failed\\n"); return 1; }}')

    for line in (root / "src/fixtures/integer-oracle.tsv").read_text().splitlines():
        if line.startswith("#") or not line:
            continue
        ty, operation, lhs, rhs, expected = line.split()
        mnemonic = {"bit_and": "and", "bit_or": "or", "bit_xor": "xor"}.get(operation, operation)
        name = f"oracle_{len(functions)}"
        functions.append(f"export function {ty} ${name}() {{\n@entry\n%x ={ty} {mnemonic} {lhs}, {rhs}\nret %x\n}}")
        declarations.append(f'extern {"uint32_t" if ty == "w" else "uint64_t"} {name}(void);')
        check(f"{name}()", int(expected))
    assert len(functions) == 384
    extra_count = 0
    for line in (root / "src/fixtures/scalar-extra-oracle.tsv").read_text().splitlines():
        if not line or line.startswith("#"):
            continue
        ty, opcode, lhs, rhs, expected = line.split()
        name = f"scalar_extra_{extra_count}"
        functions.append(f"export function {ty} ${name}() {{\n@entry\n%x ={ty} {opcode} {lhs}, {rhs}\nret %x\n}}")
        declarations.append(f'extern {"uint32_t" if ty == "w" else "uint64_t"} {name}(void);')
        check(f"{name}()", int(expected))
        extra_count += 1
    assert extra_count == 832
    functions.append((root / "src/fixtures/compare-loop.ssa").read_text())
    declarations.append("extern uint64_t sum_until(uint64_t);")
    for n in (0, 1, 2, 10, 100):
        check(f"sum_until({n})", n * (n - 1) // 2)
    functions.append("export function l $shift_args(l %a, l %b, l %c, l %d, w %amount) {\n@entry\n%x =l shl %a, %amount\n%y =l add %x, %d\nret %y\n}")
    declarations.append("extern uint64_t shift_args(uint64_t, uint64_t, uint64_t, uint64_t, uint32_t);")
    for amount in (0, 65):
        check(f"shift_args(3, 0, 0, UINT64_C({1 << 36}), {amount})", (3 << (amount & 63)) + (1 << 36))
    unary_count = 0
    for line in (root / "src/fixtures/unary-oracle.tsv").read_text().splitlines():
        if not line or line.startswith("#"):
            continue
        ty, opcode, operand_ty, operand, expected = line.split()
        name = f"unary_{unary_count}"
        functions.append(f"export function {ty} ${name}({operand_ty} %v) {{\n@entry\n%x ={ty} {opcode} %v\nret %x\n}}")
        ctype = "uint32_t" if ty == "w" else "uint64_t"
        argument_ctype = "uint32_t" if operand_ty == "w" else "uint64_t"
        declarations.append(f'extern {ctype} {name}({argument_ctype});')
        bits = int(operand) & ((1 << (32 if operand_ty == "w" else 64)) - 1)
        check(f"{name}(UINT64_C({bits}))", int(expected))
        unary_count += 1
    assert unary_count == 384
    division_count = 0
    for line in (root / "src/fixtures/division-oracle.tsv").read_text().splitlines():
        if not line or line.startswith("#"):
            continue
        ty, opcode, lhs, rhs, expected = line.split()
        name = f"division_{division_count}"
        functions.append(f"export function {ty} ${name}({ty} %a, {ty} %b) {{\n@entry\n%x ={ty} {opcode} %a, %b\nret %x\n}}")
        ctype = "uint32_t" if ty == "w" else "uint64_t"
        declarations.append(f"extern {ctype} {name}({ctype}, {ctype});")
        check(f"{name}(UINT64_C({lhs}), UINT64_C({rhs}))", int(expected))
        division_count += 1
    assert division_count == 1228
    for ty, width in (("w", 32), ("l", 64)):
        for opcode in ("div", "udiv", "rem", "urem"):
            name = f"trap_{opcode}_{ty}"
            ctype = "uint32_t" if ty == "w" else "uint64_t"
            functions.append(f"export function {ty} ${name}({ty} %a, {ty} %b) {{\n@entry\n%x ={ty} {opcode} %a, %b\nret %x\n}}")
            declarations.append(f"extern {ctype} {name}({ctype}, {ctype});")
            traps.append(f"if (which == {len(traps)}) {{ volatile {ctype} result = {name}(1, 0); (void)result; return 3; }}")
            constant_name = f"constant_zero_{opcode}_{ty}"
            functions.append(f"export function {ty} ${constant_name}() {{\n@b\n%x ={ty} {opcode} 1, 0\nret %x\n}}")
            declarations.append(f"extern {ctype} {constant_name}(void);")
            traps.append(f"if (which == {len(traps)}) {{ volatile {ctype} result = {constant_name}(); (void)result; return 3; }}")
            if opcode in ("div", "rem"):
                minimum, minus_one = 1 << (width - 1), (1 << width) - 1
                traps.append(f"if (which == {len(traps)}) {{ volatile {ctype} result = {name}(UINT64_C({minimum}), UINT64_C({minus_one})); (void)result; return 3; }}")
                constant_name = f"constant_overflow_{opcode}_{ty}"
                functions.append(f"export function {ty} ${constant_name}() {{\n@b\n%x ={ty} {opcode} {minimum}, {minus_one}\nret %x\n}}")
                declarations.append(f"extern {ctype} {constant_name}(void);")
                traps.append(f"if (which == {len(traps)}) {{ volatile {ctype} result = {constant_name}(); (void)result; return 3; }}")
    functions.append("export function l $divide_args(l %a, l %b, l %c, l %d) {\n@entry\n%q =l div %a, %b\n%r =l rem %a, %b\n%v =l add %q, %r\n%v2 =l add %v, %c\n%out =l add %v2, %d\nret %out\n}")
    declarations.append("extern uint64_t divide_args(uint64_t, uint64_t, uint64_t, uint64_t);")
    check(f"divide_args(UINT64_C({(1 << 64) - 17}), 5, UINT64_C({1 << 35}), 7)", (1 << 35) + 2)
    functions.append((root / "src/fixtures/mixed-programs.ssa").read_text())
    declared = set()
    mixed_count = 0
    for line in (root / "src/fixtures/mixed-programs.tsv").read_text().splitlines():
        if not line or line.startswith("#"):
            continue
        index, ty, a, b, count, expected = line.split()
        name = f"mixed_{index}"
        if name not in declared:
            ctype = "uint32_t" if ty == "w" else "uint64_t"
            declarations.append(f"extern {ctype} {name}({ctype}, {ctype}, uint32_t);")
            declared.add(name)
        check(f"{name}(UINT64_C({a}), UINT64_C({b}), UINT32_C({count}))", int(expected))
        mixed_count += 1
    assert mixed_count == 512 and len(declared) == 32
    functions.append((root / "src/fixtures/constant-jump.ssa").read_text())
    for name, expected in (("jconstant", 0), ("jproduct", 0), ("jnegative", 0), ("jnonzero", 1)):
        declarations.append(f"extern uint32_t {name}(void);")
        check(f"{name}()", expected)
    functions.append((root / "src/fixtures/phi-loop.ssa").read_text())
    declarations.append("extern uint32_t swap(uint32_t);")
    for count in range(8):
        check(f"swap({count})", 1 if count % 2 == 0 else 2)

    for ty, ctype in (("w", "uint32_t"), ("l", "uint64_t")):
        name = f"arguments_{ty}"
        parameters = ", ".join(f"{ty} %p{i}" for i in range(8))
        body = [f"%s1 ={ty} add %p0, %p1"]
        body.extend(f"%s{i} ={ty} add %s{i-1}, %p{i}" for i in range(2, 8))
        functions.append(f"export function {ty} ${name}({parameters}) {{\n@entry\n" + "\n".join(body) + "\nret %s7\n}")
        declarations.append(f"extern {ctype} {name}(" + ", ".join([ctype] * 8) + ");")
        values = [0xFFFFFFFF, 2, 3, 4, 5, 6, 0x80000000, 9]
        if ty == "l":
            values[0] = 1 << 40
            values[6] = 0xFFFFFFFFFFFFFFFF
        mask = (1 << (32 if ty == "w" else 64)) - 1
        check(name + "(" + ", ".join(f"UINT64_C({v})" for v in values) + ")", sum(values) & mask)

    functions.append("export function w $long_condition(l %p) {\n@entry\njnz %p, @yes, @no\n@yes\nret 1\n@no\nret 0\n}")
    declarations.append("extern uint32_t long_condition(uint64_t);")
    for bits in (1 << 40, (1 << 40) | 1, 0xFFFFFFFF00000000, 0x80000000):
        check(f"long_condition(UINT64_C({bits}))", int(bool(bits & 0xFFFFFFFF)))

    functions.append("export function w $critical_edge(w %p) {\n@entry\njnz %p, @join, @right\n@right\n%r =w copy 7\njmp @join\n@join\n%x =w phi @entry 3, @right %r\nret %x\n}")
    declarations.append("extern uint32_t critical_edge(uint32_t);")
    check("critical_edge(0)", 7)
    check("critical_edge(1)", 3)
    functions.append("export function w $same_target(w %p) {\n@entry\njnz %p, @join, @join\n@join\n%x =w phi @entry 42\nret %x\n}")
    declarations.append("extern uint32_t same_target(uint32_t);")
    check("same_target(0)", 42)
    check("same_target(1)", 42)
    # Home-reuse regressions: dead definitions still write, parallel phis
    # preserve live-through values, and dead incoming parameters are homed too.
    chain = ["%v0 =l copy 1"] + [f"%v{i} =l add %v{i-1}, 1" for i in range(1, 301)]
    functions.append("export function l $home_chain() {\n@entry\n" + "\n".join(chain) + "\nret %v300\n}")
    declarations.append("extern uint64_t home_chain(void);")
    check("home_chain()", 301)
    functions.append("export function l $home_dead_write(l %p) {\n@b\n%dead =w copy 0\nret %p\n}")
    declarations.append("extern uint64_t home_dead_write(uint64_t);")
    check("home_dead_write(UINT64_C(0xfedcba9876543210))", 0xfedcba9876543210)
    functions.append("export function w $home_dead_phi(w %p) {\n@entry\njnz %p, @left, @right\n@left\njmp @join\n@right\njmp @join\n@join\n%r =w phi @left 11, @right 22\n%dead =w phi @left 99, @right 100\n%sum =w add %r, %p\nret %sum\n}")
    declarations.append("extern uint32_t home_dead_phi(uint32_t);")
    check("home_dead_phi(5)", 16)
    check("home_dead_phi(0)", 22)
    functions.append("export function w $home_dead_parameter(w %p, w %unused) {\n@entry\nret %p\n}")
    declarations.append("extern uint32_t home_dead_parameter(uint32_t, uint32_t);")
    check("home_dead_parameter(17, 99)", 17)

    functions.append((root / "src/fixtures/preserved-homes.ssa").read_text())
    declarations.extend(["extern uint64_t preserved_homes(void);", "extern uint32_t zbe_check_preserved(uint64_t (*)(void));"])
    check("preserved_homes()", 21)
    check("zbe_check_preserved(preserved_homes)", 0)
    functions.append((root / "src/fixtures/halt.ssa").read_text())
    declarations.extend(["extern void halt_direct(void);", "extern uint32_t halt_if(uint32_t);", "extern void halt_after_div(uint32_t);"])
    check("halt_if(0)", 42)
    termination = [("halt-direct", "halt_direct()", signal.SIGILL),
                   ("halt-conditional", "halt_if(1)", signal.SIGILL),
                   ("halt-after-fault", "halt_after_div(0)", signal.SIGFPE),
                   ("halt-after-division", "halt_after_div(1)", signal.SIGILL)]
    functions.append("export function $nothing() {\n@entry\nret\n}")
    declarations.append("extern void nothing(void);")

    with tempfile.TemporaryDirectory(prefix="zbe-native-check-") as directory:
        work = Path(directory)
        source = work / "input.ssa"
        assembly = work / "output.s"
        driver = work / "driver.c"
        executable = work / "native-check"
        source.write_text("\n".join(functions) + "\n")
        trap_dispatch = "\n".join(traps)
        termination_dispatch = "\n".join(f'if (strcmp(argv[1], "{name}") == 0) {{ {call}; return 99; }}' for name, call, _ in termination)
        driver.write_text("\n".join(declarations) + "\n#include <stdlib.h>\nint main(int argc, char **argv) {\nif (argc == 2) {\n" + termination_dispatch + "\nint which = atoi(argv[1]);\n" + trap_dispatch + "\nreturn 4; }\nnothing();\n" + "\n".join(checks) + f'\nputs("{len(checks)} native integer/ABI/phi checks passed");\nreturn 0;\n}}\n')
        run([compiler, *compiler_flags, str(source), str(assembly)])
        chain_assembly = assembly.read_text().split("home_chain:\n", 1)[1].split(".size home_chain,", 1)[0]
        match = re.search(r"subq \$(\d+), %rsp", chain_assembly)
        expected_frame = 16 if args.reuse_stack_homes or args.callee_saved_homes else 2416
        if match is None or int(match.group(1)) != expected_frame:
            raise SystemExit(f"Home-chain frame is not {expected_frame} bytes")
        run([args.cc, "-std=c11", "-O2", "-Wall", "-Wextra", "-Werror", "-no-pie", str(driver), str(assembly), str(root / "src/fixtures/check-preserved.s"), "-o", str(executable)])
        run([str(executable)])
        for index in range(len(traps)):
            result = subprocess.run([str(executable), str(index)], capture_output=True, timeout=30)
            if result.returncode != -signal.SIGFPE:
                raise SystemExit(f"Native arithmetic trap {index} returned {result.returncode}, expected SIGFPE")
        print(f"{len(traps)} native integer arithmetic-fault checks passed")
        for name, _, expected_signal in termination:
            result = subprocess.run([str(executable), name], capture_output=True, timeout=30)
            if result.returncode != -expected_signal:
                raise SystemExit(f"Native termination {name} returned {result.returncode}, expected signal {expected_signal}")
        print(f"{len(termination)} native termination/ordering checks passed")

        invalid = {
            "entry-edge": ((root / "src/fixtures/entry-backedge.ssa").read_text(), "EntryHasPredecessors"),
            "unsupported": ("export function s $bad(d %a) {\n@b\n%r =s truncd %a\nret %r\n}", "unsupported_construct"),
            "ssa": ("export function w $bad() {\n@entry\njnz 0, @left, @join\n@left\n%x =w copy 1\njmp @join\n@join\nret %x\n}", "InvalidSSA"),
            "syntax": ("export function w $bad() {\n@b\nret %missing\n}", "unknown_value"),
        }
        for name, (text, diagnostic) in invalid.items():
            bad_source = work / f"{name}.ssa"
            bad_output = work / f"{name}.s"
            bad_source.write_text(text)
            result = subprocess.run([compiler, *compiler_flags, str(bad_source), str(bad_output)], capture_output=True, text=True, timeout=30)
            if result.returncode == 0 or bad_output.exists() or diagnostic not in result.stderr:
                raise SystemExit(f"Invalid {name} input was accepted, created output, or had the wrong diagnostic")
            bad_output.write_text("preserve-existing-output")
            result = subprocess.run([compiler, *compiler_flags, str(bad_source), str(bad_output)], capture_output=True, text=True, timeout=30)
            if result.returncode == 0 or bad_output.read_text() != "preserve-existing-output":
                raise SystemExit(f"Invalid {name} input overwrote an existing output")
        usage = subprocess.run([compiler], capture_output=True, text=True, timeout=30)
        if usage.returncode != 2 or "usage:" not in usage.stderr:
            raise SystemExit("Usage check failed")
        original = source.read_bytes()
        same = subprocess.run([compiler, *compiler_flags, str(source), str(source)], capture_output=True, text=True, timeout=30)
        if same.returncode == 0 or source.read_bytes() != original:
            raise SystemExit("Same-path output overwrote its input")
        for flags in (["--unknown"], ["--fold-integers", "--fold-integers"], ["--reuse-stack-homes", "--reuse-stack-homes"], ["--callee-saved-homes", "--callee-saved-homes"]):
            assembly.write_text("preserve-existing-output")
            rejected = subprocess.run([compiler, *flags, str(source), str(assembly)], capture_output=True, text=True, timeout=30)
            if rejected.returncode != 2 or "usage:" not in rejected.stderr or assembly.read_text() != "preserve-existing-output":
                raise SystemExit("Invalid or duplicate flags did not preserve output")
        # All accepted orders of the three flags select the same pipeline.
        small = work / "flag-order.ssa"
        small.write_text("export function w $flag_order() {\n@b\n%x =w add 1, 2\nret %x\n}")
        reference = None
        for index, flags in enumerate(itertools.permutations(["--fold-integers", "--reuse-stack-homes", "--callee-saved-homes"])):
            output = work / f"flag-order-{index}.s"
            run([compiler, *flags, str(small), str(output)])
            actual = output.read_bytes()
            if reference is not None and reference != actual:
                raise SystemExit("Flag ordering changed assembly")
            reference = actual
        print("15 CLI rejection/output-preservation/flag-order checks passed")


if __name__ == "__main__":
    main()
