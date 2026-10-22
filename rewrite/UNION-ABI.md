# Bounded named unions and native ABI

The frontend accepts `type :U = [align A] { { members } { members } ... }`.
Every alternative is nonempty; fields are b/h/w/l/s/d or an earlier named
regular record/union/opaque declaration, with positive repeats. There are no commas between arms;
commas within an arm and a trailing field comma follow regular-record syntax.
No anonymous inline unions, forward/self references, empty types or
first-class aggregate arithmetic/phi/copy are added.

## Owned checked layout

`Record.kind` distinguishes regular declarations from `union_type`. Regular
records retain their existing flat `runs` API and empty `variants`. A union owns
one flat run array plus `Variant { first_run, run_count, size, alignment }`
headers. Headers partition every run exactly once. Each arm starts at byte zero,
uses normal member alignment/exact declared child stride, and has its own checked size.
The union takes maximum arm size/alignment and rounds to effective alignment;
explicit alignment is a minimum. This is not a host-language layout guess.

Both builders and module-aware consumers recompute ALL arms, including unused
ones and cached ranges/layout facts. Checked range addition precedes slicing.
Earlier-only nominal IDs remain module scoped. Names still use the separately
owned `record_names` pool, never codegen symbols. No hidden owner backpointers,
active-member tag, new scalar carrier or ABI descriptor is introduced.

Limits remain 4096 declarations, 4096 field runs per declaration (ALL union arms
combined), 65536 module runs, repeat 1..2147483647, checked u64 sizes and power-of-
two alignment <=64. Header count is bounded by the nonempty-run budget. Parser
checks logical temporary run/header growth before appending. Fields and arm
views are copied; source buffers, caller lists and later table growth do not
invalidate owned metadata. Failure consumes no published type ID or run budget;
like the existing builder, an interned unused type name may remain on OOM.
Cleanup frees owned arrays independently of a mutable kind discriminator.

## Complete bounded Linux AMD64 endpoint

The existing native direct/indirect, nonvariadic scalar-ENV, variadic call and
variadic-definition endpoints accept union descriptors under the SAME limits:
size 1..4096, effective alignment <=16. The classifier merges occupied bytes
from ALL overlapping arms (INTEGER dominates SSE), including unions nested at
non-eightbyte offsets. Size <=16 uses the existing INTEGER/SSE/NO_CLASS lanes;
size >16 uses MEMORY. Complete GP/SSE tuples roll back together when either bank
is full. Padding-only lanes consume no register. Declared storage/stack extent
is distinct from active lanes. Existing private parameter objects, per-call
result pads, hidden RDI/RAX and raw named-stack-end/176-byte variadic save rules
are reused, not replaced by scalar-long ABI erasure.

Aggregate `vaarg`, ENV+varargs, other targets, vectors, unsupported alignment/
size and aggregate interpreter execution remain explicit refusals. C helpers
may consume a union from the SAME live `va_list *`, without escaping it, then IL
may continue scalar vaarg. Standalone scalar interpreter validation cannot
inspect unrelated inaccessible module metadata; module evaluation validates all
declarations first. Pre-write parser/validation/planner/emitter errors and OOM
preserve existing output; later filesystem I/O atomicity is not promised.

## Independent evidence and compatibility

`aggregate_abi_union_test.zig` covers owned publication/OOM retry, max-versus-sum,
all-arm validation/tampering, shifted nested layouts, UINT64_MAX/product/cursor/
rounding boundaries, parser/module limits, and the exact 65536-byte frame cap.
`aggregate_abi_union_check.py` executes independent C unions and hand assembly,
raw NaN/zero/infinity/subnormal transport, read-only source and guarded result
spans, private copies, ENV bridges, hidden results, bank rollback and shared
va_list continuation. It checks six immutable prior record modules and scalar
references against goldens made ONLY with published compiler 203886b; matched
scalar fragments first require equal symbols/order and function ordinals.
Old regular-record/INTEGER/SSE/MEMORY APIs and whole assembly are preserved.
Only the precise historical union-declaration rejection is upgraded positively.

The semantic design is SHA256
`4d9dce86d8254fc6a6795c2c69ab18c78b67badfc44b3c767323874262c0a92b`.
Primary authority is official AMD64 SysV classification plus independent C/ASM.
Pinned QBE e786f06032fefa2e3790d6b1c9e31ed138f475a6 parsefields/parsetyp and
classification support the bounded semantics, but its fixed expanded-field
representation, unchecked layout limits and suspected padding-only-lane issue
are NOT claimed as full oracle parity. This does not assert an unexecuted
upstream crash or preserve that padding-class discrepancy.

Opaque child strides are unrounded declared bytes, unlike padded regular/union
children. See [OPAQUE-ABI.md](OPAQUE-ABI.md) for owned payload validation and forced
MEMORY transport. Small unions transitively containing opaque members refuse
native ABI use, even when another arm has ordinary INTEGER/SSE fields.
