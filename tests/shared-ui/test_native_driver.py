"""Inert oracle tests. All PPMs and markers here are synthetic test fixtures.

No native runtime, compiler, display, input injection or real capture is used.
"""
from __future__ import annotations

import argparse
import copy
import importlib.util
import io
import json
import os
import queue
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import Mock, patch

sys.dont_write_bytecode = True
PATH = Path(__file__).with_name("native_driver.py")
SPEC = importlib.util.spec_from_file_location("shared_native_driver_under_test", PATH)
assert SPEC and SPEC.loader
driver = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = driver
SPEC.loader.exec_module(driver)

ROOT_RECT = {"x": 0, "y": 0, "width": 40, "height": 40}
COUNTER = {"x": 4, "y": 4, "width": 10, "height": 10}
BUTTON = {"x": 20, "y": 20, "width": 10, "height": 10}
LABEL = {"x": 22, "y": 23, "width": 6, "height": 4}
COUNTS = {"counter": [0, 1, 2], "disabled-loading": [0, 0, 0, 1]}
CANDIDATE, GPUI = "a" * 40, "b" * 40


def marker(fixture="counter", phase=0, **updates):
    count = COUNTS[fixture][phase]
    result = {"fixture": fixture, "phase": phase, "count": count, "value": count,
              "enabled": fixture == "counter" or phase > 0,
              "loading": fixture == "disabled-loading" and phase == 1,
              "pressed": False, "focused": phase > 0, "releases": phase,
              "actions": ["Activate"] * count, "root": ROOT_RECT.copy(),
              "button": BUTTON.copy(), "buttonLabel": LABEL.copy(), "counter": COUNTER.copy(),
              "scale": 1.0, "title": "test-window",
              "scene": {"schema_version": 1, "viewport": ROOT_RECT.copy(), "scale": 1.0,
                        "items": [{"kind": "text", "text": f"Count: {count}"},
                                  {"kind": "text_run", "text": "Increment"},
                                  {"kind": "text", "text": "Shared counter"}]},
              "frame": {"path": f"frame-{phase}.ppm", "width": 40, "height": 40, "scale": 1.0}}
    result.update(updates)
    return result


class ImportTests(unittest.TestCase):
    def test_import_and_help_do_not_start_process_or_inject_input(self):
        spec = importlib.util.spec_from_file_location("inert_shared_driver_check", PATH)
        assert spec and spec.loader
        imported = importlib.util.module_from_spec(spec)
        with patch("subprocess.Popen", side_effect=AssertionError("process on import")), \
             patch("subprocess.run", side_effect=AssertionError("command on import")), \
             patch("sys.stdout", new=io.StringIO()):
            spec.loader.exec_module(imported)
            with self.assertRaises(SystemExit) as exit:
                imported.main(["--help"])
            self.assertEqual(exit.exception.code, 0)

    def test_macos_cli_is_rejected_before_any_runtime(self):
        with patch("subprocess.Popen", side_effect=AssertionError("host launched")), \
             patch("sys.stderr", new=io.StringIO()):
            with self.assertRaises(SystemExit):
                driver.main(["--platform", "macos", "--candidate-sha", CANDIDATE,
                             "--evidence-dir", "/unused"])


