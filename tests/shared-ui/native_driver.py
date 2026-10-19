#!/usr/bin/env python3
"""Opt-in real Linux/Windows shared-counter evidence; importing is inert.

This driver proves the bounded shared-ui-contract/v1 pointer fixtures and the
shared Button theme's real pointer/Space trace. It does not establish general
DOM/native parity, full keyboard/IME behavior or accessibility.
Host input and pixel decoding use the existing native-ui helpers. Unit tests
exercise this oracle with explicitly synthetic data, never host input.
"""
from __future__ import annotations

import argparse
from datetime import datetime, timezone
import hashlib
import importlib.util
import json
import math
import os
from pathlib import Path
import platform as host_platform
import re
import subprocess
import sys
import tempfile
import time
from typing import Any
import uuid

ROOT = Path(__file__).resolve().parents[2]
# Only these declared fixtures are driven with actual native host pointer input.
# Additional Button contracts are validated below, but portable event tests must
# never be presented as native-window/keyboard qualification.
FIXTURES = {"counter": "counter-two-activations", "disabled-loading": "counter-disabled-loading", "card": "card-counter-two-activations", "spacing": "spacing-count-and-toggle", "palette": "palette-count-and-toggle", "shell": "shell-counter-two-activations", "shell-compact": "shell-compact-counter-two-activations", "shell-visible": "shell-visible-wide", "shell-visible-compact": "shell-visible-compact"}
CONTRACT_PHASES = {
    "counter-two-activations": 3,
    "card-counter-two-activations": 3,
    "spacing-count-and-toggle": 5,
    "palette-count-and-toggle": 6,
    "shell-counter-two-activations": 3,
    "shell-compact-counter-two-activations": 3,
    "shell-visible-wide": 1,
    "shell-visible-compact": 1,
    "counter-disabled-loading": 4,
    "button-interrupted-loading": 6,
    "button-interrupted-disabled": 6,
}
SHA = re.compile(r"[0-9a-f]{40}\Z")
COMMON_PATHS = ("ui/core", "ui/runtime", "ui/theme", "examples/shared_counter", "examples/shared_button_theme")
BOUND_PATHS = (*COMMON_PATHS, "native/ui", "native/examples/shared_counter",
               "native/examples/shared_counter_host", "tests/shared-ui", "tests/native-ui/drive_native_ui.py",
               "styles/shared-ui.css", "fixtures/shared-ui", "tools/theme_tokens", "scripts/generate-shared-theme.mjs",
               "docs/shared-card.md", "docs/shared-stack-spacing.md", "docs/shared-button-palettes.md", "docs/shared-app-shell.md")

THEME_SLOTS = {"normal_border", "focused_border", "disabled_border", "normal_fill", "hovered_fill",
               "pressed_fill", "loading_fill", "disabled_fill", "enabled_foreground", "disabled_foreground"}
THEME_FLAGS = ("disabled", "loading", "focused", "hovered", "pressed")
THEME_CONTROL_KEYS = {"key-arm-inside": ("Right", 0x27), "key-arm-outside": ("Delete", 0x2E), "key-t": ("Prior", 0x21), "key-c": ("Next", 0x22),
                      "key-n": ("Home", 0x24), "key-d": ("End", 0x23),
                      "key-l": ("Up", 0x26), "key-b": ("Down", 0x28), "key-f": ("Left", 0x25)}
# These are observations of a fixed host-input trace, never controller logic.
# Gate transitions clear GPUI hover; Chromium's raw :hover can remain set.
THEME_PHASES = [dict(name=name, theme=theme, mode=mode, hovered=hovered, focused=focused,
                     pressed=pressed, count=count, inputs=inputs)
                for name, theme, mode, hovered, focused, pressed, count, inputs in [
    ("light-normal", "light", "normal", False, False, False, 0, []),
    ("dark-normal", "dark", "normal", False, False, False, 0, ["key-t"]),
    ("dark-hover", "dark", "normal", True, False, False, 0, ["move-inside"]),
    ("light-hover", "light", "normal", True, False, False, 0, ["key-t"]),
    ("light-focus-hover", "light", "normal", True, True, False, 0, ["key-f"]),
    ("dark-focus-hover", "dark", "normal", True, True, False, 0, ["key-t"]),
    ("dark-focus", "dark", "normal", False, True, False, 0, ["move-outside"]),
    ("dark-space-held", "dark", "normal", False, True, True, 0, ["space-down"]),
    ("light-space-held", "light", "normal", False, True, True, 0, ["key-t"]),
    ("light-space-activation", "light", "normal", False, True, False, 1, ["space-up"]),
    ("light-pointer-held", "light", "normal", True, True, True, 1, ["move-inside", "pointer-down"]),
    ("dark-pointer-held", "dark", "normal", True, True, True, 1, ["key-t"]),
    ("dark-pointer-activation", "dark", "normal", True, True, False, 2, ["pointer-up"]),
    ("dark-loading-focus", "dark", "loading", False, True, False, 2, ["key-l"]),
    ("light-loading-focus", "light", "loading", False, True, False, 2, ["key-t"]),
    ("light-disabled-loading", "light", "disabled-loading", False, False, False, 2, ["key-b"]),
    ("dark-disabled-loading", "dark", "disabled-loading", False, False, False, 2, ["key-t"]),
    ("dark-disabled", "dark", "disabled", False, False, False, 2, ["key-d"]),
    ("light-disabled", "light", "disabled", False, False, False, 2, ["key-t"]),
    ("light-reenabled", "light", "normal", False, False, False, 2, ["key-n"]),
    ("light-refocused", "light", "normal", False, True, False, 2, ["key-f"]),
    ("light-space-before-gate", "light", "normal", False, True, True, 2, ["space-down"]),
    ("light-space-loading-cancel", "light", "loading", False, True, False, 2, ["key-l"]),
    ("dark-space-loading-cancel", "dark", "loading", False, True, False, 2, ["key-t"]),
    ("dark-space-gate-restored", "dark", "normal", False, True, False, 2, ["key-n"]),
    ("dark-stale-space-release", "dark", "normal", False, True, False, 2, ["space-up"]),
    ("dark-pointer-before-gate", "dark", "normal", True, True, True, 2, ["move-inside", "pointer-down"]),
    ("dark-pointer-disabled-cancel", "dark", "disabled", False, False, False, 2, ["key-d"]),
    ("light-pointer-disabled-cancel", "light", "disabled", False, False, False, 2, ["key-t"]),
    ("light-pointer-gate-restored", "light", "normal", False, False, False, 2, ["key-n"]),
    # Windows can refresh hover when capture is released; an explicit exit and
    # re-entry gives both hosts the same observed hover while count stays fixed.
    ("light-stale-pointer-release", "light", "normal", True, False, False, 2,
     ["pointer-up", "move-outside", "move-inside"]),
    ("light-fresh-activation", "light", "normal", True, True, False, 3, ["move-inside", "pointer-down", "pointer-up"]),
    ("dark-retained-focus-hover", "dark", "normal", True, True, False, 3, ["key-t"]),
    ("dark-pointer-before-outside", "dark", "normal", True, True, True, 3, ["pointer-down"]),
    ("light-outside-cancel", "light", "normal", False, True, False, 3, ["move-outside", "key-t", "pointer-up"]),
    ("light-final-activation", "light", "normal", True, True, False, 4, ["move-inside", "pointer-down", "pointer-up"]),
]]


def _load_legacy() -> Any:
    name = "_yami_shared_ui_native_helpers"
    spec = importlib.util.spec_from_file_location(name, ROOT / "tests/native-ui/drive_native_ui.py")
    if spec is None or spec.loader is None:
        raise RuntimeError("cannot load native-ui helpers")
    module = importlib.util.module_from_spec(spec)
    sys.modules[name] = module
    spec.loader.exec_module(module)
    return module


# The imported module has a __main__ guard. No process, GUI, input, or build runs
# during either import. In particular, no macOS input helper is ever called here.
def _load_palette() -> Any:
    # The provenance script loads this driver by path from another directory.
    # Resolve the sibling explicitly rather than relying on sys.path or cwd.
    spec = importlib.util.spec_from_file_location("_yami_palette_oracle", Path(__file__).with_name("palette_oracle.py"))
    if spec is None or spec.loader is None:
        raise RuntimeError("cannot load palette oracle")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


palette = _load_palette()
validate_palette_marker = palette.validate_palette_marker
validate_palette_sequence = palette.validate_palette_sequence
inspect_palette_pixels = palette.inspect_palette_pixels
native = _load_legacy()
E2EError = native.E2EError


def load_contract(path: Path = ROOT / "fixtures/shared-ui/contract-v1.json") -> dict[str, Any]:
    contract = json.loads(path.read_text(encoding="utf-8"))
    if contract.get("version") != "shared-ui-contract/v1" or contract.get("profileDifferences") != []:
        raise E2EError("unsupported shared UI contract")
    fixtures = contract.get("fixtures")
    if not isinstance(fixtures, list) or len(fixtures) != len(CONTRACT_PHASES):
        raise E2EError("shared UI contract fixture set changed")
    by_id = {item.get("id"): item.get("expected") for item in fixtures}
    if set(by_id) != set(CONTRACT_PHASES):
        raise E2EError("shared UI contract has unknown or duplicate fixtures")
    for fixture_id, count in CONTRACT_PHASES.items():
        expected = by_id[fixture_id]
        if not isinstance(expected, dict) or set(expected) != {"counts"}:
            raise E2EError("fixture expectation must contain only counts")
        values = expected["counts"]
        if not isinstance(values, list) or len(values) != count or any(type(v) is not int for v in values):
            raise E2EError("fixture count phases changed")
    return contract


def expected_counts(contract: dict[str, Any], fixture: str) -> list[int]:
    for item in contract["fixtures"]:
        if item["id"] == FIXTURES[fixture]:
            return item["expected"]["counts"]
    raise E2EError("fixture is missing from the contract")


