#!/usr/bin/env python3
"""Drive the shared Yami native sample through real host input and check pixels."""

from __future__ import annotations

import argparse
from collections import Counter
from dataclasses import dataclass
import json
import math
import os
from pathlib import Path
import queue
import re
import subprocess
import sys
import threading
import time
from typing import Any, Callable
import uuid


MARKER = re.compile(r"^(YAMI_NATIVE_UI_[A-Z_]+) (\{.*\})$")


class E2EError(RuntimeError):
    pass


@dataclass(frozen=True)
class PPM:
    width: int
    height: int
    pixels: bytes

    def pixel(self, x: int, y: int) -> tuple[int, int, int]:
        offset = (y * self.width + x) * 3
        return tuple(self.pixels[offset : offset + 3])  # type: ignore[return-value]


def _ppm_token(data: bytes, index: int) -> tuple[bytes, int]:
    while index < len(data):
        if data[index] in b" \t\r\n\v\f":
            index += 1
        elif data[index] == ord("#"):
            end = data.find(b"\n", index)
            if end < 0:
                raise E2EError("unterminated comment in PPM header")
            index = end + 1
        else:
            break
    start = index
    while index < len(data) and data[index] not in b" \t\r\n\v\f#":
        index += 1
    if index == start:
        raise E2EError("unexpected end of PPM header")
    return data[start:index], index


def read_ppm(path: Path) -> PPM:
    data = path.read_bytes()
    magic, index = _ppm_token(data, 0)
    if magic not in (b"P6", b"P3"):
        raise E2EError(f"unsupported PPM encoding in {path}: {magic!r}")
    width_token, index = _ppm_token(data, index)
    height_token, index = _ppm_token(data, index)
    maxval_token, index = _ppm_token(data, index)
    try:
        width = int(width_token)
        height = int(height_token)
        maxval = int(maxval_token)
    except ValueError as error:
        raise E2EError(f"invalid PPM dimensions in {path}") from error
    if width <= 0 or height <= 0 or maxval != 255:
        raise E2EError(f"invalid PPM geometry/range in {path}: {width}x{height}, {maxval}")

    if magic == b"P6":
        if index >= len(data) or data[index] not in b" \t\r\n\v\f":
            raise E2EError(f"missing PPM raster separator in {path}")
        if data[index : index + 2] == b"\r\n":
            index += 2
        else:
            index += 1
        pixels = data[index:]
    else:
        values = data[index:].split()
        try:
            channels = [int(value) for value in values]
        except ValueError as error:
            raise E2EError(f"invalid PPM raster in {path}") from error
        pixels = bytes(channels)
    expected_size = width * height * 3
    if len(pixels) != expected_size:
        raise E2EError(
            f"PPM raster size mismatch in {path}: expected {expected_size}, got {len(pixels)}"
        )
    return PPM(width, height, pixels)


def _rect(value: Any, field: str) -> tuple[float, float, float, float]:
    if not isinstance(value, dict):
        raise E2EError(f"marker field {field!r} must be an object")
    try:
        x, y, width, height = (float(value[key]) for key in ("x", "y", "width", "height"))
    except (KeyError, TypeError, ValueError) as error:
        raise E2EError(f"marker field {field!r} must contain x, y, width, height") from error
    if not all(math.isfinite(number) for number in (x, y, width, height)) or width <= 0 or height <= 0:
        raise E2EError(f"marker field {field!r} has invalid bounds")
    return x, y, width, height


def _pixel_bounds(
    image: PPM, rect: tuple[float, float, float, float], scale: float
) -> tuple[int, int, int, int]:
    x, y, width, height = rect
    left = max(0, math.floor(x * scale))
    top = max(0, math.floor(y * scale))
    right = min(image.width, math.ceil((x + width) * scale))
    bottom = min(image.height, math.ceil((y + height) * scale))
    if left >= right or top >= bottom:
        raise E2EError(f"logical region {rect!r} falls outside {image.width}x{image.height} frame")
    return left, top, right, bottom


