#!/usr/bin/env python3
"""Exercise the Yami sample Button through macOS's native AXPress action."""

from __future__ import annotations

import argparse
import importlib.util
import json
import os
import plistlib
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import uuid

from drive_native_ui import E2EError, ProcessOutput, _build_native_sample


def drive(args: argparse.Namespace) -> int:
    if sys.platform != "darwin":
        raise E2EError("the macOS AX proof requires Darwin")
    if not args.command:
        raise E2EError("provide the native sample command after `--`")

    evidence_dir = args.evidence_dir.resolve()
    evidence_dir.mkdir(parents=True, exist_ok=True)
    log_path = args.log.resolve()
    log_path.parent.mkdir(parents=True, exist_ok=True)
    client_path = evidence_dir / "macos_ax_client"
    compile_result = subprocess.run(
        [
            "/usr/bin/clang",
            "-fobjc-arc",
            "-Wall",
            "-Wextra",
            str(Path(__file__).with_name("macos_ax_client.m")),
            "-framework",
            "AppKit",
            "-framework",
            "ApplicationServices",
            "-framework",
            "CoreFoundation",
            "-o",
            str(client_path),
        ],
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        encoding="utf-8",
        errors="replace",
        check=False,
    )
    (evidence_dir / "macos-ax-client-build.log").write_text(
        compile_result.stdout, encoding="utf-8"
    )
    if compile_result.returncode != 0:
        raise E2EError(
            "macOS AX client compilation failed; see "
            f"{evidence_dir / 'macos-ax-client-build.log'}"
        )

    env = os.environ.copy()
    run_title = f"{args.window_title} [native-ax-{uuid.uuid4().hex}]"
    env.update(
        {
            "YAMI_NATIVE_UI_AX_E2E": "1",
            "YAMI_NATIVE_UI_WINDOW_TITLE": run_title,
        }
    )
    if args.fixture:
        env["YAMI_SHARED_UI_FIXTURE"] = args.fixture
    workspace_root = env.get("YAMI_NATIVE_WORKSPACE_ROOT")
    if not workspace_root:
        raise E2EError("YAMI_NATIVE_WORKSPACE_ROOT must be set by native_ui_workspace.sh")
    workspace_path = Path(workspace_root).resolve()
    module_root = Path(
        env.get("YAMI_NATIVE_MODULE_ROOT", workspace_path / "native")
    ).resolve()
    runtime_target: tempfile.TemporaryDirectory[str] | None = None
    process: subprocess.Popen[str] | None = None
    output: ProcessOutput | None = None
    try:
        shared_driver_path = Path(__file__).resolve().parents[1] / "shared-ui" / "native_driver.py"
        shared_spec = importlib.util.spec_from_file_location(
            "_yami_shared_ax_build_driver", shared_driver_path
        )
        if shared_spec is None or shared_spec.loader is None:
            raise E2EError("cannot load the shared native build plan")
        shared_driver = importlib.util.module_from_spec(shared_spec)
        sys.modules[shared_spec.name] = shared_driver
        shared_spec.loader.exec_module(shared_driver)
        runtime_target = tempfile.TemporaryDirectory(
            prefix="yami-native-ax-build-", dir=workspace_path
        )
        executable = shared_driver.build_sample(
            args.command,
            "macos",
            workspace_path,
            module_root,
            Path(runtime_target.name),
            evidence_dir,
            env,
            600,
        )
        run_command = [str(executable)]
        bundle_id = f"org.f4ah6o.yami-kumo.native-ax.{uuid.uuid4().hex}"
        app_bundle = Path(runtime_target.name) / "YamiNativeAX.app"
        app_contents = app_bundle / "Contents"
        app_executables = app_contents / "MacOS"
        app_executables.mkdir(parents=True)
        app_executable = app_executables / "YamiNativeAX"
        shutil.copy2(run_command[0], app_executable)
        with (app_contents / "Info.plist").open("wb") as plist_file:
            plistlib.dump(
                {
                    "CFBundleExecutable": "YamiNativeAX",
                    "CFBundleIdentifier": bundle_id,
                    "CFBundleName": "YamiNativeAX",
                    "CFBundlePackageType": "APPL",
                    "LSMinimumSystemVersion": "13.0",
                    "NSPrincipalClass": "NSApplication",
                },
                plist_file,
            )
        print(f"Launching registered native sample: {app_executable}", flush=True)
        process = subprocess.Popen(
            [str(app_executable), *run_command[1:]],
            cwd=workspace_path,
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
        ready = output.wait_marker(
            "YAMI_NATIVE_UI_AX_READY", timeout=args.startup_timeout
        )
        if ready.get("title") != run_title:
            raise E2EError("sample READY title does not match the uniquely launched window")

        client = subprocess.run(
            [
                str(client_path),
                str(process.pid),
                run_title,
                args.button_name,
                bundle_id,
                str(app_bundle),
            ],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            encoding="utf-8",
            errors="replace",
            timeout=args.client_timeout,
            check=False,
        )
        if client.returncode != 0:
            if client.returncode == 77:
                raise E2EError(
                    "macOS Accessibility permission is not granted to the AX client: "
                    + client.stderr.strip()
                )
            raise E2EError(
                "macOS AX client failed: "
                + (client.stderr.strip() or client.stdout.strip() or str(client.returncode))
            )
        try:
            client_report = json.loads(client.stdout)
        except json.JSONDecodeError as error:
            raise E2EError(f"macOS AX client returned invalid JSON: {error}") from error
        if (
            client_report.get("pid") != process.pid
            or client_report.get("requestedWindowTitle") != run_title
            or not isinstance(client_report.get("observedWindowTitle"), str)
            or not client_report.get("observedWindowTitle")
            or type(client_report.get("windowTitleMatched")) is not bool
            or client_report.get("bundleID") != bundle_id
            or client_report.get("bundlePath") != str(app_bundle)
            or client_report.get("initialCount") != 0
            or client_report.get("finalCount") != 1
            or client_report.get("action") != "AXPress"
            or client_report.get("closeRequested") is not True
        ):
            raise E2EError(f"macOS AX client report does not prove the expected action: {client_report}")

        complete = output.wait_marker(
            "YAMI_NATIVE_UI_AX_COMPLETE", timeout=args.marker_timeout
        )
        if (
            complete.get("count") != 1
            or complete.get("value") != 1
            or complete.get("destroyed") is not True
        ):
            raise E2EError(f"sample did not finish with the App Entity count at 1: {complete}")
        return_code = process.wait(timeout=10)
        if return_code != 0:
            raise E2EError(f"native sample exited with status {return_code}")

        report = {
            "platform": "macos",
            "inputDelivery": "AXUIElementPerformAction(kAXPressAction) against the uniquely launched sample process",
            "windowTitle": run_title,
            "bundleID": bundle_id,
            "bundlePath": str(app_bundle),
            "ready": ready,
            "client": client_report,
            "complete": complete,
            "sampleLog": str(log_path),
        }
        report_path = evidence_dir / "macos-ax-report.json"
        report_path.write_text(
            json.dumps(report, indent=2, sort_keys=True) + "\n", encoding="utf-8"
        )
        print(f"macOS AX proof passed; report: {report_path}", flush=True)
        print(json.dumps(report, indent=2, sort_keys=True), flush=True)
        return 0
    except (E2EError, OSError, subprocess.SubprocessError, KeyError, ValueError) as error:
        print(f"macOS AX proof failed: {error}", file=sys.stderr, flush=True)
        if process is not None and process.poll() is None:
            process.terminate()
            try:
                process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait(timeout=5)
        if output is not None:
            output.drain()
            output.log.flush()
        if log_path.is_file():
            lines = log_path.read_text(encoding="utf-8", errors="replace").splitlines()
            print(f"Native sample log: {log_path}", file=sys.stderr, flush=True)
            for line in lines[-80:]:
                print(line, file=sys.stderr)
        raise
    finally:
        if output is not None:
            output.close()
        if runtime_target is not None:
            runtime_target.cleanup()


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--evidence-dir", type=Path, required=True)
    parser.add_argument("--log", type=Path, required=True)
    parser.add_argument("--window-title", default="Yami-kumo Native UI")
    parser.add_argument("--button-name", default="Click me")
    parser.add_argument("--fixture", default=None)
    parser.add_argument("--startup-timeout", type=float, default=240.0)
    parser.add_argument("--client-timeout", type=float, default=45.0)
    parser.add_argument("--marker-timeout", type=float, default=45.0)
    parser.add_argument("command", nargs=argparse.REMAINDER, help="native sample command after --")
    args = parser.parse_args()
    if args.command[:1] == ["--"]:
        args.command = args.command[1:]
    try:
        return drive(args)
    except E2EError:
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
