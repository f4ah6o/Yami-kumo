#!/bin/bash
set -eu
out=/workspace/evidence/yami-linux-ime-attempt19
prefix=/workspace/gpui-locked-profile/prefix
runtime=$(mktemp -d /tmp/yami-ime-XXXXXX)
chmod 700 "$runtime"
mkdir -p "$runtime"/{home,config/mozc,cache,data,component,schemas}
pids=()
cleanup() { for pid in "${pids[@]}"; do kill "$pid" 2>/dev/null || true; done; for pid in "${pids[@]}"; do wait "$pid" 2>/dev/null || true; done; rm -rf "$runtime"; }
trap cleanup EXIT
export HOME="$runtime/home" XDG_CONFIG_HOME="$runtime/config" XDG_CACHE_HOME="$runtime/cache" XDG_DATA_HOME="$runtime/data" XDG_RUNTIME_DIR="$runtime"
export XDG_DATA_DIRS="$prefix/usr/share:/usr/share" GSETTINGS_SCHEMA_DIR="$runtime/schemas" GSETTINGS_BACKEND=memory IBUS_COMPONENT_PATH="$runtime/component" IBUS_ADDRESS_FILE="$runtime/ibus-address"
export MOZC_IBUS_CANDIDATE_WINDOW=ibus NO_AT_BRIDGE=1 GI_TYPELIB_PATH="$prefix/usr/lib/x86_64-linux-gnu/girepository-1.0" WESTON_DATA_DIR="$prefix/usr/share/weston"
cp "$prefix"/usr/share/glib-2.0/schemas/*ibus*.xml "$runtime/schemas/"
printf 'active_on_launch: true\nengines {\n name: "mozc-jp"\n longname: "Mozc"\n layout: "default"\n rank: 80\n symbol: "あ"\n composition_mode: HIRAGANA\n}\n' > "$runtime/config/mozc/ibus_config.textproto"
printf "[org.freedesktop.ibus.general]\npreload-engines=['mozc-jp']\nengines-order=['mozc-jp']\nuse-system-keyboard-layout=true\n" > "$runtime/schemas/99-yami.gschema.override"
glib-compile-schemas --strict "$runtime/schemas"
cp /workspace/mozc-client-build/artifacts/mozc.xml "$runtime/component/mozc.xml"
"$prefix/usr/lib/mozc/mozc_server" > "$out/mozc-server.log" 2>&1 & pids+=("$!")
for i in $(seq 1 100); do test -f "$runtime/config/mozc/.session.ipc" && break; sleep .05; done
find "$runtime/config/mozc" -maxdepth 2 -ls > "$out/mozc-ipc.log"
kill -0 "${pids[0]}" || { echo 'mozc server exited'; exit 1; }
test -f "$runtime/config/mozc/.session.ipc" || { echo 'mozc server IPC not ready'; exit 1; }
"$prefix/usr/bin/ibus-daemon" --cache=none --address="unix:path=$runtime/ibus-bus" --panel=disable --config="$prefix/usr/libexec/ibus-dconf" --emoji-extension=disable --timeout=3000 --verbose > "$out/ibus-daemon.log" 2>&1 & pids+=("$!")
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
export WAYLAND_DISPLAY=yami-ime XDG_SESSION_TYPE=wayland LIBGL_ALWAYS_SOFTWARE=1 GALLIUM_DRIVER=llvmpipe
weston --backend=x11 --renderer=pixman --shell="$prefix/usr/lib/x86_64-linux-gnu/weston/desktop-shell.so" --socket="$WAYLAND_DISPLAY" --width=960 --height=640 --idle-time=0 --config="$runtime/weston.ini" --log="$out/weston.log" > "$out/weston-stdio.log" 2>&1 & pids+=("$!")
python3 /workspace/gpui-yami-accept/scripts/wait_wayland_ready.py --pid "${pids[-1]}" --socket "$runtime/$WAYLAND_DISPLAY" --timeout-seconds 30
for i in $(seq 1 100); do if test -f "$out/ibus-ui-wayland.log" && grep -q 'bind(.*zwp_input_method_v1' "$out/ibus-ui-wayland.log"; then break; fi; sleep .05; done
if ! grep -q 'bind(.*zwp_input_method_v1' "$out/ibus-ui-wayland.log" 2>/dev/null; then echo 'IBus did not bind input method'; exit 1; fi
printf 'IBus Wayland input-method bound\n'

python3 /workspace/yami-linux-accept/tests/native-ui/ime-evidence/drive_live.py
