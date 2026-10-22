#!/usr/bin/env python3
"""Drive the Shared Settings sample on Linux and check its frame markers.

This lane exercises the same portable model as the DOM test. Text entry uses
the compositor key path (no input-method engine is installed in CI), so the
`ime` claim stays NOT_RUN in the retained report.
"""

from __future__ import annotations

import argparse
import json
import os
import queue
import re
import subprocess
import sys
import threading
import time
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

MARKER = re.compile(r"^(YAMI_NATIVE_UI_SETTINGS) (\{.*\})$")
WINDOW_TITLE = "Yami-kumo Shared Settings"


def candidate_sha() -> str:
    sha = os.environ.get("YAMI_SHARED_UI_CANDIDATE_SHA") or os.environ.get("GITHUB_SHA")
    if sha:
        return sha.strip()
    root = os.environ.get("YAMI_NATIVE_YAMI_ROOT")
    if root:
        return subprocess.check_output(
            ["git", "-C", root, "rev-parse", "HEAD"], text=True
        ).strip()
    return "0" * 40


class SettingsError(RuntimeError):
    pass


class Output:
    def __init__(self, process: subprocess.Popen[str], log_path: Path):
        self.process = process
        self.log = log_path.open("w", encoding="utf-8", errors="replace")
        self.lines: queue.Queue[str | None] = queue.Queue()
        self.frames: list[dict[str, Any]] = []
        self.text_route: dict[str, Any] | None = None
        self._reader = threading.Thread(target=self._read, daemon=True)
        self._reader.start()

    def _read(self) -> None:
        assert self.process.stdout is not None
        for line in self.process.stdout:
            self.lines.put(line)
        self.lines.put(None)

    def _handle(self, line: str) -> None:
        self.log.write(line)
        self.log.flush()
        match = MARKER.match(line.rstrip("\r\n"))
        if match:
            try:
                payload = json.loads(match.group(2))
            except json.JSONDecodeError as error:
                raise SettingsError(f"invalid marker JSON: {error}") from error
            if payload.get("phase") == "frame":
                self.frames.append(payload)
            elif payload.get("phase") == "text":
                self.text_route = payload

    def pump(self, timeout: float = 0.05) -> None:
        try:
            line = self.lines.get(timeout=timeout)
        except queue.Empty:
            return
        if line is None:
            raise SettingsError(
                f"Settings sample exited early (exit={self.process.poll()})"
            )
        self._handle(line)

    def next_line(self, timeout: float) -> str:
        try:
            line = self.lines.get(timeout=timeout)
        except queue.Empty as error:
            raise SettingsError("timed out waiting for Settings output") from error
        if line is None:
            raise SettingsError(
                f"Settings sample exited early (exit={self.process.poll()})"
            )
        self._handle(line)
        return line

    def wait_frame(self, predicate, timeout: float) -> dict[str, Any]:
        deadline = time.monotonic() + timeout
        while True:
            for frame in self.frames:
                if predicate(frame):
                    return frame
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                raise SettingsError(
                    f"timed out waiting for frame; frames={self.frames[-3:]}"
                )
            self.next_line(remaining)

    def close(self) -> None:
        self.log.close()


def driver_log(output: Output, message: str) -> None:
    output.log.write(f"DRIVER {message}\n")
    output.log.flush()


def xdotool(*args: str) -> None:
    subprocess.run(["xdotool", *args], check=True, stdout=subprocess.DEVNULL)


def x11_window_names() -> list[tuple[int, str]]:
    listing = subprocess.run(
        ["xdotool", "search", "--name", ".*"], capture_output=True, text=True
    )
    windows: list[tuple[int, str]] = []
    for token in listing.stdout.split():
        name = subprocess.run(
            ["xdotool", "getwindowname", token], capture_output=True, text=True
        ).stdout.strip()
        windows.append((int(token), name))
    return windows


def wait_window(output: Output, timeout: float) -> int:
    """Locate the X window the lane should drive.

    The sample title lives on the Wayland surface, not on any X window, so
    under Weston/Xvfb the only client-visible window is the compositor
    output ("Weston Compositor - screen0"). Prefer an X window that already
    carries the sample title in case a compositor propagates it, then fall
    back to the compositor output window. Every candidate is logged into
    the evidence log.
    """
    deadline = time.monotonic() + timeout
    logged: set[int] = set()
    while time.monotonic() < deadline:
        output.pump()
        titled = subprocess.run(
            ["xdotool", "search", "--name", WINDOW_TITLE],
            capture_output=True,
            text=True,
        )
        if titled.stdout.strip():
            window = int(titled.stdout.split()[0])
            driver_log(output, f"found app-titled X window {window}")
            return window
        windows = x11_window_names()
        for window, name in windows:
            if window not in logged:
                logged.add(window)
                driver_log(output, f"X window {window}: {name!r}")
        for window, name in windows:
            if "Weston" in name:
                driver_log(output, f"using compositor window {window}: {name!r}")
                return window
        time.sleep(0.2)
    raise SettingsError(
        f"no compositor or app-titled X window appeared (want {WINDOW_TITLE!r})"
    )


