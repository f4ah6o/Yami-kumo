#!/usr/bin/env python3
"""Drive the Shared Settings sample on Linux or Windows and check its markers.

This lane exercises the same portable model as the DOM test. On Windows the
sample arms the opt-in IMM32 text route, so ASCII characters may arrive as a
portable commit or, when that route is unavailable, as a WM_CHAR character on
the key path. The retained report names the transport that actually delivered
text, and the `ime` claim stays NOT_RUN in both cases.
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

sys.path.insert(0, str(Path(__file__).resolve().parent))
import drive_native_ui  # noqa: E402  (sibling module with the tested Win32 helpers)

MARKER = re.compile(r"^(YAMI_NATIVE_UI_SETTINGS) (\{.*\})$")
WINDOW_TITLE = "Yami-kumo Shared Settings"


def candidate_sha() -> str:
    """Bind the report to the checked-out commit, not the PR merge commit."""
    sha = os.environ.get("YAMI_SHARED_UI_CANDIDATE_SHA")
    if sha:
        return sha.strip()
    root = os.environ.get("YAMI_NATIVE_YAMI_ROOT")
    if root:
        try:
            return subprocess.check_output(
                ["git", "-C", root, "rev-parse", "HEAD"],
                text=True,
                encoding="utf-8",
            ).strip()
        except (OSError, subprocess.SubprocessError):
            pass
    sha = os.environ.get("GITHUB_SHA")
    if sha:
        return sha.strip()
    return "0" * 40


class SettingsError(RuntimeError):
    pass


def parse_marker(line: str) -> dict[str, Any] | None:
    """Return the JSON payload of one Settings marker line, or None."""
    match = MARKER.match(line.rstrip("\r\n"))
    if not match:
        return None
    try:
        payload = json.loads(match.group(2))
    except json.JSONDecodeError as error:
        raise SettingsError(f"invalid marker JSON: {error}") from error
    if not isinstance(payload, dict):
        raise SettingsError(f"Settings marker is not an object: {payload!r}")
    return payload


def classify_text_transport(markers: list[dict[str, Any]], platform: str = "windows") -> str | None:
    """Name the host path that delivered committed text, if any.

    A `commit` can only come from the portable text route (IMM32 on Windows),
    while `key` with `character` means WM_CHAR reached the ordinary key path.
    The report must not claim IMM when only the key path fired.
    """
    if platform == "linux":
        for marker in reversed(markers):
            if marker.get("phase") == "text" and marker.get("status") == "key-path":
                return "direct-keyboard"
        if any(marker.get("phase") == "commit" for marker in markers):
            return "text-input-v1-commit"
        return None
    if any(marker.get("phase") == "commit" for marker in markers):
        return "imm32-commit"
    if any(
        marker.get("phase") == "key" and marker.get("key") == "character"
        for marker in markers
    ):
        return "key-character"
    return None


def text_marker_summary(markers: list[dict[str, Any]]) -> list[dict[str, Any]]:
    """Keep the transport and key markers, dropping the bulky frame copies."""
    keys = ("phase", "status", "transport", "route", "epoch", "key", "text", "operation", "error")
    return [
        {key: marker[key] for key in keys if key in marker}
        for marker in markers
        if marker.get("phase") in ("text", "commit", "preedit", "cancel", "focus-lost", "exit")
    ]


def _windows_ime_names() -> list[str]:
    """List installed Japanese TSF text services, best effort."""
    names: list[str] = []
    try:
        import winreg

        base = r"SOFTWARE\Microsoft\CTF\TIP"
        root = winreg.HKEY_LOCAL_MACHINE
        with winreg.OpenKey(root, base) as tips:
            index = 0
            while True:
                try:
                    tip = winreg.EnumKey(tips, index)
                except OSError:
                    break
                index += 1
                profile_path = f"{base}\\{tip}\\LanguageProfile\\0x00000411"
                try:
                    with winreg.OpenKey(root, profile_path) as profiles:
                        profile_index = 0
                        while True:
                            try:
                                profile = winreg.EnumKey(profiles, profile_index)
                            except OSError:
                                break
                            profile_index += 1
                            try:
                                with winreg.OpenKey(
                                    root, f"{profile_path}\\{profile}"
                                ) as entry:
                                    description, _ = winreg.QueryValueEx(
                                        entry, "Description"
                                    )
                            except OSError:
                                continue
                            if description and description not in names:
                                names.append(description)
                except OSError:
                    continue
    except (ImportError, OSError):
        pass
    return names


def _windows_ime_description() -> str:
    names = _windows_ime_names()
    if names:
        return ", ".join(names)
    try:
        import ctypes

        user32 = ctypes.WinDLL("user32", use_last_error=True)
        imm32 = ctypes.WinDLL("imm32", use_last_error=True)
        user32.GetKeyboardLayout.restype = ctypes.c_void_p
        imm32.ImmGetDescriptionW.restype = ctypes.c_uint
        layout = user32.GetKeyboardLayout(0)
        buffer = ctypes.create_unicode_buffer(256)
        length = imm32.ImmGetDescriptionW(layout, buffer, len(buffer))
        return buffer.value if length else "not installed"
    except (OSError, AttributeError):
        return "not installed"


def environment() -> dict[str, Any]:
    """Record the host facts the lane note asks to keep with the evidence."""
    import platform

    details: dict[str, Any] = {
        "python": sys.version.split()[0],
        "platform": platform.platform(),
    }
    try:
        version = subprocess.run(
            ["moon", "version", "--all"],
            capture_output=True,
            text=True,
            encoding="utf-8",
            errors="replace",
            timeout=20,
        )
        lines = (version.stdout or version.stderr).strip().splitlines()
        details["moon"] = lines[:3]
    except (OSError, subprocess.SubprocessError):
        pass
    if os.name == "nt":
        details["ime"] = _windows_ime_description()
    return details


def environment_lines(details: dict[str, Any]) -> list[str]:
    lines = ["# settings-lane environment"]
    for key in ("platform", "python", "moon", "ime"):
        value = details.get(key)
        if value is None:
            continue
        if isinstance(value, list):
            value = " | ".join(value)
        lines.append(f"# {key}: {value}")
    return lines


class Output:
    def __init__(self, process: subprocess.Popen[str], log_path: Path):
        self.process = process
        self.log = log_path.open("w", encoding="utf-8", errors="replace")
        self.lines: queue.Queue[str | None] = queue.Queue()
        self.frames: list[dict[str, Any]] = []
        self.markers: list[dict[str, Any]] = []
        self.exit: dict[str, Any] | None = None
        self._reader = threading.Thread(target=self._read, daemon=True)
        self._reader.start()

    def _read(self) -> None:
        assert self.process.stdout is not None
        for line in self.process.stdout:
            self.lines.put(line)
        self.lines.put(None)

    def write_header(self, lines: list[str]) -> None:
        for line in lines:
            self.log.write(line + "\n")
        self.log.flush()

    def _handle(self, line: str) -> None:
        self.log.write(line)
        self.log.flush()
        payload = parse_marker(line)
        if payload is None:
            return
        self.markers.append(payload)
        if payload.get("phase") == "frame":
            self.frames.append(payload)
        elif payload.get("phase") == "exit":
            self.exit = payload

    def _exit_message(self) -> str:
        detail = ""
        if self.exit is not None:
            detail = f"; reason={self.exit.get('reason')} ticks={self.exit.get('ticks')}"
        return f"Settings sample exited early (exit={self.process.poll()}){detail}"

    def pump(self, timeout: float = 0.05) -> None:
        try:
            line = self.lines.get(timeout=timeout)
        except queue.Empty:
            return
        if line is None:
            raise SettingsError(self._exit_message())
        self._handle(line)

    def next_line(self, timeout: float) -> str:
        try:
            line = self.lines.get(timeout=timeout)
        except queue.Empty as error:
            raise SettingsError(
                f"timed out waiting for Settings output; markers={self.markers[-5:]}"
            ) from error
        if line is None:
            raise SettingsError(self._exit_message())
        self._handle(line)
        return line

    def wait_frame(self, predicate, timeout: float, after: int = 0) -> dict[str, Any]:
        deadline = time.monotonic() + timeout
        while True:
            for frame in self.frames[after:]:
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
    def key(name: str) -> None:
        xdotool("key", "--clearmodifiers", name)

    flow = drive_dialog(output, key, "Tab", "Return", "Escape")
    return {"typed": typed, **flow, "x11Focus": focus}


def drive_dialog(output: Output, key, tab, enter, escape) -> dict[str, Any]:
    def step(value, predicate):
        after = len(output.frames)
        key(value)
        return output.wait_frame(predicate, 10.0, after=after)

    save_focus = step(tab, lambda f: f.get("focus") == "save")
    step(enter, lambda f: f.get("dialog") is True and f.get("focus") == "confirm")
    cancelled = step(escape, lambda f: f.get("dialog") is False and f.get("focus") == "save")
    dialog = step(enter, lambda f: f.get("dialog") is True and f.get("focus") == "confirm")
    saved = step(enter, lambda f: f.get("status") == "saved" and f.get("name") == "abc" and f.get("dialog") is False)
    return {"saveFocus": save_focus, "cancelled": cancelled, "dialog": dialog, "saved": saved}


def drive_windows(output: Output, timeout: float) -> dict[str, Any]:
    native = drive_native_ui
    # The sample stops itself at its tick limit. Do not let a slow window
    # lookup outlive it and turn the failure into a meaningless EOF.
    window_timeout = min(max(timeout, 1.0), 60.0)
    hwnd, user32, types = native._windows_window(
        WINDOW_TITLE, window_timeout, pid=output.process.pid
    )
    native._windows_focus(user32, hwnd)
    native._require_foreground(user32, hwnd)
    _, _, _, INPUT, _, KEYBDINPUT = types

    def send(events: list[Any]) -> None:
        # Losing the foreground would send the rest of the sequence to another
        # window; fail instead of recording a misleading pass.
        native._require_foreground(user32, hwnd)
        native._windows_send_input(user32, types, events)

    def send_text(character: str) -> None:
        send(
            [
                INPUT(type=1, ki=KEYBDINPUT(0, ord(character), 0x0004, 0, 0)),
                INPUT(type=1, ki=KEYBDINPUT(0, ord(character), 0x0004 | 0x0002, 0, 0)),
            ]
        )

    def send_key(vk: int) -> None:
        send(
            [
                INPUT(type=1, ki=KEYBDINPUT(vk, 0, 0, 0, 0)),
                INPUT(type=1, ki=KEYBDINPUT(vk, 0, 0x0002, 0, 0)),
            ]
        )

    time.sleep(0.3)
    for character in "abc":
        send_text(character)
    try:
        typed = output.wait_frame(lambda frame: frame.get("name") == "abc", 6.0)
    except SettingsError:
        # Only a live preedit justifies an Enter commit. Without one, Enter
        # would submit the empty draft and hide the missing text path.
        if not any(marker.get("phase") == "preedit" for marker in output.markers):
            raise
        send_key(0x0D)
        typed = output.wait_frame(lambda frame: frame.get("name") == "abc", 10.0)
    return {"typed": typed, **drive_dialog(output, send_key, 0x09, 0x0D, 0x1B)}


def write_report(path: Path, report: dict[str, Any]) -> None:
    temporary = path.with_name(f".{path.name}.tmp")
    temporary.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n")
    temporary.replace(path)


def build_pass_report(
    *,
    platform: str,
    candidate: str,
    frames: dict[str, dict[str, Any]],
    transport: str,
    markers: list[dict[str, Any]],
    details: dict[str, Any],
    started: str,
    command: list[str],
) -> dict[str, Any]:
    return {
        "schemaVersion": "settings-lane/v1",
        "fixtureId": "settings-flow",
        "candidateSha": candidate,
        "platform": platform,
        "backend": "gpui-native",
        "target": "native",
        "layer": "runtime",
        "status": "pass",
        "windowTitle": WINDOW_TITLE,
        "frames": frames,
        "result": {
            "name": frames["typed"].get("name"),
            "dialog": frames["dialog"].get("dialog"),
            "status": frames["saved"].get("status"),
        },
        "textTransport": transport,
        "textMarkers": text_marker_summary(markers),
        "environment": details,
        "startedAt": started,
        "finishedAt": datetime.now(timezone.utc).isoformat(),
        "command": command,
        "input": (
            "xdotool XTest -> Weston X11 backend -> Wayland client"
            if platform == "linux"
            else "Win32 SendInput (INPUT/KEYBDINPUT) to the visible HWND"
        ),
        "claims": {
            "settings.flow": "PASS",
            "settings.text": (
                "PASS (IMM32 commit)"
                if transport == "imm32-commit"
                else f"PASS ({transport}, no IME engine)" if platform == "linux"
                else "PASS (WM_CHAR key path, no IME engine)"
            ),
            "settings.ime": "NOT_RUN",
            "settings.ax": "NOT_RUN",
        },
    }


def build_fail_report(
    *,
    platform: str,
    candidate: str,
    error: str,
    markers: list[dict[str, Any]],
    exit_marker: dict[str, Any] | None,
    details: dict[str, Any],
    started: str,
    command: list[str],
) -> dict[str, Any]:
    return {
        "schemaVersion": "settings-lane/v1",
        "fixtureId": "settings-flow",
        "candidateSha": candidate,
        "platform": platform,
        "backend": "gpui-native",
        "target": "native",
        "layer": "runtime",
        "status": "fail",
        "windowTitle": WINDOW_TITLE,
        # The matrix schema requires a declared reason on every non-pass lane.
        "reason": error,
        "error": error,
        "textMarkers": text_marker_summary(markers),
        "sampleExit": exit_marker,
        "environment": details,
        "startedAt": started,
        "finishedAt": datetime.now(timezone.utc).isoformat(),
        "command": command,
    }


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
    details = environment()
    process = subprocess.Popen(
        command,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        encoding="utf-8",
        errors="replace",
        bufsize=1,
    )
    output = Output(process, args.log)
    output.write_header(environment_lines(details))
    try:
        frames = (
            drive_linux(output, args.timeout)
            if args.platform == "linux"
            else drive_windows(output, args.timeout)
        )
        transport = classify_text_transport(output.markers, args.platform)
        if transport is None:
            raise SettingsError(
                "text reached the model without a text-transport marker"
            )
        process.terminate()
        report = build_pass_report(
            platform=args.platform,
            candidate=candidate_sha(),
            frames=frames,
            transport=transport,
            markers=output.markers,
            details=details,
            started=started,
            command=command,
        )
        write_report(args.evidence_dir / f"settings-{args.platform}.json", report)
        print(f"Shared Settings {args.platform} lane passed", flush=True)
        return 0
    except (
        SettingsError,
        drive_native_ui.E2EError,
        OSError,
        subprocess.SubprocessError,
    ) as error:
        report = build_fail_report(
            platform=args.platform,
            candidate=candidate_sha(),
            error=str(error),
            markers=output.markers,
            exit_marker=output.exit,
            details=details,
            started=started,
            command=command,
        )
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
