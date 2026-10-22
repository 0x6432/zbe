# Bounded align16 regular-record ABI and NO_CLASS padding

Linux AMD64 ELF SysV LP64 direct record definitions, calls and results accept
nonempty regular b/h/w/l/s/d records of declared size1..16 and effective
alignment<=16. Existing17..4096-byte, alignment<=16 MEMORY records remain
unchanged. Generic owned declarations are broader than target eligibility.
This does not add vectors/SSEUP/x87, union/opaque/unaligned aggregates, C++
invisible references, other targets, first-class aggregate arithmetic/copy/phi,
record-bearing variadic sites or aggregate interpreter execution. Nonvariadic ENV/indirect record calls are now supported (AGGREGATE-CALL-TARGETS.md).
Alignment32/64 and used records above4096 remain explicit target refusals;
unused valid declarations remain metadata, including UINT64_MAX layouts.

## Chosen ABI policy, not a pinned-QBE parity claim

This subset follows official AMD64 psABI1.0 (March12,2025), section3.2.3, with
independent C11 aligned layouts and hand-written assembly as primary oracles.
It deliberately does not reproduce the pinned QBE e786f06032fefa2e3790d6b1c9e31ed138f475a6
padding-class limitation. Its parsefields rounds align16{s} to16; sysv.c leaves
the padding-only eightbyte Kx, but retr uses KBASE(class) as a return-bank index
and argsclass counts non-INTEGER as SSE without an explicit NO_CLASS skip.
all.h defines Kx=-1 and KBASE(k)=((k)>>1). These are source observations, not
an executed upstream crash or measured result. No pinned-QBE ABI oracle parity
is claimed for padding-only lanes. Existing well-defined subsets stay intact.

## Layout, physical lanes and active registers are different facts

The validated owned record DAG retains nominal IDs, exact field/run offsets,
positive compact repetitions, padded nested strides and declared alignment/size.
The transient classifier shifts INTEGER/SSE occupied-byte masks by actual child
offsets; padding contributes no class and INTEGER dominates within an eightbyte.
Effective16 alignment rounds every small such object to size16. A nonempty
regular layout begins at a real field: only its trailing second eightbyte can
be wholly NO_CLASS. No leading/all-NO_CLASS or empty aggregate is introduced.

New align16 arguments/results use existing explicit-offset register_record
variants, including all-INTEGER align16 records. Old align<=8 all-INTEGER
variants keep their public shape and emitted bytes. Physical offsets0 and8 are
scanned separately from active lane count; NO_CLASS is omitted from the tuple.
It consumes no GP/SSE register, source read, destination write or register-bank
increment. It does NOT reduce the declared16-byte private object, result pad,
stack spill extent or required16 alignment.

Returns use independent compressed banks: I/N -> RAX only; S/N -> XMM0 only;
II -> RAX/RDX; SS -> XMM0/XMM1; IS -> RAX/XMM0; SI -> XMM0/RAX. NO_CLASS does
not create a fake RDX/XMM1 result. Arguments count both banks transactionally;
if any active lane cannot fit, the complete argument spills and neither bank
advances. Following scalars may still use available registers.

Active lane spans remain within the declared object: min(8,size-offset).
For size16 active spans are8, including unspecified padding within that active
eightbyte. SSE transport is raw movq, not conversion or arithmetic. A wholly
padding-only lane is not transported. ABI padding is not promised zero,
initialized, bit-preserved or stable across a call. Tests compare initialized
field bits, not padding, and do not count padding-only mutations as failures.

## End-to-end frame, calls and ownership

No new emitter backend or ownership system is introduced. Fresh ModulePlans
validate generic metadata and globally preflight all target sites before plan,
home, frame or writer allocation. Source/name ownership remains module-local;
external detached snapshots never authorize emission or edited IR. All unused
records and descriptor slots still validate before target refusal.

Owned incoming objects and per-site result pads reserve full16 bytes at16
alignment. Existing exact-lane emitter helpers unpack active incoming registers
before LEA/homing, preserve other live GP/XMM lanes, and capture results before
RAX is reused for a pad address. Loop sites reuse their own pad; distinct sites
and recursive frames own separate objects. MEMORY hidden RDI/RAX is unchanged.
Stack fallback copies the full declared16 bytes before register marshalling.

RBP/current RSP remain16-aligned, including dynamic allocations. A spill uses
alignUp(cursor,16), extent16; displacement checks use inclusive last byte
16+offset+size-1 before i32 casts. Checked u64 arithmetic, the65536-byte fixed
frame cap and default refusals remain. No larger-alignment stack realignment
is added. Six GP args plus long spill0, aligned record16, following long32
require outgoing48. A32-byte prefix, one16-byte object, two16-byte pads and
outgoing48 require frame128. These are literal independent geometry examples.

## Independent conformance and compatibility

The new harness uses13 explicit C layouts with _Alignas(16), literal
sizeof/alignof/offsetof assertions, both-direction calls/results, all active
class combinations, nested children, raw signed-zero/infinity/NaN/subnormal bits,
MXCSR/callee-saved checks, distinct byvalue objects, recursion, same-site loops,
distinct pads, dynamic allocations and hidden MEMORY32 results. Hand-written
pressure callees verify5/6GP,7/8SSE, padding-lane bank non-consumption, both-bank
rollback, following real arguments and literal stack offsets/alignment.

Guard sources expose a FULL16-readable-byte object before a protected page;
no invalid8-readable-byte contract is invented for a size16 record. A separate
initialized II return probe proves both contents and no fault; its deliberate
second-lane overread must fault. Other runtime controls perturb real argument
banks, stack offsets/alignment, initialized fallback bytes and mixed result
lifetimes—not only unspecified padding.

Fresh exact whole prior8b1a scalar-only modules and INTEGER/SSE/MEMORY fixture
outputs are retained for every option. New aggregate-bearing modules cannot
be whole-module compared with the old rejecting compiler: paired references
prove exact symbol strings/IDs and function ordinals, then compare only the
unaffected scalar fragments. Exhaustive allocation failures/retries, maximum
4096-record DAG with unused UINT64_MAX metadata, detached facts, tampered unused
layout rejection and a literal65536 frame cap exercise the ownership boundary.
No full-C/QBE/target parity or interpreter execution is implied.

Opaque declarations and their separate forced-MEMORY native rules (including
short opaques and large containing records) are now supported as specified in
[OPAQUE-ABI.md](OPAQUE-ABI.md). This does not infer register layouts for small
opaque-containing records; those uses remain explicit native refusals.
