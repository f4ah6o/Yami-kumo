"""In-memory/fake-process supervisor checks; these tests never spawn a process."""

import importlib.util
import hashlib
from pathlib import Path
import subprocess
import time
import unittest
from unittest import mock


SCRIPT = Path(__file__).resolve().parents[2] / "scripts" / "measure_button_phases.py"
SPEC = importlib.util.spec_from_file_location("measure_button_phases", SCRIPT)
SUPERVISOR = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(SUPERVISOR)


class FakeProcess:
    pid = 43210
    stdout = None
    stderr = None

    def __init__(self):
        self.returncode = None
        self.wait_calls = 0
        self.kill_calls = 0

    def poll(self):
        return self.returncode

    def wait(self, timeout=None):
        self.wait_calls += 1
        self.returncode = 0
        return 0

    def kill(self):
        self.kill_calls += 1
        self.returncode = -9


class FailingReceipts:
    def checkpoint(self, _record):
        raise OSError("injected receipt write failure")


class SupervisorInertTests(unittest.TestCase):
    def test_node_retention_error_is_preserved_from_cli_json(self):
        raw = (b"noise\n"
               b'{"status":"unverified","cases":0,"retention_error":{'
               b'"code":"ENOSPC","stage":"reserve_evidence_files","run_token":"abc"}}\n')
        parsed = SUPERVISOR.parse_node_summary(raw)
        self.assertEqual(parsed["retention_error"]["code"], "ENOSPC")
        self.assertEqual(parsed["retention_error"]["stage"], "reserve_evidence_files")

    def test_outer_log_capture_hashes_raw_bytes_and_marks_overflow(self):
        raw = bytes([0x00, 0xff, 0x80, 0x0a, 0x42])
        kept = raw[:4]
        capture = SUPERVISOR.RawCapture(99, capacity=4)
        with mock.patch.object(SUPERVISOR, "write_all") as write, \
             mock.patch.object(SUPERVISOR.os, "fsync"), \
             mock.patch.object(SUPERVISOR.os, "ftruncate") as truncate, \
             mock.patch.object(SUPERVISOR, "read_exact", return_value=kept):
            capture.append(raw)
            metadata = capture.finalize()
        self.assertEqual(write.call_args.args[1], kept)
        self.assertEqual(truncate.call_args.args[1], len(kept))
        self.assertEqual(metadata["observed_length"], len(raw))
        self.assertEqual(metadata["retained_length"], len(kept))
        self.assertEqual(metadata["sha256"], hashlib.sha256(raw).hexdigest())
        self.assertEqual(metadata["retained_sha256"], hashlib.sha256(kept).hexdigest())
        self.assertTrue(metadata["truncated"])
        self.assertFalse(metadata["verified"])

    def test_post_popen_receipt_failure_stops_and_reaps_only_fresh_group(self):
        child = FakeProcess()
        record = {"status": "unverified"}
        popen = mock.Mock(return_value=child)
        with mock.patch.object(SUPERVISOR.os, "getpgid", return_value=child.pid), \
             mock.patch.object(SUPERVISOR, "group_exists", side_effect=[False, False, False]), \
             mock.patch.object(SUPERVISOR, "signal_owned_group", return_value=True) as signal_group:
            with self.assertRaisesRegex(OSError, "injected receipt"):
                SUPERVISOR.launch_and_record(["node", "fake"], Path("/tmp"), {}, record,
                                             FailingReceipts(), popen_factory=popen)
        popen.assert_called_once()
        self.assertEqual(child.wait_calls, 1)
        signal_group.assert_called_once_with(child.pid, SUPERVISOR.signal.SIGTERM)
        self.assertEqual(record["process_group"], child.pid)
        self.assertTrue(record["owned_group_gone"])
        self.assertEqual(record["status"], "unverified")

    def test_post_popen_cleanup_error_keeps_group_state_conservative(self):
        child = FakeProcess()
        record = {"status": "unverified"}
        with mock.patch.object(SUPERVISOR.os, "getpgid", return_value=child.pid), \
             mock.patch.object(SUPERVISOR, "stop_and_reap", side_effect=OSError("injected cleanup failure")):
            with self.assertRaisesRegex(OSError, "injected receipt"):
                SUPERVISOR.launch_and_record(["node", "fake"], Path("/tmp"), {}, record,
                                             FailingReceipts(), popen_factory=mock.Mock(return_value=child))
        self.assertFalse(record["owned_group_gone"])
        self.assertEqual(record["group_cleanup_error"], "injected cleanup failure")

    def test_signal_and_timeout_paths_are_injectable_without_spawning(self):
        out_read, out_write = SUPERVISOR.os.pipe()
        err_read, err_write = SUPERVISOR.os.pipe()
        child = FakeProcess()
        child.stdout = SUPERVISOR.os.fdopen(out_read, "rb", buffering=0)
        child.stderr = SUPERVISOR.os.fdopen(err_read, "rb", buffering=0)
        captures = (object(), object())
        try:
            with self.assertRaisesRegex(InterruptedError, "injected signal"):
                SUPERVISOR.monitor_owned(child, captures, lambda: "injected signal", time.monotonic() + 10)
            with self.assertRaisesRegex(TimeoutError, "deadline expired"):
                SUPERVISOR.monitor_owned(child, captures, lambda: None, time.monotonic() - 1)
        finally:
            child.stdout.close()
            child.stderr.close()
            SUPERVISOR.os.close(out_write)
            SUPERVISOR.os.close(err_write)


if __name__ == "__main__":
    unittest.main()
