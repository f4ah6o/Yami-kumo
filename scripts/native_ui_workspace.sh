#!/bin/sh
set -eu

if command -v python3 >/dev/null 2>&1; then
  python_bin=python3
elif command -v python >/dev/null 2>&1; then
  python_bin=python
else
  echo "Python 3.11 or newer is required to manage moon.work" >&2
  exit 2
fi

if [ "$#" -lt 1 ]; then
  echo "usage: $0 <command> [args...]" >&2
  exit 2
fi

normalize_path() {
  "$python_bin" - "$1" <<'PY'
import pathlib
import sys

print(pathlib.Path(sys.argv[1]).resolve().as_posix())
PY
}

shell_path() {
  if command -v cygpath >/dev/null 2>&1; then
    cygpath -u "$1"
  else
    printf '%s\n' "$1"
  fi
}

yami_root_native=$(normalize_path "$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd -P)")
gpui_root_native=$(normalize_path "${GPUI_SOURCE:-"$yami_root_native/../gpui.mbt"}")
yami_root=$(shell_path "$yami_root_native")
gpui_root=$(shell_path "$gpui_root_native")
if [ ! -f "$gpui_root/moon.mod" ]; then
  echo "GPUI source module not found: $gpui_root_native (set GPUI_SOURCE)" >&2
  exit 2
fi
if [ ! -f "$yami_root/moon.mod" ] || [ ! -f "$yami_root/native/moon.mod" ]; then
  echo "Yami root and native module manifests are required under $yami_root" >&2
  exit 2
fi

created_workspace=0
created_manifest=0
created_manifest_sha=
created_script=0
created_script_sha=
if [ -n "${YAMI_NATIVE_WORKSPACE_ROOT:-}" ]; then
  workspace_root_native=$(normalize_path "$YAMI_NATIVE_WORKSPACE_ROOT")
  workspace_root=$(shell_path "$workspace_root_native")
  if [ -e "$workspace_root" ] && [ ! -d "$workspace_root" ]; then
    echo "native UI workspace path is not a directory: $workspace_root_native" >&2
    exit 2
  fi
  if [ ! -d "$workspace_root" ]; then
    mkdir -p "$workspace_root"
    created_workspace=1
  fi
else
  workspace_root_native=$("$python_bin" - <<'PY'
import os
import tempfile

parent = os.environ.get("RUNNER_TEMP") or os.environ.get("TMPDIR") or None
print(tempfile.mkdtemp(prefix="yami-native-ui-", dir=parent))
PY
)
  workspace_root=$(shell_path "$workspace_root_native")
  created_workspace=1
fi

# The workspace is deliberately temporary and can live outside both source
# trees. Moon workspaces support absolute module members, which avoids placing
# moon.work in a parent directory shared by unrelated checkouts.
"$python_bin" - "$workspace_root_native" "$gpui_root_native" "$yami_root_native" <<'PY'
import os
import sys

workspace = os.path.realpath(sys.argv[1])
if workspace == os.path.sep:
    raise SystemExit("refusing to place moon.work at the filesystem root")
for root in map(os.path.realpath, sys.argv[2:]):
    if os.path.commonpath([workspace, root]) == root:
        raise SystemExit(
            f"refusing to place a temporary workspace inside source module {root}"
        )
PY

