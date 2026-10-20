#!/bin/sh
set -eu

# Run both macOS TextField proofs while holding a user-activity assertion, then
# copy their JSON evidence to a stable directory outside _build logs.
root=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd -P)
out=${1:-"$root/_build/native-ui/macos/proofs-$(date +%Y%m%d-%H%M%S)"}
mkdir -p "$out"

if [ "$(uname -s)" != Darwin ]; then
  echo "The macOS TextField proofs require macOS." >&2
  exit 2
fi
if [ "$(/usr/bin/env sh -c 'command -v caffeinate' && echo yes)" = yes ]; then
  caffeinate -u -t 1800 &
  keep_awake=$!
  trap 'kill "$keep_awake" 2>/dev/null || true' EXIT INT TERM
fi

sh "$root/scripts/native_ui_macos.sh" --text-ime-proof | tee "$out/ime.stdout"
cp "$root/_build/native-ui/macos/ime.json" "$out/ime.json"
sh "$root/scripts/native_ui_macos.sh" --text-ax-proof | tee "$out/ax.stdout"
cp "$root/_build/native-ui/macos/text-ax.json" "$out/text-ax.json"

python3 - "$out" <<'PY'
import json
import pathlib
import sys

out = pathlib.Path(sys.argv[1])
ime = json.loads((out / "ime.json").read_text())
ax = json.loads((out / "text-ax.json").read_text())
claims = {**ime["claims"], **ax["claims"]}
for name in (
    "ime.live-engine.preedit",
    "ime.live-engine.commit",
    "ax.macos.textfield.role-value-focus",
):
    if claims.get(name) != "PASS":
        print(f"FAIL: {name} is {claims.get(name)}")
        sys.exit(1)
print(json.dumps(claims, ensure_ascii=False, sort_keys=True))
print(f"evidence: {out}")
PY
