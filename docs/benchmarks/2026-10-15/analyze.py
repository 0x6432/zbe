"""Single reconciled computation and independent raw-data check for this run."""
import csv
import json
from pathlib import Path
import statistics

import pandas as pd

RAW = Path("/data/raw")
OUT = Path("/data/analysis")
source = RAW / "zbe-perf-20261015.csv"
metadata = json.loads((RAW / "zbe-perf-20261015-metadata.json").read_text())
assert len(metadata["benchmark_source_hashes"]) == 6
assert len(metadata["validated_stdout"]) == 6
frame = pd.read_csv(source)
keys = ["phase", "program", "compiler"]
assert len(frame) == 329
assert not frame.duplicated(keys + ["round"]).any()
assert frame.notna().all().all() and (frame["seconds"] > 0).all()
assert frame.groupby(keys).size().eq(7).all()

summary = frame.groupby(keys)["seconds"].agg(["size", "median", "min", "max"]).reset_index()
summary.to_csv(OUT / "perf-summary.csv", index=False)

# Independent numeric check: do not reuse pandas' grouped data or statistics.
independent = {}
with source.open() as stream:
    for row in csv.DictReader(stream):
        key = tuple(row[column] for column in keys)
        independent.setdefault(key, []).append(float(row["seconds"]))
for row in summary.to_dict("records"):
    values = independent[(row["phase"], row["program"], row["compiler"])]
    assert abs(statistics.median(values) - row["median"]) < 1e-12
    assert len(values) == row["size"]


def cell(phase, program, compiler):
    return summary.loc[
        (summary.phase == phase) & (summary.program == program) & (summary.compiler == compiler)
    ].iloc[0].to_dict()


def paired_change(phase, program, baseline, candidate):
    rows = frame.loc[(frame.phase == phase) & (frame.program == program)]
    pivot = rows.pivot(index="round", columns="compiler", values="seconds")
    values = (100 * (pivot[candidate] / pivot[baseline] - 1)).tolist()
    return {"median_percent": statistics.median(values), "min_percent": min(values), "max_percent": max(values)}


programs = sorted(frame.loc[frame.phase == "runtime", "program"].unique())
compile_program = frame.loc[frame.phase == "compile", "program"].iloc[0]
compile_results = []
for level in (0, 2):
    before = cell("compile", compile_program, f"Baseline -O{level}")
    after = cell("compile", compile_program, f"Candidate -O{level}")
    compile_results.append({
        "level": level, "baseline_ms": before["median"] * 1000, "candidate_ms": after["median"] * 1000,
        "paired_change": paired_change("compile", compile_program, f"Baseline -O{level}", f"Candidate -O{level}"),
    })
runtime_results = []
for program in programs:
    reference = cell("runtime", program, "C reference")
    opt0 = cell("runtime", program, "Candidate -O0")
    opt2 = cell("runtime", program, "Candidate -O2")
    identical = all(metadata["assembly_hashes"][program][f"Baseline -O{level}"] ==
                    metadata["assembly_hashes"][program][f"Candidate -O{level}"] for level in (0, 2))
    assert identical
    runtime_results.append({
        "program": program, "reference_ms": reference["median"] * 1000,
        "opt0_ms": opt0["median"] * 1000, "opt2_ms": opt2["median"] * 1000,
        "opt2_vs_reference_ratio": reference["median"] / opt2["median"],
        "opt2_vs_baseline": paired_change("runtime", program, "Baseline -O2", "Candidate -O2"),
        "baseline_candidate_assembly_identical": identical,
    })

