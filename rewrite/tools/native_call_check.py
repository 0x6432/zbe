#!/usr/bin/env python3
"""Bounded native Linux SysV direct-scalar-call regressions (not full ABI parity)."""
from pathlib import Path
import argparse
import platform
import resource
import subprocess
import tempfile

CTYPES = {"w": "uint32_t", "l": "uint64_t", "s": "float", "d": "double"}

def main() -> None:
    root = Path(__file__).resolve().parents[1]
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--compiler", type=Path, default=root / "zig-out/bin/zbe-native")
    parser.add_argument("--cc", default="cc")
    for flag in ("fold-integers", "reuse-stack-homes", "callee-saved-homes"):
        parser.add_argument("--" + flag, action="store_true")
    args = parser.parse_args()
    if platform.system() != "Linux" or platform.machine() not in ("x86_64", "amd64"):
        raise SystemExit("Native call checks require Linux x86_64; no result claimed.")
    resource.setrlimit(resource.RLIMIT_CORE, (0, 0))
    flags = ["--" + flag for flag in ("fold-integers", "reuse-stack-homes", "callee-saved-homes") if getattr(args, flag.replace("-", "_"))]
    il, helpers, declarations, checks = [], [], [], []
    headers = '#include <stdint.h>\n#include <stdio.h>\n#include <string.h>\n'
    def check(expression: str, expected: int) -> None:
        index = len(checks)
        checks.append(f'if ((uint64_t)({expression}) != UINT64_C({expected})) {{ fprintf(stderr, "call check {index} failed\\n"); return 1; }}')

    # Distinct exact small integers make every position observable, without host
    # floating arithmetic deriving expected results. Both bank-overflow orders,
    # empty/small/large signatures and all four scalar return types are covered.
    for n in range(128):
        if n == 0:
            types = ["l"] * 10 + ["d"] * 10
        elif n == 1:
            types = ["s"] * 11 + ["w"] * 11
        elif n < 6:
            types = ["wlsd"[n - 2]] * 33
        else:
            state = 0x9E3779B9 ^ n
            types = []
            for _ in range(n % 34):
                state = (1664525 * state + 1013904223) & 0xFFFFFFFF
                types.append("wlsd"[(state >> 27) & 3])
        result = "wlsd"[n % 4]
        params = ", ".join(f"{t} %v{i}" for i, t in enumerate(types))
        callargs = params
        il.append(f"export function {result} $call_case_{n}({params}) {{\n@e\n%a ={result} call $helper_{n}({callargs})\n%b ={result} call $helper_{n}({callargs})\n%r ={result} add %a, %b\nret %r\n}}")
        cparams = ", ".join(f"{CTYPES[t]} v{i}" for i, t in enumerate(types)) or "void"
        terms = " + ".join(f"UINT64_C({i+1}) * (uint64_t)v{i}" for i in range(len(types))) or "0"
        helpers.append(f"{CTYPES[result]} helper_{n}({cparams}) {{ return ({CTYPES[result]})(11 + {terms}); }}")
        declarations.append(f"extern {CTYPES[result]} call_case_{n}({', '.join(CTYPES[t] for t in types) or 'void'});")
        for seed in (1, 3, 7):
            values = [((i * 17 + n * 3 + seed) % 97) + 1 for i in range(len(types))]
            actual = ", ".join(f"({CTYPES[t]}){v}" for t, v in zip(types, values))
            check(f"call_case_{n}({actual})", 2 * (11 + sum((i + 1) * v for i, v in enumerate(values))))

    # Internal recursion and mutually recursive forward definitions. Native
    # recursion is bounded by test inputs, not by interpreter limits.
    il.append("""export function l $call_factorial(l %n) {
@entry
%c =w culel %n, 1
jnz %c, @base, @step
@base
ret 1
@step
%next =l sub %n, 1
%v =l call $call_factorial(l %next)
%r =l mul %n, %v
ret %r
}
export function w $call_even(w %n) {
@entry
jnz %n, @step, @base
@base
ret 1
@step
%next =w sub %n, 1
%r =w call $call_odd(w %next)
ret %r
}
function w $call_odd(w %n) {
@entry
jnz %n, @step, @base
@base
ret 0
@step
%next =w sub %n, 1
%r =w call $call_even(w %next)
ret %r
}""")
    declarations += ["extern uint64_t call_factorial(uint64_t);", "extern uint32_t call_even(uint32_t);"]
    factorial = 1
    for n in range(11):
        factorial *= max(1, n)
        check(f"call_factorial({n})", factorial)
    for n in range(21):
        check(f"call_even({n})", int(n % 2 == 0))

    # Keep all scalar classes and more than five simultaneous values live across
    # an assembly helper that explicitly destroys every SysV volatile GP/SSE reg.
    il.append("""function l $call_keep(l %a, l %b, l %c, l %d, w %e, s %s, d %t) {
@entry
%r =l call $zbe_call_clobber()
%sb =w cast %s
%sl =l extuw %sb
%tb =l cast %t
%el =l extuw %e
%ab =l xor %a, %b
%cd =l xor %c, %d
%st =l xor %sl, %tb
%x =l xor %ab, %cd
%y =l xor %x, %st
%z =l xor %y, %el
%out =l add %z, %r
ret %out
}
export function l $call_preserved() {
@entry
%s =s cast 2143363909
%d =d cast 9221140253039434428
%r =l call $call_keep(l 4294967297, l 8589934594, l 12884901891, l 17179869188, w 4294967280, s %s, d %d)
ret %r
}
export function l $call_alignment() {
@entry
%r =l call $zbe_call_alignment()
ret %r
}""")
    declarations += ["extern uint64_t call_preserved(void);", "extern uint64_t call_alignment(void);", "extern uint64_t zbe_check_preserved(uint64_t (*)(void));"]
    expected = 4294967297 ^ 8589934594 ^ 12884901891 ^ 17179869188 ^ 4294967280 ^ 2143363909 ^ 9221140253039434428
    check("call_preserved()", expected + 17)
    check("zbe_check_preserved(call_preserved)", 0)
    check("call_alignment()", 8)

    # Loop phi scratch, live values, saved originals and outgoing overflow slots
    # all occur in one frame. Two discarded results remain observable effects.
    params = ["l %acc"] + [f"l {i}" for i in range(2, 11)] + [f"d d_{i}" for i in range(1, 11)]
    il.append(f"""export function l $call_phi(w %count) {{
@entry
jmp @loop
@loop
%n =w phi @entry %count, @body %next
%acc =l phi @entry 1, @body %sum
jnz %n, @body, @done
@body
%r =w call $helper_0({', '.join(params)})
%wide =l extuw %r
%sum =l add %acc, %wide
%next =w sub %n, 1
jmp @loop
@done
ret %acc
}}
export function w $call_effects() {{
@entry
%unused1 =w call $zbe_effect()
%unused2 =w call $zbe_effect()
%count =w call $zbe_effect_count()
ret %count
}}""")
    helpers += ["static uint32_t effect_count;", "uint32_t zbe_effect(void) { return ++effect_count; }", "uint32_t zbe_effect_count(void) { return effect_count; }"]
    declarations += ["extern uint64_t call_phi(uint32_t);", "extern uint32_t call_effects(void);"]
    # helper_0 returns word; all chosen loop expectations remain in range.
    constant = 11 + sum(i * i for i in range(2, 11)) + sum((i + 10) * i for i in range(1, 11))
    for n in range(6):
        value = 1
        for _ in range(n):
            value += value + constant
        check(f"call_phi({n})", value)
    check("call_effects()", 2)

    # Raw floating arguments/returns, including signed zero and NaN payloads.
    helpers += ["float zbe_identity_s(float x) { return x; }", "double zbe_identity_d(double x) { return x; }"]
    il += ["export function w $call_bits_s(w %bits) {\n@e\n%x =s cast %bits\n%y =s call $zbe_identity_s(s %x)\n%r =w cast %y\nret %r\n}",
           "export function l $call_bits_d(l %bits) {\n@e\n%x =d cast %bits\n%y =d call $zbe_identity_d(d %x)\n%r =l cast %y\nret %r\n}"]
    declarations += ["extern uint32_t call_bits_s(uint32_t);", "extern uint64_t call_bits_d(uint64_t);"]
    for bits in (0, 0x80000000, 0x3f800000, 0x7f800000, 0xff800000, 0x7fc12345, 0xffc12345, 1):
        check(f"call_bits_s(UINT32_C({bits}))", bits)
    for bits in (0, 0x8000000000000000, 0x3ff0000000000000, 0x7ff0000000000000, 0xfff0000000000000, 0x7ff8123456789abc, 0xfff8123456789abc, 1):
        check(f"call_bits_d(UINT64_C({bits}))", bits)

    # Preserve full-width/raw payloads in outgoing overflow slots as well as
    # argument registers. No floating arithmetic touches these payloads.
    for ty, count, bits_type, patterns in (
        ("l", 8, "l", (0, 1, 0x8000000000000000, 0xffffffffffffffff, 1 << 40, 0x1234567887654321, 0x7fffffffffffffff, 0x100000001)),
        ("s", 10, "w", (0, 0x80000000, 0x3f800000, 0x7f800000, 0xff800000, 0x7fc12345, 0xffc12345, 1)),
        ("d", 10, "l", (0, 0x8000000000000000, 0x3ff0000000000000, 0x7ff0000000000000, 0xfff0000000000000, 0x7ff8123456789abc, 0xfff8123456789abc, 1)),
    ):
        cparams = ", ".join(f"{CTYPES[ty]} v{i}" for i in range(count))
        unused = " ".join(f"(void)v{i};" for i in range(count - 1))
        helpers.append(f"{CTYPES[ty]} stack_identity_{ty}({cparams}) {{ {unused} return v{count-1}; }}")
        convert_in = f"%x ={ty} cast %bits\n" if ty != "l" else ""
        value = "%x" if ty != "l" else "%bits"
        prefix = [f"{ty} {i+1}" if ty == "l" else f"{ty} {ty}_{i+1}" for i in range(count - 1)]
        callargs = ", ".join(prefix + [f"{ty} {value}"])
        convert_out = f"%out ={bits_type} cast %r\nret %out" if ty != "l" else "ret %r"
        il.append(f"export function {bits_type} $call_stack_bits_{ty}({bits_type} %bits) {{\n@e\n{convert_in}%r ={ty} call $stack_identity_{ty}({callargs})\n{convert_out}\n}}")
        declarations.append(f"extern {CTYPES[bits_type]} call_stack_bits_{ty}({CTYPES[bits_type]});")
        for bits in patterns:
            check(f"call_stack_bits_{ty}(UINT64_C({bits}))", bits)

    assembly_helpers = """.text
.globl zbe_call_alignment
zbe_call_alignment:
movq %rsp, %rax
andq $15, %rax
ret
.globl zbe_call_clobber
zbe_call_clobber:
""" + "\n".join(f"xorq %{r}, %{r}" for r in ("rax", "rcx", "rdx", "rdi", "rsi", "r8", "r9", "r10", "r11")) + "\n" + "\n".join(f"pxor %xmm{i}, %xmm{i}" for i in range(16)) + "\nmovl $17, %eax\nret\n.section .note.GNU-stack,\"\",@progbits\n"
    with tempfile.TemporaryDirectory(prefix="zbe-calls-") as directory:
        work = Path(directory)
        src, asm, c, support, binary = [work / name for name in ("calls.ssa", "calls.s", "main.c", "support.s", "check")]
        src.write_text("\n".join(il) + "\n")
        c.write_text(headers + "\n".join(helpers + declarations) + "\nint main(void) {\n" + "\n".join(checks) + '\nreturn 0;\n}\n')
        support.write_text(assembly_helpers)
        subprocess.run([str(args.compiler.resolve()), *flags, str(src), str(asm)], check=True, timeout=90)
        subprocess.run([args.cc, "-std=c11", "-O2", "-Wall", "-Wextra", "-Werror", "-no-pie", str(c), str(asm), str(support), str(root / "src/fixtures/check-preserved.s"), "-o", str(binary)], check=True, timeout=90)
        subprocess.run([str(binary)], check=True, timeout=30)
        print(f"{len(checks)} native direct-call/ABI/effect checks passed")
        # Signature failures must not create/truncate output, including a forward
        # definition and result/count/class mismatches; externs remain contractual.
        for name, text in {
            "result": "function w $f() {\n@e\n%r =w call $g()\nret %r\n}\nfunction l $g() {\n@e\nret 1\n}",
            "arity": "function w $f() {\n@e\n%r =w call $g()\nret %r\n}\nfunction w $g(w %x) {\n@e\nret %x\n}",
            "class": "function w $f() {\n@e\n%r =w call $g(s s_1)\nret %r\n}\nfunction w $g(w %x) {\n@e\nret %x\n}",
        }.items():
            src.write_text(text)
            asm.unlink()
            for existing in (False, True):
                if existing:
                    asm.write_text("preserve-existing-output")
                result = subprocess.run([str(args.compiler.resolve()), *flags, str(src), str(asm)], capture_output=True, text=True, timeout=30)
                if result.returncode == 0 or "CallSignatureMismatch" not in result.stderr:
                    raise SystemExit(f"Invalid {name} call signature accepted or wrong diagnostic")
                if (existing and asm.read_text() != "preserve-existing-output") or (not existing and asm.exists()):
                    raise SystemExit("Invalid call signature changed output")
        print("6 call-signature rejection/output-preservation checks passed")

if __name__ == "__main__":
    main()