def _number(value: Any, label: str, *, positive: bool = False) -> float:
    if type(value) not in (int, float) or not math.isfinite(value) or (positive and value <= 0):
        raise E2EError(f"{label} must be a finite {'positive ' if positive else ''}number")
    return float(value)


def _bounds(value: Any, label: str) -> tuple[float, float, float, float]:
    if not isinstance(value, dict):
        raise E2EError(f"{label} bounds must be an object")
    for key in ("x", "y", "width", "height"):
        _number(value.get(key), f"{label}.{key}", positive=key in ("width", "height"))
    return native._rect(value, label)


def _inside(inner: tuple[float, ...], outer: tuple[float, ...], label: str) -> None:
    x, y, w, h = inner
    ox, oy, ow, oh = outer
    if x < ox or y < oy or x + w > ox + ow + 1e-6 or y + h > oy + oh + 1e-6:
        raise E2EError(f"{label} is outside its containing bounds")


def validate_marker(marker: dict[str, Any], fixture: str, phase: int,
                    counts: list[int], *, presented: bool = False,
                    complete: bool = False) -> None:
    """Check fixed contract phases without treating self-reported counts as pixels."""
    if not isinstance(marker, dict) or marker.get("fixture") != fixture:
        raise E2EError("marker fixture does not match the launched fixture")
    if type(marker.get("phase")) is not int or marker["phase"] != phase:
        raise E2EError(f"expected exact phase {phase}, got {marker.get('phase')!r}")
    if phase < 0 or phase >= len(counts):
        raise E2EError("phase is outside the contract")
    count = counts[phase]
    for key in ("count", "value"):
        if type(marker.get(key)) is not int or marker[key] != count:
            raise E2EError(f"phase {phase} expected {key} {count}, got {marker.get(key)!r}")
    for key in ("enabled", "loading", "pressed", "focused"):
        if type(marker.get(key)) is not bool:
            raise E2EError(f"{key} must be a boolean")
    enabled = fixture != "disabled-loading" or phase > 0
    loading = fixture == "disabled-loading" and phase == 1
    if marker["enabled"] != enabled or marker["loading"] != loading:
        raise E2EError("phase button enabled/loading gates do not match the fixture")
    if marker["pressed"]:
        raise E2EError("settled phase cannot have a pressed button")
    if type(marker.get("releases")) is not int or marker["releases"] != phase:
        raise E2EError("phase must follow exactly one actual primary release per click")
    if marker.get("actions") != ["Activate"] * (phase if fixture in ("spacing", "palette") else count):
        raise E2EError("accepted action trace disagrees with the contract count")
    scale = _number(marker.get("scale"), "scale", positive=True)
    root = _bounds(marker.get("root"), "root")
    if root[:2] != (0.0, 0.0):
        raise E2EError("root must use frame-local origin")
    for key in ("button", "buttonLabel", "counter"):
        _inside(_bounds(marker.get(key), key), root, key)
    _inside(_bounds(marker["buttonLabel"], "buttonLabel"), _bounds(marker["button"], "button"), "buttonLabel")
    scene = marker.get("scene")
    if not isinstance(scene, dict) or not isinstance(scene.get("items"), list):
        raise E2EError("marker must contain canonical scene object and items")
    texts = [item.get("text") for item in scene["items"] if isinstance(item, dict)
             and item.get("kind") in ("text", "text_run")]
    if fixture == "spacing":
        labels = (f"Count: {count}", "Increment", "Shared <stack>", "Spacing", "Fixed Card")
    elif fixture == "palette":
        labels = (f"Count: {count}", "Increment", "Shared palette", "Palette")
    elif fixture in ("shell", "shell-compact", "shell-visible", "shell-visible-compact"):
        labels = (f"Count: {count}", "Increment", "Shared AppShell")
    else:
        labels = (f"Count: {count}", "Increment", "Shared counter")
    if any(texts.count(text) != 1 for text in labels):
        raise E2EError("canonical scene is missing or duplicates shared counter text")
    if _bounds(scene.get("viewport"), "scene.viewport") != root:
        raise E2EError("scene viewport disagrees with root bounds")
    if _number(scene.get("scale"), "scene.scale", positive=True) != scale:
        raise E2EError("scene scale disagrees with native scale")
    if fixture == "palette":
        validate_palette_marker(marker, phase)
    if fixture == "spacing":
        validate_spacing_geometry(marker, phase)
    if fixture == "card":
        validate_card_geometry(marker)
        if phase > 0 and marker["focused"] is not True:
            raise E2EError("Card nested Button lost actual pointer focus")
    if fixture in ("shell", "shell-compact", "shell-visible", "shell-visible-compact"):
        validate_shell_marker(marker, fixture)
    if presented or complete:
        frame = marker.get("frame")
        if not isinstance(frame, dict) or not isinstance(frame.get("path"), str) or not frame["path"]:
            raise E2EError("presented frame requires retained PPM path")
        for key in ("width", "height"):
            if type(frame.get(key)) is not int or frame[key] <= 0:
                raise E2EError("frame dimensions must be positive integers")
        if _number(frame.get("scale"), "frame.scale", positive=True) != scale:
            raise E2EError("capture scale disagrees with native scale")
        if abs(root[2] * scale - frame["width"]) > 1 or abs(root[3] * scale - frame["height"]) > 1:
            raise E2EError("root dimensions disagree with native capture")
    if complete and marker.get("destroyed") is not True:
        raise E2EError("COMPLETE must confirm host window destruction")



def validate_card_geometry(marker: dict[str, Any]) -> None:
    """Fixed <=1 logical pixel snapping budget, never font-size parity."""
    card = _bounds(marker.get("card"), "card")
    _inside(card, _bounds(marker.get("root"), "root"), "card")
    children = [_bounds(marker.get(key), key) for key in ("heading", "counter", "button")]
    x, y, width, height = card
    # Native children retain intrinsic widths; the content envelope, not every
    # individual child, meets the right padding edge. DOM flex children stretch.
    differences = [children[0][1] - y, y + height - children[-1][1] - children[-1][3],
                   min(child[0] for child in children) - x,
                   x + width - max(child[0] + child[2] for child in children)]
    for child in children:
        _inside(child, card, "Card child")
    if any(abs(value - 17) > 1 for value in differences):
        raise E2EError("Card content inset must be border 1 plus padding 16")
    gaps = [b[1] - a[1] - a[3] for a, b in zip(children, children[1:])]
    if any(abs(gap - 12) > 1 for gap in gaps):
        raise E2EError("Card child gap must be 12 logical pixels")
    validate_card_paint(marker, ("Shared counter", f"Count: {marker['count']}", "Increment"))


def validate_card_paint(marker: dict[str, Any], child_texts: tuple[str, ...], *,
                        allow_preceding_siblings: bool = False) -> None:
    """Bind the fixed Card quads and order to their actual descendant text."""
    card = _bounds(marker.get("card"), "card")
    x, y, width, height = card
    items = marker["scene"]["items"]
    border = [i for i, item in enumerate(items) if item.get("kind") == "quad"
              and _bounds(item.get("bounds"), "quad") == card]
    if len(border) != 1:
        raise E2EError("Card must paint exactly one outer border quad")
    index = border[0]
    if index + 1 >= len(items):
        raise E2EError("Card interior quad missing")
    outer, inner = items[index:index + 2]
    if outer.get("color") != {"red":166,"green":171,"blue":178,"alpha":255}:
        raise E2EError("Card border color changed")
    if inner.get("kind") != "quad" or inner.get("color") != {"red":245,"green":247,"blue":250,"alpha":255}:
        raise E2EError("Card interior color changed")
    if _bounds(inner.get("bounds"), "Card interior") != (x+1, y+1, width-2, height-2):
        raise E2EError("Card painted border must be exactly 1 logical pixel")
    if any(item.get("kind") in ("text", "text_run")
           and (not allow_preceding_siblings or item.get("text") in child_texts)
           for item in items[:index + 2]):
        raise E2EError("Card paint must precede its text descendants")
    ids = [item.get("id") for item in items]
    if any(type(value) is not int or value <= 0 for value in ids) or len(set(ids)) != len(ids):
        raise E2EError("scene IDs must be unique positive integers")


SPACING_KEYS = {"expanded", "stack", "row", "cardLabel", "toggle", "toggleLabel",
                "togglePressed", "toggleFocused", "buttonId", "toggleId", "actionKeys"}
SPACING_ACTIONS = ["increment", "spacing-toggle", "increment", "spacing-toggle"]
SPACING_EXPANDED = [False, False, True, True, False]
GEOMETRY_TOLERANCE = 1.0  # Logical pixels; fixed before implementation and capture.


def _stack_geometry(parent: tuple[float, ...], children: list[tuple[float, ...]],
                    *, axis: int, gap: float, padding: float, label: str) -> None:
    """Intrinsic fixtures measure all edges of the direct-child content union."""
    x, y, width, height = parent
    for child in children:
        _inside(child, parent, label + " child")
    insets = (min(child[0] for child in children) - x,
              min(child[1] for child in children) - y,
              x + width - max(child[0] + child[2] for child in children),
              y + height - max(child[1] + child[3] for child in children))
    if any(abs(value - padding) > GEOMETRY_TOLERANCE for value in insets):
        raise E2EError(f"{label} content-union padding must be {padding} logical pixels")
    if any(abs(b[axis] - a[axis] - a[axis + 2] - gap) > GEOMETRY_TOLERANCE
           for a, b in zip(children, children[1:])):
        raise E2EError(f"{label} ordered child gap must be {gap} logical pixels")


