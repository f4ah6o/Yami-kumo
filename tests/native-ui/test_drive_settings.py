"""Regression tests for the Shared Settings lane evidence helpers.

The Windows input path itself is exercised only by the real-device lane. These
tests cover marker decoding, transport classification and the retained report
so a driver refactor cannot silently relabel a key-path run as an IMM commit.
"""

from __future__ import annotations

import importlib.util
import os
import pathlib
import sys
import unittest
from unittest.mock import patch

sys.dont_write_bytecode = True

DRIVER_PATH = pathlib.Path(__file__).with_name("drive_settings.py")
SPEC = importlib.util.spec_from_file_location("yami_settings_driver", DRIVER_PATH)
assert SPEC is not None and SPEC.loader is not None
driver = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = driver
SPEC.loader.exec_module(driver)


class MarkerTests(unittest.TestCase):
    def test_frame_marker_is_decoded(self):
        self.assertEqual(
            driver.parse_marker('YAMI_NATIVE_UI_SETTINGS {"phase":"frame","name":"abc"}'),
            {"phase": "frame", "name": "abc"},
        )

    def test_non_marker_lines_are_ignored(self):
        self.assertIsNone(driver.parse_marker("# settings-lane environment"))
        self.assertIsNone(driver.parse_marker("Settings started\n"))

    def test_invalid_json_is_rejected(self):
        with self.assertRaises(driver.SettingsError):
            driver.parse_marker("YAMI_NATIVE_UI_SETTINGS {oops}")


class TransportTests(unittest.TestCase):
    def test_commit_wins_over_a_later_key_event(self):
        markers = [
            {"phase": "text", "status": "started", "transport": "imm32"},
            {"phase": "commit", "text": "abc"},
            {"phase": "key", "key": "character"},
        ]
        self.assertEqual(driver.classify_text_transport(markers), "imm32-commit")

    def test_key_path_is_recorded_when_the_route_is_unavailable(self):
        markers = [
            {
                "phase": "text",
                "status": "unavailable",
                "operation": "begin_text_input",
            },
            {"phase": "key", "key": "character"},
        ]
        self.assertEqual(driver.classify_text_transport(markers), "key-character")

    def test_no_text_evidence_is_not_a_transport(self):
        self.assertIsNone(driver.classify_text_transport([{"phase": "frame"}]))

    def test_summary_keeps_transport_markers_and_drops_frames(self):
        summary = driver.text_marker_summary(
            [
                {"phase": "frame", "name": "abc"},
                {
                    "phase": "text",
                    "status": "started",
                    "transport": "imm32",
                    "epoch": 3,
                },
                {"phase": "commit", "text": "abc"},
            ]
        )
        self.assertEqual(
            summary,
            [
                {
                    "phase": "text",
                    "status": "started",
                    "transport": "imm32",
                    "epoch": 3,
                },
                {"phase": "commit", "text": "abc"},
            ],
        )


class LinuxTransportTests(unittest.TestCase):
    def test_direct_keyboard_is_not_relabelled_as_imm(self):
        markers = [{"phase": "text", "status": "key-path", "route": "direct-keyboard"},
                   {"phase": "key", "key": "character"}]
        self.assertEqual(driver.classify_text_transport(markers, "linux"), "direct-keyboard")

    def test_linux_portable_commit_is_not_imm(self):
        self.assertEqual(driver.classify_text_transport([{"phase": "commit", "text": "abc"}], "linux"),
                         "text-input-v1-commit")

    def test_keyboard_marker_without_armed_route_is_not_linux_text_evidence(self):
        self.assertIsNone(driver.classify_text_transport([{"phase": "key", "key": "character"}], "linux"))


class FreshFrameTests(unittest.TestCase):
    def test_old_dialog_frame_cannot_satisfy_reopen(self):
        output = driver.Output.__new__(driver.Output)
        output.frames = [{"dialog": True}]
        with self.assertRaises(driver.SettingsError):
            output.wait_frame(lambda f: f.get("dialog"), 0, after=1)


class ReportTests(unittest.TestCase):
    def frames(self):
        return {
            "typed": {
                "phase": "frame",
                "name": "abc",
                "dialog": False,
                "status": "editing",
            },
            "dialog": {
                "phase": "frame",
                "name": "abc",
                "dialog": True,
                "status": "editing",
            },
            "saved": {
                "phase": "frame",
                "name": "abc",
                "dialog": False,
                "status": "saved",
            },
        }

    def pass_report(self, transport: str):
        return driver.build_pass_report(
            platform="windows",
            candidate="a" * 40,
            frames=self.frames(),
            transport=transport,
            markers=[
                {"phase": "text", "status": "started", "transport": "imm32"},
            ],
            details={"platform": "Windows"},
            started="2026-10-22T00:00:00+00:00",
            command=["windows.exe", "--settings-e2e"],
        )

    def test_pass_report_names_the_result_and_transport(self):
        report = self.pass_report("imm32-commit")
        self.assertEqual(report["schemaVersion"], "settings-lane/v1")
        self.assertEqual(report["fixtureId"], "settings-flow")
        self.assertEqual(report["status"], "pass")
        self.assertEqual(
            report["result"],
            {"name": "abc", "dialog": True, "status": "saved"},
        )
        self.assertEqual(report["textTransport"], "imm32-commit")
        self.assertEqual(report["claims"]["settings.text"], "PASS (IMM32 commit)")
        self.assertEqual(report["claims"]["settings.ime"], "NOT_RUN")
        self.assertEqual(report["claims"]["settings.ax"], "NOT_RUN")

    def test_key_path_report_does_not_claim_imm(self):
        report = self.pass_report("key-character")
        self.assertEqual(
            report["claims"]["settings.text"],
            "PASS (WM_CHAR key path, no IME engine)",
        )

    def test_fail_report_retains_markers_and_exit(self):
        report = driver.build_fail_report(
            platform="windows",
            candidate="b" * 40,
            error="timed out waiting for frame",
            markers=[{"phase": "text", "status": "started"}],
            exit_marker={"phase": "exit", "reason": "tick-limit", "ticks": 6000},
            details={"platform": "Windows"},
            started="2026-10-22T00:00:00+00:00",
            command=["windows.exe", "--settings-e2e"],
        )
        self.assertEqual(report["status"], "fail")
        self.assertEqual(report["reason"], report["error"])
        self.assertEqual(report["sampleExit"]["reason"], "tick-limit")
        self.assertEqual(
            report["textMarkers"],
            [{"phase": "text", "status": "started"}],
        )


class CandidateTests(unittest.TestCase):
    def test_explicit_candidate_bound_by_the_lane_wins(self):
        with patch.dict(
            os.environ,
            {"YAMI_SHARED_UI_CANDIDATE_SHA": "c" * 40},
            clear=False,
        ):
            self.assertEqual(driver.candidate_sha(), "c" * 40)


class EnvironmentLineTests(unittest.TestCase):
    def test_header_lists_environment(self):
        lines = driver.environment_lines(
            {"platform": "Windows", "moon": ["moon 1", "moonc 1"]}
        )
        self.assertEqual(lines[0], "# settings-lane environment")
        self.assertIn("# platform: Windows", lines)
        self.assertIn("# moon: moon 1 | moonc 1", lines)

    def test_missing_values_are_skipped(self):
        self.assertEqual(len(driver.environment_lines({})), 1)


if __name__ == "__main__":
    unittest.main()