def _region_pixels(
    image: PPM, rect: tuple[float, float, float, float], scale: float
) -> list[tuple[int, int, int]]:
    left, top, right, bottom = _pixel_bounds(image, rect, scale)
    return [image.pixel(x, y) for y in range(top, bottom) for x in range(left, right)]


def _foreground_count(
    image: PPM,
    rect: tuple[float, float, float, float],
    scale: float,
    background: tuple[int, int, int] | None = None,
) -> int:
    pixels = _region_pixels(image, rect, scale)
    if background is None:
        background, _ = Counter(pixels).most_common(1)[0]
    # Antialiased glyph edges can be close to the background; a 12-level RGB
    # channel threshold accepts those while ignoring flat background regions.
    return sum(max(abs(channel - background[i]) for i, channel in enumerate(pixel)) > 12
               for pixel in pixels)


def _frame_background(image: PPM) -> tuple[int, int, int]:
    # Sparse full-frame sampling identifies the page/window background without
    # allocating a color tuple for every pixel in high-DPI captures.
    sampled = Counter(
        image.pixel(x, y)
        for y in range(0, image.height, 8)
        for x in range(0, image.width, 8)
    )
    return sampled.most_common(1)[0][0]


def _changed_pixels(
    before: PPM,
    after: PPM,
    rect: tuple[float, float, float, float] | None = None,
    scale: float = 1.0,
) -> int:
    if (before.width, before.height) != (after.width, after.height):
        raise E2EError("native frame dimensions changed between count 0 and count 1")
    if rect is None:
        return sum(
            before.pixels[offset : offset + 3] != after.pixels[offset : offset + 3]
            for offset in range(0, len(before.pixels), 3)
        )
    left, top, right, bottom = _pixel_bounds(before, rect, scale)
    return sum(
        before.pixel(x, y) != after.pixel(x, y)
        for y in range(top, bottom)
        for x in range(left, right)
    )


def _read_ppm_path(frame: dict[str, Any], evidence_dir: Path, label: str) -> Path:
    raw_path = frame.get("path")
    if not isinstance(raw_path, str) or not raw_path:
        raise E2EError(f"{label} frame marker must include a PPM path")
    candidate = Path(raw_path)
    if not candidate.is_absolute():
        candidate = evidence_dir / candidate
    candidate = candidate.resolve()
    try:
        candidate.relative_to(evidence_dir.resolve())
    except ValueError as error:
        raise E2EError(f"{label} PPM path escapes the evidence directory: {candidate}") from error
    if not candidate.is_file():
        raise E2EError(f"{label} PPM capture was not written: {candidate}")
    return candidate


def _marker_state(marker: dict[str, Any], expected_count: int) -> None:
    if marker.get("count") != expected_count or marker.get("value") != expected_count:
        raise E2EError(
            f"expected presented count/value {expected_count}, got "
            f"{marker.get('count')!r}/{marker.get('value')!r}"
        )
    if not isinstance(marker.get("scene"), dict):
        raise E2EError("PRESENTED marker must include the canonical scene object")
    frame = marker.get("frame")
    if not isinstance(frame, dict):
        raise E2EError("PRESENTED marker must include native frame metadata")
    try:
        scale = float(frame["scale"])
        width = int(frame["width"])
        height = int(frame["height"])
    except (KeyError, TypeError, ValueError) as error:
        raise E2EError("frame metadata must include width, height, and scale") from error
    if width <= 0 or height <= 0 or not math.isfinite(scale) or scale <= 0:
        raise E2EError("invalid native frame dimensions or scale")


def _marker_rect(marker: dict[str, Any], key: str) -> tuple[float, float, float, float]:
    if key not in marker:
        raise E2EError(f"PRESENTED marker is missing {key!r} bounds")
    return _rect(marker[key], key)