def validate_spacing_geometry(marker: dict[str, Any], phase: int) -> None:
    spacing = marker.get("spacing")
    if not isinstance(spacing, dict) or set(spacing) != SPACING_KEYS:
        raise E2EError("spacing observation schema is incomplete or unknown")
    if type(spacing["expanded"]) is not bool or spacing["expanded"] != SPACING_EXPANDED[phase]:
        raise E2EError("spacing model expanded state does not match the pointer phase")
    if spacing["actionKeys"] != SPACING_ACTIONS[:phase]:
        raise E2EError("spacing action targets do not match actual pointer sequence")
    if any(type(spacing[key]) is not bool for key in ("toggleFocused", "togglePressed")):
        raise E2EError("spacing focus/pressed observations must be booleans")
    if spacing["togglePressed"]:
        raise E2EError("spacing settled phase cannot have a pressed toggle")
    if marker["focused"] != (phase in (1, 3)) or spacing["toggleFocused"] != (phase in (2, 4)):
        raise E2EError("actual pointer focus was not preserved through spacing updates")
    ids = (spacing["buttonId"], spacing["toggleId"])
    if any(type(value) is not int or value <= 0 for value in ids) or ids[0] == ids[1]:
        raise E2EError("spacing Button binding IDs must be distinct positive integers")
    items = marker["scene"]["items"]
    for text, binding_id in zip(("Increment", "Spacing"), ids):
        labels = [item for item in items if item.get("kind") in ("text", "text_run") and item.get("text") == text]
        if len(labels) != 1 or labels[0].get("id") != binding_id + 3:
            raise E2EError("spacing binding ID does not identify the actual scene Button label")
    stack = _bounds(spacing["stack"], "spacing.stack")
    row = _bounds(spacing["row"], "spacing.row")
    card = _bounds(marker.get("card"), "card")
    heading = _bounds(marker.get("heading"), "heading")
    counter = _bounds(marker.get("counter"), "counter")
    button = _bounds(marker.get("button"), "button")
    toggle = _bounds(spacing["toggle"], "spacing.toggle")
    card_label = _bounds(spacing["cardLabel"], "spacing.cardLabel")
    _inside(stack, _bounds(marker["root"], "root"), "spacing.stack")
    _inside(_bounds(spacing["toggleLabel"], "spacing.toggleLabel"), toggle, "spacing.toggleLabel")
    expanded = spacing["expanded"]
    _stack_geometry(stack, [heading, counter, row, card], axis=1,
                    gap=12 if expanded else 0, padding=16 if expanded else 4, label="outer stack")
    _stack_geometry(row, [button, toggle], axis=0,
                    gap=16 if expanded else 4, padding=8 if expanded else 0, label="inner row")
    _stack_geometry(card, [card_label], axis=1, gap=12, padding=17, label="fixed Card")
    validate_card_paint(marker, ("Fixed Card",), allow_preceding_siblings=True)


def validate_spacing_sequence(markers: list[dict[str, Any]]) -> None:
    if len(markers) != 5:
        raise E2EError("spacing requires all five settled phases")
    for phase, marker in enumerate(markers):
        validate_spacing_geometry(marker, phase)
        for field in ("buttonId", "toggleId"):
            if marker["spacing"][field] != markers[0]["spacing"][field]:
                raise E2EError("spacing update replaced a stable native Button binding ID")
        for field in ("root", "scale"):
            if marker[field] != markers[0][field]:
                raise E2EError(f"spacing host {field} changed across settled phases")
    # Fresh pointer activations must be delivered at moved geometry, then return
    # to the original collapsed geometry after the second toggle.
    for field in ("stack", "row", "toggle"):
        if markers[2]["spacing"][field] == markers[1]["spacing"][field]:
            raise E2EError(f"spacing {field} did not move/change after toggle")
        if markers[4]["spacing"][field] != markers[0]["spacing"][field]:
            raise E2EError(f"spacing {field} did not restore its collapsed geometry")
    if markers[2]["button"] == markers[1]["button"]:
        raise E2EError("spacing increment Button did not move before fresh activation")


def validate_shell_marker(marker: dict[str, Any], fixture: str) -> None:
    """Validate shell mode, region visibility and the main Button's enclosure."""
    shell = marker.get("shell")
    if not isinstance(shell, dict) or set(shell) != {"mode", "regions"}:
        raise E2EError("shell marker is missing its mode/regions observation")
    mode = shell.get("mode")
    if mode not in ("wide", "compact"):
        raise E2EError("shell mode must be wide or compact")
    regions = shell.get("regions")
    expected_regions = {"brand", "navigationTrigger", "globalSearch", "headerActions",
                        "accountMenu", "rail", "sidebar", "tabs", "main",
                        "contextPanel", "bottomBar"}
    if not isinstance(regions, dict) or set(regions) != expected_regions:
        raise E2EError("shell region observation schema is incomplete or unknown")
    for name in ("brand", "main"):
        if not isinstance(regions[name], dict):
            raise E2EError(f"required shell region {name} has no bounds")
    if mode == "wide":
        for name in ("rail", "sidebar"):
            if not isinstance(regions[name], dict):
                raise E2EError(f"wide shell region {name} is missing")
        for name in ("navigationTrigger", "contextPanel"):
            if regions[name] is not None:
                raise E2EError(f"wide shell region {name} must be absent")
    else:
        for name in ("rail", "sidebar", "contextPanel"):
            if regions[name] is not None:
                raise E2EError(f"compact shell region {name} must be absent")
        if not isinstance(regions["navigationTrigger"], dict):
            raise E2EError("compact shell navigation trigger is missing")
    root = _bounds(marker.get("root"), "root")
    # The fixture is an outer-window request; compositors may clamp it. Validate
    # that the observed mode agrees with the actual content width and keep the
    # height positive rather than assuming a title-bar-free exact height.
    if mode == "wide" and root[2] <= 820:
        raise E2EError("wide shell root width must exceed the compact boundary")
    if mode == "compact" and root[2] > 820:
        raise E2EError("compact shell root width exceeds the compact boundary")
    if root[3] <= 0 or root[3] > 1000:
        raise E2EError("shell root height is outside the bounded content envelope")
    main = _bounds(regions["main"], "shell.main")
    brand = _bounds(regions["brand"], "shell.brand")
    _inside(main, root, "shell.main")
    _inside(brand, root, "shell.brand")
    button = _bounds(marker.get("button"), "button")
    label = _bounds(marker.get("buttonLabel"), "buttonLabel")
    counter = _bounds(marker.get("counter"), "counter")
    _inside(button, main, "button")
    _inside(label, button, "buttonLabel")
    _inside(counter, main, "counter")
    if marker.get("buttonName") != "Increment":
        raise E2EError("shell AX Button name changed")
    if mode == "wide":
        rail = _bounds(regions["rail"], "shell.rail")
        sidebar = _bounds(regions["sidebar"], "shell.sidebar")
        _inside(rail, root, "shell.rail")
        _inside(sidebar, root, "shell.sidebar")
        if rail[0] + rail[2] > sidebar[0] + 1:
            raise E2EError("wide rail overlaps the sidebar")
        if sidebar[0] + sidebar[2] > main[0] + 1:
            raise E2EError("wide sidebar overlaps main")


def inspect_card_pixels(image: Any, marker: dict[str, Any]) -> list[list[int]]:
    x, y, w, h = _bounds(marker["card"], "card")
    scale = marker["scale"]
    # Four edge midpoints and an interior padding point; none overlaps text.
    points = [(x+w/2,y+0.5),(x+w-0.5,y+h/2),(x+w/2,y+h-0.5),(x+0.5,y+h/2),(x+4,y+4)]
    colors = [list(image.pixel(int(px*scale), int(py*scale))) for px, py in points]
    for actual, expected in zip(colors, [(166,171,178)]*4 + [(245,247,250)]):
        if len(actual) != 3 or any(abs(a-b) > 2 for a,b in zip(actual,expected)):
            raise E2EError("actual Card border/interior pixels disagree with the fixed paint")
    return colors

def inspect_frame(marker: dict[str, Any], directory: Path) -> tuple[Any, dict[str, Any]]:
    path = native._read_ppm_path(marker["frame"], directory, f"phase {marker['phase']}")
    image = native.read_ppm(path)
    frame = marker["frame"]
    if (image.width, image.height) != (frame["width"], frame["height"]):
        raise E2EError("PPM dimensions disagree with capture metadata")
    scale = marker["scale"]
    counter_pixels = native._foreground_count(image, _bounds(marker["counter"], "counter"), scale)
    label_pixels = native._foreground_count(image, _bounds(marker["buttonLabel"], "buttonLabel"), scale)
    button_pixels = native._foreground_count(image, _bounds(marker["button"], "button"), scale,
                                              native._frame_background(image))
    if counter_pixels <= 0:
        raise E2EError("counter has no contrasting text pixels")
    if label_pixels <= 0:
        raise E2EError("button label has no contrasting pixels inside its label bounds")
    if button_pixels <= 0:
        raise E2EError("button has no visible foreground pixels")
    card_pixels = inspect_card_pixels(image, marker) if marker["fixture"] in ("card", "spacing") else None
    toggle_pixels = None
    if marker["fixture"] == "spacing":
        toggle_pixels = native._foreground_count(image, _bounds(marker["spacing"]["toggleLabel"], "toggleLabel"), scale)
        if toggle_pixels <= 0:
            raise E2EError("spacing toggle label has no contrasting pixels")
    palette_pixels = inspect_palette_pixels(image, marker) if marker["fixture"] == "palette" else None
    return image, {"palettePixels": palette_pixels, "toggleLabelPixels": toggle_pixels, "cardPixels": card_pixels, "path": str(path), "sha256": digest(path), "width": image.width,
                   "height": image.height, "scale": scale, "counterPixels": counter_pixels,
                   "buttonLabelPixels": label_pixels, "buttonPixels": button_pixels}


