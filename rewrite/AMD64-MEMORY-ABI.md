# Bounded native MEMORY-record ABI

Linux AMD64 ELF/SysV LP64 supports direct-symbol calls and definitions with
MEMORY-record arguments/results mixed with existing scalars. Eligible records have
declared size17..4096 and effective alignment1/2/4/8/16, from the existing regular
b/h/w/l/s/d declaration DAG. These bounds are a project subset/resource policy, not
universal ABI rules. This closed universe has no SSEUP vectors; its >16-byte
records are MEMORY under official psABI1.0 (March12,2025) §§3.2.2–3.2.3. Pinned QBE
`e786f06032fefa2e3790d6b1c9e31ed138f475a6` `amd64/sysv.c`/`doc/abi.txt` is secondary
source evidence. Layouts never come from the compiler host's C layout.

Small integer-only size1..16 records are a separate implemented subset described in
[SMALL-INTEGER-ABI.md](SMALL-INTEGER-ABI.md), including stack fallback without GP consumption.
Small SSE/mixed register records are separately supported in
[SMALL-SSE-ABI.md](SMALL-SSE-ABI.md). Small align16/NO_CLASS records are supported in [ALIGN16-ABI.md](ALIGN16-ABI.md). Not supported: align32/64, vectors, opaque/union/unaligned types,
non-SysV targets or record-bearing variadic signatures/calls. Nonvariadic indirect/ENV record calls are now supported (AGGREGATE-CALL-TARGETS.md). Rules
are site-local: scalar env/variadic callers may call eligible record callees, and
record functions may make scalar env/vararg/indirect calls. Valid unused generic
types, including tiny, align64 or UINT64_MAX layouts, remain accepted metadata.
First-class aggregate arithmetic/copy/phi/data classes and ALL interpreter record
execution remain refused; long SSA carriers are addresses, not erased ABI tags.

## Fresh planning and scalar compatibility

Emission validates every owned layout/body/symbol/descriptor ID/known nominal
signature. A global target scan checks ALL functions/calls, including unused and
unreachable uses, before any plan-set/home/writer allocation or frame geometry.
Only UnsupportedAggregatePlan maps to UnsupportedAggregateAbi; malformed metadata,
OOM and resource errors propagate without broad error masking.

`abi_amd64_plan.ModulePlans` owns fresh plans only for record-relevant functions.
No external/stale plan is an input to the emitter, and no owner backpointer or
persistent cache is added to IR. Pure-scalar modules allocate no plan arrays and
use their unchanged scalar frame/marshalling path. Planned functions borrow their
fresh owned home layout/frame/call/pad facts during that same emission operation;
no second coloring or duplicate outgoing reservation is computed.

## Runtime ABI mechanics

A MEMORY-result function saves incoming hiddenRDI in a private fixed slot before
ordinary parameter homing/scratch. HiddenRDI shifts ordinary INTEGER registers to
RSI/RDX/RCX/R8/R9 but leaves SSE independent. A MEMORY argument is a pointer to its
writable incoming by-value stack copy: its SSA home stores RBP+16+byte_offset,
not its first8 bytes or the original caller's source pointer.

Outgoing copy regions use currentRSP+byte_offset. Copy each record's EXACT declared
bytes, including declared padding but excluding extra ABI spill padding, with
`rep movsb`. Finish ALL copies before scalar GP/SSE marshalling: copies clobber
RSI/RDI/RCX/flags, whereas durable homes are stack/RBX/R12..R15 and scalar loads use
RAX. Then set hiddenRDI to the fixed return pad and issue the direct call. Scalar
payload widths/subword signedness and unspecified excess bits retain old rules.

Each syntactic record-result call has one distinct aligned fixed pad per function
invocation. The call result is its long address. Same-site loop executions overwrite
that site's pad; distinct sites and recursive activations are separate. Object
pads never coalesce merely because pointer SSA homes can reuse a color. Pointers
to pads expire with their owning invocation; no heap/snapshot lifetime is promised.

A record return copies declared bytes from its long operand to the saved hidden
destination, then reloads the ORIGINAL destination intoRAX (not advancedRDI).
Existing preserved-original restoration and `leave;ret` remain. Nested calls cannot
lose the hidden pointer because it is not retained only in a caller-saved register.

All fixed homes/scratch/saved originals/optional176-byte scalar-vararg area/hidden
slot/pads plus MAXIMUM outgoing reservation fit the existing64KiB cap and probing.
Pads remain RBP-relative. Dynamic allocation still subtracts alignedA fromRSP and
returns newRSP+outgoing, keeping moving outgoing storage below every live object.
No libc copy/allocation helper, extra per-call stack reservation or new interpreter
memory model is introduced. ABI clearDF is required.

## Native pointer contracts, not a noalias proof

Sources must denote live readable declared-size spans; destinations need sufficient
writable size/alignment. Invalid native pointers can fault. Compiler-private
outgoing writes must not alias sources in a way that changes later argument values.
Normal incoming/pad/dynamic/source objects are above that region; arbitrary forged
addresses are not justified by long typing. Partial copy overlap is unsupported,
not silently upgraded to memmove. Identical full spans can be copied safely.

The ABI result buffer must not alias data visible to the callee through other names,
including scalar pointers/escaped same-site pad pointers. Fixed pad disjointness
alone does NOT prove that general condition. No host dereferencing/provenance check
is performed by the compiler. These are native caller/program lifetime/noalias
contracts, not synthetic-memory guarantees.

## Independent checks and output boundary

`tools/aggregate_abi_native_check.py` links/runs independent C and hand-assembly in
PIE/non-PIE, checks noTEXTREL, exact mixed80-byte GP/SSE stack offsets in both
directions, hiddenRDI/originalRAX, preserved registers, by-value mutation isolation,
distinct-site/same-site/recursive pads, dynamic allocation and scalar env/varargs.
C layouts are checked against explicit sizeof/alignof/offsetof expectations, never
used to derive production layouts. Tests compare initialized fields/byte arrays,
not unspecified C padding. Guard pages cover17/23/24/31/32/4096 exact copies with
read-only sources and distinct noalias destination buffers; contents and faults
are checked. `--mutation-controls` links/runs rounded/omitted-copy and wrongRAX
assembly defects and requires real runtime failures.

Immutable scalar oracles come from prior45ec2c9:8 whole scalar fixtures x8 option
modes. For scalar functions in a mixed module, the prior compiler cannot compile
the whole module: paired scalar-reference fixtures assert exact symbol ID/order
and function ordinals, then compare ONLY unaffected fragments. Record-relevant
functions use independent C/assembly expectations, never scalar-erasure oracles.

All compiler allocation failures (including final writer extraction) clean up and
permit same-module retry. Parsing/validation/planning/emission refusal or OOM before
driverwrite preserves a preexisting CLI output. The existing later writeFile is NOT
an atomic replacement guarantee on filesystem/I/O failure.