class ProcessOutput:
    def __init__(self, process: subprocess.Popen[str], log_path: Path):
        self.process = process
        self.log = log_path.open("w", encoding="utf-8", errors="replace")
        self.lines: queue.Queue[str | None] = queue.Queue()
        self.events: list[tuple[str, dict[str, Any]]] = []
        self._reader = threading.Thread(target=self._read_stdout, daemon=True)
        self._reader.start()

    def _read_stdout(self) -> None:
        assert self.process.stdout is not None
        for line in self.process.stdout:
            self.lines.put(line)
        self.lines.put(None)

    def _line(self, timeout: float) -> str:
        try:
            line = self.lines.get(timeout=timeout)
        except queue.Empty as error:
            raise E2EError("timed out waiting for native sample output") from error
        if line is None:
            raise E2EError(f"native sample exited before required marker (exit={self.process.poll()})")
        self.log.write(line)
        self.log.flush()
        if line.startswith("YAMI_NATIVE_UI_") or "error" in line.lower() or "failed" in line.lower():
            print(line.rstrip(), flush=True)
        match = MARKER.match(line.rstrip("\r\n"))
        if match:
            try:
                payload = json.loads(match.group(2))
            except json.JSONDecodeError as error:
                raise E2EError(f"invalid JSON in {match.group(1)} marker: {error}") from error
            if not isinstance(payload, dict):
                raise E2EError(f"{match.group(1)} marker must contain a JSON object")
            event = (match.group(1), payload)
            self.events.append(event)
        return line

    def wait_marker(
        self,
        marker_name: str,
        predicate: Callable[[dict[str, Any]], bool] = lambda _payload: True,
        timeout: float = 180.0,
    ) -> dict[str, Any]:
        checked = 0
        deadline = time.monotonic() + timeout
        while True:
            for name, payload in self.events[checked:]:
                if name == marker_name and predicate(payload):
                    return payload
            checked = len(self.events)
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                raise E2EError(f"timed out waiting for {marker_name}")
            self._line(remaining)

    def close(self) -> None:
        self.log.close()

    def drain(self) -> None:
        while True:
            try:
                line = self.lines.get_nowait()
            except queue.Empty:
                break
            if line is None:
                break
            self.log.write(line)
        self.log.flush()


def _linux_click(ready: dict[str, Any], origin_x: int, origin_y: int) -> None:
    rect = _rect(ready.get("button"), "button")
    scale = float(ready.get("scale", 1.0))
    x, y, width, height = rect
    target_x = origin_x + round((x + width / 2) * scale)
    target_y = origin_y + round((y + height / 2) * scale)
    subprocess.run(["xdotool", "mousemove", "--sync", str(target_x), str(target_y)], check=True)
    subprocess.run(["xdotool", "click", "--clearmodifiers", "1"], check=True)


def _linux_escape() -> None:
    subprocess.run(["xdotool", "key", "--clearmodifiers", "Escape"], check=True)


