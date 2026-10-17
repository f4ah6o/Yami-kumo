#!/usr/bin/env python3
"""Opt-in real Linux/Windows shared-counter evidence; importing is inert.

This driver proves the bounded shared-ui-contract/v1 pointer fixtures. It does
not establish general DOM/native parity, keyboard/IME behavior or accessibility.
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
FIXTURES = {"counter": "counter-two-activations", "disabled-loading": "counter-disabled-loading", "card": "card-counter-two-activations", "spacing": "spacing-count-and-toggle", "palette": "palette-count-and-toggle"}
CONTRACT_PHASES = {
    "counter-two-activations": 3,
    "card-counter-two-activations": 3,
    "spacing-count-and-toggle": 5,
    "palette-count-and-toggle": 6,
    "counter-disabled-loading": 4,
    "button-interrupted-loading": 6,
    "button-interrupted-disabled": 6,
}
SHA = re.compile(r"[0-9a-f]{40}\Z")
COMMON_PATHS = ("ui/core", "ui/runtime", "examples/shared_counter")
BOUND_PATHS = (*COMMON_PATHS, "native/ui", "native/examples/shared_counter",
               "native/examples/shared_counter_host", "tests/shared-ui", "tests/native-ui/drive_native_ui.py",
               "styles/shared-ui.css", "fixtures/shared-ui", "docs/shared-card.md", "docs/shared-stack-spacing.md", "docs/shared-button-palettes.md")


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
    labels = (f"Count: {count}", "Increment", "Shared <stack>", "Spacing", "Fixed Card") if fixture == "spacing" else ((f"Count: {count}", "Increment", "Shared palette", "Palette") if fixture == "palette" else (f"Count: {count}", "Increment", "Shared counter"))
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
    if platform not in ("linux", "windows"):
        raise E2EError("shared native host evidence supports Linux and Windows only")
    if (platform == "linux" and not sys.platform.startswith("linux")) or (platform == "windows" and os.name != "nt"):
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
    if platform not in ("linux", "windows"):
        raise E2EError("unsupported shared native build platform")
    name = "ubuntu" if platform == "linux" else "windows"
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
        for phase in range(1, len(counts)):
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
    protected = (*FIXTURES, "results.json", "provenance.json", "shared-native-report.json",
                 "native-build.log", "toolchain.log")
    if any((evidence / name).exists() for name in protected):
        raise E2EError("refusing to overwrite existing shared native evidence")
    if args.log is not None:
        aggregate = args.log.resolve()
        if aggregate.exists() or aggregate.parent != evidence or aggregate.name in protected:
            raise E2EError("aggregate log must be a fresh, separate file in the evidence root")
    env = os.environ.copy()
    report: dict[str, Any] = {"status": "fail", "platform": args.platform, "startedAt": started,
                             "scope": "shared counter real-host pointer runtime and retained pixels only",
                             "fixtures": []}
    try:
        preflight(args.platform, env)
        for value in (args.startup_timeout, args.marker_timeout, args.build_timeout):
            if not math.isfinite(value) or value <= 0:
                raise E2EError("timeouts must be finite positive numbers")
        contract = load_contract()
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
            for fixture in FIXTURES:
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
        _write(evidence / "results.json", results)
        report.update({"status": "pass", "finishedAt": finished, "candidateSha": args.candidate_sha,
                       "inputDelivery": "XTest in isolated Xvfb/Weston" if args.platform == "linux"
                       else "Win32 SendInput to uniquely titled foreground HWND"})
        print(f"Shared native counter proof passed: {evidence / 'results.json'}", flush=True)
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
                              for fixture in FIXTURES if (evidence / fixture / "native-ui.log").is_file())
            args.log.write_text(content, encoding="utf-8")


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--platform", choices=("linux", "windows"), required=True)
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