def inspect_frame_sequence(markers: list[dict[str, Any]], directory: Path) -> dict[str, Any]:
    if len(markers) == 1:
        _, report = inspect_frame(markers[0], directory)
        return {"captures": [report], "changedCounterPixels": 0}
    images, reports, paths = [], [], set()
    spacing = bool(markers) and markers[0]["fixture"] == "spacing"
    if markers and markers[0]["fixture"] == "palette":
        validate_palette_sequence(markers)
    if spacing:
        validate_spacing_sequence(markers)
    for marker in markers:
        image, report = inspect_frame(marker, directory)
        if report["path"] in paths:
            raise E2EError("each phase must retain a distinct PPM capture path")
        paths.add(report["path"])
        images.append(image)
        reports.append(report)
        if marker["fixture"] in ("shell", "shell-compact", "shell-visible", "shell-visible-compact"):
            # The shell counter is an intrinsic text column; "Count: 1" can be
            # narrower than "Count: 0" with proportional host fonts.
            stable = ("root", "button", "buttonLabel", "scale")
        else:
            stable = ("root", "scale") if spacing else ("root", "counter", "button", "buttonLabel", "scale")
            if marker["fixture"] == "card":
                stable += ("card", "heading")
        for key in stable:
            if marker[key] != markers[0][key]:
                raise E2EError(f"{key} changed between settled phase captures")
    counter = _bounds(markers[0]["counter"], "counter")
    changed = native._changed_pixels(images[0], images[-1], counter, markers[0]["scale"])
    if changed <= 0:
        raise E2EError("final counter pixels did not change from the initial capture")
    # Disabled/loading transitions must preserve the actual visible count too.
    for index in range(1, len(markers)):
        if spacing:
            previous = native._region_pixels(images[index - 1], _bounds(markers[index - 1]["counter"], "counter"), markers[index - 1]["scale"])
            current = native._region_pixels(images[index], _bounds(markers[index]["counter"], "counter"), markers[index]["scale"])
            if markers[index]["count"] == markers[index - 1]["count"] and previous != current:
                raise E2EError("spacing-only update changed the translated counter pixels")
            if markers[index]["count"] != markers[index - 1]["count"] and previous == current:
                raise E2EError("spacing increment did not change the counter pixels")
        elif markers[index]["count"] == markers[index - 1]["count"]:
            if native._changed_pixels(images[index - 1], images[index], counter, markers[index]["scale"]) != 0:
                raise E2EError("gated click changed the counter pixels")
    return {"captures": reports, "changedCounterPixels": changed}


def load_theme_contract(path: Path = ROOT / "fixtures/shared-ui/button-theme-v1.json") -> dict[str, Any]:
    contract = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(contract, dict) or contract.get("version") != "shared-button-theme/v1":
        raise E2EError("unsupported shared Button theme contract")
    themes = contract.get("themes")
    if not isinstance(themes, dict) or set(themes) != {"light", "dark"}:
        raise E2EError("theme contract requires exact light and dark palettes")
    for palette in themes.values():
        if not isinstance(palette, dict) or set(palette) != THEME_SLOTS:
            raise E2EError("theme contract requires all ten semantic color slots")
        for rgb in palette.values():
            if not isinstance(rgb, list) or len(rgb) != 3 or any(type(c) is not int or not 0 <= c <= 255 for c in rgb):
                raise E2EError("theme color must be an opaque RGB triple")
    states = contract.get("states")
    if not isinstance(states, list) or len(states) != 32:
        raise E2EError("theme contract requires all 32 state combinations")
    seen = set()
    for state in states:
        if not isinstance(state, dict) or set(state) != set(THEME_FLAGS) | {"border", "fill", "foreground"}:
            raise E2EError("theme state schema changed")
        if any(type(state[k]) is not bool for k in THEME_FLAGS):
            raise E2EError("theme state flags must be booleans")
        key = tuple(state[k] for k in THEME_FLAGS)
        if key in seen:
            raise E2EError("duplicate theme state expectation")
        seen.add(key)
        for field in ("border", "fill", "foreground"):
            if state[field] not in THEME_SLOTS or not state[field].endswith("_" + field):
                raise E2EError("theme state refers to an invalid paint slot")
    return contract


def theme_colors(marker: dict[str, Any], contract: dict[str, Any]) -> dict[str, list[int]]:
    flags = {"disabled": not marker["enabled"], **{name: marker[name] for name in THEME_FLAGS[1:]}}
    matched = [state for state in contract["states"] if all(state[key] == value for key, value in flags.items())]
    if len(matched) != 1:
        raise E2EError("native Button state has no unique shared paint expectation")
    return {field: contract["themes"][marker["theme"]][matched[0][field]]
            for field in ("border", "fill", "foreground")}


def validate_theme_marker(marker: dict[str, Any], phase: int, contract: dict[str, Any], *,
                          complete: bool = False) -> None:
    if not isinstance(marker, dict) or marker.get("fixture") != "theme":
        raise E2EError("theme marker does not identify the launched fixture")
    if type(marker.get("phase")) is not int or marker["phase"] != phase or not 0 <= phase < len(THEME_PHASES):
        raise E2EError("theme marker skipped, duplicated or changed its exact capture phase")
    expected = THEME_PHASES[phase]
    for field in ("theme", "mode", "hovered", "focused", "pressed", "count"):
        if type(marker.get(field)) is not type(expected[field]) or marker[field] != expected[field]:
            raise E2EError(f"theme phase {phase} {expected['name']} has unexpected {field}: {marker.get(field)!r}")
    for field, value in (("enabled", expected["mode"] not in ("disabled", "disabled-loading")),
                         ("loading", expected["mode"] in ("loading", "disabled-loading")),
                         ("value", expected["count"])):
        if type(marker.get(field)) is not type(value) or marker[field] != value:
            raise E2EError(f"theme {field} does not match common fixture props")
    if marker.get("actionKeys") != ["increment"] * expected["count"]:
        raise E2EError("theme trace has lost, duplicated or redirected semantic activation")
    for field in ("buttonId", "toggleId", "revision", "windowId"):
        if type(marker.get(field)) is not int or marker[field] <= 0:
            raise E2EError(f"theme {field} must be a positive native identity")
    if marker["buttonId"] == marker["toggleId"]:
        raise E2EError("theme Buttons must have distinct identities")
    if type(marker.get("inputSequence")) is not int or marker["inputSequence"] < 0:
        raise E2EError("theme host input sequence is invalid")
    if not isinstance(marker.get("title"), str) or not marker["title"]:
        raise E2EError("theme marker has no uniquely bound window title")
    scale = _number(marker.get("scale"), "theme.scale", positive=True)
    root = _bounds(marker.get("root"), "root")
    if root[:2] != (0.0, 0.0):
        raise E2EError("theme root must have frame-local origin")
    for field in ("button", "buttonLabel", "counter", "heading", "toggle", "toggleLabel"):
        _inside(_bounds(marker.get(field), field), root, field)
    _inside(_bounds(marker["buttonLabel"], "buttonLabel"), _bounds(marker["button"], "button"), "buttonLabel")
    _inside(_bounds(marker["toggleLabel"], "toggleLabel"), _bounds(marker["toggle"], "toggle"), "toggleLabel")
    scene = marker.get("scene")
    if not isinstance(scene, dict) or not isinstance(scene.get("items"), list):
        raise E2EError("theme marker requires a canonical scene")
    if _bounds(scene.get("viewport"), "scene.viewport") != root or _number(scene.get("scale"), "scene.scale", positive=True) != scale:
        raise E2EError("theme scene viewport or scale disagrees with its host")
    items = scene["items"]
    if any(not isinstance(item, dict) for item in items):
        raise E2EError("theme scene item must be an object")
    ids = [item.get("id") for item in items]
    if any(type(value) is not int or value <= 0 for value in ids) or len(set(ids)) != len(ids):
        raise E2EError("theme scene IDs must be unique positive integers")
    texts = [item.get("text") for item in items if item.get("kind") in ("text", "text_run")]
    if any(texts.count(value) != 1 for value in ("Shared Button theme", "Increment", "Toggle theme", f"Count: {marker['count']}")):
        raise E2EError("theme canonical scene lost or duplicated common fixture text")
    binding = marker["buttonId"]
    paint = []
    for offset, kind in ((1, "quad"), (2, "quad"), (3, "text")):
        matches = [item for item in items if item["id"] == binding + offset]
        if len(matches) != 1 or (matches[0].get("kind") not in ("text", "text_run") if kind == "text" else matches[0].get("kind") != kind):
            raise E2EError("theme scene does not use the retained GPUI Button paint IDs")
        paint.append(matches[0])
    if [items.index(item) for item in paint] != list(range(items.index(paint[0]), items.index(paint[0]) + 3)):
        raise E2EError("theme border, fill and measured text order changed")
    expected_colors = theme_colors(marker, contract)
    for item, field in zip(paint, ("border", "fill", "foreground")):
        rgb = expected_colors[field]
        if item.get("color") != dict(zip(("red", "green", "blue", "alpha"), [*rgb, 255])):
            raise E2EError(f"theme scene {field} differs from shared semantic tokens")
    x, y, width, height = _bounds(marker["button"], "button")
    inset = 2 if marker["focused"] else 1
    if _bounds(paint[0].get("bounds"), "border") != (x, y, width, height):
        raise E2EError("theme border is detached from the retained Button")
    if _bounds(paint[1].get("bounds"), "fill") != (x + inset, y + inset, width - 2 * inset, height - 2 * inset):
        raise E2EError("theme fill no longer has the GPUI focus inset")
    if paint[2].get("text") != "Increment":
        raise E2EError("theme foreground is not the actual Button label")
    frame = marker.get("frame")
    if not isinstance(frame, dict) or not isinstance(frame.get("path"), str) or not frame["path"]:
        raise E2EError("theme observation requires a retained PPM path")
    if any(type(frame.get(k)) is not int or frame[k] <= 0 for k in ("width", "height")):
        raise E2EError("theme capture dimensions must be positive integers")
    if _number(frame.get("scale"), "frame.scale", positive=True) != scale:
        raise E2EError("theme capture scale disagrees with native scale")
    if abs(root[2] * scale - frame["width"]) > 1 or abs(root[3] * scale - frame["height"]) > 1:
        raise E2EError("theme capture dimensions disagree with its scene")
    if complete and marker.get("destroyed") is not True:
        raise E2EError("theme completion requires actual window destruction")


