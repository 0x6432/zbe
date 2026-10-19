# Checked AMD64 ABI plans — prerequisite only

`abi_amd64_plan.FunctionPlan.init(allocator, module, function_id, options)` produces
an owned target-planning snapshot. Externally supplied snapshots are **not emitter
inputs**. The native endpoint now builds fresh emission-scoped ModulePlans internally,
with complete global eligibility before allocation; see [AMD64-MEMORY-ABI.md](AMD64-MEMORY-ABI.md).
All interpreter aggregate guards remain unchanged. The standalone planning API never
executes code or authorizes later use of edited IR.

## Target scope and validation

Plans target Linux AMD64 SysV LP64, not the host's language layout. Record layout
and nominal IDs come from the module's already validated owned declaration layer;
type names remain in `record_names`, separate from code-generation symbols.

The planner accepts mixed scalars and MEMORY records whose declared size is
17..4096 bytes and effective alignment is at most16. This is a conservative target
subset and resource policy, not a restriction on valid declarations. Generic
metadata still permits tiny, align32/64 and UINT64_MAX records; unused declarations
do not trigger target refusal. The additional integer-only size1..16, align1/2/4/8 target subset has whole-argument
GP tuples and RAX/RDX results; see [SMALL-INTEGER-ABI.md](SMALL-INTEGER-ABI.md).
SSE/mixed size1..16 records now have tagged GP/XMM lane plans and atomic BOTH-bank
assignment; see [SMALL-SSE-ABI.md](SMALL-SSE-ABI.md). No small align16+, vector, opaque,
unaligned, C++ invisible-reference or non-SysV classification is provided.

In this closed b/h/w/l/s/d record universe, a record larger than two eightbytes
cannot satisfy the official ABI's SSE/SSEUP vector exception, hence is MEMORY.
Do not generalize that statement to future vector types. The basis is pinned QBE
`e786f06032fefa2e3790d6b1c9e31ed138f475a6` `amd64/sysv.c` and `doc/abi.txt`, plus
AMD64 psABI1.0 March12,2025 §§3.2.2–3.2.3.

Eligibility is **per signature/call**, not whole-function contagion:
- A record-bearing function signature cannot itself be variadic/environment-bearing.
- A record-bearing call must itself be direct-symbol, nonvariadic and without env.
- A scalar-only env/variadic caller may contain an eligible direct record call.
- An eligible record-signature function may contain scalar env/variadic/indirect calls.

Invalid selected FunctionId is checked first. Full existing module validation
(including unused layouts, all descriptor IDs and known nominal signatures) comes
next. An allocation-free target scan then checks the selected signature and EVERY
call site, including unreachable sites, before any plan/home/interference allocation
or frame geometry can mask a later unsupported site. Module validation itself can
allocate/fail. Generic invalid metadata wins over target refusal. Other functions
are generically validated, but are not independently target-planned by this API.

## Signature facts

Each argument retains its exact descriptor, scalar pointer/value carrier, declared
payload and register or byte-based stack location. Subword payloads are1/2 bytes
with word carriers; word/single4 and long/double8. Scalar stack extent is always8;
ABI padding and carrier width never erase signedness or change language payload.

GP and SSE banks exhaust independently in declaration order. A MEMORY result uses
hiddenRDI and returns that original address inRAX; ordinary GP allocation starts
atRSI, with SSE unchanged. MEMORY arguments consume no GP/SSE slot. Their byte
regions are aligned to max(8,record alignment), extent rounded8; outgoing area is
rounded16 with HIGH-address trailing padding. Stack offsets are currentRSP-relative;
incoming addresses use RBP+16+offset. Checked positive record size and inclusive
last byte `16+offset+(declared_bytes-1) <= INT32_MAX` prevent overflow before casts.
Scalar displacement compatibility retains the old start-only bound.

Scalar-only envRAX, variadic occupied-SSE count and176-byte register-save-area
rules are project compatibility contracts and are retained, not redefined by this
planner. Old scalar marshalling instructions and the existing cursor are unchanged.

## Frame snapshot and ownership

Home options use the existing owned coloring layout; baseline identity homes,
phi scratch and saved-original register slots preserve existing scalar geometry.
The plan owns all argument/call/pad/private-parameter-object arrays and any home layout. It stores no borrowed
Module/Function/record/name/layout pointers, hidden ownership links or global cache.
Allocator lifetime must cover the plan; call `deinit` once. Module/source storage
may be destroyed after construction. IDs remain nominal module-scoped ordinals,
not cross-module provenance tokens.

Every syntactic record-result call receives a distinct fixed, aligned pad. Pointer
home reuse never coalesces object storage. A MEMORY-return function also reserves
one saved hidden-pointer slot. With downward cursorC, sizeS and alignmentA, reserve
`end = alignUp(C+S,A)` and locate object at `RBP-end`; alignment gaps are padding.
The maximum outgoing reservation, not the sum of calls, sits below the fixed
prefix. All fixed storage plus outgoing is checked against the existing64KiB cap.
No allocation expands repeated fields or allocates record-byte-sized buffers.

Pads stay RBP-relative. Existing dynamic allocation subtracts alignedA fromRSP and
returns newRSP+outgoing; the outgoing region therefore moves below every live
allocation. The planner only records this geometry: it emits no probes or allocation
instructions. Same-site repeated calls may overwrite that site's pad; distinct
sites/recursive invocations remain separate. Pad disjointness does NOT prove the
ABI's arbitrary-pointer/noalias return-buffer contract. Stage3 must address that
operational contract and exact-size copy/clobber order explicitly.

The snapshot is immutable by convention, not authorization to use edited IR. A
future verified consumer must rebuild from current validated module data; no
emitter(snapshot,module) bypass or execution opt-in exists. Failures publish no
partial plan and leave source IR and previously owned snapshots unchanged.

## Coverage / nonclaims

Focused tests use independent literal mixed GP/SSE/byte-offset tables, checked
inclusive-limit/overflow/frame-cap oracles, payload-vs-extent controls, module-ID
and nominal mismatch tests, complete eligibility precedence, all scalar home modes,
per-site restrictions and copied snapshot lifetimes. Every allocation failure and
same-module retry checks ownership balance. Old scalar cursor comparisons are
secondary to independent prefix/register expectations.

The standalone planning API is not itself execution. Bounded native MEMORY
integration is separately documented in [AMD64-MEMORY-ABI.md](AMD64-MEMORY-ABI.md).
Other aggregate classes and all aggregate interpretation remain unsupported.
