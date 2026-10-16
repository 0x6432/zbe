# Independent scalar frontend

`frontend.parse(allocator, Source, &diagnostic)` returns an owned `Module`. It borrows input only during the call; names that survive parsing are interned into the module. The caller deinitializes successful modules. Any failed parse frees tokens, name maps and all partially constructed functions. `InvalidInput` carries a typed diagnostic with a half-open source byte span; allocator/resource errors propagate separately. There is no process exit or CLI diagnostic rendering in this API.

## Currently accepted subset

```text
[export] function [w|l|s|d] $name([type %parameter, ...]) {
@block
    %result =type phi @predecessor operand, @predecessor operand
    %result =type copy operand
    %result =type neg operand
    %result =w|l extsb|extub|extsh|extuh word-operand
    %result =l extsw|extuw word-operand
    %result =type add|sub|mul|and|or|xor operand, operand
    %result =w|l shl|shr|sar operand, word-count
    %result =w|l ceq[w|l]|cne[w|l]|cslt[w|l]|csle[w|l]|csgt[w|l]|csge[w|l]|cult[w|l]|cule[w|l]|cugt[w|l]|cuge[w|l] operand, operand
    jmp @block
    jnz operand, @true, @false
    ret [operand]
}
```

The ellipsis above describes repeated parameters, **not** variadic IL. A missing function result type means void. Every actual block must end in exactly one explicit terminator; the example lists alternative instruction/terminator forms, not a single valid block. Labels occupy their own lines; instructions end at a newline or closing brace. LF and CRLF input, comments and blank lines are supported. Function export linkage is retained in the IR.

- Types are the four base scalar types. Binary operands and copied/returned values must match their declared type exactly. Implicit mixed-width temporary conversions are not implemented.
- `copy`, `add`, `sub`, `mul` support matching integer or floating types; bitwise operations require integer types.
- `neg` preserves the operand/result width. Integer negation wraps; floating negation flips only the sign bit, including signed zero and NaN payloads. Integer extensions consume word operands: byte/half extensions produce word or long, while word extensions produce long only. They sign- or zero-extend the selected low bits. These are ordinary instructions, not extended ABI parameter types.
- Shifts require a word count, including when shifting a long. Only the low five (word) or six (long) count bits are used; `shr` is logical and `sar` is arithmetic.
- Integer comparison opcode suffixes select operand width independently of the word/long result width. Results are exactly zero or one. For example, `%r =l csltw %a, %b` compares word operands as signed integers and produces a long. Floating comparisons are unsupported.
- Decimal integer constants wrap modulo 2^64, with explicit low-word truncation in word contexts. An untyped immediate branch condition is retained as long; branch interpretation tests its low 32 bits.
- Floating literals retain their `s_`/`d_` width, including decimal/hex spellings, signed zero, infinity and plain NaN. Numeric conversion uses Zig, not libc. NaN payload spellings are scanned intact but **rejected explicitly by this parser** until payload semantics are implemented.
- Phi nodes precede ordinary instructions in a block. The parser retains typed predecessor/value pairs; `ssa.validate` checks predecessor coverage and incoming-edge dominance.
- Forward **block targets** are resolved by a declaration pass. Temporary result types are predeclared, so loop backedges and layout-independent forward references are accepted; scalar SSA validation must establish actual definition availability. Parameters and blocks are scoped per function; duplicate function/block/value names are rejected.
- The lexer returns borrowed raw spans, including string escapes and quoted global names; it does not silently decode/rewrite names. Quoted globals, strings as operands, aggregates, data, memory operations, calls, varargs, extended ABI types and unimplemented opcodes are explicitly rejected by the parser.

## Not a full verifier or compiler

Parsing checks syntax and the current IR's structural/type invariants. It does **not** prove SSA dominance or validate phi edges. In particular, a textually earlier definition in a non-dominating block is not yet rejected. Call `ssa.validate` for current scalar ordering/dominance checks before using parsed IR as verified SSA. The bounded interpreter does this automatically. Current scalar phi-edge coverage and dominance are checked by `ssa.validate`; full-IL verification remains future work. See SCALAR-SEMANTICS.md.

The new API is not yet a drop-in QBE parser: strict malformed-number rejection is intentional and does not emulate legacy scanf prefix recovery; diagnostic codes are not a promise of the old CLI's exact messages. The legacy CLI and compatibility modes are unchanged.

`src/fixtures/constant-jump.ssa` is copied unchanged from the existing `tests/upstream-bug-jnz-constant.ssa` regression. Tests parse all four functions independently and inspect typed constants/targets; this is parsing coverage, **not** proof of compiled execution or optimized branch folding.
