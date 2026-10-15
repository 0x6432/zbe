#!/usr/bin/env python3
"""Verify the local full-suite entry point propagates build and suite failures."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parent.parent


class FullSuiteEntryPoint(unittest.TestCase):
    def check_run(self, zig_status, core_status, corpus_status, expected):
        with tempfile.TemporaryDirectory() as work:
            root = Path(work)
            (root / 'tools').mkdir()
            (root / 'bin').mkdir()
            (root / 'corpus').mkdir()
            shutil.copy(ROOT / 'tools/all.sh', root / 'tools/all.sh')
            zig = root / 'bin/zig'
            zig.write_text('#!/bin/sh\nexit "$ZIG_STATUS"\n')
            zig.chmod(0o755)
            (root / 'tools/ci.sh').write_text(
                '#!/bin/sh\nprintf "%s\\n" "$1" >> "$CALLS"\n'
                'case "$1" in core) exit "$CORE_STATUS";; corpus) exit "$CORPUS_STATUS";; esac\n')
            calls = root / 'calls'
            environment = {
                **os.environ, 'PATH': str(root / 'bin') + os.pathsep + os.environ['PATH'],
                'ZIG_STATUS': str(zig_status), 'CORE_STATUS': str(core_status),
                'CORPUS_STATUS': str(corpus_status), 'CORPUS': str(root / 'corpus'),
                'CALLS': str(calls), 'FUZZ': '',
            }
            result = subprocess.run(['sh', str(root / 'tools/all.sh')], env=environment,
                                    capture_output=True, text=True, timeout=10)
            self.assertEqual(expected, result.returncode)
            observed = calls.read_text().splitlines() if calls.exists() else []
            wanted = [] if zig_status else ['core'] if core_status else ['core', 'corpus']
            self.assertEqual(wanted, observed)

    def test_build_failure_stops_the_gate(self): self.check_run(7, 0, 0, 7)
    def test_core_failure_stops_the_gate(self): self.check_run(0, 3, 0, 3)
    def test_corpus_failure_propagates(self): self.check_run(0, 0, 5, 5)
    def test_success_requires_all_selected_gates(self): self.check_run(0, 0, 0, 0)


if __name__ == '__main__':
    unittest.main()