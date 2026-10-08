"""Regression tests for the independent native-frame proof oracle."""

from __future__ import annotations

import importlib.util
import pathlib
import tempfile
import unittest

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

if __name__ == "__main__":
    unittest.main()
