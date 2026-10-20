# Bounded native small INTEGER-record ABI

Implementation scope (verification checkpoints are recorded separately).
Accepted design: SHA256 7ed74a4309e46d793c304a3b58ba901ba55fbe2c08a3bcab0487e7c04d06abdf.
Build on the separately verified bounded MEMORY endpoint, not a new scalar carrier ABI.

## Closed target scope

Linux AMD64 ELF SysV LP64 direct record signatures/calls, declared size1..16,
effective alignment1/2/4/8, recursively only b/h/w/l fields in the existing owned
record DAG. All occupied one/two eightbytes must classify INTEGER. Small floating/mixed records are now separately supported by
[SMALL-SSE-ABI.md](SMALL-SSE-ABI.md), and align16/NO_CLASS by [ALIGN16-ABI.md](ALIGN16-ABI.md). Alignment32/64, vectors/opaque/union,
record-bearing variadic sites and ALL interpreter record uses remain
refused. Valid unused generic records remain metadata. Existing size17..4096 MEMORY
support, including its permitted s/d leaves and align16, is not narrowed.

Nominal descriptors still identify module-owned records, with long ADDRESS SSA
carriers. Planner-only GP tuples and INTEGER-result variants retain identity,
declared bytes, alignment and exact lane widths. A size9 record has8-byte and1-byte
lanes, not two readable qwords. Classification is separate from argument transport:
a spilled INTEGER argument does not turn its return classification into MEMORY.

## ABI assignment and ownership

INTEGER results use RAX then RDX, without hiddenRDI. MEMORY results retain hiddenRDI
and shifted ordinary GP bank. Before assigning a record argument, require enough
GP registers for ALL its lanes. Otherwise put the WHOLE object on stack without
consuming any GP register; later smaller/scalar arguments can use remaining GP
capacity. SSE bank stays independent. Stack layout retains checked declaration-order
packing,8-byte extent rounding,16-byte outgoing rounding and inclusive displacement
checks. Existing scalar subword payload/extent and excess-bit rules remain.

Register-passed record parameters receive distinct private fixed objects: store
incoming lane bytes, then home the object ADDRESS. Stack-passed records use their
writable incoming by-value copies. Every syntactic record-result call, INTEGER or
MEMORY, has its own fixed pad per invocation. These objects never coalesce because
SSA pointer homes share a color. Same-site loops overwrite that site's pad; recursive
activations are distinct; addresses expire with their activation.

All private objects/pads, homes, scratch, preserved originals, optional scalar-vararg
save area and MAX outgoing fit the existing64KiB cap/probes. Outgoing stays current-RSP
relative; fixed objects RBP-relative; dynamic allocation keeps newRSP+outgoing.

## Safe lane transport and register lifetimes

Full lanes use8-byte accesses. Partial lanes use bounded1/2/4-byte chunks whose sum
is exactly the lane's declared width. Packing zeroes unspecified high bits; unpacking
ignores them. Masking a full-width overread is NOT safe. Declared layout padding is
inside the object; extra ABI extent rounding is not readable source storage.

Prologue unpacking uses R10 scratch and RBP-relative stores, never destroying an
incoming GP/SSE argument before it is homed. Retain existing preserved-original,
hiddenRDI and scalar-env homing order. Materialize object pointers only after stores.

Calls finish ALL stack record copies before ANY scalar/tuple GP marshalling. Tuple
packing uses stable sourceR11 and scratchR10, not an assigned GP argument register.
Set hiddenRDI only for MEMORY results. Immediately capture both INTEGER return lanes
into the fixed result pad before loading its address into RAX: do not lose RDX while
unpacking lane0. Then home the pad's address as the long call result.

INTEGER returns preserve source address in R11, pack lane0 into RAX and lane1 into
RDX with R10 scratch. Packing lane1 must not clobber completed RAX. Restore preserved
originals/leave/ret without changing results. MEMORY return copying and original
hidden-destination RAX remain a separate unchanged branch.

## Validation, refusals and independent evidence

Generic module/type/SSA/nominal validation precedes a complete allocation-free global
eligibility scan, itself before plan/home/frame/writer allocations. Compute integer
leaf shape over compact earlier-record runs with a bounded transient4096-entry table,
not recursive/exponential expansion or trusted caches. Owned plans copy final facts;
external/stale plans cannot authorize emission. No new globals/owner backpointers.
Every allocation failure must clean up partial multi-function plans and permit retry.

Independent C and hand-assembly must cover both interop directions, exact GP rollback,
MEMORY hidden shift, RAX/RDX order, short guarded sources, poisoned excess bits,
distinct by-value objects/pads, recursion/dynamic allocation, scalar mixtures and
frame boundaries. Distinct executable lost-RAX-on-second-pack and lost-RDX-on-first-
unpack defects are required, alongside lane swaps/rounded loads/partial-bank defects.
Do not assert unspecified C padding or derive production layout from host C.

Scalar-only whole-module bytes must stay identical; unaffected mixed-module
fragments need matched symbol IDs/order and function ordinals. Upgrade individual
now-eligible tiny native refusals only with stronger positive independent checks;
retain unsupported alignment/size, aggregate-vararg and interpreter refusals. Supported SSE and nonvariadic ENV/indirect record cases are now positive in their own C/ASM harnesses.
Native pointer/lifetime/partial-overlap contracts remain explicit, not proven from
long typing. Pre-write compiler refusal/OOM preserves CLI output; no claim of later
filesystem atomic replacement. Focused/full gates and independent reviews are still
required; no test is claimed by this reader design.

Sources: official psABI1.0 March12,2025 §3.2.3; pristine QBE
 e786f06032fefa2e3790d6b1c9e31ed138f475a6 amd64/sysv.c and doc/abi.txt.
The pinned QBE source explicitly warns about rounded register-aggregate out-of-bounds
accesses; it is secondary ABI evidence, NOT an oracle for short-span memory safety.

## Running the independent checks

`python3 tools/aggregate_abi_small_integer_check.py --check` verifies the
reviewed fixtures; without `--check` it actually links and executes PIE/non-PIE
C and handwritten assembly. Add `--mutation-controls` to require six executed
defects to fail (including the two distinct result-register lifetime defects).
All eight folding/home option combinations are supported. The C byte-array
layouts cover every size1..16 and a separately asserted nested align8 layout;
short sources terminate at read-only guard boundaries, excess incoming/result
bits are poisoned, and callee-saved registers are independently seeded.

The older MEMORY harness and immutable prior scalar/matched-fragment oracles
remain separate checks. Only individually newly eligible native negative cases
are upgraded; interpreter and unrelated native refusal assertions remain.
Compilation/validation/planning/emission failures, including final writer
allocation failure, precede driver output writes; later filesystem I/O failures
are not promised atomic replacement. Native pointers remain caller contracts,
not a runtime safety sandbox or arbitrary-pointer noalias proof.

New INTEGER-bearing prefix/suffix modules additionally establish exact symbol
strings/IDs and function ordinals against paired scalar-reference modules. Only
four unaffected scalar fragments are compared, using64 immutable hashes generated
by the published prior `2c5ce8f1f599effa1b1e62b0ac681c6e7ad75778` compiler, not
the current implementation. `--baseline-compiler` also checks actual prior bytes.
Whole scalar-module identity remains covered by the unchanged MEMORY harness.