class MarkerTests(unittest.TestCase):
    def check(self, value, fixture="counter", phase=0, **kwargs):
        driver.validate_marker(value, fixture, phase, COUNTS[fixture], presented=True, **kwargs)

    def test_all_contract_phases(self):
        contract = driver.load_contract()
        for fixture, counts in COUNTS.items():
            self.assertEqual(driver.expected_counts(contract, fixture), counts)
            for phase in range(len(counts)):
                self.check(marker(fixture, phase), fixture, phase)

    def test_wrong_fixture_phase_or_value_is_rejected(self):
        for updates in ({"fixture": "other"}, {"phase": 1}, {"phase": False}, {"count": True},
                        {"count": 1}, {"value": 1}, {"value": 0.0}):
            with self.subTest(updates=updates), self.assertRaises(driver.E2EError):
                self.check(marker() | updates)

    def test_disabled_and_loading_gate_and_action_trace(self):
        for fixture, phase, updates in (("disabled-loading", 0, {"enabled": True}),
                                        ("disabled-loading", 1, {"loading": False}),
                                        ("disabled-loading", 1, {"enabled": False}),
                                        ("disabled-loading", 2, {"actions": ["Activate"]}),
                                        ("counter", 2, {"actions": ["Activate"]}),
                                        ("counter", 1, {"actions": ["Increment"]})):
            with self.subTest(fixture=fixture, phase=phase), self.assertRaises(driver.E2EError):
                self.check(marker(fixture, phase, **updates), fixture, phase)

    def test_actual_release_required_and_pressed_frame_rejected(self):
        for updates in ({"releases": 0}, {"releases": True}, {"pressed": True}, {"focused": 1}):
            with self.subTest(updates=updates), self.assertRaises(driver.E2EError):
                self.check(marker("counter", 1, **updates), "counter", 1)

    def test_nonfinite_coerced_and_outside_geometry_rejected(self):
        for value in (float("nan"), float("inf"), True, "1", 0, -1):
            with self.subTest(scale=value), self.assertRaises(driver.E2EError):
                self.check(marker(scale=value))
        for field in ("button", "counter", "buttonLabel"):
            for change in ({"x": -1}, {"width": 100}, {"height": True}, {"y": "4"}):
                value = marker()
                value[field].update(change)
                with self.subTest(field=field, change=change), self.assertRaises(driver.E2EError):
                    self.check(value)

    def test_scene_text_object_viewport_and_scale_are_required(self):
        for replacement in ({}, "{}", {"items": []}):
            with self.subTest(scene=replacement), self.assertRaises(driver.E2EError):
                self.check(marker(scene=replacement))
        for mutate in (lambda s: s["items"].pop(),
                       lambda s: s["items"].append(s["items"][0]),
                       lambda s: s.update(scale=2),
                       lambda s: s["viewport"].update(width=39)):
            value = marker()
            mutate(value["scene"])
            with self.assertRaises(driver.E2EError):
                self.check(value)

    def test_capture_metadata_requires_exact_types_and_geometry(self):
        for updates in ({"width": True}, {"height": 0}, {"scale": 2}, {"width": 50}, {"path": None}):
            value = marker()
            value["frame"].update(updates)
            with self.subTest(updates=updates), self.assertRaises(driver.E2EError):
                self.check(value)

    def test_complete_requires_destroyed_final_phase_and_retained_frame(self):
        value = marker("counter", 2, destroyed=True)
        self.check(value, "counter", 2, complete=True)
        for updates in ({"destroyed": False}, {"count": 1}, {"frame": None}):
            with self.subTest(updates=updates), self.assertRaises(driver.E2EError):
                self.check(value | updates, "counter", 2, complete=True)

    def test_contract_rejects_extra_or_changed_fixture_schema(self):
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / "contract.json"
            original = driver.load_contract()
            variants = [original | {"profileDifferences": ["unchecked"]},
                        original | {"version": "future"}, original | {"fixtures": []}]
            changed = copy.deepcopy(original)
            changed["fixtures"][0]["expected"]["counts"][0] = False
            variants.append(changed)
            for fixture_id in ("button-interrupted-loading", "button-interrupted-disabled"):
                changed = copy.deepcopy(original)
                next(item for item in changed["fixtures"] if item["id"] == fixture_id)["expected"]["counts"][0] = False
                variants.append(changed)
            changed = copy.deepcopy(original)
            changed["fixtures"][-1]["id"] = "unknown"
            variants.append(changed)
            changed = copy.deepcopy(original)
            changed["fixtures"][-1]["id"] = changed["fixtures"][0]["id"]
            variants.append(changed)
            for value in variants:
                path.write_text(json.dumps(value))
                with self.assertRaises(driver.E2EError):
                    driver.load_contract(path)

    def test_new_button_contracts_do_not_expand_real_native_input_claims(self):
        self.assertEqual(driver.FIXTURES, {
            "counter": "counter-two-activations",
            "disabled-loading": "counter-disabled-loading",
            "card": "card-counter-two-activations",
            "spacing": "spacing-count-and-toggle",
        })
        self.assertEqual(set(driver.CONTRACT_PHASES) - set(driver.FIXTURES.values()), {
            "button-interrupted-loading", "button-interrupted-disabled",
        })


def card_marker():
    value = marker()
    value["fixture"] = "card"
    value["root"] = {"x":0,"y":0,"width":200,"height":200}
    value["card"] = {"x":24,"y":24,"width":100,"height":118}
    value["heading"] = {"x":41,"y":41,"width":66,"height":20}
    value["counter"] = {"x":41,"y":73,"width":66,"height":20}
    value["button"] = {"x":41,"y":105,"width":66,"height":20}
    value["buttonLabel"] = {"x":45,"y":109,"width":50,"height":12}
    value["scene"]["viewport"] = value["root"].copy()
    for index,item in enumerate(value["scene"]["items"]):
        item["id"] = index+4
    value["scene"]["items"][:0] = [
        {"kind":"quad","id":2,"bounds":value["card"].copy(),"color":{"red":166,"green":171,"blue":178,"alpha":255}},
        {"kind":"quad","id":3,"bounds":{"x":25,"y":25,"width":98,"height":116},"color":{"red":245,"green":247,"blue":250,"alpha":255}},
    ]
    return value


