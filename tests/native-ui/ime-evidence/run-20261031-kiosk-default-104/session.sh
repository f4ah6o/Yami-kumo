#!/bin/bash
set -eu
out=/workspace/evidence/yami-ci-kiosk-default-104
prefix=/workspace/gpui-locked-profile/prefix
runtime=$(mktemp -d /tmp/yami-noime-default-XXXXXX)
chmod 700 "$runtime"
weston_pid=
cleanup() {
  if [ -n "$weston_pid" ]; then kill "$weston_pid" 2>/dev/null || true; wait "$weston_pid" 2>/dev/null || true; fi
  rm -rf "$runtime"
}
trap cleanup EXIT
export XDG_RUNTIME_DIR="$runtime" WAYLAND_DISPLAY=yami-noime-default XDG_SESSION_TYPE=wayland
export LIBGL_ALWAYS_SOFTWARE=1 GALLIUM_DRIVER=llvmpipe WESTON_DATA_DIR="$prefix/usr/share/weston"
cat > "$runtime/weston.ini" <<CONFIG
[shell]
client=$prefix/usr/libexec/weston-desktop-shell
panel-position=none
locking=false
background-color=0xff202020
animation=none
startup-animation=none
close-animation=none
focus-animation=none
background-image=
CONFIG
weston --backend=x11 --renderer=gl --shell="$prefix/usr/lib/x86_64-linux-gnu/weston/kiosk-shell.so" --socket="$WAYLAND_DISPLAY" --width=960 --height=640 --idle-time=0 --no-config --log="$out/weston.log" > "$out/weston-stdio.log" 2>&1 &
weston_pid=$!
python3 /workspace/gpui-retained-route/scripts/wait_wayland_ready.py --pid "$weston_pid" --socket "$runtime/$WAYLAND_DISPLAY" --timeout-seconds 25
python3 "$out/drive.py"
