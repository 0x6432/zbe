# Bounded native fixed-frame probing

The Linux AMD64 emitter reserves its already-validated fixed frame in steps of at most **4,096 bytes**, touching the byte at the new RSP after **each** step, including a final nonzero remainder. Zero-frame functions reserve and touch nothing. Final RSP and 16-byte alignment, RBP-relative homes/phi scratch/saved originals, incoming argument offsets and outgoing argument slots are unchanged. The existing **64 KiB fixed-frame limit** remains enforced before emission.

The probe is `testb $0, (%rsp)`: it performs a memory read without changing argument registers, SSE state, preserved originals or frame bytes. The changed flags are dead in the prologue. Each touch occurs inside the newly reserved extent before another descent; no helper call, mutable global, runtime buffer or new interpreter memory effect is introduced. This prevents this fixed reservation from jumping over a 4 KiB-or-larger inaccessible guard page.

This is **not** complete stack-clash hardening, dynamic `alloc4`/`alloc8`/`alloc16` support, arbitrary stack-limit validation, an interpreter/native stack model equivalence or an all-platform guarantee. Host mapping/guard policy remains external. Touching an exhausted frame can fault earlier than a later home write; exhausted-stack behavior is not assigned a portable defined-program result. The core still does not probe or authorize arbitrary IL load/store addresses.

## Direct boundaries and allocation errors

Two additional unit tests check reservation/touch order, positive aligned step sizes, exact total extent and touch count for **0, 16, 4,080, 4,096, 4,112, 8,192 and 65,536 bytes**, plus exhaustive allocating-writer failure cleanup at the maximum frame. Frame construction owns bound/alignment checks; the private emission helper asserts its internal preconditions. No partially emitted assembly escapes library failure.

## Protected-stack native regressions

`tools/native_frame_check.py` requires Linux x86_64 with 4 KiB pages, bounded subprocesses and disabled core dumps. It creates two immediate-return functions whose unreachable blocks contain simultaneously live unknown call results, preserving large frames even with integer folding and home reuse. The unknown external function aborts if accidentally reached. Their entry returns perform no ordinary home writes, so a fault is not accidentally explained by executed dead code.

A standalone assembly adapter calls the function on a controlled stack with a one-page accessible top, one inaccessible intervening guard page and accessible lower memory. A 128-byte aligned top margin keeps the unprobed saved-original area wholly below the guard even at an exact page boundary. The adapter uses/restores full R12 and the old stack explicitly; it is a test boundary, not production IL address reinterpretation. Real probes must stop at the guard with **SIGSEGV** for both frame sizes. A test-only mutation removes just probe touches while retaining reservations, home layout and restoration; both protected-stack calls must then return successfully. These **negative controls** establish that the guard checks distinguish probing from unrelated later memory accesses. Full preserved-register restoration and ordinary results are checked separately.

The eighth native harness adds **six result/preserved checks**, **two guard-page SIGSEGV checks** and **two unprobed negative controls** per option combination. It also verifies that large prologues have bounded aligned steps, matching touch counts and a sufficiently large total reservation. All eight harnesses run in all eight options and Debug/ReleaseSafe/ReleaseFast. Twelve independent generators remain unchanged. Actual results are recorded in HANDOFF.md after completion, not inferred from this design.
