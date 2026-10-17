# Checked long scalar symbol-plus-offset operands

Ordinary scalar operands accept `$symbol+N` with a bare or bounded quoted global name (QUOTED-GLOBALS.md), where N is one checked
signed decimal **i32** addend (including zero). A negative addend is written
`$symbol+-8`; `$symbol-8` is not subtraction syntax. Spaces around `+` are allowed,
but a scalar operand cannot continue across a physical newline. Chained arithmetic,
TLS/extern expressions and float or symbolic addends are rejected.
Numeric integer operands retain their existing wrapping rules; checked address
addends do not wrap. Data initializer addends remain separately checked **i64**
(DATA-RELOCATIONS.md), with their existing multiline/item grammar unchanged.

`ir.SymbolOffset` stores a module-pool symbol ID and an i32 addend. The distinct
`Operand.symbol_offset` leaves the existing bare `Operand.symbol` API unchanged.
Both are long-only address expressions, not loads, host pointers, scalar constants
or SSA definitions. For word use, copy the address to a long temporary then use
its explicit low-word projection. `referencedValue` returns null; the allocation-
free `referencedSymbol` covers both symbol variants. Owner scope remains a caller
invariant, not a compile-time capability.

All scalar instruction-use contexts, phi inputs and terminators retain the operand.
Module validation checks IDs and target validation checks assembler spelling,
including unreachable paths and manually built indirect targets. Direct `$callee`
syntax retains known-signature checking; `$callee+0(...)` is deliberately not a
direct call. Copy an address expression to a long temporary to call indirectly.
This does not infer an internal signature for that indirect address.

## Linux AMD64 executable boundary

Materialization emits one full-width `leaq symbol+N(%rip), scratch64`, spelling a
negative displacement as `symbol-N`. Minimum i32 is printed directly without
negation. No absolute text immediate, dynamic text relocation, new persistent
scratch register or implicit memory load is introduced. The existing R11 indirect
target capture and R10 store-address lifetime remain unchanged.

The **combined** symbol placement and displacement must fit the assembler/linker's
existing RIP-relative small-code-model relocation contract. Admitting an i32 addend
is not a guarantee that every such expression can link at every placement. Unit
boundary tests check parsing/emission; native linkage checks use bounded valid
array offsets, not extreme displacement placement. This is the Linux AMD64
PIE/non-PIE executable slice, not shared-object preemption/GOT policy, TLS, full PIC,
all code models or full QBE constant expressions. Runtime accesses still require
valid native object lifetime, extent and permissions.

## Analyses and interpreter boundary

Production operand iteration copies the tagged address payload without inventing
an SSA use. Independent liveness/interference oracle switches separately classify
it as non-SSA. The folder retains unknown address facts and never guesses layout,
equality or nonzero values. By default, reached interpretation returns
`UnsupportedSymbolAddress`, even with Image or synthetic stack memory enabled.
Unreached paths, ordinary step-budget precedence, call-dispatch refusal precedence,
earlier Image writes and owned frame cleanup retain their existing behavior.
There is no host/linker resolver, host-pointer conversion or caller Image resizing.
Explicit synthetic data globals require the separate option described below.

## Regression approach

Focused tests exercise signed boundaries, copied iteration storage, long-only
classes, malformed/range rejection, module/target tampering in independent scalar
positions, unknown folding, interpreter refusal and exhaustive allocation-failure
cleanup. The new fixture joins both independent analysis-oracle bundles. A separate
native harness compares linked addresses against C expressions inside C/IL-owned
arrays, including a middle alias for valid negative offsets, byte loads/stores,
parallel phi swaps, direct/indirect mixed-register and overflow arguments, blits,
low-word projections and all five preserved GP registers. PIE requires high
addresses and both executable modes reject TEXTREL. Existing generators and
correctness fixture bytes stay unchanged. HANDOFF.md records actual verification;
this document alone is not a test-success or parity claim.

## Explicit module-global evaluation

Opt-in initialized globals use a separate owned synthetic model
(INTERPRETER-GLOBALS.md), including defined-data-only symbolic initializers
(INTERPRETER-DATA-RELOCATIONS.md). Defaults still refuse symbols; function/external
addresses remain unsupported. Image ownership and native linker/stack behavior
do not change.
