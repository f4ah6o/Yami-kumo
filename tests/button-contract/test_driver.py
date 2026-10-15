import json
from pathlib import Path
import unittest

from drive_linux import key_command


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


if __name__ == "__main__":
    unittest.main()
