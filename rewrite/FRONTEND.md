# Independent scalar frontend

`frontend.parse(allocator, Source, &diagnostic)` returns an owned `Module`. It borrows input only during the call; names that survive parsing are interned into the module. The caller deinitializes successful modules. Any failed parse frees tokens, name maps and all partially constructed functions. `InvalidInput` carries a typed diagnostic with a half-open source byte span; allocator/resource errors propagate separately. There is no process exit or CLI diagnostic rendering in this API.

## Currently accepted subset

```text
[export] function [w|l|s|d] $name([type %parameter, ...]) {
@block
    %result =type phi @predecessor operand, @predecessor operand
    %result =type call $direct_symbol(type operand, type operand)
    call $void_symbol(type operand, type operand)
    %result =type copy operand
    %result =type neg operand
    %result =type cast opposite-class-same-width-operand
    %result =d exts single-operand
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
- Direct nonvariadic scalar-result or void-result calls with explicitly typed base-scalar arguments are accepted; empty argument lists are allowed. Void calls are effect-only statements with no result definition. Known callee result presence/type must match; omitting a nonvoid return is not permitted. Indirect/variadic/environment/aggregate/extended-ABI calls are unsupported. Native emission checks known module-local signatures; external signatures remain a caller contract. The standalone evaluator reports `UnsupportedCall` only when a call is reached; module-aware evaluation can interpret internal direct calls, but never external functions (see MODULE-EVALUATION.md). See CALLS.md.
- Types are the four base scalar types. Binary operands and copied/returned values must match their declared type exactly. Implicit mixed-width temporary conversions are not implemented.
- `copy`, `add`, `sub`, `mul`, `div` support matching integer or floating types; bitwise operations, `udiv`, `rem` and `urem` require integer types.
- Integer `div` truncates the signed quotient toward zero; `rem` has the dividend's sign. `udiv`/`urem` use unsigned bits. The evaluator returns `DivisionByZero` or `IntegerOverflow` for exceptional integer pairs; native AMD64 execution faults instead. See SCALAR-SEMANTICS.md for this explicit boundary.
- `neg` preserves the operand/result width. Integer negation wraps; floating negation flips only the sign bit, including signed zero and NaN payloads. Integer extensions consume word operands: byte/half extensions produce word or long, while word extensions produce long only. They sign- or zero-extend the selected low bits. These are ordinary instructions, not extended ABI parameter types.
- `cast` preserves raw bits across word/single or long/double classes in either direction. It is not numeric conversion. `exts` widens a single to double, exactly for finite values. Double-to-single `truncd` and numeric integer/float conversions are still unsupported.
- Shifts require a word count, including when shifting a long. Only the low five (word) or six (long) count bits are used; `shr` is logical and `sar` is arithmetic.
- Integer comparison opcode suffixes select operand width independently of the word/long result width. Results are exactly zero or one. For example, `%r =l csltw %a, %b` compares word operands as signed integers and produces a long. Floating comparisons use their own single/double suffixes and predicates.
- Decimal integer constants wrap modulo 2^64, with explicit low-word truncation in word contexts. An untyped immediate branch condition is retained as long; branch interpretation tests its low 32 bits.
- Floating comparisons return word or long zero/one independently of operand width. NaN makes `ne` and `uo` true and `eq`/relative comparisons/`o` false. Signed zeros compare equal; infinities retain numeric ordering. Exception flags and unmasked floating traps are not part of this subset's conformance claim.
- Floating literals retain their `s_`/`d_` width, including decimal/hex spellings, signed zero, infinity and plain NaN. Numeric conversion uses Zig, not libc. NaN payload spellings are scanned intact but **rejected explicitly by this parser** until payload semantics are implemented.
- Phi nodes precede ordinary instructions in a block. The parser retains typed predecessor/value pairs; `ssa.validate` checks predecessor coverage and incoming-edge dominance.
- Forward **block targets** are resolved by a declaration pass. Temporary result types are predeclared, so loop backedges and layout-independent forward references are accepted; scalar SSA validation must establish actual definition availability. Parameters and blocks are scoped per function; duplicate function/block/value names are rejected.
- The lexer returns borrowed raw spans, including string escapes and quoted global names; it does not silently decode/rewrite names. Quoted globals, strings as operands, aggregates, data, memory operations, unsupported call forms, varargs, extended ABI types and unimplemented opcodes are explicitly rejected by the parser.

## Not a full verifier or compiler

Parsing checks syntax and the current IR's structural/type invariants. It does **not** prove SSA dominance, validate phi edges or enforce the first-block predecessor restriction. In particular, a textually earlier definition in a non-dominating block is not yet rejected. Call `ssa.validate` for current scalar ordering/dominance checks before using parsed IR as verified SSA. The bounded interpreter does this automatically. `ssa.validate` returns `EntryHasPredecessors` for any edge targeting the first block, including from an unreachable block, matching QBE's invocation-entry rule. Current scalar phi-edge coverage and dominance are checked by `ssa.validate`; full-IL verification remains future work. See SCALAR-SEMANTICS.md.

The new API is not yet a drop-in QBE parser: strict malformed-number rejection is intentional and does not emulate legacy scanf prefix recovery; diagnostic codes are not a promise of the old CLI's exact messages. The legacy CLI and compatibility modes are unchanged.

`src/fixtures/constant-jump.ssa` is copied unchanged from the existing `tests/upstream-bug-jnz-constant.ssa` regression. Tests parse all four functions independently and inspect typed constants/targets; this is parsing coverage, **not** proof of compiled execution or optimized branch folding.
