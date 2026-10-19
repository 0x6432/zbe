# Bounded native SSE / mixed INTEGER–SSE record ABI

Linux AMD64 ELF SysV LP64 direct-symbol definitions/calls now accept regular
nonempty records of declared size1..16, effective alignment1/2/4/8, recursively
b/h/w/l/s/d. This extends [SMALL-INTEGER-ABI.md](SMALL-INTEGER-ABI.md), preserving
its all-INTEGER plan variants and emitted instructions. Existing17..4096
[MEMORY records](AMD64-MEMORY-ABI.md) remain separate and unchanged. Generic
owned declarations are broader than target eligibility; valid unused types do
not become target errors. Layouts are never inferred from the compiler host's C.

No vectors/SSEUP/x87, small align16+, padding-only NO_CLASS lane, opaque/union/
unaligned type, other target, first-class aggregate arithmetic/copy/phi/data
class or interpreter aggregate execution is added. Record-bearing env/variadic/
indirect signatures or call sites remain explicitly refused. Restrictions are
site-local: scalar env/variadic callers can contain ordinary direct record calls,
and record-signature functions can retain scalar env/vararg/indirect calls.
Long SSA carriers remain addresses; nominal ABI descriptors are not erased.

## Offset-sensitive class merging

The owned regular layout determines actual field byte positions. In each
occupied eightbyte, any b/h/w/l leaf makes the class INTEGER; otherwise s/d makes
SSE; padding contributes no class. Two packed floats in one eightbyte use ONE
XMM register. This is not scalar argument classification repeated per field.

A transient earlier-declaration table has two u16 occupied-byte masks per record,
not just cached merged child classes. For a nested child beginning at offset4,
its bytes can cross into different parent lanes:

- Q={w,s}; Parent={s,:Q}: size12/align4, INTEGER/SSE.
- Q={s,w}; Parent={s,:Q}: size12/align4, SSE/INTEGER.

Both Q records alone merge to INTEGER; shifting only that merged class would
misclassify their parents. The mask table uses bounded compact runs/positive
repeats, with no recursion or record-byte-sized allocation; huge unused generic
layouts are not expanded. Generic IDs/layouts validate before indexing/shifting.
No table/module/record pointer is retained by a completed owned plan.

SSE lanes in this closed aligned subset have declared width4 or8. Eligibility
checks that invariant and rejects any empty lane; it does not guess a class for
padding or round a readable source up to a register width. Fully INTEGER records
retain their existing `integer_record` public plan facts. New `register_record`
argument/result variants contain tagged GP/XMM lane assignments, nominal record
IDs, declared size/alignment, byte offsets and exact spans.

## Atomic allocation across BOTH banks

Count all GP and SSE lanes of an argument before assigning any of them. The
whole argument uses registers only if BOTH banks have sufficient capacity:
RDI/RSI/RDX/RCX/R8/R9 and XMM0..7. Otherwise the entire argument uses its checked
stack-copy region and consumes NEITHER bank. A later argument may still use
registers in either bank. Scalar banks remain independent and keep their old
payload/subword rules. MEMORY results reserve hiddenRDI, reducing ordinary GP
capacity by1, without changing SSE capacity.

Record return classification is independent of whether an argument spilled:

| classes in memory order | offset0 return | offset8 return |
|---|---|---|
| INTEGER/INTEGER | RAX | RDX |
| SSE/SSE | XMM0 | XMM1 |
| INTEGER/SSE | RAX | XMM0 |
| SSE/INTEGER | XMM0 | RAX, not RDX |

Register results have no hidden pointer. MEMORY results still copy exact bytes
to their saved hidden destination and return that ORIGINAL address in RAX.

## Exact raw bits and lifetimes

No floating arithmetic, conversion, MXCSR-dependent operation or helper call is
used for record lane transport. A4-byte SSE lane uses raw `movd`; an8-byte lane
uses raw `movq`, including packed two-float payloads. No16-byte vector load/store
or rounded8-byte access to a4-byte tail is permitted. NaN payloads, signaling
bits, infinities and signed zeros are copied, not numerically interpreted.
Unspecified excess bits are ignored; unspecified C padding is not a value oracle.

Each register-passed record parameter has a distinct private fixed object,
independent of SSA pointer-home coloring. Incoming lanes are stored before its
address is homed. GP unpack and SSE4 capture use R10 scratch only, preserving all
other incoming GP/XMM lanes. SSE8 can directly store raw64 bits to the object.
Existing saved-original/hidden-pointer/scalar-vararg/env homing order remains.
Stack-passed records point to their writable incoming by-value copy.

Calls complete ALL stack record copies before ANY record/scalar register
marshalling. Stable sourceR11 and scratchR10 preserve assigned GP lanes; raw SSE
moves target only their assigned XMM, never XMM0 as an incidental temporary.
Existing scalar loads use RAX and their own disjoint assigned argument registers.
Immediately after a call all result lanes are captured into the site's private
pad before LEA overwrites RAX. SSE capture must not lose a still-live GP result;
GP capture must not lose XMM0/XMM1. Returns similarly keep the source in R11 and
preserve every completed RAX/RDX/XMM0/XMM1 lane while packing the next.

Per-site pads are separate per activation, even when homes share colors.
Same-site loops overwrite that site's pad; recursion has distinct activation
storage; addresses expire with their owning activation. Fixed objects/pads,
homes/phi scratch/preserved originals/optional176-byte scalar-vararg area and
MAX outgoing retain the checked64KiB cap/probes. Fixed objects remain RBP-relative;
outgoing remains current-RSP-relative below live dynamic allocations.
Native pointer/lifetime/noalias contracts are unchanged; this is not a sandbox
or a proof about arbitrary scalar-pointer aliases.

## Validation, ownership and checks

Generic module/type/body/descriptor-ID/nominal-signature validation precedes an
allocation-free complete global target scan, before all plan-set/home/frame/
writer allocation. Ineligible uses still map narrowly to UnsupportedAggregateAbi;
invalid metadata, OOM and resource errors retain their own errors. Emission builds
fresh owned ModulePlans; external or stale snapshots never authorize it. Partial
plans, incoming objects and pads clean up on every failure and permit retry.
Standalone/interpreter module boundaries and reached-step/root refusal order are
unchanged. Compilation failures preserve outputs before driver writes; later
filesystem write failures are not promised atomic replacement.

`tools/aggregate_abi_small_sse_check.py --check` verifies fixtures and immutable
prior4dac source/assembly oracles. Without `--check` it actually links/runs C and
hand-assembly in PIE/non-PIE. `--mutation-controls` requires executed defects to
fail: rounded4/12-byte tails, arithmetic quieting sNaN, split packed floats,
first-XMM clobber, wrong S/I return bank, cross-bank result capture clobbers,
later-parameter prologue clobber and partial rollback of EITHER bank. The C/ASM
checks cover both directions, raw IEEE patterns, poisoned XMM excess bits,
MXCSR/nonvolatile preservation,32/16-byte stack oracles, hidden MEMORY results,
private objects, loop/recursion/dynamic pads and scalar env/vararg callers.
C sizeof/alignof/offsetof and initialized fields are independent expectations,
never inputs to production classification.

The harness also checks WHOLE prior INTEGER/MEMORY fixture assembly exactly,
plus matched unaffected scalar fragments in new SSE-bearing prefix/suffix
modules. Paired references prove exact symbol strings/IDs and function ordinals;
no impossible prior whole-SSE-module differential or self-generated compiler
oracle is claimed. `--baseline-compiler` compares actual prior4dac bytes too.
Old whole-scalar, INTEGER and MEMORY harnesses remain separate mandatory checks.
