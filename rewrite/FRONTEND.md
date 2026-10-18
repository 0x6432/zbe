# Independent scalar frontend

`frontend.parse(allocator, Source, &diagnostic)` returns an owned `Module`. It borrows input only during the call; names that survive parsing are interned into the module. The caller deinitializes successful modules. Any failed parse frees tokens, name maps and all partially constructed functions. `InvalidInput` carries a typed diagnostic with a half-open source byte span; allocator/resource errors propagate separately. There is no process exit or CLI diagnostic rendering in this API.

## Currently accepted subset

```text
[export] function [w|l|s|d] $name([type %parameter, ...]) {
@block
    %result =type phi @predecessor operand, @predecessor operand
    %result =type call $direct_symbol(type operand, type operand)
    call $void_symbol(type operand, type operand)
    %result =type call %long_target(type operand, type operand)
    call %long_target(type operand, type operand)
    %result =w|l loadsb|loadub|loadsh|loaduh|loadsw|loaduw|loadw long-address
    %result =l|s|d loadl|loads|loadd long-address
    blit long-source, long-destination, nonnegative-constant-count
    storeb|storeh|storew word-value, long-address
    storel|stores|stored matching-scalar-value, long-address
    %result =type copy operand
    %result =type neg operand
    %result =type cast opposite-class-same-width-operand
    %result =d exts single-operand
    %result =s|d swtof word-operand
    %result =s|d sltof long-operand
    %result =w|l stosi single-operand
    %result =w|l dtosi double-operand
    %result =w|l extsb|extub|extsh|extuh word-operand
    %result =l extsw|extuw word-operand
    %result =type add|sub|mul|div|udiv|rem|urem|and|or|xor operand, operand
    %result =w|l shl|shr|sar operand, word-count
    %result =w|l ceq[w|l]|cne[w|l]|cslt[w|l]|csle[w|l]|csgt[w|l]|csge[w|l]|cult[w|l]|cule[w|l]|cugt[w|l]|cuge[w|l] operand, operand
    %result =w|l ceq[s|d]|cne[s|d]|clt[s|d]|cle[s|d]|cgt[s|d]|cge[s|d]|co[s|d]|cuo[s|d] operand, operand
    jmp @block
    jnz operand, @true, @false
    ret [operand]
    hlt
}
```

The ellipsis above describes repeated parameters, **not** variadic IL. A missing function result type means void. Every actual block must end in exactly one explicit terminator; the example lists alternative instruction/terminator forms, not a single valid block. Labels occupy their own lines; instructions end at a newline or closing brace. LF and CRLF input, comments and blank lines are supported. Function export linkage is retained in the IR.