class CardGeometryTests(unittest.TestCase):
    def test_fixed_card_geometry_and_paint_order(self):
        driver.validate_card_geometry(card_marker())

    def test_native_intrinsic_widths_measure_the_content_envelope(self):
        value = card_marker()
        value["counter"]["width"] = 30
        value["button"]["width"] = 48
        driver.validate_card_geometry(value)
        # The widest child need not be the first one.
        value["heading"]["width"] = 30
        value["counter"]["width"] = 66
        driver.validate_card_geometry(value)

    def test_content_envelope_insets_and_each_child_containment_remain_required(self):
        variants = []
        value = card_marker()
        for key in ("heading", "counter", "button"):
            value[key]["width"] -= 3
        variants.append(value)  # right content inset 20 instead of 17
        value = card_marker()
        for key in ("heading", "counter", "button"):
            value[key]["x"] += 3
            value[key]["width"] -= 3
        variants.append(value)  # left content inset 20 instead of 17
        value = card_marker(); value["counter"]["width"] = 100; variants.append(value)
        value = card_marker(); value["counter"]["x"] = 23; variants.append(value)
        value = card_marker(); value["counter"]["y"] = 23; variants.append(value)
        value = card_marker(); value["counter"]["height"] = 120; variants.append(value)
        for value in variants:
            with self.subTest(value=value), self.assertRaises(driver.E2EError):
                driver.validate_card_geometry(value)

    def test_wrong_insets_gaps_border_paint_and_ids_are_rejected(self):
        variants = []
        value = card_marker(); value["heading"]["x"] += 3; variants.append(value)
        value = card_marker(); value["counter"]["y"] += 3; variants.append(value)
        value = card_marker(); value["scene"]["items"][1]["bounds"]["x"] += 1; variants.append(value)
        value = card_marker(); value["scene"]["items"][0]["color"]["red"] = 0; variants.append(value)
        value = card_marker(); value["scene"]["items"].insert(0, value["scene"]["items"].pop()); variants.append(value)
        value = card_marker(); value["scene"]["items"][1]["id"] = 2; variants.append(value)
        value = card_marker(); del value["heading"]; variants.append(value)
        for value in variants:
            with self.subTest(value=value), self.assertRaises(driver.E2EError):
                driver.validate_card_geometry(value)

    def test_actual_pixel_oracle_rejects_blank_border_and_interior(self):
        value = card_marker()
        pixels = bytearray(bytes((245,247,250)) * (200*200))
        for x,y in [(74,24),(123,83),(74,141),(24,83)]:
            offset = (y*200+x)*3
            pixels[offset:offset+3] = bytes((166,171,178))
        image = driver.native.PPM(200,200,bytes(pixels))
        self.assertEqual(len(driver.inspect_card_pixels(image,value)),5)
        for x,y in [(74,24),(123,83),(74,141),(24,83),(28,28)]:
            changed = pixels.copy(); offset = (y*200+x)*3
            changed[offset:offset+3] = bytes((0,0,0))
            with self.subTest(point=(x,y)), self.assertRaises(driver.E2EError):
                driver.inspect_card_pixels(driver.native.PPM(200,200,bytes(changed)),value)


SPACING_COUNTS = [0, 1, 1, 2, 2]


def spacing_marker(phase=0, **updates):
    """Synthetic font-independent geometry, never retained native evidence."""
    expanded = phase in (2, 3)
    pad, gap, row_pad, row_gap = (16, 12, 8, 16) if expanded else (4, 0, 0, 4)
    def rect(x, y, width, height):
        return {"x": x, "y": y, "width": width, "height": height}
    left, top = 24 + pad, 24 + pad
    row_width, row_height = 60 + 50 + row_gap + row_pad * 2, 20 + row_pad * 2
    heading = rect(left, top, 80, 10)
    counter = rect(left, top + 10 + gap, 50, 10)
    row = rect(left, counter["y"] + 10 + gap, row_width, row_height)
    button = rect(left + row_pad, row["y"] + row_pad, 60, 20)
    toggle = rect(button["x"] + 60 + row_gap, button["y"], 50, 20)
    card = rect(left, row["y"] + row_height + gap, 94, 44)
    card_label = rect(left + 17, card["y"] + 17, 60, 10)
    stack = rect(24, 24, row_width + pad * 2, card["y"] + 44 + pad - 24)
    root = rect(0, 0, 300, 300)
    count = SPACING_COUNTS[phase]
    value = {"fixture": "spacing", "phase": phase, "count": count, "value": count,
             "enabled": True, "loading": False, "pressed": False, "focused": phase in (1, 3),
             "releases": phase, "actions": ["Activate"] * phase, "root": root, "scale": 1.0,
             "title": "test-window", "heading": heading, "counter": counter, "button": button,
             "buttonLabel": rect(button["x"] + 4, button["y"] + 4, 50, 10), "card": card,
             "spacing": {"expanded": expanded, "stack": stack, "row": row, "cardLabel": card_label,
                         "toggle": toggle, "toggleLabel": rect(toggle["x"] + 4, toggle["y"] + 4, 40, 10),
                         "togglePressed": False, "toggleFocused": phase in (2, 4),
                         "buttonId": 40, "toggleId": 48,
                         "actionKeys": ["increment", "spacing-toggle", "increment", "spacing-toggle"][:phase]},
             "scene": {"schema_version": 1, "viewport": root.copy(), "scale": 1.0, "items": [
                 {"kind": "quad", "id": 1, "bounds": root.copy(), "color": {"red":255,"green":255,"blue":255,"alpha":255}},
                 {"kind": "text", "id": 19, "text": "Shared <stack>"},
                 {"kind": "text", "id": 27, "text": f"Count: {count}"},
                 {"kind": "text_run", "id": 43, "text": "Increment"},
                 {"kind": "text_run", "id": 51, "text": "Spacing"},
                 {"kind": "quad", "id": 57, "bounds": card.copy(), "color": {"red":166,"green":171,"blue":178,"alpha":255}},
                 {"kind": "quad", "id": 58, "bounds": rect(card["x"]+1, card["y"]+1, 92, 42), "color": {"red":245,"green":247,"blue":250,"alpha":255}},
                 {"kind": "text", "id": 67, "text": "Fixed Card"}]},
             "frame": {"path": f"frame-{phase}.ppm", "width": 300, "height": 300, "scale": 1.0}}
    value.update(updates)
    return value