evidence = {
    "metadata": metadata,
    "row_count": len(frame),
    "independent_check": "Every grouped median independently reproduced with csv + statistics.median",
    "profiling": "CSV: no nulls or duplicate rows; use phase/program/compiler/round as the key, not incidental distinct timing values. Nested JSON is non-tabular provenance and was parsed/validated explicitly.",
    "compile_results": compile_results,
    "runtime_results": runtime_results,
    "finding": "Audit/hardening changes leave benchmark-generated assembly unchanged; runtime timing differences between snapshots are not a new optimizer gain",
    "coverage": "7 shuffled rounds, one native LP64 host, 6 C workloads, 82 accepted IL files per compiler batch",
    "limitations": "Process startup and Python harness overhead included; a single sandbox run is not a general performance guarantee",
    "comparison_plan": [
        {"comparison": "Baseline versus candidate compilation", "grain": "82-file batch per round and optimization level",
         "population": "Same 76 upstream SSA and 6 corrected benchmark IL files", "unit": "ms",
         "derivation": "Medians and within-round percent changes", "disposition": "table",
         "reason": "Only two optimization-level pairs; retain measured variation without implying a new speedup"},
        {"comparison": "Existing -O2 versus C reference generated-code runtime", "grain": "program and compiler",
         "population": "All six benchmark programs, seven samples each", "unit": "ms",
         "derivation": "Median of seven observed execution times", "disposition": "chart",
         "reason": "Six workloads show where existing optimizer benefits differ; no top-N exclusion"},
        {"comparison": "Baseline versus candidate generated-code runtime", "grain": "program and compiler",
         "population": "Same six fixtures at O0/O2", "unit": "ms / percent",
         "derivation": "Byte-identical assembly hashes and within-round timing deltas", "disposition": "prose",
         "reason": "Identical generated assembly rules out claiming a new code-generation optimization from noisy times"},
        {"comparison": "GCC timing context", "grain": "program and compiler", "population": "Same six fixtures",
         "unit": "ms", "derivation": "Seven-sample median", "disposition": "omit",
         "reason": "Retained in full summary; GCC also supplies independently validated program outputs, but is not the audit baseline"},
    ],
}
assert metadata["compile_files"] == 82
(OUT / "perf-evidence.json").write_text(json.dumps(evidence, indent=2))

spec = {
    "version": 1, "form": "categorical-bars", "mode": "grouped",
    "title": "Existing -O2 performance varies by workload",
    "aside": "Median execution time in milliseconds over seven native runs; lower is better",
    "labels": programs, "axis": {"zero": True},
    "colorMap": {"C reference": "purple", "zbe -O0": "blue", "zbe -O2": "teal"},
    "series": [
        {"label": label, "valueKind": "durationMs", "role": role, "data": [row[column] for row in runtime_results]}
        for label, role, column in [
            ("C reference", "base", "reference_ms"), ("zbe -O0", "aux", "opt0_ms"), ("zbe -O2", "subject", "opt2_ms")
        ]
    ],
}
(OUT / "perf-chart-spec.json").write_text(json.dumps(spec, indent=2))
lines = [
    "| workload | C reference | zbe -O0 | zbe -O2 |",
    "|---|---:|---:|---:|",
]
for row in runtime_results:
    lines.append("| {program} | {reference_ms:.1f} ms | {opt0_ms:.1f} ms | {opt2_ms:.1f} ms |".format(**row))
(OUT / "perf-findings-table.md").write_text("\n".join(lines) + "\n")
print(json.dumps({"compile_results": compile_results, "runtime_results": runtime_results}, indent=2))
# Follow-up: a new, explicitly controlled measurement tests the address matcher.
# Earlier raw evidence remains immutable and its values are not pooled with this.
address_source = RAW / 'zbe-address-perf-final-20261015.csv'
address_meta = json.loads((RAW / 'zbe-address-perf-final-20261015-metadata.json').read_text())
a = pd.read_csv(address_source)
assert len(a) == 196 and not a.duplicated(keys + ['round']).any()
assert a.notna().all().all() and (a.seconds > 0).all()
assert set(a.repeats) == {1, 10}
a['per_run_seconds'] = a.seconds / a.repeats
asum = a.groupby(keys).per_run_seconds.agg(['size', 'median', 'min', 'max']).reset_index()
asum.to_csv(OUT / 'address-perf-summary.csv', index=False)
independent_address = {}
for row in csv.DictReader(address_source.open()):
    key = tuple(row[col] for col in keys)
    independent_address.setdefault(key, []).append(float(row['seconds']) / int(row['repeats']))
for row in asum.to_dict('records'):
    values = independent_address[(row['phase'], row['program'], row['compiler'])]
    assert len(values) == row['size']
    assert abs(statistics.median(values) - row['median']) < 1e-12

def acell(phase, program, compiler):
    return asum.loc[(asum.phase == phase) & (asum.program == program) & (asum.compiler == compiler)].iloc[0]