- `hlt` has no operands and closes its block with target-dependent program termination, independently of the function result type. The evaluator returns `Halted`; Linux AMD64 emits `ud2`. See HALT.md.
- Direct nonvariadic scalar-result or void-result calls with explicitly typed base-scalar arguments are accepted; empty argument lists are allowed. Void calls are effect-only statements with no result definition. Known callee result presence/type must match; omitting a nonvoid return is not permitted. Indirect calls now accept a long temporary or integer-address literal as target; address/signature validity is a native caller contract and module interpretation refuses reached address targets (see INDIRECT-CALLS.md). Aggregate calls are unsupported; environment calls are described in ENVIRONMENT-CALLS.md; native variadic definitions/vastart
are supported separately (VARIADIC-FUNCTIONS.md); external/indirect variadic call-site markers are supported separately (VARIADIC-CALLS.md); sb/ub/sh/uh annotations in scalar ABI positions are described in SUBWORD-ABI.md. Native emission checks known module-local signatures; external signatures remain a caller contract. The standalone evaluator reports `UnsupportedCall` only when a call is reached; module-aware evaluation can interpret internal direct calls, but never external functions (see MODULE-EVALUATION.md). See CALLS.md.
- Scalar loads/stores accept long addresses and exact source/result classes; signed/unsigned narrow loads extend to word or long, while byte/half stores truncate word sources. `loadw` is an exact `loadsw` alias, including sign extension when its result is long. Stores are effect-only; both evaluators require an opt-in bounded image or synthetic stack model to execute memory, otherwise returning `UnsupportedMemory` without host dereferences (see MEMORY-EVALUATION.md). Effect-only `blit` now accepts two long addresses and an exact nonnegative decimal count through 2,147,483,647; partial overlap is invalid (BLITS.md). Native `alloc4`/`alloc8`/`alloc16` now accept a long size and produce a long address; evaluators default to `UnsupportedAllocation` even with an Image; opt-in `Options.stack_memory` supplies bounded synthetic objects (INTERPRETER-ALLOCATIONS.md). Bare unquoted `$symbol` long-address operands are now accepted (SYMBOL-ADDRESSES.md); bounded numeric/zero-fill data definitions are supported separately (DATA.md), while checked i32 scalar symbol+offset operands are described in SYMBOL-OFFSETS.md; TLS/extern forms remain unsupported. See MEMORY.md.
- SSA arithmetic types are the four base scalar types. Function/call ABI positions additionally accept sb/ub/sh/uh, retaining word SSA values and unspecified upper bits (SUBWORD-ABI.md). Long temporaries in word contexts explicitly project their low 32 bits in the owned IR, including arithmetic, phi/call/return/store operands and shift counts (LOW-WORD.md). Other source/result classes remain exact; implicit word-to-long extension is rejected.
- `copy`, `add`, `sub`, `mul`, `div` support matching integer or floating types; bitwise operations, `udiv`, `rem` and `urem` require integer types.
- Integer `div` truncates the signed quotient toward zero; `rem` has the dividend's sign. `udiv`/`urem` use unsigned bits. The evaluator returns `DivisionByZero` or `IntegerOverflow` for exceptional integer pairs; native AMD64 execution faults instead. See SCALAR-SEMANTICS.md for this explicit boundary.
- `neg` preserves the operand/result width. Integer negation wraps; floating negation flips only the sign bit, including signed zero and NaN payloads. Integer extensions consume word operands: byte/half extensions produce word or long, while word extensions produce long only. They sign- or zero-extend the selected low bits. These are ordinary instructions, not extended ABI parameter types.
- `cast` preserves raw bits across word/single or long/double classes in either direction. It is not numeric conversion. `exts` widens a single to double, exactly for finite values. Signed numeric `swtof`/`sltof`/`stosi`/`dtosi` are supported with explicit source/result classes; float-to-signed truncates toward zero and the evaluator returns `ConversionOutOfRange` for invalid domains. Unsigned `uwtof`/`ultof`/`stoui`/`dtoui` are also supported with checked evaluator domains (UNSIGNED-CONVERSIONS.md). Double-to-single `truncd` remains unsupported. See SIGNED-CONVERSIONS.md.
- Shifts require a word count, including when shifting a long. Only the low five (word) or six (long) count bits are used; `shr` is logical and `sar` is arithmetic.
- Integer comparison opcode suffixes select operand width independently of the word/long result width. Results are exactly zero or one. For example, `%r =l csltw %a, %b` compares word operands as signed integers and produces a long. Floating comparisons use their own single/double suffixes and predicates.
- Decimal integer constants wrap modulo 2^64, with explicit low-word truncation in word contexts. An untyped immediate branch condition is retained as long; branch interpretation tests its low 32 bits.
- Floating comparisons return word or long zero/one independently of operand width. NaN makes `ne` and `uo` true and `eq`/relative comparisons/`o` false. Signed zeros compare equal; infinities retain numeric ordering. Exception flags and unmasked floating traps are not part of this subset's conformance claim.
- Floating literals retain their `s_`/`d_` width, including decimal/hex spellings, signed zero, infinity and plain NaN. Numeric conversion uses Zig, not libc. NaN payload spellings are scanned intact but **rejected explicitly by this parser** until payload semantics are implemented.
- Phi nodes precede ordinary instructions in a block. The parser retains typed predecessor/value pairs; `ssa.validate` checks predecessor coverage and incoming-edge dominance.
- Forward **block targets** are resolved by a declaration pass. Temporary result types are predeclared, so loop backedges and layout-independent forward references are accepted; scalar SSA validation must establish actual definition availability. Parameters and blocks are scoped per function; duplicate function/block/value names are rejected.
- The lexer returns borrowed raw spans, including string escapes and quoted global names; it does not silently decode/rewrite names. Unsupported quoted-name bytes/escapes, strings as operands, aggregates, unsupported string classes/escapes and general relocation forms in data, unsupported memory operations, unsupported call forms, aggregate ABI forms and combined environment/variadic forms, non-scalar ABI types and unimplemented opcodes are explicitly rejected by the parser.

