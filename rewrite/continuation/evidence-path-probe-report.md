# Evidence-path substitution probe — 2026-11-10

**Disposition: BLOCKED / gate remains HELD.** This is a synthetic harness investigation, not a real Valgrind scan, a security proof, or a gate pass. No proposed collector or gate change is approved by these results.

## Scope and identity

- Checkout was detached at `055301dbcf79fe4b07bba15b1d6eb873f18fa4b7`; working tree was clean before the original investigation. During the later probe revision, unrelated `rewrite/src` edits were present and/or appeared concurrently; this investigation did not alter them. No commits, branch/ref changes, pushes, force pushes, production/compiler changes, or host-security changes were made by this investigation.
- Read `rewrite/ZBE-HANDOFF.md`, `rewrite/EXTERN-GOT-WIP.md`, `rewrite/continuation/next-design-revised.md`, `rewrite/continuation/evidence-isolation-design.md`, and `rewrite/continuation/valgrind-syscall-provenance.md`. The earlier report's `/data/zbe-integration-signal-gate-20261025/preparation` and `/data/zbe-evidence-isolation-prototype` were absent here, as was `/usr/bin/valgrind`; `command -v valgrind` found none on PATH. The unavailable preparation/controller cannot be inspected or run in this sandbox.
- Inspected repository `tools/memcheck.sh`: it creates a private temporary directory, passes `--log-file` inside it to Valgrind, then reopens that path for the checks. Private directory permissions alone do not separate a same-UID client from the driver. This is an observation about the repository script, not a measurement of the missing preparation's complete behavior.

## Synthetic experiment

Added `rewrite/continuation/evidence_path_substitution_probe.py`, a standalone, temporary-directory-only test. It does not modify the gate. It executes the repository driver with a **stub** Valgrind and a **fake** client and reference; it never executes the real compiler or Valgrind. The stub opens the log file, runs the client and writes to its still-open original file descriptor, returning zero. The clean case writes only a clean summary; the other cases write a fatal-tool marker plus a clean summary. This is a controlled model of the driver's fatal-message check, not a claim that a real fatal Valgrind startup produces a clean summary or returns zero.

- Clean control: the client leaves the path alone, and the stub writes a clean summary without a fatal marker. The driver accepts all 12 synthetic cases.
- Fatal control: the client leaves the path alone. The driver reads the fatal marker and rejects all 12 synthetic cases; the probe checks for exactly one marker in each individual failure section.
- Substitution: the same-UID fake client finds the driver's temporary log via `TMPDIR`, atomically replaces the pathname with a forged clean summary, and exits. The stub writes its fatal marker and summary to the now-unlinked original inode. The driver reads the replacement and accepts all 12 cases. Explicit runtime checks, which remain active under `-O`, verify statuses, actual summaries, each target/optimization argument pair, failure sections, marker counts and cleanup. Printed values are taken from the observed driver output and call counts, not expected strings.

Reproduction from the repository root:

```sh
python3 rewrite/continuation/evidence_path_substitution_probe.py
python3 -O rewrite/continuation/evidence_path_substitution_probe.py
```

Both commands produced the following observed output:

```text
clean: driver exit=0; memcheck: 12 passed, 0 failed (0 reference-confirmed rejections); synthetic client calls=12; fatal markers=0
control: driver exit=1; memcheck: 0 passed, 12 failed (0 reference-confirmed rejections); synthetic client calls=12; fatal markers=12
substitute: driver exit=0; memcheck: 12 passed, 0 failed (0 reference-confirmed rejections); synthetic client calls=12; fatal markers=0
BLOCKED: substitution was accepted by the current path consumer; this synthetic fixture is not Valgrind or gate evidence.
```

Additionally, the following in-memory negative control forced the supposedly clean stub to emit a fatal marker, confirming that the explicit checks reject this incorrect result in both modes; it did not modify the probe file:

```sh
for opt in normal optimized; do
  if [ "$opt" = optimized ]; then set -- -O; else set --; fi
  PROBE_CHECK_MODE="$opt" python3 "$@" - <<'PYCODE' || exit 1
from pathlib import Path
import os, runpy, tempfile
m = runpy.run_path('rewrite/continuation/evidence_path_substitution_probe.py')
g = m['run_case'].__globals__
g['STUB'] = g['STUB'].replace('[ "$PROBE_MODE" != clean ]', '[ 1 = 1 ]')
with tempfile.TemporaryDirectory(prefix='zbe-probe-negative-check-') as tmp:
    try:
        m['run_case'](Path(tmp), 'clean')
    except RuntimeError as exc:
        if 'unexpected status or summary' not in str(exc):
            raise
        print(f"{os.environ['PROBE_CHECK_MODE']}: deliberately fatal clean control rejected by explicit checks")
    else:
        raise SystemExit('FAIL: explicit check did not reject altered clean control')
PYCODE
done
```

Observed:

```text
normal: deliberately fatal clean control rejected by explicit checks
optimized: deliberately fatal clean control rejected by explicit checks
```

In the original investigation, `python3 tools/memcheck-test.py` reported `Ran 26 tests in 2.767s` and `OK`; it was not rerun during this revision.

The 26 existing tests are also stub-based classification/coverage tests, not scans. This experiment demonstrates a pathname-consumption weakness under the modeled same-UID write access; it does **not** demonstrate that a real Valgrind process yields this particular status or log sequence, bypasses `--error-exitcode=99`, or that a real compiler is malicious. The attacker can deny progress; a passing synthetic adversary test could not prove complete mediation.

SHA-256 for the exact files used:

```text
7fe9651e74c9c4b22a7bc6d58af1ce228cdd69736e6c9d7f09c9e91c39ee2406  tools/memcheck.sh
8b47b20600c9ab5b43cdb210bc89537dfdd0ded9599b2072566ccd288e02f015  tools/memcheck-test.py
a5a58902a75d840c953ee701286fac5eb7454430450e1a7c0554bb6ec2dff84c  rewrite/continuation/evidence_path_substitution_probe.py
```

## Why no fix was installed

Keeping an already-open descriptor or checking an inode could address this one path replacement but would not prove exclusive log authorship: a guest may be able to write the underlying inode or alias a shared writer, and the controller and driver still need the same protected, complete case-bound bytes. Copying or hashing after execution would not establish authorship. The prior provenance report identifies a common guest/core syscall site and unresolved descriptor, process, peer, loss and handoff routes. A high FD or narrow filter is therefore not a defensible substitute. Without the real preparation, pinned tool, complete mediation design, protected handoff and independent reviews, installing a purported fix would be misleading.

Next: restore the exact preparation and pinned Valgrind source/build in an authorized environment; independently review guest/core separation and complete syscall/FD/peer mediation, and design loss-detecting collection with an immutable case-bound handoff to both consumers. Validate real and adversarial cases without changing the approved workload, followed by fresh reviews and authorization before any full gate. If any route remains unclassified, keep HOLD. No hosted CI, integration gate or terminal audit was run here.