def apair(phase, program, before, after):
    subset = a.loc[(a.phase == phase) & (a.program == program)]
    pivot = subset.pivot(index='round', columns='compiler', values='per_run_seconds')
    values = (100 * (pivot[after] / pivot[before] - 1)).tolist()
    assert all(pd.notna(values))
    return {'median_percent': statistics.median(values), 'min_percent': min(values), 'max_percent': max(values)}
address_runtime = []
for program in programs:
    sample_count = 21 if program == 'hash' else 7
    assert (asum.loc[(asum.phase == 'runtime') & (asum.program == program), 'size'] == sample_count).all()
    address_runtime.append({
        'program': program, 'samples_per_compiler': sample_count,
        'processes_per_sample': 10 if program == 'hash' else 1,
        'before_ms': float(acell('runtime', program, 'Before -O2')['median']) * 1000,
        'after_ms': float(acell('runtime', program, 'After -O2')['median']) * 1000,
        'reference_ms': float(acell('runtime', program, 'C reference')['median']) * 1000,
        'paired_change': apair('runtime', program, 'Before -O2', 'After -O2'),
        'assembly_changed': address_meta['assembly_hashes'][program]['Before -O2'] != address_meta['assembly_hashes'][program]['After -O2'],
    })
address_compile = []
for level in (0, 2):
    address_compile.append({
        'level': level,
        'before_ms': float(acell('compile', '82-file batch', f'Before -O{level}')['median']) * 1000,
        'after_ms': float(acell('compile', '82-file batch', f'After -O{level}')['median']) * 1000,
        'paired_change': apair('compile', '82-file batch', f'Before -O{level}', f'After -O{level}'),
    })
for row in address_runtime:
    row['after_vs_reference_percent'] = 100 * (row['after_ms'] / row['reference_ms'] - 1)
hash_result = next(row for row in address_runtime if row['program'] == 'hash')
sort_result = next(row for row in address_runtime if row['program'] == 'sort')
address_finding = f"Scaled addressing: sort {sort_result['paired_change']['median_percent']:+.1f}%, hash {hash_result['paired_change']['median_percent']:+.1f}% paired runtime; one sandbox, not a general performance guarantee"
evidence['comparison_plan'][1]['disposition'] = 'table'
evidence['comparison_plan'][1]['reason'] = 'Retained as prior baseline context; follow-up chart directly tests the measured matcher change across all six workloads' 
evidence['preliminary_address_candidate'] = {'status': 'Superseded by signed-32-bit displacement fallback; not final-source verification', 'csv': 'zbe-address-perf-20261015.csv', 'metadata': 'zbe-address-perf-20261015-metadata.json'}
evidence['address_followup'] = {
    'metadata': address_meta, 'row_count': len(a), 'runtime_results': address_runtime,
    'compile_results': address_compile, 'finding': address_finding,
    'independent_check': 'All grouped medians independently reproduced from CSV; per-process mean seconds = recorded batch seconds / repeats',
    'profiling': 'No nulls/duplicates; phase/program/compiler/round is the key, not incidental unique seconds. Nested provenance JSON validated explicitly: 6 source/output groups and hashes, 82 compile inputs, three compiler binaries.',
    'coverage': 'All six workloads and 82 IL compile inputs. Seven paired rounds; hash has 21 rounds with 10 processes per observation. No rows discarded.',
    'comparison_plan': [
        {'comparison': 'Address matcher before vs after runtime', 'grain': 'workload and paired round',
         'population': 'all six fixtures', 'unit': 'percent',
         'derivation': 'median(100 * (after per-process seconds / before per-process seconds - 1))',
         'finding': address_finding, 'disposition': 'chart',
         'reason': 'Relative change exposes hash without hiding shorter workloads on a four-second raw scale; retain all six, including regressions'},
        {'comparison': 'Absolute runtime and C reference', 'grain': 'workload and compiler',
         'population': 'same six fixtures', 'unit': 'ms', 'derivation': 'median of per-observation process mean',
         'finding': 'Full raw levels remain supporting context', 'disposition': 'table',
         'reason': 'Retain full levels and opposing changes without a second redundant chart'},
        {'comparison': 'Compiler batch runtime', 'grain': '82-file batch and optimization level',
         'population': 'same 76 upstream SSA + six corrected benchmark IL inputs', 'unit': 'ms and percent',
         'derivation': 'medians and paired per-round changes', 'finding': 'Small noisy compilation sample, not proof of no regression',
         'disposition': 'prose', 'reason': 'Two level pairs do not require another plot'},
    ],
}
assert len(address_meta['sources']) == 6 and len(address_meta['validated_stdout']) == 6
assert len(address_meta['compile_inputs']) == 82 and len(address_meta['compiler_hashes']) == 3
(OUT / 'perf-evidence.json').write_text(json.dumps(evidence, indent=2))
address_spec = {
    'version': 1, 'form': 'categorical-bars', 'mode': 'grouped', 'orientation': 'horizontal',
    'title': address_finding.split(';')[0],
    'aside': 'Negative means faster · 7 paired rounds; hash 21 rounds × 10 processes · one native host',
    'labels': programs, 'subjectIndex': programs.index('sort'), 'axis': {'zero': True},
    'colorMap': {name: 'green' if name == 'sort' else 'neutral' for name in programs},
    'derived': True, 'derivationReason': 'Median paired percent change in per-process runtime: 100 × (after / before − 1)',
    'series': [{'label': 'After vs before runtime', 'role': 'subject', 'valueKind': 'percent',
                'derived': True, 'derivationReason': 'Median of within-round percent changes; batch seconds divided by repeats',
                'data': [row['paired_change']['median_percent'] for row in address_runtime]}],
}
(OUT / 'address-chart-spec.json').write_text(json.dumps(address_spec, indent=2))
lines = ['| workload | C reference (ms) | Before -O2 (ms) | After -O2 (ms) | Paired change |', '|---|---:|---:|---:|---:|']
for row in address_runtime:
    lines.append(f"| {row['program']} | {row['reference_ms']:.2f} | {row['before_ms']:.2f} | {row['after_ms']:.2f} | {row['paired_change']['median_percent']:+.1f}% |")
