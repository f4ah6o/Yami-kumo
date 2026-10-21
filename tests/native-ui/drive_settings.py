#!/usr/bin/env python3
"""Drive the Shared Settings sample on Linux and check its frame markers.

This lane exercises the same portable model as the DOM test. Text entry uses
the compositor key path (no input-method engine is installed in CI), so the
`ime` claim stays NOT_RUN in the retained report.
"""

from __future__ import annotations

import argparse
import json
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


class SettingsError(RuntimeError):
    pass


class Output:
    def __init__(self, process: subprocess.Popen[str], log_path: Path):
        self.process = process
        self.log = log_path.open("w", encoding="utf-8", errors="replace")
        self.lines: queue.Queue[str | None] = queue.Queue()
        self.frames: list[dict[str, Any]] = []
        self._reader = threading.Thread(target=self._read, daemon=True)
        self._reader.start()

    def _read(self) -> None:
        assert self.process.stdout is not None
        for line in self.process.stdout:
            self.lines.put(line)
        self.lines.put(None)

    def next_line(self, timeout: float) -> str:
        try:
            line = self.lines.get(timeout=timeout)
        except queue.Empty as error:
            raise SettingsError("timed out waiting for Settings output") from error
        if line is None:
            raise SettingsError(
                f"Settings sample exited early (exit={self.process.poll()})"
            )
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


def xdotool(*args: str) -> None:
    subprocess.run(["xdotool", *args], check=True, stdout=subprocess.DEVNULL)


def wait_window(timeout: float) -> None:
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        found = subprocess.run(
            ["xdotool", "search", "--name", WINDOW_TITLE],
            capture_output=True,
            text=True,
        )
        if found.stdout.strip():
            return
        time.sleep(0.2)
    raise SettingsError(f"window {WINDOW_TITLE!r} did not appear")


def drive_linux(output: Output, timeout: float) -> dict[str, Any]:
    wait_window(timeout)
    xdotool("search", "--sync", "--name", WINDOW_TITLE, "windowactivate", "--sync")
    time.sleep(0.3)
    xdotool("type", "--delay", "60", "abc")
    typed = output.wait_frame(lambda f: f.get("name") == "abc", 10.0)
    xdotool("key", "--clearmodifiers", "Tab")
    time.sleep(0.3)
    xdotool("key", "--clearmodifiers", "Return")
    dialog = output.wait_frame(lambda f: f.get("dialog") is True, 10.0)
    xdotool("key", "--clearmodifiers", "Return")
    saved = output.wait_frame(lambda f: f.get("status") == "saved", 10.0)
    return {"typed": typed, "dialog": dialog, "saved": saved}


def write_report(path: Path, report: dict[str, Any]) -> None:
    temporary = path.with_name(f".{path.name}.tmp")
    temporary.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n")
    temporary.replace(path)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--evidence-dir", type=Path, required=True)
    parser.add_argument("--log", type=Path, required=True)
    parser.add_argument("--timeout", type=float, default=180.0)
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
        frames = drive_linux(output, args.timeout)
        process.terminate()
        report = {
            "platform": "linux",
            "status": "passed",
            "windowTitle": WINDOW_TITLE,
            "frames": frames,
            "startedAt": started,
            "finishedAt": datetime.now(timezone.utc).isoformat(),
            "command": command,
            "input": "xdotool XTest -> Weston X11 backend -> Wayland client",
            "claims": {
                "settings.flow": "PASS",
                "settings.text": "PASS (key path, no IME engine)",
                "settings.ime": "NOT_RUN",
                "settings.ax": "NOT_RUN",
            },
        }
        write_report(args.evidence_dir / "settings-linux.json", report)
        print("Shared Settings Linux lane passed", flush=True)
        return 0
    except (SettingsError, OSError, subprocess.SubprocessError) as error:
        report = {
            "platform": "linux",
            "status": "failed",
            "windowTitle": WINDOW_TITLE,
            "error": str(error),
            "startedAt": started,
            "finishedAt": datetime.now(timezone.utc).isoformat(),
            "command": command,
        }
        write_report(args.evidence_dir / "settings-linux.json", report)
        print(f"Shared Settings Linux lane failed: {error}", file=sys.stderr)
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
