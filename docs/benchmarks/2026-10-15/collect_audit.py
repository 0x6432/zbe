"""Collect paired timings; reuse the repository's fail-closed command helpers."""
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

ROOT = Path("/data/zbe")
RAW = Path("/data/raw")
WORK = Path("/data/perf-work")
RAW.mkdir(exist_ok=True)
WORK.mkdir(exist_ok=True)
CSV = RAW / "zbe-perf-20261015.csv"
META = RAW / "zbe-perf-20261015-metadata.json"
assert not CSV.exists() and not META.exists(), "Raw measurements are immutable"
spec = importlib.util.spec_from_file_location("bench", ROOT / "tools/bench.py")
bench = importlib.util.module_from_spec(spec)
spec.loader.exec_module(bench)


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def revision(path):
    return subprocess.check_output(["git", "-C", str(path), "rev-parse", "HEAD"], text=True).strip()


affinity = "unavailable"
try:
    cpu = min(os.sched_getaffinity(0))
    os.sched_setaffinity(0, {cpu})
    affinity = [cpu]
except (AttributeError, OSError):
    pass

baseline = Path("/data/zbe-baseline/zig-out/bin/qbe")
candidate = Path("/data/zbe-audit-perf/zig-out/bin/qbe")
reference = Path("/data/qbe-cfix/qbe")
compilers = {
    "C reference": [str(reference)],
    "Baseline -O0": [str(baseline), "-O0"],
    "Candidate -O0": [str(candidate), "-O0"],
    "Baseline -O2": [str(baseline), "-O2"],
    "Candidate -O2": [str(candidate), "-O2"],
}
sources = sorted((ROOT / "bench").glob("*.c"))
programs = {}
il_files = []
assembly_identity = {}
outputs = {}
for source in sources:
    name = source.stem
    il = WORK / (name + ".qbe")
    bench.checked(["/data/cproc/cproc", "-emit-qbe", "-o", str(il), str(source)])
    il_files.append(il)
    programs[name] = {}
    assembly_identity[name] = {}
    expected = None
    for label, command in compilers.items():
        key = label.lower().replace(" ", "_")
        assembly = WORK / (name + "_" + key + ".s")
        executable = assembly.with_suffix("")
        bench.checked(command + ["-o", str(assembly), str(il)])
        bench.checked(["cc", "-o", str(executable), str(assembly)])
        programs[name][label] = str(executable)
        assembly_identity[name][label] = sha(assembly)
    for level in (0, 2):
        label = "GCC -O" + str(level)
        executable = WORK / (name + "_gcc" + str(level))
        bench.checked(["cc", "-O" + str(level), "-o", str(executable), str(source)])
        programs[name][label] = str(executable)
    for label, executable in programs[name].items():
        result = bench.checked([executable])
        if expected is None:
            expected = result.stdout
        assert result.stdout == expected, (name, label, "OUTPUT MISMATCH")
    outputs[name] = expected
    for level in (0, 2):
        assert assembly_identity[name]["Baseline -O" + str(level)] == assembly_identity[name]["Candidate -O" + str(level)], (name, level, "assembly changed")

files = sorted((ROOT / "test").glob("*.ssa")) + il_files
for file in files:
    for command in compilers.values():
        bench.checked(command + [str(file)])

metadata = {
    "question": "Did the audit/hardening introduce a performance regression, and where is existing -O2 useful?",
    "host": platform.platform(),
    "machine": platform.machine(),
    "affinity": affinity,
    "clock": "time.perf_counter_ns",
    "zig": "0.18.0-dev.35+5e754304d",
    "build_mode": "ReleaseFast, -Dcpu=baseline for both Zig snapshots",
    "baseline_revision": revision("/data/zbe-baseline"),
    "candidate_revision": revision("/data/zbe-audit-perf"),
    "cproc_revision": revision("/data/cproc"),
    "current_repository_revision": revision(ROOT),
    "reference_patch_sha256": sha(ROOT / "tools/qbe-cfix.patch"),
    "compiler_binaries": {label: {"path": command[0], "sha256": sha(command[0])} for label, command in compilers.items()},
    "compiler_commands": compilers,
    "cc_version": bench.checked(["cc", "--version"]).stdout.splitlines()[0],
    "compile_files": len(files),
    "compile_file_hashes": {str(file): sha(file) for file in files},
    "benchmark_source_hashes": {str(source): sha(source) for source in sources},
    "benchmark_source_note": "divs.c uses corrected, defined wrapping arithmetic for EVERY compiler snapshot",
    "assembly_hashes": assembly_identity,
    "validated_stdout": outputs,
    "repetitions": 7,
    "order": "Fixed-seed shuffle across compiler groups and across all executable groups each round",
    "random_seed": 6432,
    "limits": "Single native sandbox, process startup included, no statistical or cross-machine generalization",
}
META.write_text(json.dumps(metadata, indent=2))


def compile_batch(command):
    for file in files:
        bench.timed(command + [str(file)])


# One untimed warmup per exact measured command/group.
for command in compilers.values():
    compile_batch(command)
for executables in programs.values():
    for executable in executables.values():
        bench.timed([executable])

rng = random.Random(6432)
with CSV.open("x", newline="") as stream:
    writer = csv.DictWriter(stream, fieldnames=["phase", "program", "compiler", "round", "order", "seconds"])
    writer.writeheader()
    for repetition in range(1, 8):
        tasks = [("compile", f"{len(files)}-file batch", label, lambda command=command: compile_batch(command)) for label, command in compilers.items()]
        tasks += [("runtime", name, label, lambda executable=executable: bench.timed([executable])) for name, executables in programs.items() for label, executable in executables.items()]
        rng.shuffle(tasks)
        for order, (phase, program, label, run) in enumerate(tasks):
            start = time.perf_counter_ns()
            run()
            elapsed = (time.perf_counter_ns() - start) / 1e9
            writer.writerow({"phase": phase, "program": program, "compiler": label, "round": repetition, "order": order, "seconds": elapsed})
            stream.flush()
        print("Completed paired round", repetition, flush=True)
print("MEASUREMENTS COMPLETE", CSV, flush=True)