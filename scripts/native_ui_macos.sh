#!/bin/sh
set -eu

mode=${1:---ui-proof}
if [ "$#" -gt 1 ]; then
  echo "usage: $0 [--ui-proof|--ax-proof|--build-and-test|--shared-counter-build-and-test|--shared-counter-ui-proof|--shared-counter-ax-proof]" >&2
  exit 2
fi
case "$mode" in
  --ui-proof|--ax-proof|--build-and-test|--shared-counter-build-and-test|--shared-counter-ui-proof|--shared-counter-ax-proof) ;;
  *)
    echo "usage: $0 [--ui-proof|--ax-proof|--build-and-test|--shared-counter-build-and-test|--shared-counter-ui-proof|--shared-counter-ax-proof]" >&2
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

run_macos_python_driver() {
  driver=$1
  shift
  sh "$yami_root/scripts/native_ui_workspace.sh" \
    sh -c 'exec "$YAMI_PYTHON_BIN" "$@"' yami-python "$driver" "$@"
}

sh "$yami_root/scripts/native_ui_workspace.sh" \
  sh -c 'moon test "$GPUI_SOURCE/platform/macos_text" --target native --deny-warn --no-parallelize' \
  > "$evidence_dir/core-text-tests.log" 2>&1 || {
    tail -n 160 "$evidence_dir/core-text-tests.log" >&2 || true
    exit 1
  }

if [ "$mode" = "--shared-counter-build-and-test" ]; then
  sh "$yami_root/scripts/native_ui_workspace.sh" \
    sh "$yami_root/scripts/shared_native_ui_tests.sh"
  sh "$yami_root/scripts/native_ui_workspace.sh" \
    moon build "$yami_root/native/examples/shared_counter/macos" --target native --deny-warn
  printf '%s\n' '{"platform":"macos","build":"passed","runtime":"not-run","accessibility":"not-run"}' \
    > "$evidence_dir/shared-native-build.json"
  echo "Shared counter macOS build and portable tests passed; runtime UI and AX were not run."
  exit 0
fi

if [ "$mode" = "--shared-counter-ui-proof" ]; then
  : "${YAMI_SHARED_UI_CANDIDATE_SHA:?exact candidate SHA is required}"
  sh "$yami_root/scripts/native_ui_workspace.sh" \
    sh "$yami_root/scripts/shared_native_ui_tests.sh"
  run_macos_python_driver "$yami_root/tests/shared-ui/native_driver.py" \
    --platform macos \
    --scenario shared \
    --fixtures shell,shell-compact \
    --evidence-dir "$evidence_dir" \
    --log "$evidence_dir/native-ui.log" \
    --candidate-sha "$YAMI_SHARED_UI_CANDIDATE_SHA" \
    -- moon run "$yami_root/native/examples/shared_counter/macos" --target native
  exit 0
fi

if [ "$mode" = "--shared-counter-ax-proof" ]; then
  run_macos_python_driver "$yami_root/tests/native-ui/drive_macos_ax.py" \
    --evidence-dir "$evidence_dir" \
    --log "$evidence_dir/native-ax.log" \
    --button-name Increment \
    --fixture shell \
    -- moon run "$yami_root/native/examples/shared_counter/macos" --target native
  exit 0
fi

sh "$yami_root/scripts/native_ui_workspace.sh" \
  sh "$yami_root/scripts/native_ui_tests.sh"

if [ "$mode" = "--build-and-test" ]; then
  sh "$yami_root/scripts/native_ui_workspace.sh" \
    moon build "$yami_root/native/examples/macos" --target native --deny-warn
  if ! /usr/bin/clang -fobjc-arc -Wall -Wextra -Werror \
      "$yami_root/tests/native-ui/macos_ax_client.m" \
      -framework AppKit -framework ApplicationServices \
      -framework CoreFoundation -framework CoreGraphics \
      -o "$evidence_dir/macos_host_input" \
      > "$evidence_dir/macos-host-input-helper-build.log" 2>&1; then
    tail -n 120 "$evidence_dir/macos-host-input-helper-build.log" >&2 || true
    exit 1
  fi
  if ! "$evidence_dir/macos_host_input" --guard-fixtures \
      > "$evidence_dir/macos-host-input-guard-fixtures.log" 2>&1; then
    cat "$evidence_dir/macos-host-input-guard-fixtures.log" >&2 || true
    exit 1
  fi
  echo "macOS native build and portable tests passed; runtime UI proof was not run."
  exit 0
fi

if [ "$mode" = "--ax-proof" ]; then
  run_macos_python_driver "$yami_root/tests/native-ui/drive_macos_ax.py" \
      --evidence-dir "$evidence_dir" \
      --log "$evidence_dir/native-ax.log" \
      -- moon run "$yami_root/native/examples/macos" --target native
  exit 0
fi

run_macos_python_driver "$yami_root/tests/native-ui/drive_native_ui.py" \
    --platform macos \
    --evidence-dir "$evidence_dir" \
    --log "$evidence_dir/native-ui.log" \
    -- moon run "$yami_root/native/examples/macos" --target native
