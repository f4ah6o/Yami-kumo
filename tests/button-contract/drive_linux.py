#!/usr/bin/env python3
"""Replay shared Button fixtures in the owned Xvfb/Weston session."""
from __future__ import annotations

import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import uuid

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tests/native-ui"))
from drive_native_ui import ProcessOutput, _build_native_sample, _stop_owned_sample, _region_pixels, read_ppm


def inject(*arguments: str) -> None:
    subprocess.run(["xdotool", *arguments], check=True, timeout=5)


def source_hashes() -> dict[str, str]:
    paths = subprocess.check_output(["git", "ls-files", "-z", "--cached", "--others", "--exclude-standard"], cwd=ROOT).decode().split("\0")
    return {name: hashlib.sha256((ROOT / name).read_bytes()).hexdigest() for name in sorted(filter(None, paths))}


def key_command(phase: str) -> list[str]:
    if phase not in ("enter-down", "enter-up", "space-down", "space-up"):
        raise ValueError(f"Host driver cannot qualify keyboard phase {phase}")
    key, action = phase.split("-")
    return ["keydown" if action == "down" else "keyup", "Return" if key == "enter" else "space"]


def main() -> None:
    if os.environ.get("YAMI_NATIVE_UI_ISOLATED") != "1" or os.environ.get("WAYLAND_DISPLAY") != "yami-native-ui":
        raise RuntimeError("Button host fixtures require the script-owned isolated Xvfb/Weston session")
    out = Path(os.environ["YAMI_NATIVE_UI_EVIDENCE_DIR"]) / "button-contract-host"
    out.mkdir()
    fixture = ROOT / "tests/button-contract/fixtures.json"
    suite = json.loads(fixture.read_text())
    report = {"status": "running", "source_revision": subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip(), "fixture_sha256": hashlib.sha256(fixture.read_bytes()).hexdigest(), "platform": "linux", "input": "xdotool -> isolated X11 Weston -> Wayland -> GPUI", "physical_hardware": "not-run", "accessibility": "not-run", "cases": []}
    save = lambda: (out / "report.json").write_text(json.dumps(report, indent=2) + "\n")
    save()
    env = dict(os.environ, GPUI_NATIVE_E2E="1", YAMI_NATIVE_UI_BUTTON_CONTRACT="1", YAMI_NATIVE_UI_E2E="0")
    report["source_hashes"] = source_hashes()
    report["source_dirty"] = bool(subprocess.check_output(["git", "status", "--porcelain"], cwd=ROOT))
    report["gpui_revision"] = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=env["GPUI_SOURCE"], text=True).strip()
    workspace = Path(env["YAMI_NATIVE_WORKSPACE_ROOT"])
    command, target = _build_native_sample(["moon", "run", str(ROOT / "native/examples/ubuntu"), "--target", "native"], "linux", workspace, ROOT / "native", out, env)
    report["native_executable_sha256"] = hashlib.sha256(Path(command[0]).read_bytes()).hexdigest()
    try:
        for case in suite["cases"]:
            if not case.get("host"):
                report["cases"].append({"id": case["id"], "status": "not-run", "reason": "This host driver does not yet qualify repeat, focus transfer, unmatched release or loading"})
                continue
            directory = out / case["id"]
            directory.mkdir()
            case_env = dict(env, YAMI_NATIVE_UI_EVIDENCE_DIR=str(directory), YAMI_NATIVE_UI_DISABLED="1" if case["disabled"] else "0", YAMI_NATIVE_UI_WINDOW_TITLE=f"Button contract {uuid.uuid4().hex}")
            # --sync waits forever when the previous case ended here already.
            # Per-operation delivery is acknowledged by host sequence markers.
            inject("mousemove", "790", "590")
            process = subprocess.Popen(command, cwd=workspace, env=case_env, stdin=subprocess.DEVNULL, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, bufsize=1)
            output = ProcessOutput(process, directory / "host.log")
            record = {"id": case["id"], "status": "running", "phases": []}
            report["cases"].append(record)
            save()
            try:
                current = output.wait_marker("YAMI_NATIVE_UI_CONTRACT", timeout=60)

                def collect(phase: str, index: int, frame: dict) -> None:
                    image = read_ppm(Path(frame["frame"]["path"]))
                    if (image.width, image.height) != (frame["frame"]["width"], frame["frame"]["height"]):
                        raise RuntimeError("GPU capture dimensions differ from the presented frame")
                    previous = record["phases"][-1]["activation_count"] if record["phases"] else 0
                    button = frame["button"]
                    pixels = _region_pixels(image, tuple(button[key] for key in ("x", "y", "width", "height")), frame["frame"]["scale"])
                    clicks = [payload for name, payload in output.events if name == "YAMI_NATIVE_UI_CLICK" and previous < payload["count"] <= frame["count"]]
                    if len(clicks) != frame["count"] - previous:
                        raise RuntimeError("Presented activation count has no matching host action marker")
                    record["phases"].append({"index": index, "phase": phase, "activation_count": frame["count"], "activation_delta": frame["count"] - previous, "activation_event": bool(clicks), "focused": frame["focused"], "pressed": frame["pressed"], "disabled": case["disabled"], "loading": False, "scene": frame["scene"], "gpu": frame["frame"], "gpu_sha256": hashlib.sha256(Path(frame["frame"]["path"]).read_bytes()).hexdigest(), "gpu_button_sha256": hashlib.sha256(bytes(channel for pixel in pixels for channel in pixel)).hexdigest(), "host_sequence": frame["sequence"]})

                def observed_action(phase: str, arguments: list[str]) -> dict:
                    after = max([payload["sequence"] for name, payload in output.events if name == "YAMI_NATIVE_UI_INPUT"] + [current["sequence"]])
                    inject(*arguments)
                    event = output.wait_marker("YAMI_NATIVE_UI_INPUT", lambda value: value["sequence"] > after and value["phase"] == phase and value["delivered"], timeout=10)
                    return output.wait_marker("YAMI_NATIVE_UI_CONTRACT", lambda value: value["sequence"] >= event["sequence"], timeout=10)

                collect("initial", 0, current)
                for index, phase in enumerate(case["steps"], 1):
                    bounds = current["button"]
                    x = round(bounds["x"] + bounds["width"] / 2)
                    y = round(bounds["y"] + bounds["height"] / 2)
                    if phase == "pointer-down":
                        current = observed_action("pointer-move", ["mousemove", "--sync", str(x), str(y)])
                        current = observed_action("pointer-down", ["mousedown", "1"])
                    elif phase in ("pointer-up", "pointer-up-outside"):
                        if phase.endswith("outside"):
                            current = observed_action("pointer-move", ["mousemove", "--sync", "790", "590"])
                        current = observed_action("pointer-up", ["mouseup", "1"])
                    elif phase == "repaint":
                        current = observed_action("pointer-move", ["mousemove", "--sync", str(x + 1), str(y)])
                    else:
                        current = observed_action(phase, key_command(phase))
                    collect(phase, index, current)
                    save()
                inject("key", "Escape")
                if process.wait(timeout=10) != 0:
                    raise RuntimeError("Native host exited unsuccessfully")
                record["status"] = "observed"
            except BaseException as error:
                record.update(status="failed", error=str(error))
                raise
            finally:
                if process.poll() is None:
                    _stop_owned_sample(process)
                output.drain()
                output.close()
                save()
        if source_hashes() != report["source_hashes"]:
            raise RuntimeError("Source changed during Native host observation")
        report["status"] = "partial"
    except BaseException as error:
        report.update(status="failed", error=str(error))
        raise
    finally:
        if target:
            target.cleanup()
        save()


if __name__ == "__main__":
    main()
