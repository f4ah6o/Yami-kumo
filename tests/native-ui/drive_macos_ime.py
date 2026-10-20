#!/usr/bin/env python3
"""Exercise the native text-field sample with a live macOS input method.

The helper selects a Japanese input source, posts key codes to the launched
application with CGEventPostToPid, and probes on-screen window metadata. The
application must be in `--text-e2e` mode and print `YAMI_NATIVE_UI_TEXT` markers.
"""

from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import queue
import shutil
import signal
import subprocess
import sys
import tempfile
import threading
import time

MARKER = "YAMI_NATIVE_UI_TEXT "
IME_OWNER_HINTS = (
    "Japanese",
    "Kotoeri",
    "InputMethod",
    "mozc",
    "azooKey",
    "GoogleJapaneseInput",
)


class ImeError(RuntimeError):
    pass


def compile_helper(evidence_dir: Path) -> Path:
    source = Path(__file__).with_name("macos_ime_helper.m")
    binary = evidence_dir / "macos_ime_helper"
    result = subprocess.run(
        [
            "/usr/bin/clang",
            "-fobjc-arc",
            "-Wall",
            "-Wextra",
            "-Werror",
            str(source),
            "-framework",
            "AppKit",
            "-framework",
            "ApplicationServices",
            "-framework",
            "Carbon",
            "-framework",
            "CoreFoundation",
            "-o",
            str(binary),
        ],
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        encoding="utf-8",
        errors="replace",
        check=False,
    )
    (evidence_dir / "ime-helper-build.log").write_text(result.stdout, encoding="utf-8")
    if result.returncode != 0:
        raise ImeError("macOS IME helper compilation failed")
    return binary


def run_helper(helper: Path, *args: str, check: bool = True) -> subprocess.CompletedProcess:
    result = subprocess.run(
        [str(helper), *args],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        encoding="utf-8",
        errors="replace",
        check=False,
    )
    if check and result.returncode != 0:
        raise ImeError(
            f"helper {args[0]} failed ({result.returncode}): {result.stderr.strip()}"
        )
    return result


def helper_json(helper: Path, *args: str, check: bool = True) -> dict:
    result = run_helper(helper, *args, check=check)
    for line in reversed(result.stdout.splitlines()):
        line = line.strip()
        if line.startswith("{"):
            return json.loads(line)
    raise ImeError(f"helper {args[0]} produced no JSON")


class AppProcess:
    def __init__(self, command: list[str], env: dict[str, str], log_path: Path):
        self.log_path = log_path
        self.log = log_path.open("w", encoding="utf-8")
        self.process = subprocess.Popen(
            command,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            encoding="utf-8",
            errors="replace",
            env=env,
            bufsize=1,
        )
        self.lines: queue.Queue[str] = queue.Queue()
        self.markers: list[dict] = []
        self.reader = threading.Thread(target=self._read, daemon=True)
        self.reader.start()

    def _read(self) -> None:
        assert self.process.stdout is not None
        for line in self.process.stdout:
            self.log.write(line)
            self.log.flush()
            stripped = line.strip()
            if stripped.startswith(MARKER):
                try:
                    payload = json.loads(stripped[len(MARKER) :])
                except json.JSONDecodeError:
                    payload = {"raw": stripped}
                payload["_line"] = stripped
                self.markers.append(payload)
            self.lines.put(stripped)

    def wait_marker(self, predicate, timeout: float, description: str) -> dict:
        deadline = time.monotonic() + timeout
        for marker in self.markers:
            if predicate(marker):
                return marker
        while time.monotonic() < deadline:
            try:
                self.lines.get(timeout=0.1)
            except queue.Empty:
                continue
            for marker in self.markers:
                if predicate(marker):
                    return marker
        raise ImeError(f"timed out waiting for {description}")

    def close(self) -> None:
        if self.process.poll() is None:
            self.process.terminate()
            try:
                self.process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                self.process.kill()
                self.process.wait(timeout=5)
        self.log.close()


def candidate_windows(probe: dict) -> list[dict]:
    windows = []
    for window in probe.get("windows", []):
        owner = window.get("owner", "")
        if any(hint in owner for hint in IME_OWNER_HINTS):
            windows.append(window)
    return windows


