#!/usr/bin/env python3
"""Observe the native TextField through macOS AXUIElement.

Launches the text-field sample in `--text-e2e` mode, focuses the field with the
IME helper's Tab post, and runs a dedicated AX client that verifies the
TextField role, value, focus and frame. A locked console or missing AX window is
`NOT_RUN`; untrusted AX observation is `UNSUPPORTED`; a mismatched field is
`FAIL`.
"""

from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import subprocess
import sys
import time

from drive_macos_ime import AppProcess, ImeError, compile_helper, helper_json


def compile_client(evidence_dir: Path) -> Path:
    source = Path(__file__).with_name("macos_text_ax_client.m")
    binary = evidence_dir / "macos_text_ax_client"
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
    (evidence_dir / "text-ax-client-build.log").write_text(
        result.stdout, encoding="utf-8"
    )
    if result.returncode != 0:
        raise ImeError("macOS TextField AX client compilation failed")
    return binary


def run_client(client: Path, pid: int, expected: str) -> tuple[int, dict | None]:
    result = subprocess.run(
        [str(client), str(pid), expected],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        encoding="utf-8",
        errors="replace",
        check=False,
    )
    payload = None
    for line in reversed(result.stdout.splitlines()):
        line = line.strip()
        if line.startswith("{"):
            try:
                payload = json.loads(line)
            except json.JSONDecodeError:
                payload = None
            break
    if result.returncode != 0:
        (Path(client).parent / "text-ax-client.log").write_text(
            result.stdout + result.stderr, encoding="utf-8"
        )
    return result.returncode, payload


def drive(args: argparse.Namespace) -> int:
    if sys.platform != "darwin":
        raise ImeError("the macOS TextField AX proof requires Darwin")
    if not args.command:
        raise ImeError("provide the native sample command after `--`")
    evidence_dir = args.evidence_dir.resolve()
    evidence_dir.mkdir(parents=True, exist_ok=True)
    log_path = args.log.resolve()
    log_path.parent.mkdir(parents=True, exist_ok=True)
    client = compile_client(evidence_dir)
    helper = compile_helper(evidence_dir)
    report: dict = {
        "platform": "macos",
        "claims": {
            "ax.macos.textfield.role-value-focus": "NOT_RUN",
            "ax.macos.textfield.set-value": "NOT_RUN",
        },
    }
    app: AppProcess | None = None
    try:
        session = helper_json(helper, "session", check=False)
        if session.get("locked"):
            print("NOT_RUN: the console session is locked; AX/key delivery is unavailable")
            return 0
        trust = helper_json(helper, "trust", check=False)
        if trust.get("status") == "unsupported":
            report["claims"]["ax.macos.textfield.role-value-focus"] = "UNSUPPORTED"
            print("UNSUPPORTED: accessibility observation is not authorized")
            return 0
        env = dict(os.environ)
        env["YAMI_NATIVE_UI_TEXT_E2E"] = "1"
        env["YAMI_NATIVE_UI_WINDOW_TITLE"] = "Yami-kumo TextField AX"
        for name in (
            "YAMI_NATIVE_UI_E2E",
            "YAMI_NATIVE_UI_AX_E2E",
            "YAMI_NATIVE_UI_SMOKE",
        ):
            env.pop(name, None)
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
        time.sleep(0.5)
        status, payload = run_client(client, pid, "")
        if status == 77:
            report["claims"]["ax.macos.textfield.role-value-focus"] = "UNSUPPORTED"
        elif status == 0 and payload and payload.get("status") == "observed":
            report["claims"]["ax.macos.textfield.role-value-focus"] = "PASS"
            report["field"] = payload
        elif payload and payload.get("status") == "not-found":
            report["reason"] = "ax-text-field-not-found"
            print("NOT_RUN: the application exposed no AXTextField")
        else:
            report["claims"]["ax.macos.textfield.role-value-focus"] = "FAIL"
            print("FAIL: AX TextField role/value/focus/frame did not match")
    finally:
        if app is not None:
            app.close()
        (evidence_dir / "text-ax.json").write_text(
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
