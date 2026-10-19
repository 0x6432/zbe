# Bounded aggregate record declarations — not an aggregate ABI

`type :Name = [align A] { MEMBER [COUNT], ... [,] }` declares an owned,
nonempty regular record. Members are b/h/w/l/s/d or previously declared records.
Types are not ELF symbols or scalar values. This layer preserves and validates
structure/layout metadata; it does not enable aggregate execution or by-value ABI classification. Explicit
record signatures/call annotations retain nominal metadata
([AGGREGATE-ABI-REPRESENTATION.md](AGGREGATE-ABI-REPRESENTATION.md)). A separate bounded
native MEMORY endpoint is described in [AMD64-MEMORY-ABI.md](AMD64-MEMORY-ABI.md); aggregate
first-class SSA classes, phis and data groups remain unsupported.

## Exact subset and layout

Pinned QBE e786f06032fefa2e3790d6b1c9e31ed138f475a6 parse.c/findtyp/parsefields/
parsetyp and doc/il.txt establish the included semantics. Scalar size and natural
alignment are1/2/4/8 for b/h/w,s/l,d. Each field run aligns the cursor to its
member's alignment, then adds count×member-size. Child stride includes its entire
padded size. Final record size rounds to max(member alignments, explicit A).
A smaller explicit alignment is a minimum, not packing: align2{d,b} is size16/
alignment8. These are QBE declared record layout facts, never host Zig/C layout,
HFA/eightbyte register classes, bitfield rules or platform ABI promises.

Counts are checked positive decimal1..2,147,483,647 (default1), never modulo
integer literals. A is a checked power of two1..64. All products, cursor additions,
member align-ups and final rounding use checkedu64; representable UINT64_MAX-size
alignment1 layouts are accepted as compact metadata, without allocating their
conceptual bytes. No Data payload cap applies to type sizes.

Unions, opaque/dark/empty types, zero/negative repeats, forward/self/mutual
references, duplicate type names, ABI subword fields, quoted type names and type
linkage attributes remain explicit refusals even when unused. The positive-count,
alignment and duplicate policies are deliberately stricter than upstream's
unchecked/count-narrowing/non-power-of-two recovery/name-shadowing behavior.
Do not claim complete aggregate syntax or ABI support.

## Ownership, bounds and namespace

Module.types owns separately allocated Record objects and copied Run slices.
AggregateTypeId is module-scoped, distinct from function ValueId and ABI classes;
only strictly earlier child IDs are valid. Record names are interned in a dedicated
Module.record_names pool; Module.symbols is exclusively the scalar/code-generation namespace. Names use the existing
pool-scoped symbols.Id, whose numeric value is NOT cross-pool provenance.
Interned names and Record pointers survive table growth; input and caller field arrays are borrowed only during
building. There is no global registry, function-owner backpointer, expanded-member
array, persistent name lookup or cached module-run counter. Authoritative type
lookup scans the bounded record table; normal symbol-pool ownership/interning
invariants remain caller obligations, as in existing IR.

Caps are4,096 records/module,4,096 field runs/record and65,536 runs/module; counts
bound metadata, not repeated bytes. They exclude token/parser scratch, symbol
storage, validation scratch, allocation metadata and emitted text. Partial
allocation can retain capacity/an unused interned name, never a published partial
record or advanced ID. Failed owned creation/table publication cleans up and can
be retried. Records/runs are destroyed before their record-name pool; both pools
are owned and destroyed by the module. Successful and failed type additions do not intern
or reorder any code-generation symbols.

The type namespace is separate from global function/data definitions. :T may
coexist with $T as equal spellings in separate pools without defining another ELF
symbol or changing scalar SymbolIds/private alias labels. A valid unused declaration
must leave scalar assembly byte-identical;
type-only modules emit only the existing empty-module scaffolding.

## Validation/API boundary and acceptance

Publication validates new layouts against already validated earlier records.
Module validation recomputes EVERY unused record's name/ID/duplicate/metadata
bounds, child ordering, counts, offsets, strides, explicit/effective alignment and
size before native emission or evaluateModule. It trusts neither cached layout
numbers nor a secondary type lookup. Record names are checked against the
record-name pool, never the code-generation symbol pool. Public edits must preserve
allocated slice/owner validity; validators cannot make arbitrary dangling pointers safe.
Standalone interpreter.evaluate(*Function) intentionally cannot inspect unrelated
module records: its scalar SSA validation/execution stays unchanged. Tests show
that tampered unused types reject in module-aware consumers while the same
standalone scalar function still runs. No hidden globals/backpointers are added.

The independent Python layout fixture uses arbitrary-precision integer division/
remainders, not production/host layout; includes271 record DAGs and the exact
A=(2^31−1), B=A², C=4B+8A+3=UINT64_MAX anchors. Product, cursor, member-alignment
and final-round overflow are separate negative tests. A temporary observed copy
of the pinned C reference supplies secondary size/alignment checks only; its
first32 expanded-field storage is not an oracle for this owned run model.

Focused tests additionally cover every aggregate-use refusal position, namespace,
source/field lifetimes, stable pointers, all-eight-mode scalar byte identity,
zero-code type-only units, unused-cache tampering, exact metadata limits,
publication-growth OOM retries and exhaustive allocation cleanup. Native tests
run independent scalar expectations in PIE/non-PIE and preserve output files on
invalid/unsupported input. Actual passes/final combined gates belong in the
coordination result; this design does not itself claim completed verification.
