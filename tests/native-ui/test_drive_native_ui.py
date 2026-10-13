"""Regression tests for the independent native-frame proof oracle."""

from __future__ import annotations

import importlib.util
import json
import pathlib
import subprocess
import tempfile
import unittest
from unittest.mock import Mock, patch

import sys
sys.dont_write_bytecode = True

DRIVER_PATH = pathlib.Path(__file__).with_name("drive_native_ui.py")
SPEC = importlib.util.spec_from_file_location("yami_native_ui_driver", DRIVER_PATH)
assert SPEC is not None and SPEC.loader is not None
driver = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = driver
SPEC.loader.exec_module(driver)


class NativeFrameVerifierTests(unittest.TestCase):
    width = 40
    height = 40
    button = {"x": 20, "y": 20, "width": 10, "height": 10}
    button_label = {"x": 22, "y": 23, "width": 6, "height": 4}
    counter = {"x": 4, "y": 4, "width": 10, "height": 10}

    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory(prefix="yami-native-ui-verifier-")
        self.directory = pathlib.Path(self.temporary.name)

    def tearDown(self) -> None:
        self.temporary.cleanup()

    def _pixels(
        self,
        *,
        glyph: tuple[int, int] | None,
        button_color: tuple[int, int, int],
        button_label: bool = True,
        button_border: bool = False,
    ) -> bytearray:
        pixels = bytearray([255] * (self.width * self.height * 3))
        for y in range(20, 30):
            for x in range(20, 30):
                offset = (y * self.width + x) * 3
                pixels[offset : offset + 3] = bytes(button_color)
        if glyph is not None:
            x, y = glyph
            offset = (y * self.width + x) * 3
            pixels[offset : offset + 3] = b"\x00\x00\x00"
        if button_label:
            offset = (25 * self.width + 24) * 3
            pixels[offset : offset + 3] = b"\xff\xff\xff"
        if button_border:
            for position in range(20, 30):
                for x, y in ((position, 20), (position, 29)):
                    offset = (y * self.width + x) * 3
                    pixels[offset : offset + 3] = b"\xff\xff\xff"
                for x, y in ((20, position), (29, position)):
                    offset = (y * self.width + x) * 3
                    pixels[offset : offset + 3] = b"\xff\xff\xff"
        return pixels

    def _write(self, name: str, pixels: bytearray) -> str:
        path = self.directory / name
        header = f"P6\n{self.width} {self.height}\n255\n".encode()
        path.write_bytes(header + pixels)
        return name

    def _marker(self, name: str, count: int, frame_path: str | None, **updates: object) -> dict:
        frame = {
            "path": frame_path,
            "width": self.width,
            "height": self.height,
            "scale": 1.0,
        }
        marker = {
            "count": count,
            "value": count,
            "scene": {"version": 1, "items": []},
            "frame": frame,
            "viewport": {"width": self.width, "height": self.height, "scale": 1.0},
            "textPixels": 1,
            "buttonPixels": 100,
            "button": self.button,
            "buttonLabel": self.button_label,
            "counter": self.counter,
        }
        marker.update(updates)
        return marker

    def _assert_frame_pair(self, before_pixels: bytearray, after_pixels: bytearray) -> dict:
        before_path = self._write("before.ppm", before_pixels)
        after_path = self._write("after.ppm", after_pixels)
        before = self._marker("before", 0, before_path)
        after = self._marker("after", 1, after_path)
        ready = {"button": self.button, "buttonLabel": self.button_label, "counter": self.counter}
        return driver._assert_frames(before, after, ready, self.directory)

    def test_visible_text_button_and_counter_change_pass(self) -> None:
        before = self._pixels(glyph=(6, 6), button_color=(70, 110, 190))
        after = self._pixels(glyph=(7, 6), button_color=(70, 110, 190))
        report = self._assert_frame_pair(before, after)
        self.assertEqual(report["changedCounterPixels"], 2)
        self.assertGreater(report["buttonForegroundPixels"][0], 0)

    def test_blank_counter_text_is_rejected_even_when_button_is_visible(self) -> None:
        before = self._pixels(glyph=None, button_color=(70, 110, 190))
        after = self._pixels(glyph=None, button_color=(70, 110, 190))
        with self.assertRaisesRegex(driver.E2EError, "Text component has no foreground pixels"):
            self._assert_frame_pair(before, after)

    def test_button_change_does_not_substitute_for_counter_change(self) -> None:
        before = self._pixels(glyph=(6, 6), button_color=(70, 110, 190))
        after = self._pixels(glyph=(6, 6), button_color=(190, 90, 70))
        with self.assertRaisesRegex(driver.E2EError, "did not change pixels in the counter text"):
            self._assert_frame_pair(before, after)

    def test_border_only_button_without_label_is_rejected(self) -> None:
        before = self._pixels(
            glyph=(6, 6), button_color=(70, 110, 190), button_label=False, button_border=True
        )
        after = self._pixels(
            glyph=(7, 6), button_color=(70, 110, 190), button_label=False, button_border=True
        )
        with self.assertRaisesRegex(driver.E2EError, "Button label has no pixels"):
            self._assert_frame_pair(before, after)

    def test_missing_scene_or_malformed_scene_is_rejected(self) -> None:
        missing = self._marker("missing", 0, "unused.ppm")
        del missing["scene"]
        with self.assertRaisesRegex(driver.E2EError, "canonical scene object"):
            driver._marker_state(missing, 0)

        malformed = self._marker("malformed", 0, "unused.ppm", scene="not-json-object")
        with self.assertRaisesRegex(driver.E2EError, "canonical scene object"):
            driver._marker_state(malformed, 0)

    def test_missing_capture_path_or_dimensions_is_rejected(self) -> None:
        missing_path = self._marker("missing-path", 0, None)
        with self.assertRaisesRegex(driver.E2EError, "must include a PPM path"):
            driver._read_ppm_path(missing_path["frame"], self.directory, "before")

        missing_dimensions = self._marker("missing-dimensions", 0, "unused.ppm")
        del missing_dimensions["frame"]["width"]
        with self.assertRaisesRegex(driver.E2EError, "width, height, and scale"):
            driver._marker_state(missing_dimensions, 0)

    def test_truncated_native_capture_is_rejected(self) -> None:
        capture = self.directory / "truncated.ppm"
        capture.write_bytes(b"P6\n40 40\n255\n\x00\x00")
        with self.assertRaisesRegex(driver.E2EError, "raster size mismatch"):
            driver.read_ppm(capture)