def focus_window(output: Output, window: int) -> dict[str, Any]:
    """Point the X input focus at the window and log what happened.

    Weston runs without an X window manager inside Xvfb, so windowactivate
    (EWMH/_NET_ACTIVE_WINDOW) has no effect; XSetInputFocus (windowfocus)
    is the primitive that works here. Both are attempted and logged so the
    evidence shows which one took.
    """
    before = subprocess.run(
        ["xdotool", "getwindowfocus", "-f"], capture_output=True, text=True
    ).stdout.strip()
    driver_log(output, f"getwindowfocus before: {before}")
    focused = subprocess.run(
        ["xdotool", "windowfocus", "--sync", str(window)],
        capture_output=True,
        text=True,
    )
    driver_log(
        output,
        f"windowfocus {window}: rc={focused.returncode} {focused.stderr.strip()}",
    )
    activated = subprocess.run(
        ["xdotool", "windowactivate", "--sync", str(window)],
        capture_output=True,
        text=True,
    )
    driver_log(
        output,
        f"windowactivate {window}: rc={activated.returncode} "
        f"{activated.stderr.strip()}",
    )
    after = subprocess.run(
        ["xdotool", "getwindowfocus", "-f"], capture_output=True, text=True
    ).stdout.strip()
    driver_log(output, f"getwindowfocus after: {after}")
    if focused.returncode != 0 and activated.returncode != 0:
        raise SettingsError(
            f"could not focus compositor window {window} "
            f"(windowfocus rc={focused.returncode}, "
            f"windowactivate rc={activated.returncode})"
        )
    return {
        "window": window,
        "focusBefore": before,
        "focusAfter": after,
        "windowfocusRc": focused.returncode,
        "windowactivateRc": activated.returncode,
    }


def drive_linux(output: Output, timeout: float) -> dict[str, Any]:
    window = wait_window(output, timeout)
    focus = focus_window(output, window)
    # The runner pre-focuses the name field; wait for that frame marker
    # before typing so key delivery is ordered against the app loop.
    output.wait_frame(lambda f: f.get("focus") == "name", min(timeout, 30.0))
    xdotool("type", "--delay", "60", "abc")
    try:
        typed = output.wait_frame(lambda f: f.get("name") == "abc", 6.0)
    except SettingsError:
        # Some text routes publish a composition and commit only on Enter.
        xdotool("key", "--clearmodifiers", "Return")
        typed = output.wait_frame(lambda f: f.get("name") == "abc", 10.0)
    xdotool("key", "--clearmodifiers", "Tab")
    # Tab must move scope focus to Save and keep it there; activating the
    # dialog from the name field would not prove traversal worked.
    output.wait_frame(lambda f: f.get("focus") == "save", 10.0)
    xdotool("key", "--clearmodifiers", "Return")
    dialog = output.wait_frame(lambda f: f.get("dialog") is True, 10.0)
    xdotool("key", "--clearmodifiers", "Return")
    saved = output.wait_frame(lambda f: f.get("status") == "saved", 10.0)
    return {"typed": typed, "dialog": dialog, "saved": saved, "x11Focus": focus}