Numeric/zero-fill data definitions are accepted outside functions; fields are packed,
alignment defaults to eight and sizes are bounded. See DATA.md for exact group,
linkage, ownership and rejection rules. Long symbolic initializer groups with one
checked signed addend are now supported separately (DATA-RELOCATIONS.md); ordinary
scalar symbol+offset operands use a separate checked i32 addend (SYMBOL-OFFSETS.md). Owned b-group byte strings are
implemented separately with bounded escapes/no implicit NUL (DATA-STRINGS.md).
This is not the full QBE data language.

## Not a full verifier or compiler

Parsing checks syntax and the current IR's structural/type invariants. It does **not** prove SSA dominance, validate phi edges or enforce the first-block predecessor restriction. In particular, a textually earlier definition in a non-dominating block is not yet rejected. Call `ssa.validate` for current scalar ordering/dominance checks before using parsed IR as verified SSA. The bounded interpreter does this automatically. `ssa.validate` returns `EntryHasPredecessors` for any edge targeting the first block, including from an unreachable block, matching QBE's invocation-entry rule. Current scalar phi-edge coverage and dominance are checked by `ssa.validate`; full-IL verification remains future work. See SCALAR-SEMANTICS.md.

The new API is not yet a drop-in QBE parser: strict malformed-number rejection is intentional and does not emulate legacy scanf prefix recovery; diagnostic codes are not a promise of the old CLI's exact messages. The legacy CLI and compatibility modes are unchanged.

`src/fixtures/constant-jump.ssa` is copied unchanged from the existing `tests/upstream-bug-jnz-constant.ssa` regression. Tests parse all four functions independently and inspect typed constants/targets; this is parsing coverage, **not** proof of compiled execution or optimized branch folding.

Opt-in interpreter-owned numeric/zero/string module globals are described in
INTERPRETER-GLOBALS.md. Defaults still refuse symbol resolution; the separate
synthetic model now accepts defined-data-only symbolic initializers
(INTERPRETER-DATA-RELOCATIONS.md), but not function/extern address lookup or host
calls.

Base-scalar result-producing vaarg accepts a long caller-supplied descriptor
(VAARG-CONSUMERS.md). Final-only variadic headers and effect-only vastart are described in VARIADIC-FUNCTIONS.md.

Nonvariadic scalar environment calls now have a distinct hidden long operand/
parameter and Linux AMD64 RAX mapping, without shifting ordinary ABI arguments
(ENVIRONMENT-CALLS.md). Root/module interpreter mapping remains synthetic and
bounded; environment+varargs and aggregates remain unsupported.

Bounded printable-ASCII quoted globals (excluding ELF `@` syntax) decode to owned canonical symbol names
across definitions/calls/scalar operands/data relocations (QUOTED-GLOBALS.md).
Native formatting escapes non-bare names while preserving existing bare output
and the private-label namespace; no host lookup or full identifier/target parity.

Zero-fill `common data` accepts independent optional export in either order,
with each flag at most once; common function/TLS/section combinations remain
refused. Only z-groups or an empty initializer are accepted (DATA-COMMON.md).