class NativeLaunchPlanTests(unittest.TestCase):
    def test_each_host_builds_the_workspace_package_then_runs_its_binary(self) -> None:
        module_root = pathlib.Path("/workspace/yami/native")
        target_dir = pathlib.Path("/workspace/temp-target")
        cases = {
            "macos": "macos",
            "linux": "ubuntu",
            "windows": "windows",
        }
        for host, package_name in cases.items():
            with self.subTest(host=host):
                package = module_root / "examples" / package_name
                plan = driver._native_run_plan(
                    ["moon", "run", str(package), "--target", "native"],
                    host,
                    module_root,
                    target_dir,
                )
                self.assertIsNotNone(plan)
                build_command, executable = plan
                self.assertEqual(build_command[1], "build")
                self.assertEqual(build_command[2], str(package.resolve()))
                self.assertIn("--target-dir", build_command)
                self.assertEqual(
                    executable,
                    target_dir
                    / "native/debug/build/f4ah6o/yami_kumo_native/examples"
                    / package_name
                    / f"{package_name}.exe",
                )

    def test_unexpected_package_or_command_shape_is_rejected(self) -> None:
        module_root = pathlib.Path("/workspace/yami/native")
        target_dir = pathlib.Path("/workspace/temp-target")
        with self.assertRaisesRegex(driver.E2EError, "must launch"):
            driver._native_run_plan(
                ["moon", "run", "/tmp/unrelated", "--target", "native"],
                "macos",
                module_root,
                target_dir,
            )
        with self.assertRaisesRegex(driver.E2EError, "must be"):
            driver._native_run_plan(
                ["moon", "run", str(module_root / "examples/macos"), "--target", "wasm"],
                "macos",
                module_root,
                target_dir,
            )