def inspect_theme_frame(marker: dict[str, Any], directory: Path, contract: dict[str, Any]) -> tuple[Any, dict[str, Any]]:
    path = native._read_ppm_path(marker["frame"], directory, f"theme phase {marker['phase']}")
    image = native.read_ppm(path)
    if (image.width, image.height) != (marker["frame"]["width"], marker["frame"]["height"]):
        raise E2EError("theme PPM dimensions differ from native capture metadata")
    colors, scale = theme_colors(marker, contract), marker["scale"]
    x, y, w, h = _bounds(marker["button"], "button")
    samples = [("border", x + w / 2, y + .5), ("border", x + .5, y + h / 2),
               ("border", x + w - .5, y + h / 2), ("border", x + w / 2, y + h - .5),
               ("fill", x + 4, y + h / 2)]
    observed = []
    for slot, px, py in samples:
        actual = list(image.pixel(int(px * scale), int(py * scale)))
        if len(actual) != 3 or any(abs(a - b) > 2 for a, b in zip(actual, colors[slot])):
            raise E2EError(f"theme actual {slot} pixels differ from shared tokens at phase {marker['phase']}")
        observed.append({"slot": slot, "rgb": actual})
    region = native._region_pixels(image, _bounds(marker["buttonLabel"], "buttonLabel"), scale)
    # Fractional glyph origins need not produce an opaque foreground pixel.
    # Test the expected foreground/fill blend instead of weakening scene RGB.
    delta = [a - b for a, b in zip(colors["foreground"], colors["fill"])]
    magnitude = sum(channel * channel for channel in delta)
    if magnitude == 0:
        raise E2EError("theme Button foreground has no contrast against fill")
    covered = []
    for pixel in region:
        coverage = sum((actual - background) * channel
                       for actual, background, channel in zip(pixel, colors["fill"], delta)) / magnitude
        residual = max(abs(actual - (background + coverage * channel))
                       for actual, background, channel in zip(pixel, colors["fill"], delta))
        if .5 <= coverage <= 1.01 and residual <= 2:
            covered.append((coverage, residual))
    # A few accidental colored pixels cannot qualify this nine-letter label.
    if len(covered) < 8:
        raise E2EError("theme Button label lacks nontrivial pixels matching its semantic foreground blend")
    counter_pixels = native._foreground_count(image, _bounds(marker["counter"], "counter"), scale)
    if counter_pixels <= 0:
        raise E2EError("theme fixture count has no visible text pixels")
    return image, {"path": str(path), "sha256": digest(path), "width": image.width, "height": image.height,
                   "scale": scale, "samples": observed, "foregroundPixels": len(covered),
                   "maximumForegroundCoverage": max(value[0] for value in covered),
                   "maximumForegroundBlendResidual": max(value[1] for value in covered), "counterPixels": counter_pixels}


def inspect_theme_sequence(markers: list[dict[str, Any]], directory: Path, contract: dict[str, Any]) -> dict[str, Any]:
    if len(markers) != len(THEME_PHASES):
        raise E2EError("theme proof requires every one of the 36 host capture phases")
    images, reports, paths = [], [], set()
    for phase, marker in enumerate(markers):
        validate_theme_marker(marker, phase, contract)
        for field in ("buttonId", "toggleId", "windowId", "title", "root", "button", "buttonLabel", "counter", "heading", "toggle", "toggleLabel", "scale"):
            if marker[field] != markers[0][field]:
                raise E2EError(f"theme switch changed retained identity or geometry: {field}")
        if phase and (marker["inputSequence"] <= markers[phase - 1]["inputSequence"] or marker["revision"] <= markers[phase - 1]["revision"]):
            raise E2EError("theme captures must follow advancing actual input and frame revisions")
        image, report = inspect_theme_frame(marker, directory, contract)
        if report["path"] in paths:
            raise E2EError("theme phases must retain distinct PPM captures")
        paths.add(report["path"])
        images.append(image)
        reports.append(report)
        if phase:
            changed = native._changed_pixels(images[phase - 1], image, _bounds(marker["counter"], "counter"), marker["scale"])
            if (changed > 0) != (marker["count"] != markers[phase - 1]["count"]):
                raise E2EError("theme/cancellation/activation disagrees with actual counter pixels")
    return {"captures": reports, "acceptedActivations": markers[-1]["count"],
            "bindingPreserved": True, "themeOnlyHeldInputPreserved": True,
            "staleGateReleasesCancelled": True, "outsideReleaseCancelled": True}


def digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def _git(root: Path, *args: str) -> str:
    result = subprocess.run(["git", "-C", str(root), *args], check=False, stdout=subprocess.PIPE,
                            stderr=subprocess.PIPE, text=True, encoding="utf-8", timeout=20)
    if result.returncode:
        raise E2EError(f"read-only git {' '.join(args)} failed: {result.stderr.strip()}")
    return result.stdout.strip()


def bind_sources(root: Path, gpui: Path, candidate: str) -> dict[str, Any]:
    if not SHA.fullmatch(candidate):
        raise E2EError("candidate must be an exact 40-character lowercase commit SHA")
    if _git(root, "rev-parse", "HEAD") != candidate:
        raise E2EError("candidate SHA does not match checked-out Yami HEAD")
    if _git(root, "status", "--porcelain", "--untracked-files=all"):
        raise E2EError("dirty Yami source cannot qualify an exact commit")
    pinned = (root / "tests/shared-ui/gpui-revision.txt").read_text(encoding="utf-8").strip()
    if not SHA.fullmatch(pinned) or _git(gpui, "rev-parse", "HEAD") != pinned:
        raise E2EError("GPUI source does not match the shared native pinned commit")
    if _git(gpui, "status", "--porcelain", "--untracked-files=all"):
        raise E2EError("dirty GPUI source cannot qualify the pinned commit")
    tracked = _git(root, "ls-files", "-z", "--", *BOUND_PATHS).split("\0")
    files = {name: digest(root / name) for name in tracked if name}
    for prefix in COMMON_PATHS:
        if not any(name.startswith(prefix + "/") and name.endswith(".mbt") for name in files):
            raise E2EError(f"missing bound common source package: {prefix}")
    return {"candidateSha": candidate, "sourceDirty": False, "gpuiRevision": pinned,
            "sourceSha256": files, "contractSha256": digest(root / "fixtures/shared-ui/contract-v1.json")}


def preflight(platform: str, env: dict[str, str]) -> None:
    if platform not in ("linux", "windows", "macos"):
        raise E2EError("shared native host evidence supports Linux, Windows and macOS")
    if ((platform == "linux" and not sys.platform.startswith("linux")) or
            (platform == "windows" and os.name != "nt") or
            (platform == "macos" and sys.platform != "darwin")):
        raise E2EError("requested platform does not match the executing host")
    if platform == "linux" and (env.get("YAMI_NATIVE_UI_ISOLATED") != "1" or not env.get("DISPLAY") or not env.get("WAYLAND_DISPLAY")):
        raise E2EError("Linux input requires the isolated Xvfb/Weston native UI session")
    for name in ("YAMI_NATIVE_WORKSPACE_ROOT", "YAMI_NATIVE_YAMI_ROOT", "YAMI_NATIVE_GPUI_ROOT", "YAMI_NATIVE_MODULE_ROOT"):
        if not env.get(name):
            raise E2EError(f"{name} must be set by native_ui_workspace.sh")
    if Path(env["YAMI_NATIVE_YAMI_ROOT"]).resolve() != ROOT:
        raise E2EError("workspace Yami source must be the checkout containing this driver")
    if Path(env["YAMI_NATIVE_MODULE_ROOT"]).resolve() != ROOT / "native":
        raise E2EError("workspace native module does not match the candidate checkout")


def build_plan(command: list[str], platform: str, module: Path, target: Path) -> tuple[list[str], Path]:
    if platform not in ("linux", "windows", "macos"):
        raise E2EError("unsupported shared native build platform")
    name = {"linux": "ubuntu", "windows": "windows", "macos": "macos"}[platform]
    package = (module / "examples/shared_counter" / name).resolve()
    if len(command) != 5 or command[:2] != ["moon", "run"] or Path(command[2]).resolve() != package or command[3:] != ["--target", "native"]:
        raise E2EError(f"command must build the bound shared sample: moon run {package} --target native")
    # Preserve the existing native workspace/debug-build convention, replacing
    # only the package suffix for this separately named shared sample.
    legacy_package = module / "examples" / name
    legacy_plan = native._native_run_plan(["moon", "run", str(legacy_package), "--target", "native"], platform, module, target)
    assert legacy_plan is not None
    build, executable = legacy_plan
    build[2] = str(package)
    executable = executable.parent.parent / "shared_counter" / name / executable.name
    return build, executable


def build_sample(command: list[str], platform: str, workspace: Path, module: Path,
                 target: Path, evidence: Path, env: dict[str, str], timeout: float) -> Path:
    build, executable = build_plan(command, platform, module, target)
    log = evidence / "native-build.log"
    try:
        result = subprocess.run(build, cwd=workspace, env=env, stdout=subprocess.PIPE,
                                stderr=subprocess.STDOUT, text=True, encoding="utf-8", errors="replace",
                                check=False, timeout=timeout)
    except subprocess.TimeoutExpired as error:
        captured = error.stdout or b""
        log.write_text(captured.decode("utf-8", errors="replace") if isinstance(captured, bytes) else captured, encoding="utf-8")
        raise E2EError("shared native build timed out; raw build log retained") from error
    log.write_text(result.stdout, encoding="utf-8")
    if result.returncode or not executable.is_file():
        raise E2EError(f"shared native build failed or binary missing (exit={result.returncode}); see {log}")
    return executable


