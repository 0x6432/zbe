"""Paired portable ReleaseFast comparison, immutable raw output, no discarded rows."""
import csv
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import platform
import random
import subprocess
import time

ROOT = Path('/data/zbe')
RAW = Path('/data/raw')
WORK = Path('/data/address-perf-final-work')
WORK.mkdir(exist_ok=True)
CSV = RAW / 'zbe-address-perf-final-20261015.csv'
META = RAW / 'zbe-address-perf-final-20261015-metadata.json'
assert not CSV.exists() and not META.exists()
spec = importlib.util.spec_from_file_location('bench', ROOT / 'tools/bench.py')
bench = importlib.util.module_from_spec(spec); spec.loader.exec_module(bench)
def sha(path): return hashlib.sha256(Path(path).read_bytes()).hexdigest()
try:
    cpu = min(os.sched_getaffinity(0)); os.sched_setaffinity(0, {cpu})
    affinity = [cpu]
except (AttributeError, OSError): affinity = None
commands = {
    'C reference': ['/data/qbe-cfix/qbe'],
    'Before -O2': ['/data/zbe-audit-perf/zig-out/bin/qbe', '-O2'],
    'After -O2': ['/data/address-perf-v2/bin/qbe', '-O2'],
}
programs, outputs, hashes, il_files = {}, {}, {}, []
for source in sorted((ROOT / 'bench').glob('*.c')):
    name = source.stem
    il = WORK / (name + '.qbe')
    bench.checked(['/data/cproc/cproc', '-emit-qbe', '-o', str(il), str(source)])
    il_files.append(il); programs[name] = {}; hashes[name] = {}; expected = None
    for label, command in commands.items():
        asm = WORK / (name + '_' + label.replace(' ', '_') + '.s')
        exe = asm.with_suffix('')
        bench.checked(command + ['-o', str(asm), str(il)])
        bench.checked(['cc', '-o', str(exe), str(asm)])
        output = bench.checked([str(exe)]).stdout
        if expected is None: expected = output
        assert output == expected, (name, label, 'output mismatch')
        programs[name][label] = str(exe); hashes[name][label] = sha(asm)
    outputs[name] = expected
files = sorted((ROOT / 'test').glob('*.ssa')) + il_files
compile_commands = {f'{when} -O{level}': [path, f'-O{level}']
    for when, path in [('Before', commands['Before -O2'][0]), ('After', commands['After -O2'][0])]
    for level in (0, 2)}
for command in compile_commands.values():
    for path in files: bench.checked(command + [str(path)])
META.write_text(json.dumps({
    'question': 'Does optimized AMD64 shift-scale recognition improve the measured hash regression?',
    'host': platform.platform(), 'machine': platform.machine(), 'affinity': affinity,
    'zig': '0.18.0-dev.35+5e754304d', 'build': 'ReleaseFast -Dcpu=baseline, both Zig compilers',
    'before_revision': subprocess.check_output(['git', '-C', '/data/zbe-audit-perf', 'rev-parse', 'HEAD'], text=True).strip(),
    'after_parent_revision': subprocess.check_output(['git', '-C', str(ROOT), 'rev-parse', 'HEAD'], text=True).strip(),
    'after_isel_sha256': sha(ROOT / 'src/amd64/isel.zig'),
    'compiler_hashes': {key: sha(value[0]) for key, value in commands.items()},
    'sources': {str(p): sha(p) for p in (ROOT / 'bench').glob('*.c')},
    'compile_inputs': {str(p): sha(p) for p in files}, 'assembly_hashes': hashes,
    'validated_stdout': outputs, 'rounds': '7 all workloads + 14 additional hash rounds',
    'repeats': '10 sequential processes per hash observation; 1 for other runtimes',
    'method': 'fixed-seed shuffled paired rounds, one CPU, untimed warmup, subprocess startup included',
    'limits': 'one sandbox; small samples, no population-wide performance guarantee',
}, indent=2))
def compile_batch(cmd):
    for p in files: bench.timed(cmd + [str(p)])
for cmd in compile_commands.values(): compile_batch(cmd)
for group in programs.values():
    for exe in group.values(): bench.timed([exe])
rng = random.Random(643203)
with CSV.open('x', newline='') as stream:
    writer = csv.DictWriter(stream, fieldnames=['phase', 'program', 'compiler', 'round', 'order', 'repeats', 'seconds'])
    writer.writeheader()
    for rep in range(1, 22):
        tasks = []
        if rep <= 7:
            tasks += [('compile', f'{len(files)}-file batch', label, 1, lambda cmd=cmd: compile_batch(cmd)) for label, cmd in compile_commands.items()]
        for name, group in programs.items():
            if rep > 7 and name != 'hash': continue
            repeats = 10 if name == 'hash' else 1
            for label, exe in group.items():
                def task(exe=exe, repeats=repeats):
                    for _ in range(repeats): bench.timed([exe])
                tasks.append(('runtime', name, label, repeats, task))
        rng.shuffle(tasks)
        for order, (phase, program, label, repeats, task) in enumerate(tasks):
            start = time.perf_counter_ns(); task(); elapsed = (time.perf_counter_ns() - start) / 1e9
            writer.writerow(dict(phase=phase, program=program, compiler=label, round=rep, order=order, repeats=repeats, seconds=elapsed))
            stream.flush()
        print('Completed paired round', rep, flush=True)
print('ADDRESS PERFORMANCE MEASUREMENTS COMPLETE', flush=True)
