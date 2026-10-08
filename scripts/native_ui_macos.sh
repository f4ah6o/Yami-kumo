#!/bin/sh
set -eu

yami_root=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd -P)
gpui_root=${GPUI_SOURCE:-"$yami_root/../gpui.mbt"}
if [ "$(uname -s)" != Darwin ]; then
  echo "The native macOS UI proof requires macOS and Xcode command line tools." >&2
  exit 2
fi
if [ ! -f "$gpui_root/script/build_and_run.sh" ]; then
  echo "GPUI macOS test-hook build script not found under $gpui_root" >&2
  exit 2
fi

evidence_dir=${YAMI_NATIVE_UI_EVIDENCE_DIR:-"$yami_root/_build/native-ui/macos"}
mkdir -p "$evidence_dir"
evidence_dir=$(CDPATH='' cd -- "$evidence_dir" && pwd -P)

# This builds the native Mac library with GPUI_TESTING, so frame readback is
# backed by the same Metal host while the normal production APIs remain gated.
set +e
sh "$gpui_root/script/build_and_run.sh" --test-hooks > "$evidence_dir/gpui-test-hooks-build.log" 2>&1
build_status=$?
set -e
if [ "$build_status" -ne 0 ]; then
  tail -n 160 "$evidence_dir/gpui-test-hooks-build.log" >&2 || true
  exit "$build_status"
fi

export GPUI_SOURCE="$gpui_root"
export GPUI_MACOS_LIBRARY="$gpui_root/_build/macos/GpuiNative.app/Contents/Frameworks/libgpui_macos.dylib"
export YAMI_NATIVE_UI_EVIDENCE_DIR="$evidence_dir"

sh "$yami_root/scripts/native_ui_workspace.sh" \
  sh -c 'moon test "$GPUI_SOURCE/platform/macos_text" --target native --deny-warn --no-parallelize' \
  > "$evidence_dir/core-text-tests.log" 2>&1 || {
    tail -n 160 "$evidence_dir/core-text-tests.log" >&2 || true
    exit 1
  }

sh "$yami_root/scripts/native_ui_workspace.sh" \
  sh "$yami_root/scripts/native_ui_tests.sh"
sh "$yami_root/scripts/native_ui_workspace.sh" \
  python3 "$yami_root/tests/native-ui/drive_native_ui.py" \
    --platform macos \
    --evidence-dir "$evidence_dir" \
    --log "$evidence_dir/native-ui.log" \
    -- moon run "$yami_root/native/examples/macos" --target native