def write_spacing_frame(directory, value, *, count=None, toggle_label=True, card_paint=True):
    pixels = bytearray(b"\xff\xff\xff" * (300 * 300))
    def pixel(x, y, color):
        offset = (y * 300 + x) * 3
        pixels[offset:offset+3] = bytes(color)
    def fill(bounds, color):
        for y in range(bounds["y"], bounds["y"] + bounds["height"]):
            for x in range(bounds["x"], bounds["x"] + bounds["width"]):
                pixel(x, y, color)
    for button in (value["button"], value["spacing"]["toggle"]):
        fill(button, (80, 80, 80))
    labels = [value["buttonLabel"]]
    if toggle_label:
        labels.append(value["spacing"]["toggleLabel"])
    for label in labels:
        pixel(label["x"]+2, label["y"]+2, (255,255,255))
    counter = value["counter"]
    pixel(counter["x"]+3+(value["count"] if count is None else count), counter["y"]+3, (0,0,0))
    if card_paint:
        card = value["card"]
        fill(card, (166,171,178))
        fill({"x":card["x"]+1,"y":card["y"]+1,"width":card["width"]-2,"height":card["height"]-2}, (245,247,250))
    path = directory / value["frame"]["path"]
    path.write_bytes(b"P6\n300 300\n255\n" + pixels)
    return path


class SpacingTests(unittest.TestCase):
    def test_all_five_model_pointer_geometry_and_identity_phases(self):
        markers = [spacing_marker(phase) for phase in range(5)]
        contract = driver.load_contract()
        self.assertEqual(driver.expected_counts(contract, "spacing"), SPACING_COUNTS)
        for phase, value in enumerate(markers):
            driver.validate_marker(value, "spacing", phase, SPACING_COUNTS, presented=True)
        driver.validate_spacing_sequence(markers)

    def test_missing_extra_and_mistyped_spacing_schema_rejected(self):
        for key in driver.SPACING_KEYS:
            value = spacing_marker(); del value["spacing"][key]
            with self.subTest(missing=key), self.assertRaises(driver.E2EError):
                driver.validate_spacing_geometry(value, 0)
        for change in ({"gap":0}, {"expanded":0}, {"buttonId":True}, {"buttonId":0},
                       {"toggleId":40}, {"togglePressed":1}, {"toggleFocused":0}):
            value = spacing_marker(); value["spacing"].update(change)
            with self.subTest(change=change), self.assertRaises(driver.E2EError):
                driver.validate_spacing_geometry(value, 0)

    def test_outer_row_all_union_insets_and_ordered_gaps_are_required(self):
        for phase in (0, 2):
            original = spacing_marker(phase)
            # Mutate each edge of each explicit stack, each direct-child gap,
            # and each fixed Card edge. These must not pass on declared tokens.
            locations = [("spacing", "stack", axis) for axis in ("x", "y", "width", "height")]
            locations += [("spacing", "row", axis) for axis in ("x", "y", "width", "height")]
            locations += [("spacing", "toggle", "x"), ("spacing", "cardLabel", "x"), ("spacing", "cardLabel", "y")]
            locations += [(None, key, "y") for key in ("counter", "card")]
            locations += [(None, "card", axis) for axis in ("x", "width", "height")]
            for group, key, axis in locations:
                value = copy.deepcopy(original)
                (value[group][key] if group else value[key])[axis] += 3
                with self.subTest(phase=phase, group=group, key=key, axis=axis), self.assertRaises(driver.E2EError):
                    driver.validate_spacing_geometry(value, phase)

    def test_tolerance_is_fixed_at_one_logical_pixel(self):
        value = spacing_marker()
        value["spacing"]["stack"]["width"] += 1
        driver.validate_spacing_geometry(value, 0)
        value["spacing"]["stack"]["width"] += .01
        with self.assertRaises(driver.E2EError):
            driver.validate_spacing_geometry(value, 0)
        self.assertEqual(driver.GEOMETRY_TOLERANCE, 1.0)

    def test_model_action_focus_and_scene_binding_identity_are_required(self):
        for phase in range(5):
            for change in ({"expanded": not (phase in (2, 3))}, {"actionKeys": ["increment"]*4},
                           {"togglePressed": True}, {"toggleFocused": phase not in (2, 4)},
                           {"buttonId": 41}, {"toggleId": 49}):
                value = spacing_marker(phase); value["spacing"].update(change)
                with self.subTest(phase=phase, change=change), self.assertRaises(driver.E2EError):
                    driver.validate_spacing_geometry(value, phase)
            value = spacing_marker(phase); value["focused"] = not value["focused"]
            with self.assertRaises(driver.E2EError):
                driver.validate_spacing_geometry(value, phase)
        markers = [spacing_marker(phase) for phase in range(5)]
        markers[2]["spacing"]["buttonId"] = 72
        next(item for item in markers[2]["scene"]["items"] if item.get("text") == "Increment")["id"] = 75
        driver.validate_spacing_geometry(markers[2], 2)  # Locally valid replacement still fails identity retention.
        with self.assertRaisesRegex(driver.E2EError, "stable native Button"):
            driver.validate_spacing_sequence(markers)

    def test_card_paint_remains_fixed_and_descendant_ordered(self):
        for mutation in (lambda v: v["scene"]["items"][5]["color"].update(red=0),
                         lambda v: v["scene"]["items"][6]["bounds"].update(width=90),
                         lambda v: v["scene"]["items"].insert(0, v["scene"]["items"].pop()),
                         lambda v: v["scene"]["items"][6].update(id=57)):
            value = spacing_marker(); mutation(value)
            with self.assertRaises(driver.E2EError):
                driver.validate_spacing_geometry(value, 0)

    def test_translated_count_rasters_and_fresh_visible_toggle_and_card(self):
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            markers = [spacing_marker(phase) for phase in range(5)]
            for value in markers:
                write_spacing_frame(directory, value)
            proof = driver.inspect_frame_sequence(markers, directory)
            self.assertEqual(proof["changedCounterPixels"], 2)
            self.assertEqual(len(proof["captures"]), 5)
            write_spacing_frame(directory, markers[2], count=0)
            with self.assertRaisesRegex(driver.E2EError, "spacing-only"):
                driver.inspect_frame_sequence(markers, directory)
            write_spacing_frame(directory, markers[2])
            write_spacing_frame(directory, markers[3], count=1)
            with self.assertRaisesRegex(driver.E2EError, "spacing increment"):
                driver.inspect_frame_sequence(markers, directory)
            for options in ({"toggle_label":False}, {"card_paint":False}):
                write_spacing_frame(directory, markers[0], **options)
                with self.subTest(options=options), self.assertRaises(driver.E2EError):
                    driver.inspect_frame(markers[0], directory)

    def test_only_five_phases_with_restored_collapsed_geometry_qualify(self):
        with self.assertRaises(driver.E2EError):
            driver.validate_spacing_sequence([spacing_marker(phase) for phase in range(4)])
        markers = [spacing_marker(phase) for phase in range(5)]
        markers[-1]["spacing"]["stack"]["width"] += 1  # Locally within tolerance, not restored.
        with self.assertRaisesRegex(driver.E2EError, "restore"):
            driver.validate_spacing_sequence(markers)

    def test_mocked_host_click_routing_uses_each_latest_button_rectangle(self):
        with tempfile.TemporaryDirectory() as temporary:
            evidence = Path(temporary)
            args = argparse.Namespace(platform="linux", window_title="test-window", startup_timeout=1,
                                      marker_timeout=1, linux_origin_x=0, linux_origin_y=0)
            process = Mock(pid=123, stdout=None)
            process.wait.return_value = 0
            process.poll.return_value = 0
            output = Mock(events=[], lines=queue.Queue())
            output._reader.is_alive.return_value = False
            markers = [spacing_marker(phase) for phase in range(5)]
            calls = []
            title = None
            def launch(command, **kwargs):
                nonlocal title
                title = kwargs["env"]["YAMI_NATIVE_UI_WINDOW_TITLE"]
                self.assertEqual(kwargs["env"]["YAMI_SHARED_UI_FIXTURE"], "spacing")
                for value in markers:
                    value["title"] = title
                return process
            def create_output(owned, path):
                path.write_text("Synthetic mocked marker stream; not host evidence.\n")
                for value in markers:
                    write_spacing_frame(path.parent, value)
                output.events.extend([("YAMI_NATIVE_UI_PRESENTED", markers[0]), ("YAMI_NATIVE_UI_READY", markers[0])])
                return output
            def click(platform, target, click_args):
                phase = len(calls) + 1
                previous = markers[phase - 1]
                expected = previous["spacing"]["toggle"] if phase in (2, 4) else previous["button"]
                self.assertEqual(target["button"], expected)
                self.assertEqual(click_args.sample_pid, 123)
                calls.append(copy.deepcopy(target["button"]))
                output.events.append(("YAMI_NATIVE_UI_PRESENTED", markers[phase]))
            def escape(platform, click_args):
                output.events.append(("YAMI_NATIVE_UI_COMPLETE", markers[-1] | {"destroyed":True}))
            with patch.object(driver.subprocess, "Popen", side_effect=launch), \
                 patch.object(driver.native, "ProcessOutput", side_effect=create_output), \
                 patch.object(driver.native, "_send_click", side_effect=click), \
                 patch.object(driver.native, "_send_escape", side_effect=escape):
                trace = driver.run_fixture(args, "spacing", SPACING_COUNTS, Path("owned-binary"), Path("workspace"), evidence, {})
            self.assertEqual(trace["status"], "pass")
            self.assertEqual(len(calls), 4)
            self.assertNotEqual(calls[0], calls[2])
            self.assertNotEqual(calls[1], calls[3])
            self.assertEqual(trace["cleanup"], {"state":"already-exited", "reaped":True, "returnCode":0})


class PixelTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary.name)

    def tearDown(self):
        self.temporary.cleanup()

    def write(self, phase, *, count=None, text=True, label=True, border=False, color=80):
        pixels = bytearray([255] * (40 * 40 * 3))
        for y in range(20, 30):
            for x in range(20, 30):
                offset = (y * 40 + x) * 3
                pixels[offset:offset + 3] = bytes([color, color, color])
        if label:
            offset = (25 * 40 + 24) * 3
            pixels[offset:offset + 3] = b"\xff\xff\xff"
        if border:
            for x in range(20, 30):
                for y in (20, 29):
                    offset = (y * 40 + x) * 3
                    pixels[offset:offset + 3] = b"\xff\xff\xff"
        if text:
            x = 6 + (phase if count is None else count)
            offset = (6 * 40 + x) * 3
            pixels[offset:offset + 3] = b"\0\0\0"
        path = self.root / f"frame-{phase}.ppm"
        path.write_bytes(b"P6\n40 40\n255\n" + pixels)
        return path

    def test_counter_and_disabled_loading_sequences_with_visible_changed_text(self):
        for fixture, counts in COUNTS.items():
            markers = [marker(fixture, phase) for phase in range(len(counts))]
            for phase, count in enumerate(counts):
                self.write(phase, count=count)
            result = driver.inspect_frame_sequence(markers, self.root)
            self.assertEqual(result["changedCounterPixels"], 2)
            self.assertEqual(len(result["captures"]), len(counts))

    def test_blank_counter_and_border_only_button_are_rejected(self):
        for kwargs, message in (({"text": False}, "counter"),
                                ({"label": False, "border": True}, "button label")):
            self.write(0, **kwargs)
            with self.subTest(kwargs=kwargs), self.assertRaisesRegex(driver.E2EError, message):
                driver.inspect_frame(marker(), self.root)

    def test_button_change_cannot_substitute_for_count_change(self):
        markers = [marker("counter", i) for i in range(3)]
        for i in range(3):
            self.write(i, count=0, color=70 + i * 20)
        with self.assertRaisesRegex(driver.E2EError, "final counter pixels"):
            driver.inspect_frame_sequence(markers, self.root)

    def test_gated_counter_change_rejected_even_if_final_changes(self):
        markers = [marker("disabled-loading", i) for i in range(4)]
        for i in range(4):
            self.write(i, count=i)
        with self.assertRaisesRegex(driver.E2EError, "gated click changed"):
            driver.inspect_frame_sequence(markers, self.root)

    def test_same_frame_path_cannot_be_reused(self):
        self.write(0)
        markers = [marker(), marker("counter", 1)]
        markers[1]["frame"]["path"] = "frame-0.ppm"
        with self.assertRaisesRegex(driver.E2EError, "distinct PPM"):
            driver.inspect_frame_sequence(markers, self.root)

    def test_ppm_metadata_truncation_and_path_escape_rejected(self):
        self.write(0)
        value = marker()
        value["frame"]["width"] = 39
        with self.assertRaisesRegex(driver.E2EError, "dimensions"):
            driver.inspect_frame(value, self.root)
        (self.root / "frame-0.ppm").write_bytes(b"P6\n40 40\n255\n\0\0\0")
        with self.assertRaisesRegex(driver.E2EError, "raster size mismatch"):
            driver.inspect_frame(marker(), self.root)
        value = marker()
        value["frame"]["path"] = "../outside.ppm"
        with self.assertRaisesRegex(driver.E2EError, "escapes"):
            driver.inspect_frame(value, self.root)

    @unittest.skipIf(os.name == "nt", "symlink creation may require Windows privileges")
    def test_capture_symlink_escape_rejected(self):
        with tempfile.TemporaryDirectory() as outside:
            target = Path(outside) / "frame.ppm"
            target.write_bytes(b"not a capture")
            (self.root / "frame-0.ppm").symlink_to(target)
            with self.assertRaisesRegex(driver.E2EError, "escapes"):
                driver.inspect_frame(marker(), self.root)


class SourceBindingTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary.name) / "yami"
        self.gpui = Path(self.temporary.name) / "gpui"
        self.files = []
        for relative, data in (("tests/shared-ui/gpui-revision.txt", GPUI),
                               ("fixtures/shared-ui/contract-v1.json", "contract"),
                               ("ui/core/view.mbt", "common view"),
                               ("ui/runtime/runtime.mbt", "common runtime"),
                               ("examples/shared_counter/counter.mbt", "common model")):
            path = self.root / relative
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(data)
            self.files.append(relative)

    def tearDown(self):
        self.temporary.cleanup()

    def git(self, root, *args):
        if args[0] == "rev-parse":
            return CANDIDATE if root == self.root else GPUI
        if args[0] == "status":
            return ""
        if args[0] == "ls-files":
            return "\0".join(self.files) + "\0"
        raise AssertionError(args)

    def test_spacing_sources_styles_and_contract_doc_are_provenance_bound(self):
        for path in ("ui/core", "ui/runtime", "examples/shared_counter", "styles/shared-ui.css",
                     "tests/shared-ui", "fixtures/shared-ui", "docs/shared-card.md", "docs/shared-stack-spacing.md"):
            self.assertIn(path, driver.BOUND_PATHS)

    def test_clean_candidate_and_dependency_bind_exact_common_source_hashes(self):
        with patch.object(driver, "_git", side_effect=self.git):
            evidence = driver.bind_sources(self.root, self.gpui, CANDIDATE)
        self.assertEqual(evidence["candidateSha"], CANDIDATE)
        self.assertEqual(evidence["gpuiRevision"], GPUI)
        self.assertFalse(evidence["sourceDirty"])
        self.assertEqual(evidence["sourceSha256"]["ui/core/view.mbt"],
                         driver.digest(self.root / "ui/core/view.mbt"))

    def test_candidate_mismatch_dirty_source_and_gpui_mismatch_rejected(self):
        variants = [(self.root, "rev-parse", "c" * 40),
                    (self.root, "status", " M examples/shared_counter/counter.mbt"),
                    (self.root, "status", "?? ignored-test-bypass.mbt"),
                    (self.gpui, "rev-parse", "c" * 40),
                    (self.gpui, "status", " M button/button.mbt")]
        for target, operation, response in variants:
            def changed(root, *args):
                return response if root == target and args[0] == operation else self.git(root, *args)
            with self.subTest(target=target, operation=operation), \
                 patch.object(driver, "_git", side_effect=changed), self.assertRaises(driver.E2EError):
                driver.bind_sources(self.root, self.gpui, CANDIDATE)

    def test_symbolic_and_short_candidates_are_rejected_without_git(self):
        with patch.object(driver, "_git", side_effect=AssertionError("git should not run")):
            for candidate in ("HEAD", "abc123", "A" * 40, "a" * 41):
                with self.subTest(candidate=candidate), self.assertRaises(driver.E2EError):
                    driver.bind_sources(self.root, self.gpui, candidate)

    def test_missing_common_source_does_not_create_evidence(self):
        self.files.remove("ui/core/view.mbt")
        with patch.object(driver, "_git", side_effect=self.git), self.assertRaisesRegex(driver.E2EError, "missing bound common"):
            driver.bind_sources(self.root, self.gpui, CANDIDATE)

    def test_git_calls_are_read_only_and_bounded(self):
        result = subprocess.CompletedProcess([], 0, "a\n", "")
        with patch.object(driver.subprocess, "run", return_value=result) as run:
            self.assertEqual(driver._git(self.root, "rev-parse", "HEAD"), "a")
        self.assertEqual(run.call_args.args[0], ["git", "-C", str(self.root), "rev-parse", "HEAD"])
        self.assertEqual(run.call_args.kwargs["timeout"], 20)


