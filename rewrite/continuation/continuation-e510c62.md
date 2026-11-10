# Continuation from e510c62 — draft, gate held

Base `e510c62f3b972b02263edb30934d873e3bed64e3` is a draft, not an accepted baseline. The integration gate remains **HELD**. The original checkpoint and e510c62 each passed three hosted rewrite CI jobs: [checkpoint run](https://github.com/0x6432/zbe/actions/runs/42689426866), [e510c62 run](https://github.com/0x6432/zbe/actions/runs/42689439989). These are not the integration gate, the standard/nightly workflows, or CI for a later tip.

## Focused allocation coverage

On e510c62 plus the changes to `extern_frontier_test.zig`, `zig test src/extern_frontier_test.zig` passed 164/164 tests separately in Debug, ReleaseSafe and ReleaseFast, with the pinned Zig version, shared verification lock, two CPUs and 4 GiB virtual-memory cap. The final-owned-slice test observes a refused shrink-remap and fails the subsequent output-sized allocation (zero-based ordinal 11 of 12), verifies writer-buffer cleanup and accounting, then retries on the same module. The in-place allocator test observes prior growth and successful final shrink (671 to 502 bytes) and sweeps nine allocation ordinals with cleanup and same-module retry. These are focused local results, not full O01–O10 or independent ABI validation. A separate independent reviewer did not complete a review of these changes.

## Expanded byte parity

See `u16-parity-expanded-20261110.md`: 488/488 whole-output comparisons across 61 fixtures and eight flag masks against a clean **source-built** predecessor, plus bounded negative controls. This is not the required published opaque predecessor or full U16/R02 acceptance. The exact result archive SHA-256 is `b8a4674caff31a02ec9a19ab580ef4ea02f9912b9d1a7bd0480d0f4bb7488ee8`; the archive remained outside the repository at `/data/zbe-u16-parity-20261110-L0XE4V/u16-parity-evidence-20261110.zip`. A separate independent reviewer did not complete a review of the harness.

## Diagnostic and mutation findings

On e510c62 the source `common extern data $x = { z 8 }` is rejected as `unsupported_construct` at column 1 (`common`), while proposed D08 calls for the `extern` token at column 8 in a declaration/linkage context. `export extern function ...` is rejected at `extern`. No parser change is included: preserving earlier ordinary malformed-input precedence and specifying overlapping invalid modifiers requires care, and the design is not ratified. The separate P1/P3 validation-order policy conflict in `continuation-dea7f2c.md` remains unresolved.

`m01-exploration-20261110.py` is an exploratory runner, not gate coverage. On GNU ld.bfd 2.41, an ordinary-LEA **function** address mutant in a non-PIE executable linked; an independent PIC oracle selected the override, the GOT control exited 0 and the mutant exited 31 on pointer inequality. The shared-object function/data mutants and PIE function mutant instead failed to link. Provider-only and independent preload-only runtime controls were not completed. This is not the isolated candidate DSO, data mutation, or complete K07/M01 calibration. Original command/output record SHA-256 `a009468e37e2b4b7d5132c030068fdb811e551796e89a48e267d6cb8dc08217c`, runner SHA-256 `e2d0ea1c59e6e21e42847da2925a4af1891513cd24df0bde16b3a1fe3bc5742e`; original record is outside the repository at `/data/m01-exploration-20261110/record.json`. Independent review did not complete.

## Evidence isolation and disposition

`valgrind-io-uring-bounded-review-20261110.md` records a conditional source-level route that a future isolation design must address; it is not an exploit demonstration or complete mediation proof. Valgrind evidence authorship and protected handoff remain unresolved. Do not run or claim the full gate, advance canonical branches, or claim independent terminal audit or acceptance until the prerequisites, gate and independent audit actually pass.