def drive(args: argparse.Namespace) -> int:
    if sys.platform != "darwin":
        raise ImeError("the macOS IME proof requires Darwin")
    if not args.command:
        raise ImeError("provide the native sample command after `--`")
    evidence_dir = args.evidence_dir.resolve()
    evidence_dir.mkdir(parents=True, exist_ok=True)
    log_path = args.log.resolve()
    log_path.parent.mkdir(parents=True, exist_ok=True)
    helper = compile_helper(evidence_dir)
    report: dict = {
        "platform": "macos",
        "claims": {
            "ime.live-engine.preedit": "NOT_RUN",
            "ime.live-engine.commit": "NOT_RUN",
            "ime.candidate.visible": "NOT_RUN",
            "ime.candidate.anchored": "NOT_RUN",
            "ime.physical-keyboard": "NOT_RUN",
        },
        "candidate": None,
        "window": None,
        "source": None,
    }
    app: AppProcess | None = None
    previous_source = ""
    try:
        trust = helper_json(helper, "trust", check=False)
        if trust.get("status") == "unsupported":
            report["claims"]["ime.live-engine.preedit"] = "UNSUPPORTED"
            report["claims"]["ime.live-engine.commit"] = "UNSUPPORTED"
            (evidence_dir / "ime.json").write_text(
                json.dumps(report, ensure_ascii=False, indent=2) + "\n",
                encoding="utf-8",
            )
            print("UNSUPPORTED: accessibility posting is not authorized")
            return 0
        try:
            selection = helper_json(helper, "select-japanese", check=True)
        except ImeError:
            (evidence_dir / "ime.json").write_text(
                json.dumps(report, ensure_ascii=False, indent=2) + "\n",
                encoding="utf-8",
            )
            print("NOT_RUN: no Japanese input source is available")
            return 0
        previous_source = selection.get("previous", "")
        report["source"] = selection.get("selected", "")

        env = dict(os.environ)
        env["YAMI_NATIVE_UI_TEXT_E2E"] = "1"
        env["YAMI_NATIVE_UI_WINDOW_TITLE"] = "Yami-kumo IME proof"
        env.pop("YAMI_NATIVE_UI_E2E", None)
        env.pop("YAMI_NATIVE_UI_AX_E2E", None)
        env.pop("YAMI_NATIVE_UI_SMOKE", None)
        app = AppProcess(args.command, env, log_path)
        app.wait_marker(
            lambda marker: marker.get("phase") == "frame", 15.0, "the first frame"
        )
        pid = app.process.pid
        helper_json(helper, "activate", str(pid))
        helper_json(helper, "type", str(pid), "tab")
        app.wait_marker(
            lambda marker: marker.get("phase") == "begin", 8.0, "the text session"
        )
        helper_json(helper, "type", str(pid), "romaji")
        preedit = app.wait_marker(
            lambda marker: marker.get("phase") == "preedit"
            and any("\u3040" <= ch <= "\u30ff" for ch in marker.get("text", "")),
            10.0,
            "a Japanese preedit",
        )
        report["preedit"] = preedit.get("text", "")
        report["claims"]["ime.live-engine.preedit"] = "PASS"
        probe = helper_json(helper, "probe")
        candidates = candidate_windows(probe)
        report["candidate"] = candidates[0] if candidates else None
        report["claims"]["ime.candidate.visible"] = (
            "PASS" if candidates else "NOT_RUN"
        )
        helper_json(helper, "type", str(pid), "space")
        time.sleep(0.4)
        probe = helper_json(helper, "probe")
        if candidates == [] and candidate_windows(probe):
            report["candidate"] = candidate_windows(probe)[0]
            report["claims"]["ime.candidate.visible"] = "PASS"
        helper_json(helper, "type", str(pid), "enter")
        commit = app.wait_marker(
            lambda marker: marker.get("phase") == "commit"
            and marker.get("text", ""),
            10.0,
            "a commit",
        )
        report["commit"] = commit.get("text", "")
        report["claims"]["ime.live-engine.commit"] = "PASS"
        document = app.wait_marker(
            lambda marker: marker.get("phase") == "frame"
            and marker.get("value", "") == report["commit"],
            8.0,
            "the committed document",
        )
        report["document"] = document.get("value", "")
    finally:
        if app is not None:
            app.close()
        if previous_source:
            run_helper(helper, "restore", previous_source, check=False)
        (evidence_dir / "ime.json").write_text(
            json.dumps(report, ensure_ascii=False, indent=2) + "\n",
            encoding="utf-8",
        )
    print(json.dumps(report["claims"], ensure_ascii=False, sort_keys=True))
    return 0


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--evidence-dir", type=Path, required=True)
    parser.add_argument("--log", type=Path, required=True)
    parser.add_argument("command", nargs=argparse.REMAINDER)
    args = parser.parse_args()
    if args.command and args.command[0] == "--":
        args.command = args.command[1:]
    try:
        return drive(args)
    except ImeError as error:
        print(f"FAIL: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
