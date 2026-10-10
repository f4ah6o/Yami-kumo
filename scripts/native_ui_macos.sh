#!/bin/sh
set -eu

mode=${1:---ui-proof}
if [ "$#" -gt 1 ]; then
  echo "usage: $0 [--ui-proof|--build-and-test]" >&2
  exit 2
fi
case "$mode" in
  --ui-proof|--build-and-test) ;;
  *)
    echo "usage: $0 [--ui-proof|--build-and-test]" >&2
    exit 2
    ;;
esac

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

# Use a supplied GPUI_TESTING library to avoid rebuilding a shared checkout;
# otherwise build the opt-in hooks before the Yami sample.
if [ -n "${GPUI_MACOS_LIBRARY:-}" ]; then
  if [ ! -f "$GPUI_MACOS_LIBRARY" ]; then
    echo "GPUI_MACOS_LIBRARY does not name a built test-hook library: $GPUI_MACOS_LIBRARY" >&2
    exit 2
  fi
  gpui_library=$GPUI_MACOS_LIBRARY
  echo "Using prebuilt GPUI native library: $gpui_library"
else
  set +e
  bash "$gpui_root/script/build_and_run.sh" --test-hooks > "$evidence_dir/gpui-test-hooks-build.log" 2>&1
  build_status=$?
  set -e
  if [ "$build_status" -ne 0 ]; then
    tail -n 160 "$evidence_dir/gpui-test-hooks-build.log" >&2 || true
    exit "$build_status"
  fi
  gpui_library="$gpui_root/_build/macos/GpuiNative.app/Contents/Frameworks/libgpui_macos.dylib"
fi

export GPUI_SOURCE="$gpui_root"
export GPUI_MACOS_LIBRARY="$gpui_library"
export YAMI_NATIVE_UI_EVIDENCE_DIR="$evidence_dir"

sh "$yami_root/scripts/native_ui_workspace.sh" \
  sh -c 'moon test "$GPUI_SOURCE/platform/macos_text" --target native --deny-warn --no-parallelize' \
  > "$evidence_dir/core-text-tests.log" 2>&1 || {
    tail -n 160 "$evidence_dir/core-text-tests.log" >&2 || true
    exit 1
  }

sh "$yami_root/scripts/native_ui_workspace.sh" \
  sh "$yami_root/scripts/native_ui_tests.sh"

if [ "$mode" = "--build-and-test" ]; then
  sh "$yami_root/scripts/native_ui_workspace.sh" \
    moon build "$yami_root/native/examples/macos" --target native --deny-warn
  echo "macOS native build and portable tests passed; runtime UI proof was not run."
  exit 0
fi

sh "$yami_root/scripts/native_ui_workspace.sh" \
  python3 "$yami_root/tests/native-ui/drive_native_ui.py" \
    --platform macos \
    --evidence-dir "$evidence_dir" \
    --log "$evidence_dir/native-ui.log" \
    -- moon run "$yami_root/native/examples/macos" --target native
