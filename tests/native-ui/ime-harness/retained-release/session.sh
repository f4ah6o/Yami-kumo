#!/bin/bash
set -eu
out=${YAMI_RELEASE_OUT:?set YAMI_RELEASE_OUT to a fresh evidence directory}
harness_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
test -d "$out" || { echo 'evidence directory must already exist'; exit 1; }
test -z "$(find "$out" -mindepth 1 -maxdepth 1 -print -quit)" || { echo 'evidence directory must be empty'; exit 1; }
prefix=/workspace/gpui-locked-profile/prefix
runtime=
pids=()
phase=environment_preflight
cleanup() {
  status=$?
  trap - EXIT
  set +e
  python3 "$harness_dir/finish.py" "$out" "$status" "$phase" "${pids[@]}" || { echo 'evidence finalization failed' >&2; status=1; }
  if test -n "$runtime"; then rm -rf "$runtime"; fi
  exit "$status"
}
trap cleanup EXIT
runtime=$(mktemp -d /tmp/yami-retained-fixture-XXXXXX)
chmod 700 "$runtime"
mkdir -p "$runtime"/{config/mozc,cache,data,component,schemas}
phase=build
python3 "$harness_dir/build.py"
export YAMI_RELEASE_BINARY="$out/app.exe"
export YAMI_RELEASE_BINARY_SHA256=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["binary_sha256"])' "$out/build.json")
phase=environment
export XDG_CONFIG_HOME="$runtime/config" XDG_CACHE_HOME="$runtime/cache" XDG_DATA_HOME="$runtime/data" XDG_RUNTIME_DIR="$runtime"
export XDG_DATA_DIRS="$prefix/usr/share:/usr/share" GSETTINGS_SCHEMA_DIR="$runtime/schemas" GSETTINGS_BACKEND=memory IBUS_COMPONENT_PATH="$runtime/component" IBUS_ADDRESS_FILE="$runtime/ibus-address"
export MOZC_IBUS_CANDIDATE_WINDOW=ibus NO_AT_BRIDGE=1 GI_TYPELIB_PATH="$prefix/usr/lib/x86_64-linux-gnu/girepository-1.0" WESTON_DATA_DIR="$prefix/usr/share/weston"
cp "$prefix"/usr/share/glib-2.0/schemas/*ibus*.xml "$runtime/schemas/"
printf 'active_on_launch: true\nengines {\n name: "mozc-jp"\n longname: "Mozc"\n layout: "default"\n rank: 80\n symbol: "あ"\n composition_mode: HIRAGANA\n}\n' > "$runtime/config/mozc/ibus_config.textproto"
printf "[org.freedesktop.ibus.general]\npreload-engines=['mozc-jp']\nengines-order=['mozc-jp']\nuse-system-keyboard-layout=true\n" > "$runtime/schemas/99-yami.gschema.override"
glib-compile-schemas --strict "$runtime/schemas"
cp /workspace/mozc-client-build/artifacts/mozc.xml "$runtime/component/mozc.xml"
setsid "$prefix/usr/lib/mozc/mozc_server" > "$out/mozc-server.log" 2>&1 & pids+=("$!")
for i in $(seq 1 100); do test -f "$runtime/config/mozc/.session.ipc" && break; sleep .05; done
test -f "$runtime/config/mozc/.session.ipc" || { echo 'mozc server IPC not ready'; exit 1; }
setsid "$prefix/usr/bin/ibus-daemon" --cache=none --address="unix:path=$runtime/ibus-bus" --panel=disable --config="$prefix/usr/libexec/ibus-dconf" --emoji-extension=disable --timeout=3000 --verbose > "$out/ibus-daemon.log" 2>&1 & pids+=("$!")
for i in $(seq 1 100); do test -f "$runtime/ibus-address" && break; sleep .05; done
test -f "$runtime/ibus-address" || { echo 'IBus address not created'; exit 1; }
export IBUS_ADDRESS=$(sed -n 's/^IBUS_ADDRESS=//p' "$runtime/ibus-address")
"$prefix/usr/bin/ibus" engine mozc-jp > "$out/engine.log" 2>&1
"$prefix/usr/bin/ibus" engine >> "$out/engine.log" 2>&1
cat > "$runtime/ibus-wrapper.sh" <<WRAPPER
#!/bin/sh
set -eu
test -n "\${WAYLAND_SOCKET:-}"
unset GTK_IM_MODULE QT_IM_MODULE
export GDK_BACKEND=wayland WAYLAND_DEBUG=client G_DBUS_DEBUG=message IBUS_ENABLE_SYNC_MODE=1
exec "$prefix/usr/libexec/ibus-ui-gtk3" --enable-wayland-im > "$out/ibus-ui-dbus.log" 2> "$out/ibus-ui-wayland.log"
WRAPPER
chmod 700 "$runtime/ibus-wrapper.sh"
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
[input-method]
path=$runtime/ibus-wrapper.sh
CONFIG
export WAYLAND_DISPLAY=yami-retained-ime XDG_SESSION_TYPE=wayland LIBGL_ALWAYS_SOFTWARE=1 GALLIUM_DRIVER=llvmpipe
setsid weston --backend=x11 --renderer=pixman --shell="$prefix/usr/lib/x86_64-linux-gnu/weston/desktop-shell.so" --socket="$WAYLAND_DISPLAY" --width=960 --height=640 --idle-time=0 --config="$runtime/weston.ini" --log="$out/weston.log" > "$out/weston-stdio.log" 2>&1 & pids+=("$!")
python3 "$harness_dir/wait_wayland_ready.py" --pid "${pids[-1]}" --socket "$runtime/$WAYLAND_DISPLAY" --timeout-seconds 25
for i in $(seq 1 100); do if test -f "$out/ibus-ui-wayland.log" && rg -q 'bind\(.*zwp_input_method_v1' "$out/ibus-ui-wayland.log"; then break; fi; sleep .05; done
rg -q 'bind\(.*zwp_input_method_v1' "$out/ibus-ui-wayland.log" || { echo 'IBus did not bind input method'; exit 1; }
printf 'IBus Wayland input-method bound\n'
compositor_window=$(sed -n 's/.*x11 output .* window id \([0-9][0-9]*\).*/\1/p' "$out/weston.log" | head -n 1)
test -n "$compositor_window"
xdotool windowfocus --sync "$compositor_window"
printf 'X compositor focus set before application start: %s\n' "$compositor_window"
phase=drive
python3 "$harness_dir/drive.py"
