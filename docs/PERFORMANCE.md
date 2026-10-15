# Portable ReleaseFast measurements — 2026-10-15

## Scope and method

One native x86-64 LP64 Linux sandbox, pinned Zig
`0.18.0-dev.35+5e754304d`, ReleaseFast with **-Dcpu=baseline** for both Zig
snapshots. The C reference patch and Python semantic oracle are unchanged.
All generated executables' successful exit status and stdout were validated
before timing. No failing command is a timing sample. `bench/divs.c` was first
corrected to use defined unsigned wrapping and the SAME corrected input was
compiled by every compiler snapshot. All six C fixtures pass native UBSan.

Raw CSVs/provenance, full-precision evidence and exact collection/analysis
scripts are in `benchmarks/2026-10-15/`. Scripts retain their sandbox paths for
provenance; reproducing on another machine requires changing those paths and
using fresh output names. Inputs are hashed, raw files are immutable, one CPU
is selected, groups are shuffled with a fixed seed, and warmups are untimed.
Subprocess startup and Python harness overhead are included. Independent
`csv`/`statistics.median` checks reproduce the pandas summary medians.
This is a small single-host experiment, not a general speed guarantee or a
claim of statistical significance. No rows or outliers were discarded.

## Audit baseline: no new generated-code speedup

The first experiment compares eeee52c with f728f27 (same functional compiler
as the published audit checkpoint). It has 329 rows: seven rounds of five
82-file compiler batches and six workloads across seven compiler settings.
The audit changes emit **byte-identical benchmark assembly** at both -O0 and
-O2; noisy runtime differences between those snapshots are not a new optimizer
gain. Existing -O2 benefits vary across workloads; notably the hash benchmark
was slower than the C reference. This prompted inspecting AMD64 addressing.

| workload | C reference | zbe -O0 | zbe -O2 |
|---|---:|---:|---:|
| collatz | 3971.4 ms | 3987.0 ms | 911.8 ms |
| divs | 1121.1 ms | 1123.6 ms | 266.8 ms |
| hash | 35.2 ms | 35.4 ms | 37.5 ms |
| matmul | 68.3 ms | 68.5 ms | 67.5 ms |
| sieve | 106.9 ms | 108.4 ms | 106.9 ms |
| sort | 299.6 ms | 300.0 ms | 278.8 ms |

## Bounded AMD64 address-scale follow-up

The final path recognizes long shifts 1..3 as address scales 2/4/8 only in
optimized instruction selection. It normalizes the matcher's view without
changing scalar IR; -O0 stays unchanged. Matches whose displacements exceed
signed 32-bit encoding limits fall back to the original register arithmetic.
Proof and regression coverage are in `OPTIMIZATION-ROADMAP.md`.

An adversarial displacement probe caught the first candidate producing
unassemblable code before publication. Its preliminary timing files remain
under `preliminary-address-scales*`; they are NOT the final-source results.
The measurements below are a fresh complete acquisition of the corrected
candidate, not selected or pooled samples. Both candidates emitted identical
assembly for all six benchmark workloads, but the corrected compiler was
rebuilt and its compilation costs measured again.

This experiment compares the prior portable f728f27 binary with the corrected
portable candidate, plus the unchanged C reference. The candidate's parent,
exact isel source and binary hashes are in provenance. There are 196 timing
rows: 28 compilation batches and 168 runtime observations. All workloads have
seven paired rounds; hash has 21 rounds, each observation averaging ten
sequential process executions. Other runtime observations use one execution.

| workload | C reference (ms) | Before -O2 (ms) | After -O2 (ms) | Paired change |
|---|---:|---:|---:|---:|
| collatz | 3963.07 | 903.85 | 920.02 | +1.1% |
| divs | 1114.21 | 260.90 | 264.88 | +1.8% |
| hash | 34.84 | 36.76 | 35.82 | -3.1% |
| matmul | 68.19 | 67.13 | 66.75 | +0.3% |
| sieve | 106.69 | 108.60 | 107.44 | -0.5% |
| sort | 299.10 | 277.65 | 249.71 | -10.6% |

“Paired change” is the median of within-round `100 * (after / before - 1)`;
it is deliberately not the ratio of the separately reported duration medians.
Negative means faster. Small opposing movements remain visible; these samples
do not establish general performance changes for the other four workloads.

Sort's paired runtime change was -10.6% (range -22.7% to -8.3% across seven rounds). Hash's paired change was -3.1% across 21 rounds, with mixed individual changes (-10.0% to +4.7%). Hash still ran 2.8% slower than the reference by the duration medians: this is a partial improvement, not elimination of that regression.

Assembly changed for hash, matmul and sort; collatz, divs and sieve remained
byte-identical. Their observed timing changes therefore do not demonstrate a
new generated-code effect. Scaled memory operands remove separate shifts in
several sort/hash paths. Changed register allocation can also affect runtime;
these measurements do not isolate one instruction's causal contribution.

## Compilation cost context

| Level | Before 82-file batch | After 82-file batch | Median paired change (range) |
|---|---:|---:|---:|
| -O0 | 236.84 ms | 236.48 ms | -0.3% (-3.4% to +1.6%) |
| -O2 | 235.25 ms | 240.08 ms | +1.3% (-0.9% to +4.5%) |

Small variations in these seven-round batches do not prove a compilation
speedup or absence of regressions. Compatibility/correctness gates are
separate from these measurements; see HANDOFF.md for actual completed
verification and source-specific GitHub CI state.
