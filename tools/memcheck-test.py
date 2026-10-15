#!/usr/bin/env python3
"""Test memcheck's classification/coverage using a stub, not a fake memory scan."""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parent.parent

class MemcheckHarness(unittest.TestCase):
    def check_status(self, status):
        with tempfile.TemporaryDirectory() as work:
            root = Path(work)
            stub = root / 'valgrind'
            stub.write_text('#!/bin/sh\nprintf "%s\\n" "$*" >> "$CALLS"\nexit "$STUB_STATUS"\n')
            stub.chmod(0o755)
            calls = root / 'calls'
            env = {**os.environ, 'PATH': work + os.pathsep + os.environ['PATH'],
                   'TMPDIR': work, 'CALLS': str(calls), 'STUB_STATUS': str(status)}
            result = subprocess.run(['sh', str(ROOT / 'tools/memcheck.sh'), 'dummy.ssa'],
                                    env=env, capture_output=True, text=True, timeout=10)
            self.assertEqual(0 if status == 0 else 1, result.returncode)
            rows = calls.read_text().splitlines()
            self.assertEqual(12, len(rows))
            for target in ('amd64_sysv', 'amd64_apple', 'amd64_win', 'arm64', 'arm64_apple', 'rv64'):
                for level in (0, 2):
                    self.assertTrue(any(' -t %s -O%d ' % (target, level) in row for row in rows))
            self.assertIn('12 passed, 0 failed' if status == 0 else '0 passed, 12 failed', result.stdout)
            self.assertEqual({'valgrind', 'calls'}, {p.name for p in root.iterdir()})

    def test_success_covers_all_targets(self): self.check_status(0)
    def test_compiler_failure_is_not_success(self): self.check_status(1)
    def test_memory_error_is_failure(self): self.check_status(99)
    def test_signal_status_is_failure(self): self.check_status(143)

if __name__ == '__main__':
    unittest.main()