def _windows_user32() -> tuple[Any, Any]:
    if os.name != "nt":
        raise E2EError("Windows SendInput helper invoked on a non-Windows host")
    import ctypes
    from ctypes import wintypes

    user32 = ctypes.WinDLL("user32", use_last_error=True)
    kernel32 = ctypes.WinDLL("kernel32", use_last_error=True)

    class POINT(ctypes.Structure):
        _fields_ = [("x", wintypes.LONG), ("y", wintypes.LONG)]

    class MOUSEINPUT(ctypes.Structure):
        _fields_ = [
            ("dx", wintypes.LONG),
            ("dy", wintypes.LONG),
            ("mouseData", wintypes.DWORD),
            ("dwFlags", wintypes.DWORD),
            ("time", wintypes.DWORD),
            ("dwExtraInfo", ctypes.c_size_t),
        ]

    class KEYBDINPUT(ctypes.Structure):
        _fields_ = [
            ("wVk", wintypes.WORD),
            ("wScan", wintypes.WORD),
            ("dwFlags", wintypes.DWORD),
            ("time", wintypes.DWORD),
            ("dwExtraInfo", ctypes.c_size_t),
        ]

    class HARDWAREINPUT(ctypes.Structure):
        _fields_ = [
            ("uMsg", wintypes.DWORD),
            ("wParamL", wintypes.WORD),
            ("wParamH", wintypes.WORD),
        ]

    class INPUTUNION(ctypes.Union):
        _fields_ = [("mi", MOUSEINPUT), ("ki", KEYBDINPUT), ("hi", HARDWAREINPUT)]

    class INPUT(ctypes.Structure):
        _anonymous_ = ("u",)
        _fields_ = [("type", wintypes.DWORD), ("u", INPUTUNION)]

    user32.EnumWindows.argtypes = [ctypes.WINFUNCTYPE(wintypes.BOOL, wintypes.HWND, wintypes.LPARAM), wintypes.LPARAM]
    user32.EnumWindows.restype = wintypes.BOOL
    user32.GetWindowTextLengthW.argtypes = [wintypes.HWND]
    user32.GetWindowTextLengthW.restype = ctypes.c_int
    user32.GetWindowTextW.argtypes = [wintypes.HWND, wintypes.LPWSTR, ctypes.c_int]
    user32.GetWindowTextW.restype = ctypes.c_int
    user32.IsWindowVisible.argtypes = [wintypes.HWND]
    user32.IsWindowVisible.restype = wintypes.BOOL
    user32.GetClientRect.argtypes = [wintypes.HWND, ctypes.POINTER(wintypes.RECT)]
    user32.GetClientRect.restype = wintypes.BOOL
    user32.ClientToScreen.argtypes = [wintypes.HWND, ctypes.POINTER(POINT)]
    user32.ClientToScreen.restype = wintypes.BOOL
    user32.GetDpiForWindow.argtypes = [wintypes.HWND]
    user32.GetDpiForWindow.restype = wintypes.UINT
    user32.SetForegroundWindow.argtypes = [wintypes.HWND]
    user32.SetForegroundWindow.restype = wintypes.BOOL
    user32.GetForegroundWindow.restype = wintypes.HWND
    user32.ShowWindow.argtypes = [wintypes.HWND, ctypes.c_int]
    user32.BringWindowToTop.argtypes = [wintypes.HWND]
    user32.SetCursorPos.argtypes = [ctypes.c_int, ctypes.c_int]
    user32.SetCursorPos.restype = wintypes.BOOL
    user32.SendInput.argtypes = [wintypes.UINT, ctypes.POINTER(INPUT), ctypes.c_int]
    user32.SendInput.restype = wintypes.UINT
    kernel32.GetLastError.restype = wintypes.DWORD
    return (user32, (ctypes, wintypes, POINT, INPUT, MOUSEINPUT, KEYBDINPUT))


def _windows_window(title: str, timeout: float = 20.0) -> tuple[int, Any, Any]:
    user32, types = _windows_user32()
    ctypes, wintypes, _, _, _, _ = types
    callback_type = ctypes.WINFUNCTYPE(wintypes.BOOL, wintypes.HWND, wintypes.LPARAM)
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        found: list[int] = []

        @callback_type
        def callback(hwnd: int, _lparam: int) -> bool:
            if not user32.IsWindowVisible(hwnd):
                return True
            length = user32.GetWindowTextLengthW(hwnd)
            text = ctypes.create_unicode_buffer(length + 1)
            user32.GetWindowTextW(hwnd, text, length + 1)
            if text.value == title:
                found.append(hwnd)
            return True

        user32.EnumWindows(callback, 0)
        if found:
            if len(found) != 1:
                raise E2EError(
                    f"expected one visible native window titled {title!r}, found {len(found)}"
                )
            return found[0], user32, types
        time.sleep(0.1)
    raise E2EError(f"could not find visible native window titled {title!r}")


def _windows_focus(user32: Any, hwnd: int) -> None:
    user32.ShowWindow(hwnd, 9)  # SW_RESTORE
    user32.BringWindowToTop(hwnd)
    user32.SetForegroundWindow(hwnd)
    deadline = time.monotonic() + 3.0
    while time.monotonic() < deadline:
        if user32.GetForegroundWindow() == hwnd:
            return
        time.sleep(0.05)
    raise E2EError("Windows native sample did not become the foreground window for SendInput")


