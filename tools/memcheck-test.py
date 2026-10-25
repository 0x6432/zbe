#!/usr/bin/env python3
"""Test memcheck classification/coverage with stubs, not a fake memory scan."""
import os
from pathlib import Path
import shutil
import signal
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parent.parent
HARNESS = Path(os.environ.get('MEMCHECK_SCRIPT', ROOT / 'tools/memcheck.sh'))
DIAGNOSTIC = 'qbe: dying: extern/thread unsupported on amd64_win'


def restore_driver_signal_defaults():
    # A background test runner can inherit ignored SIGINT. The driver must
    # enter with ordinary signal dispositions so its own traps are tested.
    for sig in (signal.SIGHUP, signal.SIGINT, signal.SIGTERM):
        signal.signal(sig, signal.SIG_DFL)


class MemcheckHarness(unittest.TestCase):
    def check_driver_signal(self, sig):
        with tempfile.TemporaryDirectory() as work:
            root = Path(work)
            stub = root / 'valgrind'
            stub.write_text('''#!/bin/sh
printf '%s\\n' "$*" >> "$CALLS"
for arg; do
  case "$arg" in --log-file=*) log=${arg#--log-file=};; esac
done
printf '==123== ERROR SUMMARY: 0 errors from 0 contexts (suppressed: 0 from 0)\\n' > "$log"
''')
            stub.chmod(0o755)
            ref = root / 'reference'
            ref.write_text('#!/bin/sh\nexit 0\n')
            ref.chmod(0o755)
            grep = root / 'grep'
            grep.write_text('''#!/bin/sh
if [ "$#" -ge 2 ] && [ "$1" = -Eq ] &&
   [ "$2" = 'Serious error when reading debug info|DWARF2 reader:|unhandled DW_FORM' ] &&
   [ "$(wc -l < "$CALLS")" -eq 12 ]; then
  printf '%s\\n' "$PPID" > "$SIGNAL_TARGET"
  kill -s "$DRIVER_SIGNAL" "$PPID" || exit 97
  exit 1
fi
exec "$REAL_GREP" "$@"
''')
            grep.chmod(0o755)
            calls = root / 'calls'
            target = root / 'signal-target'
            real_grep = shutil.which('grep')
            self.assertIsNotNone(real_grep)
            env = {**os.environ, 'PATH': work + os.pathsep + os.environ['PATH'],
                   'TMPDIR': work, 'CALLS': str(calls), 'QBEREF': str(ref),
                   'SIGNAL_TARGET': str(target), 'DRIVER_SIGNAL': sig.name[3:],
                   'REAL_GREP': real_grep}
            # Signal the driver itself from its final diagnostic grep, after
            # all 12 clean rows but before its final successful status test.
            # No sleeps, child-exit simulation, or process-group signal is used.
            with subprocess.Popen(['sh', str(HARNESS), 'dummy.ssa'], env=env,
                                  stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                  text=True, preexec_fn=restore_driver_signal_defaults) as process:
                try:
                    stdout, stderr = process.communicate(timeout=10)
                except subprocess.TimeoutExpired:
                    process.kill()
                    process.communicate()
                    raise
                self.assertEqual(128 + int(sig), process.returncode, stdout + stderr)
                self.assertEqual(process.pid, int(target.read_text()))
            rows = calls.read_text().splitlines()
            self.assertEqual(12, len(rows))
            for name in ('amd64_sysv', 'amd64_apple', 'amd64_win', 'arm64', 'arm64_apple', 'rv64'):
                for level in (0, 2):
                    self.assertTrue(any(' -t %s -O%d ' % (name, level) in row for row in rows))
            self.assertNotIn('memcheck:', stdout)
            self.assertEqual({'valgrind', 'reference', 'grep', 'calls', 'signal-target'},
                             {p.name for p in root.iterdir()})

    def check_status(self, status, *, errors=0, diagnostic='', ref_status=0,
                     ref_diagnostic='', summary=True, reference='executable',
                     success=False, rejected=0, tool_message=''):
        with tempfile.TemporaryDirectory() as work:
            root = Path(work)
            stub = root / 'valgrind'
            stub.write_text('''#!/bin/sh
printf '%s\\n' "$*" >> "$CALLS"
for arg; do
  case "$arg" in --log-file=*) log=${arg#--log-file=};; esac
done
case "$SUMMARY" in
  yes|multiple|truncated)
    printf '==123== ERROR SUMMARY: %s errors from %s contexts (suppressed: 0 from 0)' "$ERRORS" "$ERRORS" > "$log"
    [ "$SUMMARY" = truncated ] || printf '\\n' >> "$log"
    [ "$SUMMARY" != multiple ] || printf '==123== ERROR SUMMARY: 0 errors from 0 contexts (suppressed: 0 from 0)\\n' >> "$log";;
  malformed) printf '==123== ERROR SUMMARY: 0 errors from 0 contexts\\n' > "$log";;
esac
[ -z "$TOOL_MESSAGE" ] || printf '%s\\n' "$TOOL_MESSAGE" >> "$log"
[ -z "$DIAGNOSTIC" ] || printf '%s\\n' "$DIAGNOSTIC" >&2
exit "$STUB_STATUS"
''')
            stub.chmod(0o755)
            ref = root / 'reference'
            if reference != 'missing':
                ref.write_text('''#!/bin/sh
printf '%s\\n' "$*" >> "$REF_CALLS"
[ -z "$REF_DIAGNOSTIC" ] || printf '%s\\n' "$REF_DIAGNOSTIC" >&2
exit "$REF_STATUS"
''')
                ref.chmod(0o755 if reference == 'executable' else 0o644)
            calls = root / 'calls'
            ref_calls = root / 'ref-calls'
            env = {**os.environ, 'PATH': work + os.pathsep + os.environ['PATH'],
                   'TMPDIR': work, 'CALLS': str(calls), 'REF_CALLS': str(ref_calls),
                   'QBEREF': str(ref), 'STUB_STATUS': str(status),
                   'ERRORS': str(errors), 'DIAGNOSTIC': diagnostic,
                   'REF_STATUS': str(ref_status), 'REF_DIAGNOSTIC': ref_diagnostic,
                   'SUMMARY': ('yes' if summary else 'no') if isinstance(summary, bool) else summary,
                   'TOOL_MESSAGE': tool_message}
            result = subprocess.run(['sh', str(HARNESS), 'dummy.ssa'], env=env,
                                    capture_output=True, text=True, timeout=10)
            self.assertEqual(0 if success else 1, result.returncode, result.stdout + result.stderr)
            if reference != 'executable':
                self.assertFalse(calls.exists())
                self.assertIn('executable patched C reference required', result.stderr)
            else:
                rows = calls.read_text().splitlines()
                self.assertEqual(12, len(rows))
                for target in ('amd64_sysv', 'amd64_apple', 'amd64_win', 'arm64', 'arm64_apple', 'rv64'):
                    for level in (0, 2):
                        self.assertTrue(any(' -t %s -O%d ' % (target, level) in row for row in rows))
                self.assertIn('12 passed, 0 failed' if success else '0 passed, 12 failed', result.stdout)
                self.assertIn('(%d reference-confirmed rejections)' % rejected, result.stdout)
                if 'Serious error when reading debug info' in tool_message and success:
                    self.assertIn('Valgrind debug info degraded', result.stdout)
                if rejected:
                    self.assertEqual(12, len(ref_calls.read_text().splitlines()))
            # Temporary diagnostic files/directories must always be removed.
            self.assertEqual({'valgrind', 'calls', 'reference', 'ref-calls'} &
                             {p.name for p in root.iterdir()}, {p.name for p in root.iterdir()})

    def test_success_covers_all_targets(self): self.check_status(0, success=True)
    def test_compiler_failure_is_not_success(self): self.check_status(1)
    def test_unexpected_compiler_status(self): self.check_status(2)
    def test_memory_error_is_failure(self): self.check_status(99, errors=1)
    def test_signal_status_is_failure(self): self.check_status(143)
    def test_driver_hup_fails_and_cleans_up(self): self.check_driver_signal(signal.SIGHUP)
    def test_driver_int_fails_and_cleans_up(self): self.check_driver_signal(signal.SIGINT)
    def test_driver_term_fails_and_cleans_up(self): self.check_driver_signal(signal.SIGTERM)
    def test_no_completed_memory_scan_is_failure(self): self.check_status(0, summary=False)
    def test_multiple_summaries_fail_closed(self): self.check_status(0, summary='multiple')
    def test_truncated_summary_fails_closed(self): self.check_status(0, summary='truncated')
    def test_malformed_summary_fails_closed(self): self.check_status(0, summary='malformed')
    def test_fatal_tool_diagnostic_with_zero_summary(self):
        self.check_status(0, tool_message='valgrind: Fatal error at startup')
    def test_vex_failure_with_zero_summary(self):
        self.check_status(0, tool_message='vex: the impossible happened')
    def test_debug_info_degradation_is_reported(self):
        self.check_status(0, tool_message='--123-- WARNING: Serious error when reading debug info', success=True)
    def test_memory_errors_override_zero_exit(self): self.check_status(0, errors=1)
    def test_expected_input_rejection_is_scanned(self):
        self.check_status(1, diagnostic=DIAGNOSTIC, ref_status=134,
                          ref_diagnostic=DIAGNOSTIC, success=True, rejected=12)
    def test_expected_rejection_and_memory_error(self):
        self.check_status(99, errors=1, diagnostic=DIAGNOSTIC,
                          ref_status=134, ref_diagnostic=DIAGNOSTIC)
    def test_memory_summary_independent_of_compiler_status(self):
        self.check_status(1, errors=1, diagnostic=DIAGNOSTIC,
                          ref_status=134, ref_diagnostic=DIAGNOSTIC)
    def test_reference_diagnostic_must_match(self):
        self.check_status(1, diagnostic=DIAGNOSTIC, ref_status=134,
                          ref_diagnostic='qbe: dying: alloc too large')
    def test_reference_status_must_match(self):
        self.check_status(1, diagnostic=DIAGNOSTIC, ref_status=1,
                          ref_diagnostic=DIAGNOSTIC)
    def test_internal_compiler_abort_is_failure(self):
        self.check_status(134, diagnostic=DIAGNOSTIC, ref_status=134, ref_diagnostic=DIAGNOSTIC)
    def test_unlisted_matching_error_is_failure(self):
        self.check_status(1, diagnostic='qbe: dying: internal compiler failure', ref_status=134,
                          ref_diagnostic='qbe: dying: internal compiler failure')
    def test_extra_stderr_is_not_approved(self):
        self.check_status(1, diagnostic=DIAGNOSTIC + '\nextra diagnostic', ref_status=134,
                          ref_diagnostic=DIAGNOSTIC)
    def test_missing_reference_fails_closed(self): self.check_status(0, reference='missing')
    def test_unexecutable_reference_fails_closed(self): self.check_status(0, reference='unexecutable')


if __name__ == '__main__':
    unittest.main()
