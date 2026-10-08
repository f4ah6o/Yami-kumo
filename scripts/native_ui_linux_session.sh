#!/bin/sh
set -eu

if [ "$#" -ne 3 ]; then
  echo "usage: $0 <yami-root> <gpui-root> <evidence-directory>" >&2
  exit 2
fi
yami_root=$1
gpui_root=$2
evidence_dir=$3
runtime=$(mktemp -d)
chmod 700 "$runtime"
compositor_pid=

cleanup() {
  if [ -n "$compositor_pid" ]; then
    kill "$compositor_pid" 2>/dev/null || true
    wait "$compositor_pid" 2>/dev/null || true
  fi
  rm -rf "$runtime"
}
trap cleanup EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

export XDG_RUNTIME_DIR="$runtime"
export XDG_SESSION_TYPE=wayland
export WAYLAND_DISPLAY=yami-native-ui
export LIBGL_ALWAYS_SOFTWARE=1
export GALLIUM_DRIVER=llvmpipe
export GPUI_SOURCE="$gpui_root"
export YAMI_NATIVE_UI_EVIDENCE_DIR="$evidence_dir"
export FONTCONFIG_FILE="$yami_root/tests/native-ui/fonts.conf"
fontconfig_path=$(dirname "$FONTCONFIG_FILE")
export FONTCONFIG_PATH="$fontconfig_path"
export XDG_CACHE_HOME="$evidence_dir/font-cache"
mkdir -p "$XDG_CACHE_HOME"

sans_match=$(fc-match -f '%{family}|%{file}' sans)
sans_serif_match=$(fc-match -f '%{family}|%{file}' sans-serif)
case "$sans_match" in
  "DejaVu Sans|"*) ;;
  *) echo "Fontconfig 'sans' did not resolve to DejaVu Sans: $sans_match" >&2; exit 1 ;;
esac
case "$sans_serif_match" in
  "DejaVu Sans|"*) ;;
  *) echo "Fontconfig 'sans-serif' did not resolve to DejaVu Sans: $sans_serif_match" >&2; exit 1 ;;
esac
if [ "${sans_match#*|}" != "${sans_serif_match#*|}" ]; then
  echo "Fontconfig generic sans aliases resolved to different font files" >&2
  exit 1
fi
{
  printf 'FONTCONFIG_FILE=%s\n' "$FONTCONFIG_FILE"
  printf 'sans: %s\n' "$sans_match"
  printf 'sans-serif: %s\n' "$sans_serif_match"
} > "$evidence_dir/font-profile.log"

weston \
  --backend=x11-backend.so \
  --renderer=gl \
  --shell=kiosk-shell.so \
  --width=800 \
  --height=600 \
  --scale=1 \
  --socket="$WAYLAND_DISPLAY" \
  --no-config \
  --idle-time=0 \
  --log="$evidence_dir/weston.log" &
compositor_pid=$!

if ! python3 "$gpui_root/scripts/wait_wayland_ready.py" \
  --pid "$compositor_pid" \
  --socket "$runtime/$WAYLAND_DISPLAY" \
  --timeout-seconds 45; then
  echo "Weston X11 compositor did not become protocol-ready" >&2
  tail -n 120 "$evidence_dir/weston.log" >&2 || true
  exit 1
fi

sh "$yami_root/scripts/native_ui_workspace.sh" \
  sh "$yami_root/scripts/native_ui_tests.sh"
sh "$yami_root/scripts/native_ui_workspace.sh" \
  python3 "$yami_root/tests/native-ui/drive_native_ui.py" \
    --platform linux \
    --evidence-dir "$evidence_dir" \
    --log "$evidence_dir/native-ui.log" \
    --linux-origin-x 0 \
    --linux-origin-y 0 \
    -- moon run "$yami_root/native/examples/ubuntu" --target native