def _require_foreground(user32: Any, hwnd: int) -> None:
    if user32.GetForegroundWindow() != hwnd:
        raise E2EError("refusing to send input because the uniquely titled sample is not foreground")


def _windows_send_input(user32: Any, types: Any, inputs: list[Any]) -> None:
    ctypes, wintypes, _, INPUT, _, _ = types
    array = (INPUT * len(inputs))(*inputs)
    sent = user32.SendInput(len(inputs), array, ctypes.sizeof(INPUT))
    if sent != len(inputs):
        error = ctypes.get_last_error()
        raise E2EError(f"SendInput accepted {sent}/{len(inputs)} events (GetLastError={error})")


def _windows_click(ready: dict[str, Any], title: str) -> None:
    import ctypes

    hwnd, user32, types = _windows_window(title)
    _windows_focus(user32, hwnd)
    ctypes_module, wintypes, POINT, INPUT, MOUSEINPUT, _ = types
    rect = wintypes.RECT()
    if not user32.GetClientRect(hwnd, ctypes.byref(rect)):
        raise E2EError("GetClientRect failed for Yami native window")
    origin = POINT(0, 0)
    if not user32.ClientToScreen(hwnd, ctypes.byref(origin)):
        raise E2EError("ClientToScreen failed for Yami native window")
    dpi = int(user32.GetDpiForWindow(hwnd) or 96)
    dpi_scale = dpi / 96.0
    declared_scale = float(ready.get("scale", dpi_scale))
    if abs(declared_scale - dpi_scale) > 0.25:
        raise E2EError(
            f"sample scale {declared_scale} disagrees with Win32 window DPI scale {dpi_scale}"
        )
    x, y, width, height = _rect(ready.get("button"), "button")
    screen_x = origin.x + round((x + width / 2) * declared_scale)
    screen_y = origin.y + round((y + height / 2) * declared_scale)
    if not user32.SetCursorPos(screen_x, screen_y):
        raise E2EError("SetCursorPos failed before native button click")
    _require_foreground(user32, hwnd)
    mouse = [
        INPUT(type=0, mi=MOUSEINPUT(0, 0, 0, 0x0002, 0, 0)),
        INPUT(type=0, mi=MOUSEINPUT(0, 0, 0, 0x0004, 0, 0)),
    ]
    _windows_send_input(user32, types, mouse)


def _windows_escape(title: str) -> None:
    hwnd, user32, types = _windows_window(title)
    _windows_focus(user32, hwnd)
    _require_foreground(user32, hwnd)
    _, _, _, INPUT, _, KEYBDINPUT = types
    keyboard = [
        INPUT(type=1, ki=KEYBDINPUT(0x1B, 0, 0, 0, 0)),
        INPUT(type=1, ki=KEYBDINPUT(0x1B, 0, 0x0002, 0, 0)),
    ]
    _windows_send_input(user32, types, keyboard)


def _send_click(platform: str, ready: dict[str, Any], args: argparse.Namespace) -> None:
    if platform == "linux":
        _linux_click(ready, args.linux_origin_x, args.linux_origin_y)
    elif platform == "windows":
        _windows_click(ready, args.window_title)
    else:
        print(
            "macOS E2E: waiting for the GPUI testing-only NSEvent to traverse "
            "the owned NSWindow host event path.",
            flush=True,
        )


def _send_escape(platform: str, args: argparse.Namespace) -> None:
    if platform == "linux":
        _linux_escape()
    elif platform == "windows":
        _windows_escape(args.window_title)
    else:
        print(
            "macOS E2E: the GPUI testing-only Escape event will traverse the "
            "owned NSWindow host event path.",
            flush=True,
        )


