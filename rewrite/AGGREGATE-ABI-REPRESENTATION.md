# Aggregate ABI representation only — NO aggregate execution

Stage1 retains explicit owned record ABI annotations in signatures and calls.
It does not implement MEMORY-class calling, hidden returns, by-value copies,
variable-sized ABI stack plans, register aggregate classification or interpreter
aggregate execution. A successful parse/validation is NOT a compilable aggregate
ABI feature. Both native emission and reached interpreter use return
`UnsupportedAggregateAbi` at the boundaries below.

## Typed metadata, not first-class values

`ir.AbiDescriptor` is tagged `.scalar(existing AbiType)` or
`.record(module-scoped AggregateTypeId)`. Record declarations/layouts remain as
specified in [RECORD-DECLARATIONS.md](RECORD-DECLARATIONS.md). ANY valid regular
record may appear in metadata, including size1, alignment64 or compact
UINT64_MAX-size records. There is NO target classifier or17..4096-byte ABI policy
in this representation layer, and no allocation of conceptual record bytes.

Pinned QBE e786f06032fefa2e3790d6b1c9e31ed138f475a6 `doc/il.txt` Functions/Call
uses pointers for aggregate parameters/results. Accordingly, record annotations
retain a long SSA POINTER carrier while preserving their record ABI tag:

```text
type :Tiny = { b }
function :Tiny $identity(:Tiny %p) {
@e
    ret %p
}
function $caller() {
@e
    %address =:Tiny call $identity(:Tiny 0)
    ret
}
```

This parses into owned metadata; compilation/evaluation does NOT pass Tiny as
an ordinary long argument. `%address` is a long value for existing scalar SSA
uses. `:Tiny` is permitted as a function/call ABI annotation, NOT an arithmetic,
copy, phi or data group class. No aggregate Operand/Constant/ScalarType is added.
Earlier record declarations resolve through `Module.record_names`, never the
code-generation symbol pool; unknown type names have `unknown_type` diagnostics.

Coherent record+environment or record+variadic annotations are metadata too.
Existing scalar env+variadic INVALID combinations remain invalid. The hidden
environment parameter itself must normalize EXACTLY to scalar-long: a record
tag there is `InvalidEnvironment`, even with a long carrier. All aggregate uses
remain nonexecuting regardless of options; generic metadata acceptance says
nothing about future target support for these combinations.

## Coherence and ownership/API boundary

Function return_descriptor, parameter Value.parameter_descriptor,
CallArgument.descriptor and Call.result_descriptor retain tags/IDs. Legacy
scalar carrier/subword fields are kept for compatibility, NOT unchecked caches:
- Null descriptor derives the exact legacy scalar ABI annotation.
- Explicit scalar descriptor must equal that full annotation, including subword
  signedness/width, not merely its word carrier.
- Explicit record requires long carrier, no subword and actual parameter/result
  presence. A parameter annotation on an instruction/phi value is invalid.
- Contradictory public fields are `TypeMismatch`, not silently repaired/erased.

Checked returnAbi/parameterAbi/argument.abi/call.resultAbi accessors normalize
these invariants. Legacy scalar builder APIs retain their signatures/behavior;
new initDescriptor/addParameterDescriptor/addFunctionDescriptor/argument
initDescriptor and result_descriptor call options retain explicit ABI identity.
If BOTH scalar result_abi and result_descriptor are supplied, exact tagged
`.scalar(result_abi)` equality is allowed; ALL contradictions (including record
versus scalar-long) are TypeMismatch before allocation/publication.

Descriptors are inline IDs/enums; call argument tails are copied and Function
owned. Caller/parser arrays can be overwritten/freed. Records/names remain
Module owned, with stable independent record_names; no backpointer, global
registry, packed pointer or retained lookup/layout cache. Raw numeric IDs cannot
prove cross-module provenance; explicit remapping is the caller's obligation.

Detached Function builders/checks validate tag/carrier/SSA shape, not inaccessible
module type ownership. Module addFunctionDescriptor/addParameterDescriptor/
appendCallDescriptor wrappers check descriptor IDs before mutating functions.
Module validation recomputes ALL records and structural/SSA metadata, then a
complete descriptor-ID pass covers every signature and external/indirect/
unreachable call slot BEFORE known direct-call signature matching. Nominal
record IDs must match; equal layouts/sizes or long carriers are not equality.
Unknown IDs are `InvalidAggregateType`. Invalid unused metadata cannot be
hidden behind a generic execution-refusal error.

## Refusal/error precedence

Native emission does full module validation, then rejects ANY record ABI
signature/call (including unused functions/unreachable calls) BEFORE frame/home
planning, scalar ABI cursor use or output generation. The driver does not
create/modify output files on these failures. Existing scalar assembly is
byte-identical to the pre-change867 tree, including quoted COMMON/ordinary/
external aliases and unused declarations. Scalar codegen/frame logic is unchanged.

Standalone evaluate does existing structural/SSA validation, then rejects a
record root signature BEFORE execute's depth check, simulated memory setup,
frame allocation or argument binding. evaluateModule retains invalid-entry
precedence, full module validation and then the same root guard. A reached
record call charges its existing instruction step FIRST (budget exhaustion
wins), then refuses BEFORE owner/external lookup, operand resolution or child
frame publication. Memory/global/stack/vararg options cannot enable it. Unreached
record calls do not invent execution or detached module ownership; all module
metadata still validates. Scalar default errors/order remain unchanged.

Builders retain existing scalar validation order and publish only after storage
reservations/copies. Every new optional annotation and copied argument survives
failure/retry coherently; invalid dual options/IDs cannot advance parameter IDs
or install instruction definitions. Failure cleanup may retain existing allocator
capacity as before, never a partial published function/parameter/instruction.

## Evidence boundary

The independent hand-authored scalar/subword/tag table and nominal-ID tests do
not derive expectations from production carrier helpers. Focused tests cover
unused/malformed fields, complete ID-pass ordering, generic huge/overaligned
records, optimizer tag retention, detached/module guards, existing scalar errors,
input ownership and exhaustive allocation failures/retry/late parse cleanup.

`tools/aggregate_abi_representation_check.py` checks execution refusal/output
preservation and scalar assembly SHA expectations captured from EXACT pre-change
86799a806d58b871bcbb23e3a5b6a1bf46007b66 (not from the candidate). Its immutable
oracle fixture records source hashes/all8 option modes; `--baseline-compiler`
additionally compares complete bytes to an independently built prior compiler.
`--check` verifies those fixture inputs only. This is a scalar nonregression
oracle, NOT aggregate ABI execution/compatibility evidence. Full grouped gates,
independent implementation review and exact-commit CI remain publication gates.

## Scalar parser compatibility

Parsed scalar function results, parameters and call arguments/results continue to
use the established legacy scalar/subword fields with a null explicit descriptor.
This preserves existing public scalar-field mutation and error precedence. Parsed
record slots retain explicit nominal descriptors. Public descriptor builders still
accept explicit scalar tags and validate their exact coherence; this is not a
relaxation of contradictory-metadata checks.