def drive_windows(output: Output, timeout: float) -> dict[str, Any]:
    import ctypes
    from ctypes import wintypes

    user32 = ctypes.windll.user32

    class KEYBDINPUT(ctypes.Structure):
        _fields_ = [
            ("wVk", wintypes.WORD),
            ("wScan", wintypes.WORD),
            ("dwFlags", wintypes.DWORD),
            ("time", wintypes.DWORD),
            ("dwExtraInfo", ctypes.POINTER(wintypes.ULONG)),
        ]

    user32.SendInput.argtypes = (
        wintypes.UINT,
        ctypes.POINTER(KEYBDINPUT),
        ctypes.c_int,
    )
    user32.SendInput.restype = wintypes.UINT

    def send(vk: int) -> None:
        down = KEYBDINPUT(vk, 0, 0, 0, None)
        up = KEYBDINPUT(vk, 0, 2, 0, None)
        user32.SendInput(1, ctypes.byref(down), ctypes.sizeof(down))
        user32.SendInput(1, ctypes.byref(up), ctypes.sizeof(up))

    def send_text(character: str) -> None:
        down = KEYBDINPUT(0, ord(character), 0x0004, 0, None)
        up = KEYBDINPUT(0, ord(character), 0x0004 | 0x0002, 0, None)
        user32.SendInput(1, ctypes.byref(down), ctypes.sizeof(down))
        user32.SendInput(1, ctypes.byref(up), ctypes.sizeof(up))

    hwnd = 0
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline and not hwnd:
        output.pump()
        found: list[int] = []

        @ctypes.WINFUNCTYPE(wintypes.BOOL, wintypes.HWND, wintypes.LPARAM)
        def callback(window: int, _param: int) -> bool:
            length = user32.GetWindowTextLengthW(window)
            if length <= 0:
                return True
            buffer = ctypes.create_unicode_buffer(length + 1)
            user32.GetWindowTextW(window, buffer, length + 1)
            if buffer.value == WINDOW_TITLE:
                found.append(window)
                return False
            return True

        user32.EnumWindows(callback, 0)
        if found:
            hwnd = found[0]
        else:
            time.sleep(0.2)
    if not hwnd:
        raise SettingsError(f"window {WINDOW_TITLE!r} did not appear")
    user32.ShowWindow(hwnd, 9)
    user32.BringWindowToTop(hwnd)
    user32.SetForegroundWindow(hwnd)
    focus_deadline = time.monotonic() + 5.0
    while time.monotonic() < focus_deadline:
        output.pump()
        if user32.GetForegroundWindow() == hwnd:
            break
        time.sleep(0.05)
    else:
        raise SettingsError("sample window did not become foreground for SendInput")
    time.sleep(0.3)
    for character in "abc":
        send_text(character)
    try:
        typed = output.wait_frame(lambda f: f.get("name") == "abc", 6.0)
    except SettingsError:
        send(0x0D)
        typed = output.wait_frame(lambda f: f.get("name") == "abc", 10.0)
    send(0x09)
    time.sleep(0.3)
    send(0x0D)
    dialog = output.wait_frame(lambda f: f.get("dialog") is True, 10.0)
    send(0x0D)
    saved = output.wait_frame(lambda f: f.get("status") == "saved", 10.0)
    return {"typed": typed, "dialog": dialog, "saved": saved}


def write_report(path: Path, report: dict[str, Any]) -> None:
    temporary = path.with_name(f".{path.name}.tmp")
    temporary.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n")
    temporary.replace(path)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--platform", choices=("linux", "windows"), required=True)
    parser.add_argument("--evidence-dir", type=Path, required=True)
    parser.add_argument("--log", type=Path, required=True)
    parser.add_argument("--timeout", type=float, default=420.0)
    parser.add_argument("command", nargs=argparse.REMAINDER)
    args = parser.parse_args()
    command = args.command[1:] if args.command[:1] == ["--"] else args.command
    started = datetime.now(timezone.utc).isoformat()
    process = subprocess.Popen(
        command,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        bufsize=1,
    )
    output = Output(process, args.log)
    try:
        frames = drive_linux(output, args.timeout) if args.platform == "linux" else drive_windows(output, args.timeout)
        process.terminate()
        text_route = output.text_route or {}
        text_claim = (
            f"PASS ({text_route.get('route', 'key path')}, no IME engine)"
            if args.platform == "linux"
            else "PASS (key path, no IME engine)"
        )
        report = {
            "schemaVersion": "settings-lane/v1",
            "fixtureId": "settings-flow",
            "candidateSha": candidate_sha(),
            "platform": args.platform,
            "backend": "gpui-native",
            "target": "native",
            "layer": "runtime",
            "status": "pass",
            "windowTitle": WINDOW_TITLE,
            "frames": frames,
            "textTransport": text_route,
            "startedAt": started,
            "finishedAt": datetime.now(timezone.utc).isoformat(),
            "command": command,
            "input": (
                "xdotool XTest -> Weston X11 backend -> Wayland client"
                if args.platform == "linux"
                else "Win32 SendInput to the visible HWND"
            ),
            "claims": {
                "settings.flow": "PASS",
                "settings.text": text_claim,
                "settings.ime": "NOT_RUN",
                "settings.ax": "NOT_RUN",
            },
        }
        write_report(args.evidence_dir / f"settings-{args.platform}.json", report)
        print("Shared Settings Linux lane passed", flush=True)
        return 0
    except (SettingsError, OSError, subprocess.SubprocessError) as error:
        report = {
            "schemaVersion": "settings-lane/v1",
            "fixtureId": "settings-flow",
            "candidateSha": candidate_sha(),
            "platform": args.platform,
            "backend": "gpui-native",
            "target": "native",
            "layer": "runtime",
            "status": "fail",
            "windowTitle": WINDOW_TITLE,
            "error": str(error),
            "startedAt": started,
            "finishedAt": datetime.now(timezone.utc).isoformat(),
            "command": command,
        }
        write_report(args.evidence_dir / f"settings-{args.platform}.json", report)
        print(f"Shared Settings {args.platform} lane failed: {error}", file=sys.stderr)
        return 1
    finally:
        if process.poll() is None:
            process.terminate()
        try:
            process.wait(timeout=10)
        except subprocess.TimeoutExpired:
            process.kill()
        output.close()


if __name__ == "__main__":
    raise SystemExit(main())