def _assert_frames(
    before_marker: dict[str, Any],
    after_marker: dict[str, Any],
    ready: dict[str, Any],
    evidence_dir: Path,
) -> dict[str, Any]:
    _marker_state(before_marker, 0)
    _marker_state(after_marker, 1)
    before_frame = before_marker["frame"]
    after_frame = after_marker["frame"]
    before_path = _read_ppm_path(before_frame, evidence_dir, "before")
    after_path = _read_ppm_path(after_frame, evidence_dir, "after")
    before = read_ppm(before_path)
    after = read_ppm(after_path)
    for label, image, metadata in (
        ("before", before, before_frame), ("after", after, after_frame)
    ):
        if image.width != int(metadata["width"]) or image.height != int(metadata["height"]):
            raise E2EError(f"{label} PPM dimensions disagree with native capture metadata")
    scale_before = float(before_frame["scale"])
    scale_after = float(after_frame["scale"])
    if abs(scale_before - scale_after) > 1e-6:
        raise E2EError("native frame scale changed between count 0 and count 1")
    counter = _rect(ready.get("counter"), "counter")
    button = _rect(ready.get("button"), "button")
    page_background_before = _frame_background(before)
    page_background_after = _frame_background(after)
    text_pixels_before = _foreground_count(before, counter, scale_before)
    text_pixels_after = _foreground_count(after, counter, scale_after)
    button_pixels_before = _foreground_count(before, button, scale_before, page_background_before)
    button_pixels_after = _foreground_count(after, button, scale_after, page_background_after)
    changed = _changed_pixels(before, after)
    counter_changed = _changed_pixels(before, after, counter, scale_before)
    if min(text_pixels_before, text_pixels_after) <= 0:
        raise E2EError("native Text component has no foreground pixels in the counter bounds")
    if min(button_pixels_before, button_pixels_after) <= 0:
        raise E2EError("native Button component has no visible foreground pixels")
    if changed <= 0 or counter_changed <= 0:
        raise E2EError(
            "count 0 and count 1 native captures did not change pixels in the counter text"
        )
    if before_marker.get("textPixels", 0) <= 0 or after_marker.get("textPixels", 0) <= 0:
        raise E2EError("sample-reported native text pixel coverage must be positive")
    if before_marker.get("buttonPixels", 0) <= 0 or after_marker.get("buttonPixels", 0) <= 0:
        raise E2EError("sample-reported native button pixel coverage must be positive")
    return {
        "before": str(before_path),
        "after": str(after_path),
        "width": before.width,
        "height": before.height,
        "scale": scale_before,
        "textForegroundPixels": [text_pixels_before, text_pixels_after],
        "buttonForegroundPixels": [button_pixels_before, button_pixels_after],
        "changedFramePixels": changed,
        "changedCounterPixels": counter_changed,
    }


