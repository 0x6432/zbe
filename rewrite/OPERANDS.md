# Scalar instruction-use iteration

`Instruction.operands()` returns an allocation-free `OperandIterator`. Repeated `next()` returns copied scalar operands in stable source order, then `null` on every subsequent call. It never yields a definition/result, direct-call callee ID, byte count, predecessor/block ID or fabricated operand.

| Instruction | Scalar uses |
| --- | --- |
| `copy`, `unary`, numeric `convert` | operand |
| `binary`, integer/float comparison | lhs, rhs |
| `shift` | value, amount |
| `allocate` | long byte size |
| `load` | address |
| `store` | value, address |
| `blit` | source, destination, including for zero byte count |
| Direct call | typed argument operands, in order |
| Indirect call | address target, then typed argument operands |

Scalar/void call results do not change use traversal; empty and target-only calls work without special caller branches. This is a **use accessor**, not structural/type/SSA validation. It can inspect a payload without proving its operands belong to a valid function.

## Ownership and implementation

The iterator retains at most two optional fixed `Operand` values and a borrowed call-argument tail slice. It does not return a pointer or slice into a temporary instruction/union payload, store the entire function, allocate a buffer, pack numeric references or use mutable globals. Fixed operands remain valid after the original instruction value is overwritten or goes out of scope.

Call argument storage still belongs to the function (or, for manually constructed instructions, its original owner). That storage must remain alive and unmodified while iterating. The iterator does **not** duplicate arguments, extend owner lifetime, permit iteration after function deinitialization, or turn borrowed slices into capabilities. Use the accessor to construct iterators rather than mutating iterator state fields.

Production SSA validation, liveness block-use construction and interference's backward use scan now share this accessor. Definition handling, traversal/solver order, phi-edge handling, resource caps and ownership are unchanged. Phi/terminator traversal remains separate: phi operands have predecessor-edge semantics, not ordinary instruction-point uses.

The independent path-search/program-point liveness/interference oracles intentionally retain their own exhaustive tagged-union use switches. They do **not** call this iterator, so a missing/misordered production operand is not silently reproduced in the expected results. The existing mixed scalar/call/memory/blit fixtures continue through these oracles.

Three direct tests cover every fixed instruction variant (with an explicit tag-count coverage check), source order/result exclusion, repeated exhaustion, every scalar/void × direct/indirect × zero-through-four-argument call combination with all raw classes, target-only calls, and fixed-operand lifetime across overwritten/temporary instruction values. The tagged-union accessor switch remains compile-time exhaustive for future variants. Existing malformed-SSA, analysis-oracle and allocation-failure tests exercise the production consumers.

This is a focused representation/maintenance improvement, not a new optimizer, performance claim, complete compiler milestone or assertion of "100% idiomatic Zig."


`Operand.low_word` is a copied long-source projection, not a new SSA definition. `Operand.referencedValue()` returns its original source ID (or the ordinary value ID; constants return null). Production SSA/liveness/interference include that source, including phi-edge uses; independent oracles retain their own operand switches. A fourth iterator test checks projection/source identity after overwriting the originating instruction. See LOW-WORD.md.


`Operand.symbol` is a copied module-pool symbol address with long type. It is a
scalar operand, not a function-local value: referencedValue returns null and
production/independent analyses do not invent a live SSA identity for it. Direct
call-target IDs remain outside the scalar-use iterator; scalar symbol arguments
and manually constructed symbolic indirect address operands are included. See
SYMBOL-ADDRESSES.md for module ownership, emission and interpreter refusal.
