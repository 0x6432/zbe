# Typed scalar memory accesses

The independent frontend/IR/native Linux AMD64 slice supports scalar loads and stores through **long** address operands:

| Operation | Result / source class | Bytes | Meaning |
| --- | --- | --- | --- |
| `loadsb`, `loadub` | word or long | 1 | Signed / unsigned extension |
| `loadsh`, `loaduh` | word or long | 2 | Signed / unsigned extension |
| `loadsw`, `loaduw` | word or long | 4 | Signed / unsigned extension |
| `loadw` | word or long | 4 | Exact alias of `loadsw`, as in the reference parser |
| `loadl` | long | 8 | Raw bits |
| `loads`, `loadd` | single / double | 4 / 8 | Raw floating bits, including NaN payloads |
| `storeb`, `storeh`, `storew` | word | 1 / 2 / 4 | Store only the low selected bits |
| `storel` | long | 8 | Store raw bits |
| `stores`, `stored` | single / double | 4 / 8 | Store raw floating bits |

Loads use `%result =type opcode address`. Stores use `opcode value, address`; they have **no** result, dummy definition or value home. Integer literals in address contexts are long. Word/floating address temporaries, mismatched classes and extra/missing operands are rejected. Existing strict scalar typing remains: implicit long-to-word temporary conversion is not added. `loadw` to long therefore sign-extends; its intended word spelling does not silently change that reference alias.

## Ownership and analysis

`ir.LoadKind` and `StoreKind` describe access semantics rather than machine opcode numbers. `Function.defineLoad` validates the pending typed result and address before reserving instruction capacity and publishing its backlink. `appendStore` validates source/address and appends one effect. Failed allocation publishes neither instruction nor result definition. There is no additional borrowed buffer or per-instruction allocation to own.

Structural validation checks classes and both directions of definition links. SSA validation checks load addresses and both store operands for ordering/dominance. Liveness and interference retain all those uses, and stores add/kill no definition. Independent use-search/program-point oracles include a memory loop fixture. Integer folding leaves all loads unknown and preserves every store and load in source/control-flow order, **including unused loads that can fault**. No memory common-subexpression elimination, alias analysis, forwarding, hoisting or dead-store elimination is introduced.

## Native lowering and limits

The emitter captures each full address in R10 before loading a store source through RAX. Persistent homes never use these scratch registers. Narrow loads read exactly their declared width and apply the selected extension; unsigned long results use EAX writes to clear the high bits. Stores use AL/AX/EAX/RAX at the declared width. Floating accesses transfer integer raw bits without arithmetic or NaN normalization. Linux AMD64 permits the unaligned scalar accesses covered here.

Addresses must designate valid readable/writable native storage of the required extent and lifetime. Generated programs are **not sandboxed** and receive no bounds, null, alignment or permission checking. Caller-supplied addresses may fault or corrupt storage when invalid. No atomics, volatile-memory language extension, concurrency memory model, memory-mapped-device contract, globals/data declarations, address relocations or aggregate ABI are implemented. Native stack allocation is described separately in NATIVE-ALLOCATIONS.md. Native loads/stores are ordinary machine accesses, not a promise of portable host-pointer representation or target parity.

Without an explicitly supplied image or opt-in stack model, both evaluators return **`UnsupportedMemory`** for a reached load/store after consuming its instruction step. An opt-in owned `memory.Image` now provides bounded synthetic addresses and explicit byte order for safe interpretation (see MEMORY-EVALUATION.md). Opt-in interpreter stack objects extend the synthetic model with initialization/lifetime checks (INTERPRETER-ALLOCATIONS.md). No interpreter mode dereferences supplied numeric host addresses or falls back to native execution. Step exhaustion before the access wins; memory-free paths remain evaluable. Native address contracts above remain unchanged.

Constant-length byte copies are separately implemented as effect-only `blit` (BLITS.md); they do not change scalar load/store width or permission contracts.

## Bounded native verification

`python3 tools/native_memory_check.py` accepts the same three optional flags as the other harnesses. Per option combination it checks **55,198** scalar-memory outcomes:

- 17 load opcode/result combinations and six store forms, each with 266 bit patterns at eight offsets and an exact-width page-boundary access (55,062 checks). Python byte decoding supplies independent signed/unsigned load expectations; complete sentinel buffers check store width and truncation.
- Raw single/double bits, quiet NaN payloads and negative zero are moved without arithmetic.
- Loop store/load order, observation across a C mutation call, both store operands using the same pointer, pointer/value pressure exceeding preserved registers and incoming GP registers, full preserved-register checks, literal stores, and a non-taken invalid-memory path (136 checks).
- A PIE mapping with nonzero high address bits is required explicitly rather than silently missing address-truncation coverage. C pointer conversions and byte order are an explicit Linux AMD64 test convention.

Two separate PROT_NONE child-process cases require SIGSEGV for an **unused** load and an effect-only store. Exact-width accesses ending immediately before that protected page must succeed. Eight malformed-class/address checks preserve either absent or existing CLI output. Process core dumps are disabled and child execution has finite timeouts. This is a bounded regression corpus, not exhaustive memory correctness, a sanitizer, a complete QBE implementation or exhaustive interpreter memory semantics.