(OUT / 'address-findings-table.md').write_text('\n'.join(lines) + '\n')
(OUT / 'address-findings.json').write_text(json.dumps({'finding': address_finding, 'runtime': address_runtime, 'compile': address_compile}, indent=2))
print(json.dumps({'address_finding': address_finding, 'compile': address_compile}, indent=2))

# Durable repository report, formatted from the same reconciled evidence.
report_path = Path('/data/zbe/docs/PERFORMANCE.md')
preamble = report_path.read_text().split('## Bounded AMD64 address-scale follow-up')[0]
report = preamble + '''## Bounded AMD64 address-scale follow-up

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

'''
report += (OUT / 'address-findings-table.md').read_text()
report += '''
“Paired change” is the median of within-round `100 * (after / before - 1)`;
it is deliberately not the ratio of the separately reported duration medians.
Negative means faster. Small opposing movements remain visible; these samples
do not establish general performance changes for the other four workloads.

'''
report += f"Sort's paired runtime change was {sort_result['paired_change']['median_percent']:+.1f}% (range {sort_result['paired_change']['min_percent']:+.1f}% to {sort_result['paired_change']['max_percent']:+.1f}% across seven rounds). "
report += f"Hash's paired change was {hash_result['paired_change']['median_percent']:+.1f}% across 21 rounds, with mixed individual changes ({hash_result['paired_change']['min_percent']:+.1f}% to {hash_result['paired_change']['max_percent']:+.1f}%). "
report += f"Hash still ran {hash_result['after_vs_reference_percent']:.1f}% slower than the reference by the duration medians: this is a partial improvement, not elimination of that regression.\n\n"
report += '''Assembly changed for hash, matmul and sort; collatz, divs and sieve remained
byte-identical. Their observed timing changes therefore do not demonstrate a
new generated-code effect. Scaled memory operands remove separate shifts in
several sort/hash paths. Changed register allocation can also affect runtime;
these measurements do not isolate one instruction's causal contribution.

## Compilation cost context

| Level | Before 82-file batch | After 82-file batch | Median paired change (range) |
|---|---:|---:|---:|
'''
for row in address_compile:
    p = row['paired_change']
    report += f"| -O{row['level']} | {row['before_ms']:.2f} ms | {row['after_ms']:.2f} ms | {p['median_percent']:+.1f}% ({p['min_percent']:+.1f}% to {p['max_percent']:+.1f}%) |\n"
report += '''
Small variations in these seven-round batches do not prove a compilation
speedup or absence of regressions. Compatibility/correctness gates are
separate from these measurements; see HANDOFF.md for actual completed
verification and source-specific GitHub CI state.
'''
report_path.write_text(report)
