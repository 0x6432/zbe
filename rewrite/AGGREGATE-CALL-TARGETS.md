# Nonvariadic indirect and environment aggregate calls

The Linux AMD64 SysV native backend accepts nonvariadic record definitions and
calls with a scalar-long hidden environment, and typed indirect record calls,
including their combination. All previously supported regular record classes
remain supported: INTEGER/SSE/mixed small records, align16 padding-only NO_CLASS
lanes, and bounded MEMORY records. No new class, size, alignment or target is
introduced. The environment is QBE's hidden-RAX extension, not the ordinary C
closure ABI. [ALIGN16-ABI.md](ALIGN16-ABI.md) documents the explicit
SysV/C policy for padding-only lanes; pinned QBE is not that subset's oracle.

## Representation and validation

Calls retain their owned typed ABI descriptors, ordinary argument array,
optional long target and separate optional long environment. Known module-local
signatures remain nominally checked, including missing used environments.
Supplying an environment to a non-environment callee, or omitting an unused
one, follows existing scalar rules. Indirect/external signatures, target validity
and environment meaning are the native caller's contract. No target inference,
host symbol resolution, ownership backpointer or hidden global is added.

Generic validation still checks ALL descriptor IDs (including unreachable and
external/indirect slots) before known signatures. Native eligibility scans ALL
functions and sites before any plan/home/frame/writer allocation. Bounded aggregate
variadic signatures/sites are supported separately (AGGREGATE-VARIADIC.md);
unsupported classes/alignment/size and invalid metadata remain explicit failures,
including unreachable sites. Interpreter
aggregate execution and indirect host execution remain refused: root aggregate
guards follow validation and precede depth/space/argument binding; reached calls
retain step-budget-first refusal before target/environment/argument resolution.

## Native ordering and resources

Fresh owned plans are rebuilt for each emission. The existing home allocator,
fixed private incoming objects/result pads, dynamic outgoing-stack invariant,
complete frame cap, checked sizes and stack probes are unchanged. Actual operand
uses and parameter/phi interference protect distinct target/environment/source
values through nested calls; using the same value for target and environment is
valid. No invented call-use clique or new callee-saved register is needed.

The record call sequence is deliberately different from scalar early target
parking: copy outgoing stack records; marshal tuple/scalar arguments; set hidden
MEMORY result RDI; load the durable target through RAX and move it to R11 **after
all record packing**; load the environment into RAX **last**; perform the call.
All address helpers used here—including quoted COMMON aliases and offsets—use
RAX only and do not destroy R11. Direct calls without an environment use exactly
the previous sequence. Return capture still precedes address LEA scratch, keeping
mixed RAX/XMM and hidden-RDI/original-RAX contracts intact.

The prologue saves hidden result RDI first and the environment to its durable
home before any incoming record unpack/address scratch. Exact byte copies,
NO_CLASS skipping, bank rollback, by-value isolation and per-site pad lifetime
remain unchanged. No aggregate pointer is silently retyped as scalar ABI data.

## Failure and verification boundary

All owned arrays/plans/homes/writer output are cleaned on allocation failure;
same-module retry is supported. Frontend/validation/planning/emission refusal or
OOM preserves an existing output file and does not create an absent one because
the driver has not written yet. This is NOT a new atomic-filesystem-replacement
guarantee for later I/O errors.

The additive `aggregate_abi_call_targets_test.zig` and
`tools/aggregate_abi_call_targets_check.py` use literal C layout/field checks,
explicit ENV assembly bridges, independently specified pressured GP/SSE/stack
coordinates, raw signaling-NaN transport, initialized guard spans, target/env
aliasing and liveness, quoted symbol/COMMON offsets and scalar variadic callers.
The actual published fb66417 compiler supplies only old whole-module assembly
and matched scalar-fragment goldens. Mixed-module reference tests independently
pin symbol ID order and function ordinals; they do not claim the old compiler
could compile the newly eligible whole module. Runtime mutation controls must
actually fail; unspecified padding bytes are never value oracles.

Original reviewed design: SHA256
`abd0590902c878f1a493c34a7d6c28f851a4f877dad4073fca0a0f6be61142c2`.

## Aggregate variadic extension

Bounded native record variadic calls and record-bearing definitions/vastart are
now supported separately: [AGGREGATE-VARIADIC.md](AGGREGATE-VARIADIC.md). Earlier
scalar/nonvariadic descriptions above describe their original slice, not a blanket
refusal of this extension. IL vaarg remains scalar-only; ENV+varargs and aggregate
interpretation remain refused. Raw stack end differs from rounded outgoing bytes.