manifest="$workspace_root/moon.work"
script_dir="$workspace_root/script"
tree_sha() {
  "$python_bin" - "$1" <<'PY'
import hashlib
import os
import pathlib
import stat
import sys

root = pathlib.Path(sys.argv[1])
digest = hashlib.sha256()
for current, directories, files in os.walk(root):
    directories.sort()
    files.sort()
    for name in [*directories, *files]:
        path = pathlib.Path(current) / name
        relative = path.relative_to(root).as_posix().encode("utf-8")
        digest.update(relative + b"\0")
        if path.is_symlink():
            digest.update(b"L" + os.readlink(path).encode("utf-8") + b"\0")
        elif path.is_file():
            digest.update(b"F" + path.read_bytes())
        elif path.is_dir():
            digest.update(b"D")
        digest.update(stat.S_IMODE(path.lstat().st_mode).to_bytes(2, "big"))
print(digest.hexdigest())
PY
}
cleanup() {
  if [ "$created_manifest" -eq 1 ] && [ -f "$manifest" ] && [ -n "$created_manifest_sha" ]; then
    current_sha=$("$python_bin" - "$manifest" <<'PY'
import hashlib
import pathlib
import sys

print(hashlib.sha256(pathlib.Path(sys.argv[1]).read_bytes()).hexdigest())
PY
)
    if [ "$current_sha" = "$created_manifest_sha" ]; then
      rm -f "$manifest"
    else
      echo "kept changed workspace manifest: $manifest" >&2
    fi
  fi
  if [ "$created_script" -eq 1 ] && [ -d "$script_dir" ] && [ -n "$created_script_sha" ]; then
    current_sha=$(tree_sha "$script_dir")
    if [ "$current_sha" = "$created_script_sha" ]; then
      rm -rf "$script_dir"
    else
      echo "kept changed workspace helper scripts: $script_dir" >&2
    fi
  fi
  if [ "$created_workspace" -eq 1 ]; then
    rmdir "$workspace_root" 2>/dev/null || true
  fi
}
trap cleanup EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

if [ -e "$manifest" ]; then
  "$python_bin" - "$manifest" "$gpui_root_native" "$yami_root_native" "$yami_root_native/native" <<'PY'
import pathlib
import sys
import tomllib

manifest = pathlib.Path(sys.argv[1])
try:
    members = tomllib.loads(manifest.read_text(encoding="utf-8")).get("members", [])
except (OSError, tomllib.TOMLDecodeError) as error:
    raise SystemExit(f"cannot read existing workspace manifest {manifest}: {error}")
resolved = set()
for member in members:
    path = pathlib.Path(member)
    if not path.is_absolute():
        path = manifest.parent / path
    resolved.add(path.resolve())
required = {pathlib.Path(path).resolve() for path in sys.argv[2:]}
missing = sorted(str(path) for path in required - resolved)
if missing:
    raise SystemExit(
        "existing moon.work does not include all native UI members: " + ", ".join(missing)
    )
PY
else
  if [ -n "$(find "$workspace_root" -mindepth 1 -maxdepth 1 -print -quit)" ]; then
    echo "native UI workspace directory must be empty or already contain a compatible moon.work: $workspace_root" >&2
    exit 2
  fi
  (
    cd "$workspace_root"
    moon work init "$gpui_root_native" "$yami_root_native" "$yami_root_native/native"
  )
  created_manifest=1
  created_manifest_sha=$("$python_bin" - "$manifest" <<'PY'
import hashlib
import pathlib
import sys

print(hashlib.sha256(pathlib.Path(sys.argv[1]).read_bytes()).hexdigest())
PY
)
fi

gpui_script_dir="$gpui_root/script"
if [ ! -d "$gpui_script_dir" ]; then
  echo "GPUI native compiler helper directory not found: $gpui_script_dir" >&2
  exit 2
fi
gpui_script_sha=$(tree_sha "$gpui_script_dir")
if [ -e "$script_dir" ] || [ -L "$script_dir" ]; then
  existing_script_sha=$(tree_sha "$script_dir")
  if [ "$existing_script_sha" != "$gpui_script_sha" ]; then
    echo "existing workspace script directory does not match pinned GPUI helpers: $script_dir" >&2
    exit 2
  fi
else
  "$python_bin" - "$gpui_script_dir" "$script_dir" <<'PY'
import shutil
import sys

shutil.copytree(sys.argv[1], sys.argv[2])
PY
  created_script=1
  created_script_sha=$(tree_sha "$script_dir")
fi

export YAMI_NATIVE_WORKSPACE_ROOT="$workspace_root_native"
export YAMI_NATIVE_YAMI_ROOT="$yami_root_native"
export YAMI_NATIVE_GPUI_ROOT="$gpui_root_native"
export YAMI_NATIVE_MODULE_ROOT="$yami_root_native/native"
export GPUI_SOURCE="$gpui_root_native"

cd "$workspace_root"
"$@"