class MarkerStream:
    """A consuming cursor: no phase skipping or reusing a buffered old marker."""
    def __init__(self, output: Any):
        self.output = output
        self.cursor = 0

    def next(self, timeout: float) -> tuple[str, dict[str, Any]]:
        deadline = time.monotonic() + timeout
        while self.cursor >= len(self.output.events):
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                raise E2EError("timed out waiting for next shared native marker")
            line = self.output._line(remaining)
            if line.startswith("YAMI_NATIVE_UI_") and not native.MARKER.fullmatch(line.rstrip("\r\n")):
                raise E2EError("malformed native UI marker line")
        event = self.output.events[self.cursor]
        self.cursor += 1
        return event

    def initial(self, fixture: str, counts: list[int], timeout: float) -> tuple[dict, dict]:
        found: dict[str, dict] = {}
        deadline = time.monotonic() + timeout
        while len(found) < 2:
            name, marker = self.next(max(0, deadline - time.monotonic()))
            if name not in ("YAMI_NATIVE_UI_READY", "YAMI_NATIVE_UI_PRESENTED") or name in found:
                raise E2EError("expected unique initial READY and PRESENTED markers")
            validate_marker(marker, fixture, 0, counts, presented=name.endswith("PRESENTED"))
            found[name] = marker
        ready, presented = found["YAMI_NATIVE_UI_READY"], found["YAMI_NATIVE_UI_PRESENTED"]
        for key in ready:
            if key != "frame" and ready[key] != presented.get(key):
                raise E2EError(f"READY and initial PRESENTED disagree on {key}")
        return ready, presented

    def phase(self, fixture: str, phase: int, counts: list[int], timeout: float) -> dict:
        name, marker = self.next(timeout)
        if name != "YAMI_NATIVE_UI_PRESENTED":
            raise E2EError("expected PRESENTED after the host click")
        validate_marker(marker, fixture, phase, counts, presented=True)
        return marker


def _write(path: Path, data: Any) -> None:
    path.write_text(json.dumps(data, indent=2, sort_keys=True) + "\n", encoding="utf-8")


def run_fixture(args: argparse.Namespace, fixture: str, counts: list[int], executable: Path,
                workspace: Path, evidence: Path, env: dict[str, str]) -> dict[str, Any]:
    directory = evidence / fixture
    directory.mkdir()  # A stale evidence directory can never be reused as a pass.
    title = f"{args.window_title} [{fixture}-{uuid.uuid4().hex}]"
    child_env = env | {"YAMI_NATIVE_UI_E2E": "1", "GPUI_NATIVE_E2E": "1",
                       "YAMI_NATIVE_UI_WINDOW_TITLE": title,
                       "YAMI_NATIVE_UI_EVIDENCE_DIR": str(directory), "YAMI_SHARED_UI_FIXTURE": fixture}
    process = None
    output = None
    trace: dict[str, Any] = {"fixture": fixture, "windowTitle": title, "presented": [], "status": "fail"}
    try:
        process = subprocess.Popen([str(executable)], cwd=workspace, env=child_env, stdin=subprocess.DEVNULL,
                                   stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True,
                                   encoding="utf-8", errors="replace", bufsize=1)
        output = native.ProcessOutput(process, directory / "native-ui.log")
        stream = MarkerStream(output)
        ready, initial = stream.initial(fixture, counts, args.startup_timeout)
        if ready.get("title") != title:
            raise E2EError("READY title does not identify this uniquely titled sample")
        trace["ready"] = ready
        trace["presented"].append(initial)
        inspect_frame(initial, directory)  # Refuse input until the initial frame has pixels.
        click_args = argparse.Namespace(**vars(args))
        click_args.window_title, click_args.sample_pid = title, process.pid
        render_only = fixture in ("shell-visible", "shell-visible-compact")
        phases = [] if render_only else range(1, len(counts))
        for phase in phases:
            previous = trace["presented"][-1]
            target = previous
            if fixture == "palette" and phase in (2, 4, 5):
                target = previous | {"button": previous["palette"]["toggle"]}
            if fixture == "spacing" and SPACING_ACTIONS[phase - 1] == "spacing-toggle":
                target = previous | {"button": previous["spacing"]["toggle"]}
            native._send_click(args.platform, target, click_args)
            marker = stream.phase(fixture, phase, counts, args.marker_timeout)
            inspect_frame(marker, directory)
            trace["presented"].append(marker)
        trace["pixels"] = inspect_frame_sequence(trace["presented"], directory)
        native._send_escape(args.platform, click_args)
        name, complete = stream.next(args.marker_timeout)
        if name != "YAMI_NATIVE_UI_COMPLETE":
            raise E2EError("expected COMPLETE after Escape")
        validate_marker(complete, fixture, len(counts) - 1, counts, complete=True)
        for key, value in trace["presented"][-1].items():
            if complete.get(key) != value:
                raise E2EError(f"COMPLETE differs from the last settled frame: {key}")
        trace["complete"] = complete
        trace["exitCode"] = process.wait(timeout=10)
        if trace["exitCode"] != 0:
            raise E2EError(f"sample exited with status {trace['exitCode']}")
        output._reader.join(timeout=2)
        if output._reader.is_alive():
            raise E2EError("sample stdout did not close after process exit")
        # Parse even trailing markers; drain() alone would retain but not reject
        # unexpected post-COMPLETE protocol output.
        while not output.lines.empty():
            try:
                line = output._line(0.1)
            except E2EError as error:
                if "exited before required marker" not in str(error):
                    raise
                break
            if line.startswith("YAMI_NATIVE_UI_"):
                raise E2EError("unexpected native marker after COMPLETE")
        trace["status"] = "pass"
        return trace
    except (E2EError, OSError, ValueError, subprocess.SubprocessError) as error:
        trace["error"] = str(error)
        raise
    finally:
        if process is not None:
            trace["cleanup"] = native._stop_owned_sample(process)
        if output is not None:
            output._reader.join(timeout=2)
            output.drain()
            output.close()
        _write(directory / "trace.json", trace)


def send_theme_input(platform: str, operation: str, marker: dict[str, Any], args: argparse.Namespace) -> None:
    allowed = {"move-inside", "move-outside", "pointer-down", "pointer-up", "space-down", "space-up",
               "key-t", "key-n", "key-d", "key-l", "key-b", "key-f", "key-c", "key-arm-inside", "key-arm-outside"}
    if operation not in allowed or platform not in ("linux", "windows"):
        raise E2EError("unknown or unsupported native theme input")
    x, y, width, height = _bounds(marker["button"], "button")
    px, py = x + width / 2, y + height / 2
    if operation == "move-outside":
        rx, ry, rw, rh = _bounds(marker["root"], "root")
        px, py = rx + rw - 16, ry + rh - 16
    if platform == "linux":
        if operation.startswith("move-"):
            # X11 may suppress a warp to the current position. Use one bounded
            # excursion and return, even for repeated targets. Neither point
            # leaves the intended region; only the final dispatched coordinate
            # can satisfy the receipt gate. Command success is never a receipt.
            scale = marker["scale"]
            if type(scale) not in (int, float) or not math.isfinite(scale) or scale <= 0:
                raise E2EError("theme Linux pointer scale must be positive and finite")
            rx, ry, rw, rh = _bounds(marker["button"] if operation == "move-inside" else marker["root"], "pointer region")
            tx, ty = round(px * scale), round(py * scale)
            excursion_x = tx - 2
            if not (rx * scale < excursion_x < tx < (rx + rw) * scale
                    and ry * scale < ty < (ry + rh) * scale):
                raise E2EError("theme Linux pointer excursion must stay inside its target region")
            command = ["xdotool", "mousemove", str(args.linux_origin_x + excursion_x),
                       str(args.linux_origin_y + ty), "mousemove", str(args.linux_origin_x + tx),
                       str(args.linux_origin_y + ty)]
        elif operation.startswith("pointer-"):
            command = ["xdotool", "mousedown" if operation.endswith("down") else "mouseup", "1"]
        elif operation.startswith("space-"):
            command = ["xdotool", "keydown" if operation.endswith("down") else "keyup", "space"]
        else:
            command = ["xdotool", "key", THEME_CONTROL_KEYS[operation][0]]
        subprocess.run(command, check=True, timeout=10)
        return
    hwnd, user32, types = native._windows_window(args.window_title)
    ctypes, wintypes, POINT, INPUT, MOUSEINPUT, KEYBDINPUT = types
    user32.GetWindowThreadProcessId.argtypes = [wintypes.HWND, ctypes.POINTER(wintypes.DWORD)]
    user32.GetWindowThreadProcessId.restype = wintypes.DWORD
    pid = wintypes.DWORD()
    user32.GetWindowThreadProcessId(hwnd, ctypes.byref(pid))
    if pid.value != args.sample_pid:
        raise E2EError("theme SendInput window does not belong to the launched native process")
    if user32.GetForegroundWindow() != hwnd:
        native._windows_focus(user32, hwnd)
    native._require_foreground(user32, hwnd)
    if operation.startswith("move-"):
        origin = POINT(0, 0)
        rect = wintypes.RECT()
        if not user32.ClientToScreen(hwnd, ctypes.byref(origin)) or not user32.GetClientRect(hwnd, ctypes.byref(rect)):
            raise E2EError("theme native client coordinate lookup failed")
        dpi = int(user32.GetDpiForWindow(hwnd))
        if dpi <= 0 or abs(dpi / 96 - marker["scale"]) > .01:
            raise E2EError("theme native scale differs from the actual HWND DPI")
        target_x, target_y = round(px * marker["scale"]), round(py * marker["scale"])
        if not 0 <= target_x < rect.right or not 0 <= target_y < rect.bottom:
            raise E2EError("theme input point is outside the owned native client area")
        if not user32.SetCursorPos(origin.x + target_x, origin.y + target_y):
            raise E2EError("theme SetCursorPos failed")
        # Request a fresh, non-coalesced motion even when already at the target.
        # Success still does not release the barrier: the host must acknowledge
        # the actual adapter dispatch below.
        native._windows_send_input(user32, types, [
            INPUT(type=0, mi=MOUSEINPUT(0, 0, 0, 0x0001 | 0x2000, 0, 0)),
        ])
        return
    if operation.startswith("pointer-"):
        events = [INPUT(type=0, mi=MOUSEINPUT(0, 0, 0, 0x0002 if operation.endswith("down") else 0x0004, 0, 0))]
    elif operation.startswith("space-"):
        events = [INPUT(type=1, ki=KEYBDINPUT(0x20, 0, 0 if operation.endswith("down") else 0x0002, 0, 0))]
    else:
        vk = THEME_CONTROL_KEYS[operation][1]
        events = [INPUT(type=1, ki=KEYBDINPUT(vk, 0, flag, 0, 0)) for flag in (0, 0x0002)]
    native._windows_send_input(user32, types, events)


