# Native aggregate variadic calls and definitions

Linux AMD64 SysV accepts marked aggregate calls (direct or typed indirect) and
variadic definitions with named record parameters and/or record results. The
existing bounded INTEGER, SSE, mixed, NO_CLASS and MEMORY classifications apply:
regular records only, effective alignment at most16 and declared size at most4096.
This does not add aggregate first-class values, aggregate `vaarg`, vectors, unions,
other targets, ENV+varargs or aggregate interpreter execution.

## Signature, ownership and ordering

The marker counts ordinary arguments; each record counts once, hidden return RDI
and ENV do not count. Module validation still resolves every descriptor ID before
known nominal signatures and target eligibility, including unreachable calls.
Plans own copied facts and argument arrays; they borrow no module/layout pointers.
Global eligibility precedes home/plan/writer allocation. New checks and failures
free all partially built plans and permit retry against the same module.

`Signature.stack_bytes` is the raw unrounded stack end, not outgoing reservation
rounded to16. For record-bearing variadic signatures only, `vastart` uses checked
`RBP +16 +stack_bytes`, GP offset8×occupied GP (including hidden RDI), FP offset
48+16×occupied SSE, and the private176-byte GP6/SSE8 save area. The entire raw
register bank is saved before unpacking/calls. The inclusive address bound checks
the overflow pointer itself; old scalar-signature displacement policy is unchanged.
Record signatures bypass the legacy long-carrier cursor entirely. Scalar
signatures retain the old cursor/vastart path even if body record calls require a
plan. Save areas, incoming objects, private call-result pads and outgoing storage
stay disjoint under the65536-byte fixed-frame cap and dynamic stack allocation.

Marked record calls set AL to exactly occupied SSE registers across named and
unnamed arguments after all ordinary loads and late target RAX→R11 parking.
Packed float lanes count once; NO_CLASS counts zero; failed whole-tuple GP/SSE
assignment rolls back both banks. ENV+varargs remains structurally invalid.
Unmarked prior scalar and record assembly is unchanged.

## va_list and interpretation

IL `vaarg` remains scalar base-type only. Generated definitions can share the same
live24-byte descriptor with an independent C `va_list*` consumer of aggregate tail
arguments, then continue IL scalar `vaarg`; explicit24-byte copying and repeated
`vastart` are covered. This is not an aggregate-vaarg IR opcode, host-interpreter
fallback, escaping descriptor ownership or sandbox/fault-atomicity guarantee.
Interpreter aggregate root/reached-call refusals and scalar step/error precedence
remain unchanged, including internal-variadic opt-in.

## Independent acceptance

`aggregate_abi_variadic_check.py` executes C stdarg and hand-ASM AL/GP/SSE/stack
oracles, exact initialized field bytes (including raw NaNs and unchanged MXCSR), guarded source spans,
by-value isolation, named40/rounded48 and named56/rounded64 stack boundaries,
AL0..8 plus SSE spill, recursive/loop calls with target phi/nested clobber, quoted COMMON/ordinary
address paths, dynamic allocation, copied lists, active private-copy mutation,
scalar/void/floating and hidden-MEMORY results, direct/indirect targets, and scalar
variadic callers with record sites. Padding contents are not value expectations.
Runtime mutants cover lost/early AL, both-bank tuple rollback, FP exception status, rounded overflow pointers,
hidden-RDI/FP offsets, rounded overread and saving after a real caller clobber.
The latter is not claimed as a post-unpack mutation: unpacking need not clobber
any still-eligible tail register. Exhaustive allocation failures cover parse,
plan/home/save-area construction, final writer ownership transfer and same-module
retry; refusal/OOM before driver write preserves output, not arbitrary later I/O.
Prior b3fec4 assembly goldens are produced only by the published prior compiler:
whole prior scalar/record modules and matched symbol-ID/function-ordinal scalar
fragments, never whole mixed-module equivalence to an unsupported prior module.

## Reference boundary

Official x86-64 psABI revision e1ce098331da5dbd66e1ffc74162380bcc213236 (2025)
and pinned QBE base-only vaarg support ground this subset. Approved design SHA256
c3ceaddfc3f4073b05c0dd5f72dff8bdd3cc9aa862481d4e765aacbb3207e806 is unchanged;
its truncated archive hash has the separate verified erratum:
`ba0271b4722688e0fee53f59b0d05c1d5ad98ed35185bef5eea7e91ffe474f4e`.
The existing official-SysV/C NO_CLASS policy remains separate from suspected
pinned-QBE padding behavior; no new blanket upstream parity or crash claim.
