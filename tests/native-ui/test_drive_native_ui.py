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
    counter = {"x": 4, "y": 4, "width": 10, "height": 10}

    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory(prefix="yami-native-ui-verifier-")
        self.directory = pathlib.Path(self.temporary.name)

    def tearDown(self) -> None:
        self.temporary.cleanup()

    def _pixels(self, *, glyph: tuple[int, int] | None, button_color: tuple[int, int, int]) -> bytearray:
        pixels = bytearray([255] * (self.width * self.height * 3))
        for y in range(20, 30):
            for x in range(20, 30):
                offset = (y * self.width + x) * 3
                pixels[offset : offset + 3] = bytes(button_color)
        if glyph is not None:
            x, y = glyph
            offset = (y * self.width + x) * 3
            pixels[offset : offset + 3] = b"\x00\x00\x00"
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
            "textPixels": 1,
            "buttonPixels": 100,
            "button": self.button,
            "counter": self.counter,
        }
        marker.update(updates)
        return marker

    def _assert_frame_pair(self, before_pixels: bytearray, after_pixels: bytearray) -> dict:
        before_path = self._write("before.ppm", before_pixels)
        after_path = self._write("after.ppm", after_pixels)
        before = self._marker("before", 0, before_path)
        after = self._marker("after", 1, after_path)
        ready = {"button": self.button, "counter": self.counter}
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


if __name__ == "__main__":
    unittest.main()
