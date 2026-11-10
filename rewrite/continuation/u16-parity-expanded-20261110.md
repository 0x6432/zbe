# Expanded predecessor byte parity — 2026-11-10, draft evidence

This is a bounded local comparison, not U16/R02 completion or acceptance. The required published opaque predecessor is not established here. The shared full integration gate remains **HELD**; this investigation ran no gate, hosted CI, runtime/linking tests, canonical-ref change or push.

## Provenance and selection

- Clean, detached tracked trees: source predecessor `3890562118b85be550dcc19f6c400414d3f8672a` (tree `b0eb8454e6cdddd54ef91d9f24c5f064f77e865f`), draft `e510c62f3b972b02263edb30934d873e3bed64e3` (tree `b129ffde08a25dfea29fbc06d267e2b87d88928d`). This predecessor is an unaccepted integration draft, not the required published opaque oracle.
- Pinned Zig `0.18.0-dev.35+5e754304d`; executable SHA-256 `de9f60e4f053be72ffd473f46596af07dea55ce8799eaf7485a4fed339624a4f`. Both Linux AMD64 compilers were built separately with `zig build-exe src/driver.zig -O ReleaseSafe`, separate local/global caches and output paths. Predecessor compiler SHA-256 `ae977258d1f717c179c6e19a31f13b24c5b537c6144ba186cdf67ad83ccb92f2`; draft SHA-256 `47ed983ec5ca9aa06793fc8893f579285e55816a9542aea0904e11e820723141`. Build log hash `e479d49ae096b0bd53f52a668116834e2edbb4d69d326caa6fd8aacc43b1611a`.
- Manifest `u16-expanded-manifest-20261110.json`, SHA-256 `18879c421d2472c6a1af7ff00b621727f7cc3c1a6764296c4d59bdd9942c7276`, pins all 61 selected top-level `.ssa` files by SHA-256; the harness verifies both working copies against their exact commits before and after the run. These comprise the previous 21 plus 40 additional unchanged files. No `extern` token was found in the fixture corpus. The other two of 63 top-level fixtures were pre-excluded: `entry-backedge.ssa` is a registered `EntryHasPredecessors` rejection, not a successful output fixture; `aggregate_abi_representation_metadata.ssa` has enormous metadata-only layouts and was not selected for bounded emission. Generated/combined inputs from historical test harnesses and fixtures outside this directory were not enumerated.
- All builds and compiler invocations used `/data/zbe-coordination/full-verification.lock`, affinity CPUs 0 and 1, 4 GiB address-space limit and no core dumps. Runs used an isolated temporary directory and a minimal environment. Build started 09:27:27 UTC and finished 09:28:42 UTC; result file written 09:30:47 UTC. The lock also serialized the controls.

## Results

All **488/488** whole-output comparisons passed (61 fixtures × eight flag masks). Masks use bit 0 `--fold-integers`, bit 1 `--reuse-stack-homes`, bit 2 `--callee-saved-homes`. An independent reread of every output checked exact equality, non-empty bytes, lengths and recorded SHA-256. The compiler emitted **8,513,940 bytes per side** in total (17,027,880 across both); these count repeated outputs across masks, not unique bytes. Per-mask counts per compiler:

| Mask | Bytes |
| --- | ---: |
| 0 | 1,035,374 |
| 1 | 1,035,289 |
| 2 | 1,031,129 |
| 3 | 1,031,042 |
| 4 | 1,095,333 |
| 5 | 1,095,220 |
| 6 | 1,095,333 |
| 7 | 1,095,220 |

Individual outputs ranged from 44 bytes (`record_declaration_layouts.ssa`, mask 0, type-only and therefore a weak emission witness) to 143,407 bytes (`aggregate_abi_opaque.ssa`, mask 7). Individual paths, flag sets, exits, byte lengths and hashes are in `expanded-run/results.json`, SHA-256 `3e76cfcbfc2c0f0502063edcf2c29396ae7c3bf91c8cc9982e87bdf8374de699`.

## Negative controls

For `direct-calls.ssa`, each of the eight masks was rerun with the real draft compiler wrapped to append 31 bytes to its successful output. The checker rejected **8/8** altered results, returned 1, and confirmed successful baseline and draft subprocesses; default output was 1,843 vs 1,874 bytes. An exit-37 wrapper produced no output and was rejected **8/8**, with the harness returning 1. Result JSON SHA-256: byte control `6b3aa47fc4f377724f4f5f7a11c29159422626c203a78c8c32f23f5b5d43c9b8`; exit control `513b27b4747c54086a9c62d9c0e417cb4f68da3c73ffa0b208086ebfc922073c`. These controls establish detection of these two injected defects, not all possible harness failures.

## Reproduction and limitations

Scratch evidence, binary outputs, logs, wrappers and individual assembly outputs were preserved under `/data/zbe-u16-parity-20261110-L0XE4V`. With those trees and binaries available, run the following; the harness acquires the lock and applies the resource bounds itself:

```sh
B=/data/zbe-u16-parity-20261110-L0XE4V
python3 "$B/draft/rewrite/tools/extern_parity_expanded_20261110.py" \
  --baseline-tree "$B/predecessor" --draft-tree "$B/draft" \
  --baseline "$B/bin/old-zbe-native" --draft "$B/bin/new-zbe-native" \
  --output-dir "$B/independent-rerun"
```

The harness is pinned to the exact `e510c62` trees and must be run against clean checkouts of those commits, not against a later continuation tip. All compiles succeeded; byte equality does not establish correctness of either compiler, semantic/ABI/loader behavior, historical generated modules, other toolchains or compiler modes, or published-predecessor identity. This adds focused local evidence only; Exact-commit hosted rewrite CI for `e510c62` passed three matrix jobs at https://github.com/0x6432/zbe/actions/runs/42689439989, but it did not include this later harness or establish parity or gate acceptance. Full U16/R02 registration, exact-commit CI for any later tip, Valgrind evidence-authorship, the held gate and independent terminal audit remain open.