def drive(args: argparse.Namespace) -> int:
    if not args.command:
        raise E2EError("provide the native sample command after `--`")
    evidence_dir = args.evidence_dir.resolve()
    evidence_dir.mkdir(parents=True, exist_ok=True)
    log_path = args.log.resolve()
    log_path.parent.mkdir(parents=True, exist_ok=True)
    env = os.environ.copy()
    run_title = f"{args.window_title} [native-ui-{uuid.uuid4().hex}]"
    env.update(
        {
            "YAMI_NATIVE_UI_E2E": "1",
            "GPUI_NATIVE_E2E": "1",
            "YAMI_NATIVE_UI_EVIDENCE_DIR": str(evidence_dir),
            "YAMI_NATIVE_UI_WINDOW_TITLE": run_title,
        }
    )
    workspace_root = env.get("YAMI_NATIVE_WORKSPACE_ROOT")
    if not workspace_root:
        raise E2EError("YAMI_NATIVE_WORKSPACE_ROOT must be set by native_ui_workspace.sh")
    print(f"Launching native sample: {' '.join(args.command)}", flush=True)
    print(f"Evidence directory: {evidence_dir}", flush=True)
    process = subprocess.Popen(
        args.command,
        # Keep Moon's cwd at the isolated workspace root so it discovers the
        # absolute-member moon.work while the selected package path stays absolute.
        cwd=workspace_root,
        env=env,
        stdin=subprocess.DEVNULL,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        encoding="utf-8",
        errors="replace",
        bufsize=1,
    )
    output = ProcessOutput(process, log_path)
    try:
        ready = output.wait_marker("YAMI_NATIVE_UI_READY", timeout=args.startup_timeout)
        button = _rect(ready.get("button"), "button")
        counter = _rect(ready.get("counter"), "counter")
        before = output.wait_marker(
            "YAMI_NATIVE_UI_PRESENTED",
            predicate=lambda payload: payload.get("count") == 0,
            timeout=args.marker_timeout,
        )
        _marker_state(before, 0)
        click_args = argparse.Namespace(**vars(args))
        click_args.window_title = run_title
        _send_click(args.platform, ready, click_args)
        click = output.wait_marker("YAMI_NATIVE_UI_CLICK", timeout=args.marker_timeout)
        if click.get("count") != 1 or click.get("value") != 1:
            raise E2EError(f"host-delivered click did not produce count 1: {click}")
        after = output.wait_marker(
            "YAMI_NATIVE_UI_PRESENTED",
            predicate=lambda payload: payload.get("count") == 1,
            timeout=args.marker_timeout,
        )
        image_report = _assert_frames(before, after, ready, evidence_dir)
        _send_escape(args.platform, click_args)
        complete = output.wait_marker("YAMI_NATIVE_UI_COMPLETE", timeout=args.marker_timeout)
        if complete.get("count") != 1 or complete.get("value") != 1 or complete.get("destroyed") is not True:
            raise E2EError(f"native sample did not complete through host destruction: {complete}")
        return_code = process.wait(timeout=10)
        if return_code != 0:
            raise E2EError(f"native sample exited with status {return_code}")
        report = {
            "platform": args.platform,
            "inputDelivery": {
                "linux": "XTest pointer input through Xvfb -> Weston X11 backend -> Wayland client",
                "windows": "Win32 SendInput to the visible native HWND",
                "macos": "synthetic NSEvent through the owned NSWindow sendEvent path; not physical hardware",
            }[args.platform],
            "windowTitle": run_title,
            "buttonBounds": ready["button"],
            "counterBounds": ready["counter"],
            "click": click,
            "complete": complete,
            "presented": {"before": before, "after": after},
            "frames": image_report,
            "command": args.command,
        }
        report_path = evidence_dir / "native-ui-report.json"
        report_path.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n", encoding="utf-8")
        print(f"Native UI proof passed; report: {report_path}", flush=True)
        print(json.dumps(report, indent=2, sort_keys=True), flush=True)
        return 0
    except (E2EError, OSError, subprocess.SubprocessError, KeyError, ValueError) as error:
        print(f"Native UI E2E failed: {error}", file=sys.stderr, flush=True)
        if process.poll() is None:
            process.terminate()
            try:
                process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait(timeout=5)
        output.drain()
        output.log.flush()
        if log_path.is_file():
            lines = log_path.read_text(encoding="utf-8", errors="replace").splitlines()
            print(f"Native sample log: {log_path}", file=sys.stderr, flush=True)
            for line in lines[-80:]:
                print(line, file=sys.stderr)
        raise
    finally:
        output.close()


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--platform", choices=("linux", "windows", "macos"), required=True)
    parser.add_argument("--evidence-dir", type=Path, required=True)
    parser.add_argument("--log", type=Path, required=True)
    parser.add_argument("--window-title", default="Yami-kumo Native UI")
    parser.add_argument("--startup-timeout", type=float, default=240.0)
    parser.add_argument("--marker-timeout", type=float, default=45.0)
    parser.add_argument("--linux-origin-x", type=int, default=0)
    parser.add_argument("--linux-origin-y", type=int, default=0)
    parser.add_argument("command", nargs=argparse.REMAINDER, help="native command after --")
    args = parser.parse_args()
    if args.command[:1] == ["--"]:
        args.command = args.command[1:]
    try:
        return drive(args)
    except E2EError:
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
