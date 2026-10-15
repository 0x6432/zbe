#!/usr/bin/env python3
"""Fail-closed benchmark regressions, without requiring cproc or long timings."""
import contextlib
import importlib.util
import io
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('bench', Path(__file__).with_name('bench.py'))
bench = importlib.util.module_from_spec(spec)
spec.loader.exec_module(bench)


class BenchmarkSafety(unittest.TestCase):
    def test_timing_uses_completion_pipe_not_timeout_sleep_polling(self):
        with patch.object(bench.subprocess, 'run') as run:
            bench.timed(['compiler', 'fixture.ssa'])
        self.assertEqual(subprocess.PIPE, run.call_args.kwargs['stderr'])
        self.assertTrue(run.call_args.kwargs['check'])

    def test_checked_rejects_nonzero_exit_even_with_empty_stdout(self):
        with self.assertRaises(subprocess.CalledProcessError):
            bench.checked([sys.executable, '-c', 'raise SystemExit(7)'])

    def test_timing_rejects_nonzero_exit(self):
        with self.assertRaises(subprocess.CalledProcessError):
            bench.timed([sys.executable, '-c', 'raise SystemExit(7)'])

    def test_timing_rejects_signal(self):
        with self.assertRaises(subprocess.CalledProcessError):
            bench.timed([sys.executable, '-c', 'import os, signal; os.kill(os.getpid(), signal.SIGTERM)'])

    def test_commands_have_finite_timeouts(self):
        command = [sys.executable, '-c', 'import time; time.sleep(5)']
        with patch.object(bench, 'TIMEOUT', 0.05):
            for run in (bench.checked, bench.timed):
                with self.assertRaises(subprocess.TimeoutExpired):
                    run(command)

    def test_main_cleans_temporary_files_on_failure(self):
        paths = []
        def fail(work):
            paths.append(work)
            Path(work, 'partial').write_text('partial output')
            raise RuntimeError('deliberate failure')
        with patch.object(bench, 'benchmark', fail), contextlib.redirect_stderr(io.StringIO()):
            self.assertEqual(1, bench.main())
        self.assertEqual(1, len(paths))
        self.assertFalse(Path(paths[0]).exists())

    def test_main_cleans_temporary_files_on_success(self):
        paths = []
        with patch.object(bench, 'benchmark', lambda work: (paths.append(work), 0)[1]):
            self.assertEqual(0, bench.main())
        self.assertFalse(Path(paths[0]).exists())

    def test_invalid_timing_configuration_is_rejected(self):
        for key, value in (('REPS', '0'), ('REPS', '-1'), ('BENCH_TIMEOUT', '0'),
                           ('BENCH_TIMEOUT', 'inf'), ('BENCH_TIMEOUT', 'nan')):
            result = subprocess.run([sys.executable, str(Path(bench.__file__))],
                                    env={**os.environ, key: value}, capture_output=True, timeout=10)
            self.assertNotEqual(0, result.returncode)
            self.assertNotIn(b'All builds', result.stdout)

    def test_generated_build_and_run_failures_prevent_success(self):
        for stage in ('gcc', 'validate', 'timed-run'):
            with self.subTest(stage=stage), tempfile.TemporaryDirectory() as work:
                Path(work, 'bench').mkdir()
                Path(work, 'test').mkdir()
                Path(work, 'bench', 'example.c').write_text('int main(void) { return 0; }')
                Path(work, 'test', 'example.ssa').write_text('')
                def result(cmd, **kw):
                    return subprocess.CompletedProcess(cmd, 0, '', '')
                def checked(cmd, **kw):
                    if (stage == 'gcc' and cmd[0] == bench.CC) or (stage == 'validate' and len(cmd) == 1):
                        raise subprocess.CalledProcessError(7, cmd)
                    return result(cmd)
                def timed(cmd):
                    if stage == 'timed-run' and len(cmd) == 1:
                        raise subprocess.CalledProcessError(7, cmd)
                output = io.StringIO()
                with patch.object(bench, 'D', work), patch.object(bench, 'REPS', 1), \
                     patch.object(bench, 'run', result), patch.object(bench, 'checked', checked), \
                     patch.object(bench, 'timed', timed), contextlib.redirect_stdout(output):
                    with self.assertRaises(subprocess.CalledProcessError):
                        bench.benchmark(work)
                self.assertNotIn('All builds', output.getvalue())

    def test_compile_failure_prevents_a_success_report(self):
        with tempfile.TemporaryDirectory() as work:
            Path(work, 'bench').mkdir()
            Path(work, 'test').mkdir()
            Path(work, 'bench', 'example.c').write_text('int main(void) { return 0; }')
            Path(work, 'test', 'example.ssa').write_text('')
            def result(cmd, **kw):
                return subprocess.CompletedProcess(cmd, 0, '', '')
            def fail(cmd):
                raise subprocess.CalledProcessError(7, cmd)
            output = io.StringIO()
            with patch.object(bench, 'D', work), patch.object(bench, 'run', result), \
                 patch.object(bench, 'timed', fail), contextlib.redirect_stdout(output):
                with self.assertRaises(subprocess.CalledProcessError):
                    bench.benchmark(work)
            self.assertNotIn('All builds', output.getvalue())


if __name__ == '__main__':
    unittest.main()
