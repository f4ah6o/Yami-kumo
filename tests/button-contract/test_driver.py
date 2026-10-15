import json
from pathlib import Path
import unittest

from drive_linux import key_command, validate_gpu_feedback


class HostFixtureTest(unittest.TestCase):
    def test_repeat_is_not_converted_to_release(self):
        for phase in ("enter-repeat", "space-repeat", "focus-loss"):
            with self.assertRaises(ValueError):
                key_command(phase)

    def test_all_host_keyboard_steps_are_deliverable(self):
        suite = json.loads(Path(__file__).with_name("fixtures.json").read_text())
        for case in suite["cases"]:
            if case.get("host"):
                for phase in case["steps"]:
                    if phase.startswith(("enter-", "space-")):
                        key_command(phase)

    def test_changed_scene_requires_changed_gpu_roi(self):
        initial = {"phase": "initial", "scene": {"items": [{"id": 40, "color": "blue"}]}, "gpu_button_sha256": "same"}
        held = {"phase": "hover", "scene": {"items": [{"id": 40, "color": "lighter"}]}, "gpu_button_sha256": "same"}
        with self.assertRaisesRegex(RuntimeError, "GPU feedback"):
            validate_gpu_feedback([initial, held])
        held["gpu_button_sha256"] = "changed"
        self.assertTrue(validate_gpu_feedback([initial, held])[0]["gpu_button_changed"])

    def test_unchanged_scene_requires_unchanged_gpu_roi(self):
        initial = {"phase": "initial", "scene": {"items": [{"id": 40}]}, "gpu_button_sha256": "same"}
        held = dict(initial, phase="pointer-down", gpu_button_sha256="changed")
        with self.assertRaisesRegex(RuntimeError, "GPU feedback"):
            validate_gpu_feedback([initial, held])


if __name__ == "__main__":
    unittest.main()
