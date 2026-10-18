# Opt-in internal scalar variadic evaluation — bounded design

## Scope and invariants

Add `Options.internal_variadic_calls` (default false). Only reached, validated,
module-local direct calls to scalar variadic definitions gain dispatch when true.
This does not enable root tails, consumers, stack memory, globals or host lookup.
Standalone calls, external/indirect calls, environment+varargs, aggregates and
implicit promotions remain unsupported. Existing default refusals and their
precedence stay unchanged. No native/frontend/IR/validator change is required.

The existing module validator remains authoritative: exact result/subword and
named prefix identity, exact named marker, and typed scalar tails. Named arguments
initialize only ordinary parameters; extra arguments never become parameters.
Tail values retain their explicit word/long/single/double raw bits. No C default
promotion or tail-to-consumer type check is invented. Narrow ABI annotations
retain existing word transport, not inferred sign/zero extension.

## Dispatch and ownership

Resolve a reached call's target first. Default variadic refusal precedes depth
and argument resolution. When enabled, depth is checked before resolving all
arguments in declaration order, as for ordinary calls. Copy named and tail values
into a separately owned immutable invocation snapshot before publishing the child
frame; parameter SSA storage is separately initialized from only the named prefix.
Allocation failure cannot publish an incomplete child. Temporary argument storage
is freed after frame construction; the snapshot is freed on return or any error.
No pointer into the growable frame handle array survives a push. Root initialization
continues borrowing its explicit synchronous root-tail slice and never inherits
this dispatch option. Child tails never borrow caller storage or root options.

A child reached `vastart` uses its own snapshot and existing per-frame initial
cursor state. It lazily allocates exactly the existing synthetic save/overflow
object, with named bank occupancy and shared overflow placement unchanged. Empty
tails are explicit and usable; no-varop paths need no synthetic memory. Repeated
initialization resets only descriptor cursors, not source bytes. Existing complete
24-byte destination precheck/failure atomicity, raw padding initialization and
mixed-region byte order contracts apply unchanged.

## Lifetime and accounting

The child's object mark precedes all its allocations. Ordinary descendants can
consume its descriptor; their returns preserve ancestor objects. Returning releases
only this child's objects and snapshot. Escaped addresses into a returned source
are dead and never reused within evaluation. Recursion is iterative and each
variadic invocation has distinct snapshot, descriptor state and source ownership.

Call/vastart/vaarg each consume one existing shared instruction step; frame copying
and byte loops add no fictitious IL steps. max_call_depth remains root inclusive.
Snapshot storage costs O(number of call operands) per active variadic invocation,
like existing temporary argument resolution, and is NOT charged as synthetic
stack bytes. This is not a total host-memory/time bound; input size and depth
remain caller costs. Lazy source bytes use the existing cumulative round-up plus
guard reservation (not reclaimed on return), StackLimitExceeded and allocation
errors. No implicit Image resizing, stack enablement or native pointer exists.
Completed Image writes survive later faults. All owned memory cleans up.

## Verification plan and compatibility limits

Add independent raw-value/descriptor expectations across classes and byte orders,
named GP/SSE exhaustion and declaration-ordered overflow; empty/no-varop paths;
root/child isolation, forwarding, recursion and frame-array growth; repeat/reset,
copied cursors and source mutation; live ancestor/dead child/sibling lifetimes;
exact depth/step/reservation boundaries and error precedence. Exercise every
allocation failure plus successful recovery and retained prior writes. Keep all
existing fixtures, generators, native harnesses and CI unchanged, and run all
three fresh unit modes, formatting, all14 generators and all24 native configs.
Actual results and failures belong in HANDOFF.md and coordination evidence.
This document specifies a diagnostic scalar model, not full ABI/QBE parity,
performance, native invalid-address fault parity, or exact-SHA CI success.
