"""Digest raw artifacts only after compositor and IME logs have stopped."""
from __future__ import annotations

import hashlib
import json
import sys
from pathlib import Path

out = Path(sys.argv[1])
result_path = out / "result.json"
excluded = {"result.json", "artifact-manifest.json"}
items = []
for path in sorted(out.rglob("*")):
    if path.is_file() and path.name not in excluded:
        items.append({
            "path": str(path.relative_to(out)),
            "sha256": hashlib.sha256(path.read_bytes()).hexdigest(),
        })
manifest = json.dumps({"files": items}, ensure_ascii=False, indent=2).encode() + b"\n"
(out / "artifact-manifest.json").write_bytes(manifest)
result = json.loads(result_path.read_text())
result["artifact_digest"] = "sha256:" + hashlib.sha256(manifest).hexdigest()
result["artifact_digest_scope"] = "artifact-manifest.json lists raw files; excludes result and manifest"
result_path.write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n")