class BuildAndPreflightTests(unittest.TestCase):
    def test_build_plan_reuses_exact_bound_workspace_package(self):
        root = Path("/test/yami/native").resolve()
        target = Path("/test/owned-target").resolve()
        for host, name in (("linux", "ubuntu"), ("windows", "windows")):
            package = root / "examples/shared_counter" / name
            command = ["moon", "run", str(package), "--target", "native"]
            build, binary = driver.build_plan(command, host, root, target)
            self.assertEqual(build, ["moon", "build", str(package), "--target", "native", "--deny-warn", "--target-dir", str(target)])
            self.assertEqual(binary, target / "native/debug/build/f4ah6o/yami_kumo_native/examples/shared_counter" / name / f"{name}.exe")

    def test_unbound_binary_legacy_sample_wrong_target_or_args_rejected(self):
        root, target = Path("/test/native"), Path("/test/target")
        commands = [["unbound-binary"], ["moon", "run", str(root / "examples/ubuntu"), "--target", "native"],
                    ["moon", "run", str(root / "examples/shared_counter/ubuntu"), "--target", "js"],
                    ["moon", "run", str(root / "examples/shared_counter/ubuntu"), "--target", "native", "--extra"]]
        for command in commands:
            with self.subTest(command=command), self.assertRaises(driver.E2EError):
                driver.build_plan(command, "linux", root, target)

    def test_linux_global_input_requires_explicit_isolated_session(self):
        env = {"YAMI_NATIVE_UI_ISOLATED": "1", "DISPLAY": ":99", "WAYLAND_DISPLAY": "isolated",
               "YAMI_NATIVE_WORKSPACE_ROOT": "/temporary", "YAMI_NATIVE_YAMI_ROOT": str(driver.ROOT),
               "YAMI_NATIVE_GPUI_ROOT": "/gpui", "YAMI_NATIVE_MODULE_ROOT": str(driver.ROOT / "native")}
        with patch.object(driver.sys, "platform", "linux"):
            driver.preflight("linux", env)
            for key in env:
                with self.subTest(missing=key), self.assertRaises(driver.E2EError):
                    driver.preflight("linux", {name: value for name, value in env.items() if name != key})

    def test_macos_or_cross_platform_host_rejected(self):
        with self.assertRaises(driver.E2EError):
            driver.preflight("macos", {})
        with patch.object(driver.sys, "platform", "darwin"), self.assertRaises(driver.E2EError):
            driver.preflight("linux", {})

    def test_failure_retains_report_without_launch_or_pass_records(self):
        with tempfile.TemporaryDirectory() as temporary:
            args = argparse.Namespace(platform="linux", evidence_dir=Path(temporary), candidate_sha=CANDIDATE,
                                      log=None, command=[])
            with patch.object(driver, "preflight", side_effect=driver.E2EError("isolated session missing")), \
                 patch.object(driver.subprocess, "Popen", side_effect=AssertionError("host launch forbidden")), \
                 patch("sys.stderr", new=io.StringIO()):
                self.assertEqual(driver.drive(args), 1)
            report = json.loads((Path(temporary) / "shared-native-report.json").read_text())
            self.assertEqual(report["status"], "fail")
            self.assertIn("isolated session missing", report["error"])
            self.assertFalse((Path(temporary) / "results.json").exists())

    def test_existing_evidence_cannot_be_overwritten(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            retained = root / "results.json"
            retained.write_text("old evidence")
            args = argparse.Namespace(evidence_dir=root)
            with self.assertRaisesRegex(driver.E2EError, "overwrite"):
                driver.drive(args)
            self.assertEqual(retained.read_text(), "old evidence")


class StreamTests(unittest.TestCase):
    def stream(self, events):
        output = Mock(events=events)
        output._line.side_effect = AssertionError("no real process output")
        return driver.MarkerStream(output)

    def test_initial_accepts_ready_before_or_after_presented(self):
        ready, presented = marker(), marker()
        ready.pop("frame")
        events = [("YAMI_NATIVE_UI_READY", ready), ("YAMI_NATIVE_UI_PRESENTED", presented)]
        for ordered in (events, events[::-1]):
            first, second = self.stream(ordered).initial("counter", COUNTS["counter"], 1)
            self.assertEqual(first, ready)
            self.assertEqual(second, presented)

    def test_initial_rejects_duplicate_or_wrong_protocol(self):
        for events in ([("YAMI_NATIVE_UI_READY", marker())] * 2,
                       [("YAMI_NATIVE_UI_CLICK", marker())],
                       [("YAMI_NATIVE_UI_PRESENTED", marker("counter", 1))]):
            with self.subTest(events=events), self.assertRaises(driver.E2EError):
                self.stream(events).initial("counter", COUNTS["counter"], 1)

    def test_phase_must_be_next_exact_phase_and_never_reuses_old_marker(self):
        stream = self.stream([("YAMI_NATIVE_UI_PRESENTED", marker("counter", 1)),
                              ("YAMI_NATIVE_UI_PRESENTED", marker("counter", 2))])
        self.assertEqual(stream.phase("counter", 1, COUNTS["counter"], 1)["count"], 1)
        self.assertEqual(stream.phase("counter", 2, COUNTS["counter"], 1)["count"], 2)
        for phase in (0, 2):
            with self.subTest(phase=phase), self.assertRaises(driver.E2EError):
                self.stream([("YAMI_NATIVE_UI_PRESENTED", marker("counter", phase))]).phase("counter", 1, COUNTS["counter"], 1)

    def test_malformed_marker_line_is_rejected(self):
        output = Mock(events=[])
        output._line.return_value = "YAMI_NATIVE_UI_PRESENTED not-json\n"
        with self.assertRaisesRegex(driver.E2EError, "malformed"):
            driver.MarkerStream(output).next(1)


class LifecycleTests(unittest.TestCase):
    """Mocked launches/input prove orchestration only, never host behavior."""
    def exercise(self, fixture="counter", *, exit_code=0, destroyed=True, wrong_phase=False):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        evidence = Path(temporary.name)
        args = argparse.Namespace(platform="linux", window_title="test-window", startup_timeout=1,
                                  marker_timeout=1, linux_origin_x=0, linux_origin_y=0)
        process = Mock(pid=123, stdout=None)
        process.wait.return_value = exit_code
        process.poll.return_value = exit_code
        output = Mock(events=[], lines=queue.Queue())
        output._reader.is_alive.return_value = False
        calls = []
        phases = iter(range(1, len(COUNTS[fixture])))
        title = None
        raw_log = None

        def launch(command, **kwargs):
            nonlocal title
            title = kwargs["env"]["YAMI_NATIVE_UI_WINDOW_TITLE"]
            self.assertEqual(kwargs["env"]["YAMI_SHARED_UI_FIXTURE"], fixture)
            self.assertEqual(kwargs["env"]["YAMI_NATIVE_UI_E2E"], "1")
            self.assertEqual(kwargs["env"]["GPUI_NATIVE_E2E"], "1")
            self.assertEqual(command, ["owned-binary"])
            calls.append("launch")
            return process

        def publish(name, phase, **extra):
            value = marker(fixture, phase, title=title, **extra)
            output.events.append((name, value))
            assert raw_log is not None
            raw_log.write(name + " " + json.dumps(value) + "\n")
            raw_log.flush()

        def create_output(owned, path):
            nonlocal raw_log
            self.assertIs(owned, process)
            raw_log = path.open("w")
            output.close.side_effect = raw_log.close
            self.addCleanup(lambda: raw_log.close() if not raw_log.closed else None)
            # Explicit synthetic PPM unit fixtures, not claimed captures.
            helper = PixelTests()
            helper.root = path.parent
            for phase, count in enumerate(COUNTS[fixture]):
                helper.write(phase, count=count)
            publish("YAMI_NATIVE_UI_PRESENTED", 0)
            publish("YAMI_NATIVE_UI_READY", 0)
            return output

        def click(platform, target, click_args):
            calls.append("click")
            self.assertEqual(platform, "linux")
            self.assertEqual(click_args.window_title, title)
            self.assertEqual(click_args.sample_pid, 123)
            phase = next(phases)
            self.assertEqual(target["phase"], phase - 1)
            publish("YAMI_NATIVE_UI_PRESENTED", phase - 1 if wrong_phase else phase)

        def escape(platform, click_args):
            calls.append("escape")
            publish("YAMI_NATIVE_UI_COMPLETE", len(COUNTS[fixture]) - 1, destroyed=destroyed)

        with patch.object(driver.subprocess, "Popen", side_effect=launch), \
             patch.object(driver.native, "ProcessOutput", side_effect=create_output), \
             patch.object(driver.native, "_send_click", side_effect=click), \
             patch.object(driver.native, "_send_escape", side_effect=escape):
            if exit_code or not destroyed or wrong_phase:
                with self.assertRaises(driver.E2EError):
                    driver.run_fixture(args, fixture, COUNTS[fixture], Path("owned-binary"),
                                       Path("workspace"), evidence, {})
                trace = json.loads((evidence / fixture / "trace.json").read_text())
                self.assertEqual(trace["status"], "fail")
            else:
                trace = driver.run_fixture(args, fixture, COUNTS[fixture], Path("owned-binary"),
                                           Path("workspace"), evidence, {})
                self.assertEqual(trace["status"], "pass")
                self.assertEqual([item["count"] for item in trace["presented"]], COUNTS[fixture])
                self.assertEqual(calls, ["launch"] + ["click"] * (len(COUNTS[fixture]) - 1) + ["escape"])
            self.assertTrue((evidence / fixture / "native-ui.log").read_text())
            self.assertTrue(trace["cleanup"]["reaped"])
        return calls

    def test_counter_runs_two_separate_host_clicks_then_escape(self):
        self.exercise()

    def test_disabled_loading_runs_three_separate_host_clicks_then_escape(self):
        self.exercise("disabled-loading")

    def test_success_markers_cannot_override_nonzero_exit(self):
        self.exercise(exit_code=7)

    def test_escape_without_destroyed_is_not_success(self):
        self.exercise(destroyed=False)

    def test_wrong_phase_stops_before_another_input(self):
        self.assertEqual(self.exercise(wrong_phase=True), ["launch", "click"])


if __name__ == "__main__":
    unittest.main()
