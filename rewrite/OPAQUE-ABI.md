# Bounded opaque declarations and native MEMORY transport

`type :O = align A { N }` owns a named opaque/dark declaration. Alignment is
mandatory, power-of-two1..64; N is a positive checked decimal1..UINT64_MAX.
Exactly one size token and the closing brace are required: no comma or members.
Zero-size opaque declarations are not supported. `Record.createOpaque` and
`Module.addOpaque` expose the corresponding owned builder API.

## Exact metadata, not a C layout guess

Opaque `size` is EXACTLY N, never rounded to A. `align16{1}` has size1/alignment16;
`align8{13}` has size13/alignment8; `align16{17}` has size17/alignment16.
The authoritative optional `opaque_bytes` payload must agree with derived size;
explicit/effective alignment must agree, and owned runs/variants must be empty.
Regular/union declarations require a null opaque payload. Every unused declaration
and all enclosing cached layouts are revalidated before module-aware emission or
evaluation. Destruction frees actual owned arrays independently of mutable kind.
Public edits must retain valid allocations/slices; arbitrary dangling pointers are
not a supported validation input.

Earlier opaque declarations may appear in ordinary field runs and union arms.
Raw child stride is N, not roundUp(N,A). For O=align8{13}, R={:O2,b} has stride13,
second field offset26, size32/alignment8. This is not a C array of aligned13 objects.
Compact MAX=align64{UINT64_MAX} metadata is valid; enclosing multiplication,
cursor addition, member alignment and final rounding overflow remain errors.

The module cap remains4096 declarations; opaques consume ZERO field runs. Existing
4096 runs/type and65536 runs/module limits still count actual regular/union runs.
No byte expansion, global registry, owner backpointer or persistent containment
cache is introduced. Names are copied into `record_names`, never the codegen
symbol pool; Record pointers survive table growth. Failed publication consumes no
ID/run budget; unused interned names/capacity may remain. No name-pool rollback is
claimed. Missing alignment diagnoses `invalid_alignment` at the integer token;
zero/negative/overflow size diagnoses `invalid_opaque_size` at that size token.
Builder zero size is `InvalidOpaqueSize`; contradictory public metadata is
`InvalidRecordLayout`. Regular/union diagnostic and generic descriptor ordering
remain unchanged.

## Native eligibility and geometry

Linux AMD64 native use supports declared bytes1..4096 and alignment<=16.
A DIRECT opaque descriptor ALWAYS uses MEMORY, even size1..16: no GP/SSE value
register, stack by-value argument copy, hidden RDI result pointer and ORIGINAL
result pointer returned in RAX. This is QBE's explicit opaque contract, NOT a
claim that every small C byte array has SysV MEMORY classification.

Regular/union containers >16 bytes may contain opaque children and take MEMORY.
Containers <=16 bytes that transitively contain opaque children are refused as
`UnsupportedAggregateAbi`: hidden structure cannot safely supply register masks
or be treated as NO_CLASS padding. Their metadata remains legal. Fresh bounded,
allocation-free earlier-ID provenance analysis precedes every plan/home/frame/
writer allocation. Generic validation may allocate first and validates all slots
before eligibility, including external/indirect/tail/unreachable descriptors.
Only UnsupportedAggregatePlan maps to UnsupportedAggregateAbi.

For an opaque stack argument: copy exactly N bytes, align start to max(8,A),
occupy roundUp(N,max(8,A)), then advance the RAW end. Only final outgoing reserve
rounds raw end to16. Thus O1/align16 occupies16 but copies1; O13/align8 occupies16
but copies13; O17/align16 occupies32 but copies17. Incoming checked displacement
includes `16+offset+(N-1)`. Existing scalar/known-layout paths are unchanged.

Existing fresh plans, fixed disjoint result pads, stack parameter addresses,
late indirect target loading, ENV-in-RAX, AL-last and original hidden-result
return dataflow implement the endpoint. There is no register parameter object for
an opaque stack parameter: the caller's by-value stack copy is its private object.
Known/direct/indirect, nonvariadic ENV, variadic calls and definitions, and
vastart use the same endpoint. Record-bearing variadic signatures use plan GP/SSE
counters and raw named end, never the scalar carrier cursor. Scalar signatures
merely containing opaque calls retain the historical scalar vastart path.
ENV+varargs, aggregate vaarg, first-class aggregate values and aggregate interpreter
execution remain refusals. Fixed pad geometry is not a proof about arbitrary
pointer aliasing: callers must provide valid disjoint spans where required.

## Executable evidence and authority boundaries

`tools/aggregate_abi_opaque_check.py --check` checks fixture hashes and actual
published union baseline oracles. Without --check it runs independent ASM entry/
return bridges for bytes1/3/8/9/13/16/17/32/4096, align1/8/16, both directions,
known/indirect/ENV/variadic, dynamic allocation, loop/phi/live-target/environment,
recursive calls, private-copy mutation, hidden RDI/original RAX, AL and GP/SSE
pressure. Readonly page-end sources and distinct exact-end results catch overcopy
where alignment permits; non-multiple high-alignment sizes use aligned canaries.
No C representation is invented for size1/align16 or size13/align8.

Real matching C cases are packed byte+uint16 (3/1), packed byte+double (9/1),
packed+aligned8 byte+uint32-at1 (8/8), ordinary byte17, and matching large32
containers. Compile-time sizeof/alignment/offset assertions establish those layouts;
memcpy/unsigned-byte checks avoid unaligned typed access. C8 results compare only
occupied bytes0..4, not its3 C padding bytes; independent opaque ASM tests still
check all8 declared bytes. Genuine matching C types use real va_arg on the SAME
live list, followed by IL scalar continuation. Unmatched pressure A/B use explicit
QBE descriptor consumers, not claimed C va_arg equivalence or escaping list pointers.

The harness checks12 whole OLD modules and opaque-prefix/suffix invariance against
assembly hashes emitted by the actual public union compiler at commit
`c09b74646b04e0ade3d84aebdcdda59fef56819e`, tree
`2b68fd71e05b74d116e8a65bb02d7c6e4d345222`, in all8 options. It does not
claim whole-module parity for used opaque modules. Unit tests independently check
symbol strings/order, IDs and function ordinals. --mutation-controls executes
real compiling runtime assembly defects, not inert padding changes. Additional
isolated production-source defect-control results belong in author evidence.

`tools/aggregate_abi_opaque_upstream_check.py` builds the immutable hash-pinned
QBE e786f06032fefa2e3790d6b1c9e31ed138f475a6 archive in a temporary directory,
executes the positive native fixture with the independent ASM/real-C driver, then
observes exact opaque/nested declared sizes in a separate temporary print-only
parser change. Small-containing metadata is observed but NEVER used as a native
oracle. This is secondary evidence, not unchecked-upstream-arithmetic validation
or blanket QBE register/padding ABI parity. Primary opaque forcing is QBE
amd64/sysv.c typclass/selcall/selret; ordinary SysV MEMORY rules are grounded in
psABI revision e1ce098331da5dbd66e1ffc74162380bcc213236.

Run compiler/native tests under the shared verification flock, compile -j1 where
supported. Feature-specific focused results are recorded separately; no full gate,
review approval, exact-commit CI or publication success is inferred here.
