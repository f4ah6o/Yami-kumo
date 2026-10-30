"""Opt-in local control transport; this does not test an IME or host lifetime."""
from __future__ import annotations

import ctypes
import os
from pathlib import Path
import socket
import stat
import struct
import subprocess
import sys
import tempfile
import time
import unittest


@unittest.skipUnless(os.name == "posix" and hasattr(socket, "SO_PEERCRED"), "Linux Unix sockets required")
class ControlSocketTests(unittest.TestCase):
    def setUp(self) -> None:
        self.build = tempfile.TemporaryDirectory(prefix="settings-control-test-")
        library = Path(self.build.name) / "control.so"
        self.library = library
        source = Path(__file__).resolve().parents[2] / "native/examples/ubuntu/control_socket.c"
        subprocess.run(
            ["cc", "-std=c11", "-Wall", "-Wextra", "-Werror", "-fPIC", "-shared", str(source), "-o", str(library)],
            check=True, capture_output=True,
        )
        self.lib = ctypes.CDLL(str(library))
        self.lib.gpui_settings_control_path.restype = ctypes.c_char_p
        self.lib.gpui_settings_control_next.argtypes = [ctypes.c_int]
        self.lib.gpui_settings_control_reply.argtypes = [ctypes.c_int]
        self.lib.gpui_settings_control_sequence.restype = ctypes.c_int64
        self.lib.gpui_settings_control_reply_sequence.argtypes = [ctypes.c_int, ctypes.c_int64]
        self.assertEqual(self.lib.gpui_settings_control_open(), 0)
        self.path = Path(os.fsdecode(self.lib.gpui_settings_control_path()))

    def tearDown(self) -> None:
        self.lib.gpui_settings_control_close()
        self.assertFalse(self.path.exists())
        self.assertFalse(self.path.parent.exists())
        self.build.cleanup()

    def test_private_address_one_byte_request_and_disconnect(self) -> None:
        self.assertEqual(stat.S_IMODE(self.path.parent.stat().st_mode), 0o700)
        self.assertEqual(self.path.parent.stat().st_uid, os.geteuid())
        self.assertEqual(self.lib.gpui_settings_control_next(0), 0)
        with socket.socket(socket.AF_UNIX) as peer:
            peer.settimeout(2)
            peer.connect(str(self.path))
            peer.sendall(b"status-is-one-byte")
            self.assertEqual(self.lib.gpui_settings_control_next(0), ord("s"))
            self.lib.gpui_settings_control_reply(ord("S"))
            self.assertEqual(peer.recv(16), b"S")
            # Closing with unread excess bytes may produce an EOF or reset.
            try:
                self.assertEqual(peer.recv(16), b"")
            except ConnectionResetError:
                pass
        self.assertEqual(self.lib.gpui_settings_control_next(0), 0)

    def test_idle_client_has_bounded_request_time(self) -> None:
        with socket.socket(socket.AF_UNIX) as peer:
            peer.connect(str(self.path))
            started = time.monotonic()
            self.assertEqual(self.lib.gpui_settings_control_next(0), 0)
            self.assertLess(time.monotonic() - started, 2.5)
            self.assertEqual(peer.recv(1), b"")
        # The listener remains usable after a disconnected or idle client.
        with socket.socket(socket.AF_UNIX) as peer:
            peer.connect(str(self.path))
            peer.sendall(b"s")
            self.assertEqual(self.lib.gpui_settings_control_next(0), ord("s"))
            self.lib.gpui_settings_control_reply(ord("S"))
            self.assertEqual(peer.recv(1), b"S")

    def test_double_open_and_invalid_wait_fail_closed(self) -> None:
        self.assertEqual(self.lib.gpui_settings_control_open(), -1)
        self.assertEqual(self.lib.gpui_settings_control_next(-1), -1)
        self.assertEqual(self.lib.gpui_settings_control_next(30001), -1)
        self.assertTrue(self.path.exists())

    def test_disconnected_pending_request_is_not_executed(self) -> None:
        peer = socket.socket(socket.AF_UNIX)
        peer.connect(str(self.path))
        peer.sendall(b"a" + struct.pack("!q", 12))
        peer.close()
        self.assertEqual(self.lib.gpui_settings_control_next(2000), 0)
        with socket.socket(socket.AF_UNIX) as next_peer:
            next_peer.connect(str(self.path))
            next_peer.sendall(b"s")
            self.assertEqual(self.lib.gpui_settings_control_next(2000), ord("s"))
            self.lib.gpui_settings_control_reply(ord("S"))
            self.assertEqual(next_peer.recv(1), b"S")

    def test_client_can_send_status_without_transferring_owner(self) -> None:
        script = Path(__file__).resolve().parents[2] / "scripts/settings_retained_control.py"
        proc = subprocess.Popen(
            [sys.executable, str(script), str(self.path), "status"],
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True,
        )
        self.assertEqual(self.lib.gpui_settings_control_next(2000), ord("s"))
        self.lib.gpui_settings_control_reply_sequence(ord("S"), 12)
        stdout, stderr = proc.communicate(timeout=3)
        self.assertEqual(proc.returncode, 0, stderr)
        self.assertIn("owner and host retained", stdout)
        self.assertIn("next text sequence: 12", stdout)

    def test_apply_request_carries_exact_positive_sequence(self) -> None:
        with socket.socket(socket.AF_UNIX) as peer:
            peer.connect(str(self.path))
            peer.sendall(b"a" + struct.pack("!q", 42))
            self.assertEqual(self.lib.gpui_settings_control_next(2000), ord("a"))
            self.assertEqual(self.lib.gpui_settings_control_sequence(), 42)
            self.lib.gpui_settings_control_reply(ord("M"))
            self.assertEqual(peer.recv(1), b"M")
        with socket.socket(socket.AF_UNIX) as peer:
            peer.connect(str(self.path))
            peer.sendall(b"a" + struct.pack("!q", 0))
            self.assertEqual(self.lib.gpui_settings_control_next(2000), 0)
            self.assertEqual(peer.recv(1), b"")

    def test_new_process_uses_fresh_socket_and_does_not_reuse_owner(self) -> None:
        code = (
            "import ctypes,sys; lib=ctypes.CDLL(sys.argv[1]); "
            "lib.gpui_settings_control_path.restype=ctypes.c_char_p; "
            "assert lib.gpui_settings_control_open()==0; "
            "print(lib.gpui_settings_control_path().decode(),flush=True); "
            "lib.gpui_settings_control_close()"
        )
        result = subprocess.run(
            [sys.executable, "-c", code, str(self.library)],
            check=True, capture_output=True, text=True,
        )
        other = Path(result.stdout.splitlines()[-1])
        self.assertNotEqual(other, self.path)
        self.assertFalse(other.exists())
        self.assertTrue(self.path.exists())

    def test_reopen_in_same_process_uses_fresh_directory(self) -> None:
        previous = self.path
        self.lib.gpui_settings_control_close()
        self.assertFalse(previous.exists())
        self.assertFalse(previous.parent.exists())
        self.assertEqual(self.lib.gpui_settings_control_open(), 0)
        self.path = Path(os.fsdecode(self.lib.gpui_settings_control_path()))
        self.assertNotEqual(self.path, previous)
        self.assertTrue(self.path.exists())


if __name__ == "__main__":
    unittest.main()