def theme_pointer_target(operation: str, marker: dict[str, Any]) -> tuple[float, float]:
    x, y, width, height = _bounds(marker["button"], "button")
    if operation == "move-outside":
        x, y, width, height = _bounds(marker["root"], "root")
        return x + width - 16, y + height - 16
    if operation != "move-inside":
        raise E2EError("pointer barrier requires a move operation")
    return x + width / 2, y + height / 2


def theme_pointer_move(platform: str, operation: str, marker: dict[str, Any], args: argparse.Namespace,
                       stream: MarkerStream, request: int, after_sequence: int) -> dict[str, Any]:
    """Arm, inject once, then require a fresh actual dispatch before continuing.

    No repeated injection, capture retries, sleep-based success, or old receipts.
    Unexpected markers fail closed rather than skipping a failed observation.
    """
    deadline = time.monotonic() + args.marker_timeout
    x, y = theme_pointer_target(operation, marker)
    send_theme_input(platform, "key-arm-inside" if operation == "move-inside" else "key-arm-outside", marker, args)
    name, armed = stream.next(max(0, deadline - time.monotonic()))
    identity = {"request": request, "phase": marker["phase"], "windowId": marker["windowId"]}
    if name != "YAMI_NATIVE_UI_POINTER_ARMED" or any(
        type(armed.get(key)) is not int or armed[key] != value for key, value in identity.items()
    ):
        raise E2EError("unexpected theme pointer arm identity")
    arm_sequence = armed.get("armSequence")
    if type(arm_sequence) is not int or arm_sequence <= max(marker["inputSequence"], after_sequence):
        raise E2EError("stale theme pointer arm sequence")
    if type(armed.get("scale")) not in (int, float) or armed["scale"] != marker["scale"]:
        raise E2EError("theme pointer arm scale mismatch")
    for key, expected in (("x", x), ("y", y)):
        value = armed.get(key)
        if type(value) not in (int, float) or not math.isfinite(value) or abs(value - expected) > 0.01:
            raise E2EError("theme pointer arm coordinate mismatch")
    if time.monotonic() >= deadline:
        raise E2EError("theme pointer arm exceeded receipt deadline")
    send_theme_input(platform, operation, marker, args)
    name, receipt = stream.next(max(0, deadline - time.monotonic()))
    if time.monotonic() >= deadline:
        raise E2EError("theme pointer receipt exceeded deadline")
    if name != "YAMI_NATIVE_UI_POINTER_MOVED" or any(
        type(receipt.get(key)) is not int or receipt[key] != value for key, value in identity.items()
    ) or type(receipt.get("armSequence")) is not int or receipt["armSequence"] != arm_sequence:
        raise E2EError("unexpected theme pointer receipt identity")
    sequence = receipt.get("sequence")
    if type(sequence) is not int or sequence <= arm_sequence or type(receipt.get("dispatchedSequence")) is not int or receipt["dispatchedSequence"] != sequence:
        raise E2EError("theme pointer receipt lacks a fresh dispatch")
    if type(receipt.get("scale")) not in (int, float) or receipt["scale"] != marker["scale"]:
        raise E2EError("theme pointer receipt scale mismatch")
    x, y = theme_pointer_target(operation, marker)
    for key, expected in (("x", x), ("y", y)):
        value = receipt.get(key)
        if type(value) not in (int, float) or not math.isfinite(value) or abs(value - expected) > 0.51 / marker["scale"]:
            raise E2EError("theme pointer receipt coordinate mismatch")
    return {"armed": armed, "received": receipt}


def send_theme_phase_inputs(platform: str, operations: list[str], previous: dict[str, Any],
                            args: argparse.Namespace, stream: MarkerStream, pointer_request: int,
                            pointer_sequence: int, inputs: list[dict[str, Any]], phase: int) -> tuple[int, int]:
    for operation in [*operations, "key-c"]:
        event = {"phase": phase, "operation": operation, "status": "pending"}
        inputs.append(event)
        if operation.startswith("move-"):
            pointer_request += 1
            event["receipt"] = theme_pointer_move(
                platform, operation, previous, args, stream, pointer_request, pointer_sequence,
            )
            pointer_sequence = event["receipt"]["received"]["sequence"]
            event["status"] = "dispatched"
        else:
            send_theme_input(platform, operation, previous, args)
            event["status"] = "sent"
    return pointer_request, pointer_sequence


def run_theme_fixture(args: argparse.Namespace, contract: dict[str, Any], executable: Path,
                      workspace: Path, evidence: Path, env: dict[str, str]) -> dict[str, Any]:
    directory = evidence / "theme"
    directory.mkdir()
    title = f"{args.window_title} [theme-{uuid.uuid4().hex}]"
    child_env = env | {"YAMI_NATIVE_UI_E2E": "1", "GPUI_NATIVE_E2E": "1", "YAMI_SHARED_UI_FIXTURE": "theme",
                       "YAMI_NATIVE_UI_WINDOW_TITLE": title, "YAMI_NATIVE_UI_EVIDENCE_DIR": str(directory)}
    process, output, input_args = None, None, None
    trace: dict[str, Any] = {"fixture": "theme", "windowTitle": title, "status": "fail", "presented": [], "inputs": []}
    try:
        process = subprocess.Popen([str(executable)], cwd=workspace, env=child_env, stdin=subprocess.DEVNULL,
                                   stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True,
                                   encoding="utf-8", errors="replace", bufsize=1)
        output = native.ProcessOutput(process, directory / "native-ui.log")
        stream = MarkerStream(output)
        initial = {}
        for _ in range(2):
            name, marker = stream.next(args.startup_timeout)
            if name not in ("YAMI_NATIVE_UI_READY", "YAMI_NATIVE_UI_PRESENTED") or name in initial:
                raise E2EError("theme requires unique initial READY and PRESENTED")
            validate_theme_marker(marker, 0, contract)
            initial[name] = marker
        ready = initial["YAMI_NATIVE_UI_READY"]
        if ready != initial["YAMI_NATIVE_UI_PRESENTED"] or ready["title"] != title:
            raise E2EError("theme initial markers disagree or do not bind this unique process")
        trace["ready"] = ready
        trace["presented"].append(ready)
        inspect_theme_frame(ready, directory, contract)
        input_args = argparse.Namespace(**vars(args))
        input_args.window_title, input_args.sample_pid = title, process.pid
        pointer_request, pointer_sequence = 0, 0
        for phase, expected in enumerate(THEME_PHASES[1:], 1):
            previous = trace["presented"][-1]
            pointer_request, pointer_sequence = send_theme_phase_inputs(
                args.platform, expected["inputs"], previous, input_args, stream,
                pointer_request, pointer_sequence, trace["inputs"], phase,
            )
            name, marker = stream.next(args.marker_timeout)
            if name != "YAMI_NATIVE_UI_PRESENTED":
                raise E2EError("theme capture request did not produce PRESENTED")
            validate_theme_marker(marker, phase, contract)
            if marker["inputSequence"] <= pointer_sequence:
                raise E2EError("theme capture did not follow the pointer receipt")
            inspect_theme_frame(marker, directory, contract)
            trace["presented"].append(marker)
        trace["pixels"] = inspect_theme_sequence(trace["presented"], directory, contract)
        native._send_escape(args.platform, input_args)
        name, complete = stream.next(args.marker_timeout)
        if name != "YAMI_NATIVE_UI_COMPLETE":
            raise E2EError("theme Escape did not produce COMPLETE")
        validate_theme_marker(complete, len(THEME_PHASES) - 1, contract, complete=True)
        if {key: value for key, value in complete.items() if key != "destroyed"} != trace["presented"][-1]:
            raise E2EError("theme COMPLETE differs from the last captured frame")
        trace["complete"] = complete
        trace["exitCode"] = process.wait(timeout=10)
        if trace["exitCode"] != 0:
            raise E2EError(f"theme native sample exited with status {trace['exitCode']}")
        output._reader.join(timeout=2)
        if output._reader.is_alive():
            raise E2EError("theme stdout did not close after process exit")
        while not output.lines.empty():
            try:
                line = output._line(.1)
            except E2EError as error:
                if "exited before required marker" not in str(error):
                    raise
                break
            if line.startswith("YAMI_NATIVE_UI_"):
                raise E2EError("unexpected theme marker after COMPLETE")
        trace["status"] = "pass"
        return trace
    except (E2EError, OSError, ValueError, subprocess.SubprocessError) as error:
        trace["error"] = str(error)
        raise
    finally:
        if process is not None:
            if process.poll() is None and input_args is not None and trace["presented"]:
                try:
                    for operation in ("pointer-up", "space-up"):
                        send_theme_input(args.platform, operation, trace["presented"][-1], input_args)
                    trace["heldInputCleanup"] = "released"
                except (E2EError, OSError, subprocess.SubprocessError) as error:
                    trace["heldInputCleanup"] = str(error)
            trace["cleanup"] = native._stop_owned_sample(process)
        if output is not None:
            output._reader.join(timeout=2)
            output.drain()
            output.close()
        _write(directory / "trace.json", trace)


