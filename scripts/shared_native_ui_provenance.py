#!/usr/bin/env python3
"""Retain source identity for portable/build-only shared-native profiles."""
from __future__ import annotations
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys


def main() -> None:
    root = Path(__file__).resolve().parents[1]
    spec = importlib.util.spec_from_file_location("shared_native_driver", root / "tests/shared-ui/native_driver.py")
    assert spec is not None and spec.loader is not None
    driver = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = driver
    spec.loader.exec_module(driver)
    binding = driver.bind_sources(root, Path(os.environ["GPUI_SOURCE"]).resolve(),
                                  os.environ["YAMI_SHARED_UI_CANDIDATE_SHA"])
    binding["moonVersion"] = subprocess.run(["moon", "version", "--all"], check=True,
        capture_output=True, text=True).stdout
    binding["scope"] = "source identity; portable/build logs are separate; no host runtime inferred"
    directory = Path(os.environ["YAMI_NATIVE_UI_EVIDENCE_DIR"])
    directory.mkdir(parents=True, exist_ok=True)
    (directory / "portable-source.json").write_text(json.dumps(binding, indent=2, sort_keys=True) + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()