class MacHostInputTests(unittest.TestCase):
    def test_compiles_existing_ax_client_as_host_input_helper(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            evidence = pathlib.Path(directory)
            with patch.object(
                driver.subprocess,
                "run",
                side_effect=[
                    subprocess.CompletedProcess([], 0, "compiled"),
                    subprocess.CompletedProcess([], 0, "guard fixtures passed"),
                ],
            ) as run:
                helper = driver._compile_macos_input_helper(evidence)
            self.assertTrue((evidence / "macos-host-input-helper-build.log").is_file())
            self.assertIn(
                "guard fixtures passed",
                (evidence / "macos-host-input-guard-fixtures.log").read_text(),
            )

        self.assertEqual(helper.name, "macos_host_input")
        argv = run.call_args_list[0].args[0]
        self.assertTrue(any(item.endswith("macos_ax_client.m") for item in argv))
        self.assertIn("CoreGraphics", argv)
        self.assertIn("-Werror", argv)
        self.assertEqual(run.call_args_list[1].args[0], [str(helper), "--guard-fixtures"])
        self.assertEqual(run.call_args_list[1].kwargs["timeout"], 5.0)

    def test_locked_or_unknown_session_fails_preflight_before_launch(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = pathlib.Path(directory)
            args = type("Args", (), {
                "command": ["moon", "run", "/workspace/native/examples/macos", "--target", "native"],
                "platform": "macos", "evidence_dir": root / "evidence", "log": root / "native.log",
                "window_title": "Yami Native UI", "startup_timeout": 1.0, "marker_timeout": 1.0,
            })()
            with patch.dict("os.environ", {"YAMI_NATIVE_WORKSPACE_ROOT": str(root)}), \
                    patch.object(driver, "_compile_macos_input_helper", return_value=root / "helper"), \
                    patch.object(driver, "_macos_input_preflight", side_effect=driver.E2EBlocked("locked")), \
                    patch.object(driver, "_build_native_sample") as build, \
                    patch.object(driver.subprocess, "Popen") as launch:
                with self.assertRaisesRegex(driver.E2EBlocked, "locked"):
                    driver.drive(args)
            build.assert_not_called()
            launch.assert_not_called()
            report = json.loads((root / "evidence/native-ui-report.json").read_text())
            self.assertEqual(report["status"], "blocked")
            self.assertFalse(report["sampleLaunched"])

    def test_preflight_accepts_only_authorized_unlocked_console(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            evidence = pathlib.Path(directory)
            helper = evidence / "helper"
            allowed = subprocess.CompletedProcess(
                [], 0, json.dumps({"accessibility": True, "on_console": True,
                                   "session_locked": False}), "")
            with patch.object(driver.subprocess, "run", return_value=allowed) as run:
                status = driver._macos_input_preflight(helper, evidence)
            self.assertTrue(status["accessibility"])
            self.assertEqual(run.call_args.args[0], [str(helper), "--preflight"])
            self.assertEqual(run.call_args.kwargs["timeout"], driver.MACOS_PREFLIGHT_TIMEOUT_SECONDS)

            locked = subprocess.CompletedProcess(
                [], 78, json.dumps({"accessibility": True, "on_console": True,
                                    "session_locked": True}), "")
            with patch.object(driver.subprocess, "run", return_value=locked):
                with self.assertRaisesRegex(driver.E2EBlocked, "refused UI input"):
                    driver._macos_input_preflight(helper, evidence)
            self.assertTrue(json.loads(
                (evidence / "macos-host-input-preflight.json").read_text()
            )["session_locked"])

    def test_click_and_escape_use_external_helper_and_validate_identity(self) -> None:
        args = type("Args", (), {
            "macos_helper": pathlib.Path("/tmp/helper"), "sample_pid": 123,
            "window_title": "Yami Native UI [native-ui-abc]",
        })()
        click_report = {
            "action": "CGEventPost(kCGHIDEventTap) left click", "pid": 123,
            "windowTitle": args.window_title, "button": "Click me", "windowNumber": 42,
            "point": {"x": 64.5, "y": 90.5}, "axHitWithinButton": True,
            "downPostedGlobally": True, "upPostedGlobally": True, "releaseOutcome": "global",
            "eventFlags": {"downInherited": 8, "downBeforePost": 0,
                           "upInherited": 0, "upBeforePost": 0},
        }
        click_process = Mock()
        click_process.communicate.return_value = (json.dumps(click_report), "")
        click_process.returncode = 0
        with patch.object(driver.subprocess, "Popen", return_value=click_process) as run:
            driver._send_click("macos", {"button": {"x": 0, "y": 0, "width": 120, "height": 36}}, args)
        self.assertEqual(run.call_args.args[0][1:5], ["--click", "123", args.window_title, "Click me"])
        self.assertEqual(run.call_args.args[0][5:], ["120.0", "36.0"])
        self.assertEqual(
            click_process.communicate.call_args.kwargs["timeout"],
            driver.MACOS_HELPER_TIMEOUT_SECONDS,
        )

        escape_report = {
            "action": "CGEventPost(kCGHIDEventTap) Escape", "pid": 123,
            "windowTitle": args.window_title, "upPostedGlobally": True,
            "downPostedGlobally": True,
            "releaseOutcome": "global", "originalWindowGone": False,
            "eventFlags": {"downInherited": 0, "downBeforePost": 0,
                           "upInherited": 0, "upBeforePost": 0},
        }
        escape_process = Mock()
        escape_process.communicate.return_value = (json.dumps(escape_report), "")
        escape_process.returncode = 0
        with patch.object(driver.subprocess, "Popen", return_value=escape_process) as run:
            driver._send_escape("macos", args)
        self.assertEqual(run.call_args.args[0], ["/tmp/helper", "--escape", "123", args.window_title])

        mismatched = dict(click_report, pid=999)
        mismatch_process = Mock()
        mismatch_process.communicate.return_value = (json.dumps(mismatched), "")
        mismatch_process.returncode = 0
        with patch.object(driver.subprocess, "Popen", return_value=mismatch_process):
            with self.assertRaisesRegex(driver.E2EError, "launched PID"):
                driver._send_click("macos", {"button": {"x": 0, "y": 0, "width": 120, "height": 36}}, args)

        bad_flags = dict(click_report, eventFlags={"downBeforePost": 1, "upBeforePost": 0})
        bad_flags_process = Mock()
        bad_flags_process.communicate.return_value = (json.dumps(bad_flags), "")
        bad_flags_process.returncode = 0
        with patch.object(driver.subprocess, "Popen", return_value=bad_flags_process):
            with self.assertRaisesRegex(driver.E2EError, "nonzero downBeforePost"):
                driver._send_click("macos", {"button": {"x": 0, "y": 0, "width": 120, "height": 36}}, args)

    def test_hung_helper_is_terminated_and_reported_as_failure(self) -> None:
        args = type("Args", (), {
            "macos_helper": pathlib.Path("/tmp/helper"), "sample_pid": 123,
            "window_title": "Yami Native UI [native-ui-abc]",
        })()
        process = Mock()
        process.communicate.side_effect = [
            subprocess.TimeoutExpired(["/tmp/helper"], driver.MACOS_HELPER_TIMEOUT_SECONDS),
            ("", "helper stopped after termination request"),
        ]
        process.returncode = -15
        with patch.object(driver.subprocess, "Popen", return_value=process):
            with self.assertRaisesRegex(driver.E2EError, "exceeded its execution deadline"):
                driver._send_click(
                    "macos", {"button": {"x": 0, "y": 0, "width": 120, "height": 36}}, args
                )
        process.terminate.assert_called_once_with()
        self.assertEqual(process.communicate.call_count, 2)

    def test_escape_pid_release_requires_terminal_evidence_and_zero_flags(self) -> None:
        args = type("Args", (), {
            "macos_helper": pathlib.Path("/tmp/helper"), "sample_pid": 123,
            "window_title": "Yami Native UI [native-ui-abc]",
        })()
        report = {
            "action": "CGEventPost(kCGHIDEventTap) Escape", "pid": 123,
            "windowTitle": args.window_title, "upPostedGlobally": False,
            "downPostedGlobally": True,
            "releaseOutcome": "target-pid", "originalWindowGone": True,
            "eventFlags": {"downInherited": 8, "downBeforePost": 0,
                           "upInherited": 0, "upBeforePost": 0,
                           "cleanupInherited": 0, "cleanupBeforePost": 0},
        }
        process = Mock()
        process.communicate.return_value = (json.dumps(report), "")
        process.returncode = 0
        with patch.object(driver.subprocess, "Popen", return_value=process):
            accepted = driver._run_macos_input_helper(
                args, ["--escape", "123", args.window_title], report["action"]
            )
        self.assertEqual(accepted["releaseOutcome"], "target-pid")

        report["originalWindowGone"] = False
        process = Mock()
        process.communicate.return_value = (json.dumps(report), "")
        process.returncode = 0
        with patch.object(driver.subprocess, "Popen", return_value=process):
            with self.assertRaisesRegex(driver.E2EError, "without a terminal window"):
                driver._run_macos_input_helper(
                    args, ["--escape", "123", args.window_title], report["action"]
                )

    def test_helper_timeout_writes_failed_report_after_sample_cleanup(self) -> None:
        class FakeOutput:
            def __init__(self, *_args: object):
                self.log = Mock()

            def wait_marker(self, marker: str, **_kwargs: object) -> dict:
                if marker == "YAMI_NATIVE_UI_READY":
                    return {
                        "button": {"x": 20, "y": 20, "width": 120, "height": 36},
                        "buttonLabel": {"x": 40, "y": 30, "width": 40, "height": 10},
                        "counter": {"x": 4, "y": 4, "width": 10, "height": 10},
                    }
                return {"count": 0}

            def drain(self) -> None:
                pass

            def close(self) -> None:
                pass

        class FakeProcess:
            pid = 456
            stdout = None

            def __init__(self):
                self.status = None
                self.terminated = False

            def poll(self):
                return self.status

            def terminate(self):
                self.terminated = True

            def wait(self, timeout: float):
                self.status = -15
                return self.status

            def kill(self):
                self.status = -9

        with tempfile.TemporaryDirectory() as directory:
            root = pathlib.Path(directory)
            evidence = root / "evidence"
            sample = FakeProcess()
            args = type("Args", (), {
                "command": ["moon", "run", "/workspace/native/examples/macos", "--target", "native"],
                "platform": "macos", "evidence_dir": evidence, "log": root / "sample.log",
                "window_title": "Yami Native UI", "startup_timeout": 1.0, "marker_timeout": 1.0,
            })()
            with patch.dict("os.environ", {"YAMI_NATIVE_WORKSPACE_ROOT": str(root)}), \
                    patch.object(driver, "_compile_macos_input_helper", return_value=root / "helper"), \
                    patch.object(driver, "_macos_input_preflight", return_value={"accessibility": True, "on_console": True, "session_locked": False}), \
                    patch.object(driver, "_build_native_sample", return_value=(["sample"], None)), \
                    patch.object(driver.subprocess, "Popen", return_value=sample), \
                    patch.object(driver, "ProcessOutput", FakeOutput), \
                    patch.object(driver, "_marker_state"), \
                    patch.object(driver, "_send_click", side_effect=driver.E2EError("helper exceeded deadline")):
                with self.assertRaisesRegex(driver.E2EError, "helper exceeded deadline"):
                    driver.drive(args)
            report = json.loads((evidence / "native-ui-report.json").read_text())
            self.assertEqual(report["status"], "failed")
            self.assertTrue(report["sampleLaunched"])
            self.assertEqual(report["sampleCleanup"]["state"], "terminated")
            self.assertTrue(report["sampleCleanup"]["reaped"])
            self.assertTrue(sample.terminated)

    def test_sample_cleanup_tolerates_exit_between_poll_and_terminate(self) -> None:
        process = Mock()
        process.poll.return_value = None
        process.terminate.side_effect = ProcessLookupError()
        process.wait.return_value = 0
        result = driver._stop_owned_sample(process)
        self.assertEqual(result["state"], "terminated")
        self.assertEqual(result["terminate"], "already-exited")
        self.assertTrue(result["reaped"])


if __name__ == "__main__":
    unittest.main()
