#!/bin/sh
set -eu
runtime=$(mktemp -d)
chmod 700 "$runtime"
compositor_pid=
cleanup() {
  if [ -n "$compositor_pid" ]; then kill "$compositor_pid" 2>/dev/null || true; wait "$compositor_pid" 2>/dev/null || true; fi
  rm -rf "$runtime"
}
trap cleanup EXIT
export XDG_RUNTIME_DIR="$runtime" XDG_SESSION_TYPE=wayland WAYLAND_DISPLAY=yami-field-dialog LIBGL_ALWAYS_SOFTWARE=1 GALLIUM_DRIVER=llvmpipe
export FONTCONFIG_FILE=/workspace/yami-linux-accept/tests/native-ui/fonts.conf FONTCONFIG_PATH=/workspace/yami-linux-accept/tests/native-ui
export XDG_CACHE_HOME=/workspace/evidence/yami-linux-field-dialog/font-cache
mkdir -p "$XDG_CACHE_HOME"
weston --backend=x11-backend.so --renderer=gl --shell=kiosk-shell.so --width=800 --height=600 --scale=1 --socket="$WAYLAND_DISPLAY" --no-config --idle-time=0 --log=/workspace/evidence/yami-linux-field-dialog/weston.log &
compositor_pid=$!
python3 /workspace/gpui-yami-accept/scripts/wait_wayland_ready.py --pid "$compositor_pid" --socket "$runtime/$WAYLAND_DISPLAY" --timeout-seconds 45
exec_driver=0
python3 /workspace/yami-linux-accept/tests/native-ui/drive_settings.py --platform linux --evidence-dir /workspace/evidence/yami-linux-field-dialog --log /workspace/evidence/yami-linux-field-dialog/settings-linux.log -- /workspace/evidence/yami-linux-e4bb9ac-attempt2/app.exe --settings-e2e || exec_driver=$?
exit "$exec_driver"