def _artifacts(evidence: Path, paths: list[Path]) -> list[dict[str, str]]:
    artifacts = []
    for path in paths:
        relative = path.resolve().relative_to(evidence.resolve()).as_posix()
        artifacts.append({"path": relative, "sha256": digest(path)})
    return artifacts


def _timestamp() -> str:
    return datetime.now(timezone.utc).isoformat()


def drive(args: argparse.Namespace) -> int:
    started = _timestamp()
    evidence = args.evidence_dir.resolve()
    evidence.mkdir(parents=True, exist_ok=True)
    scenario = getattr(args, "scenario", "shared")
    protected = (*FIXTURES, "theme", "results.json", "theme-results.json", "provenance.json", "shared-native-report.json",
                 "native-build.log", "toolchain.log")
    if any((evidence / name).exists() for name in protected):
        raise E2EError("refusing to overwrite existing shared native evidence")
    if args.log is not None:
        aggregate = args.log.resolve()
        if aggregate.exists() or aggregate.parent != evidence or aggregate.name in protected:
            raise E2EError("aggregate log must be a fresh, separate file in the evidence root")
    env = os.environ.copy()
    report: dict[str, Any] = {"status": "fail", "platform": args.platform, "startedAt": started,
                             "scope": "bounded shared real-host inputs, common fixture colors and retained pixels",
                             "scenario": scenario,
                             "fixtures": []}
    try:
        preflight(args.platform, env)
        if args.platform == "macos":
            args.macos_helper = native._compile_macos_input_helper(evidence)
            native._macos_input_preflight(args.macos_helper, evidence)
        for value in (args.startup_timeout, args.marker_timeout, args.build_timeout):
            if not math.isfinite(value) or value <= 0:
                raise E2EError("timeouts must be finite positive numbers")
        contract = load_contract()
        if scenario not in ("shared", "theme", "all"):
            raise E2EError("unknown shared native scenario")
        theme_contract = load_theme_contract() if scenario in ("theme", "all") else None
        gpui = Path(env["YAMI_NATIVE_GPUI_ROOT"]).resolve()
        provenance = bind_sources(ROOT, gpui, args.candidate_sha)
        workspace = Path(env["YAMI_NATIVE_WORKSPACE_ROOT"]).resolve()
        module = Path(env["YAMI_NATIVE_MODULE_ROOT"]).resolve()
        # Validate before invoking any compiler or native process.
        build_plan(args.command, args.platform, module, workspace / "unused-target")
        version = subprocess.run(["moon", "version", "--all"], stdout=subprocess.PIPE,
                                 stderr=subprocess.STDOUT, check=True, text=True, timeout=20)
        (evidence / "toolchain.log").write_text(version.stdout, encoding="utf-8")
        if not version.stdout.strip():
            raise E2EError("Moon toolchain version output is empty")
        with tempfile.TemporaryDirectory(prefix="yami-shared-native-build-", dir=workspace) as temporary:
            executable = build_sample(args.command, args.platform, workspace, module, Path(temporary),
                                      evidence, env, args.build_timeout)
            if bind_sources(ROOT, gpui, args.candidate_sha) != provenance:
                raise E2EError("source binding changed during build")
            provenance["binarySha256"] = digest(executable)
            provenance["command"] = args.command
            _write(evidence / "provenance.json", provenance)
            if scenario in ("theme", "all"):
                assert theme_contract is not None
                report["theme"] = run_theme_fixture(args, theme_contract, executable, workspace, evidence, env)
            if scenario in ("shared", "all"):
                selected = [name.strip() for name in args.fixtures.split(",") if name.strip()]
                if not selected or any(name not in FIXTURES for name in selected):
                    raise E2EError("unknown or empty --fixtures selection")
                for fixture in selected:
                    report["fixtures"].append(run_fixture(args, fixture, expected_counts(contract, fixture),
                                                          executable, workspace, evidence, env))
            final_binding = bind_sources(ROOT, gpui, args.candidate_sha)
            if any(provenance.get(key) != value for key, value in final_binding.items()):
                raise E2EError("source binding changed during host execution")
        finished = _timestamp()
        results = []
        shared_paths = [evidence / name for name in ("native-build.log", "toolchain.log", "provenance.json")]
        for trace in report["fixtures"]:
            fixture = trace["fixture"]
            directory = evidence / fixture
            paths = shared_paths + [directory / "native-ui.log", directory / "trace.json"]
            paths += [Path(item["path"]) for item in trace["pixels"]["captures"]]
            results.append({"schemaVersion": "shared-ui-result/v1", "contractVersion": contract["version"],
                            "fixtureId": FIXTURES[fixture], "candidateSha": args.candidate_sha,
                            "sourceDirty": False, "startedAt": started, "finishedAt": finished,
                            "dependencies": [{"name": "gpui.mbt", "revision": provenance["gpuiRevision"]},
                                             {"name": "native-binary-sha256", "revision": provenance["binarySha256"]}],
                            "profile": {"platform": args.platform, "backend": "gpui-native", "target": "native",
                                        "layer": "runtime", "environment": {"os": host_platform.platform(),
                                        "arch": host_platform.machine(), "toolchain": version.stdout.strip()}},
                            "capability": "supported", "status": "pass", "command": args.command,
                            "exitCode": 0, "artifacts": _artifacts(evidence, paths), "profileDifferences": [],
                            "observed": {"counts": [marker["count"] for marker in trace["presented"]]}})
        if scenario in ("shared", "all"):
            _write(evidence / "results.json", results)
        if "theme" in report:
            trace = report["theme"]
            directory = evidence / "theme"
            paths = shared_paths + [directory / "native-ui.log", directory / "trace.json"]
            paths += [Path(item["path"]) for item in trace["pixels"]["captures"]]
            _write(evidence / "theme-results.json", {
                "contractVersion": "shared-button-theme/v1", "fixtureId": "shared-button-theme-host",
                "candidateSha": args.candidate_sha, "sourceDirty": False, "status": "pass", "exitCode": 0,
                "startedAt": started, "finishedAt": finished, "profile": {"platform": args.platform,
                "backend": "gpui-native", "target": "native", "layer": "runtime", "os": host_platform.platform(),
                "arch": host_platform.machine(), "toolchain": version.stdout.strip()},
                "dependencies": {"gpuiRevision": provenance["gpuiRevision"], "binarySha256": provenance["binarySha256"]},
                "artifacts": _artifacts(evidence, paths), "phaseNames": [phase["name"] for phase in THEME_PHASES],
                "observed": {"counts": [marker["count"] for marker in trace["presented"]],
                             "themes": [marker["theme"] for marker in trace["presented"]],
                             "states": [{key: marker[key] for key in ("enabled", "loading", "focused", "hovered", "pressed")}
                                        for marker in trace["presented"]],
                             "buttonIds": [marker["buttonId"] for marker in trace["presented"]]},
                "profileDifferences": ["GPUI clears hover on loading/disabled; browser :hover may remain",
                                       "native focus uses GPUI focus API; browser focus timing remains browser-owned"],
                "unverified": ["macOS real host input and GPU", "accessibility and IME"]})
        report.update({"status": "pass", "finishedAt": finished, "candidateSha": args.candidate_sha,
                       "inputDelivery": "XTest in isolated Xvfb/Weston" if args.platform == "linux"
                       else "Win32 SendInput to uniquely titled foreground HWND" if args.platform == "windows"
                       else "CGEventPost(AX target) to the uniquely titled visible app; not physical hardware"})
        print(f"Shared native {scenario} proof passed: {evidence / 'shared-native-report.json'}", flush=True)
        return 0
    except (E2EError, OSError, ValueError, subprocess.SubprocessError) as error:
        report.update({"error": str(error), "finishedAt": _timestamp()})
        print(f"Shared native counter proof failed: {error}", file=sys.stderr, flush=True)
        return 1
    finally:
        _write(evidence / "shared-native-report.json", report)
        if args.log is not None:
            args.log.parent.mkdir(parents=True, exist_ok=True)
            content = "".join(f"=== {fixture} ===\n" + (evidence / fixture / "native-ui.log").read_text(encoding="utf-8")
                              for fixture in (*FIXTURES, "theme") if (evidence / fixture / "native-ui.log").is_file())
            args.log.write_text(content, encoding="utf-8")


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--platform", choices=("linux", "windows", "macos"), required=True)
    parser.add_argument("--scenario", choices=("shared", "theme", "all"), default="all")
    parser.add_argument("--fixtures", default=",".join(FIXTURES), help="comma-separated shared fixtures to run")
    parser.add_argument("--evidence-dir", type=Path, required=True)
    parser.add_argument("--candidate-sha", required=True)
    parser.add_argument("--log", type=Path)
    parser.add_argument("--window-title", default="Yami-kumo Shared Counter")
    parser.add_argument("--startup-timeout", type=float, default=240)
    parser.add_argument("--marker-timeout", type=float, default=45)
    parser.add_argument("--build-timeout", type=float, default=600)
    parser.add_argument("--linux-origin-x", type=int, default=0)
    parser.add_argument("--linux-origin-y", type=int, default=0)
    parser.add_argument("command", nargs=argparse.REMAINDER)
    args = parser.parse_args(argv)
    if args.command[:1] == ["--"]:
        args.command = args.command[1:]
    try:
        return drive(args)
    except (E2EError, OSError, ValueError) as error:
        print(f"Shared native counter proof failed: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
