# Exploratory retained-release harness

This harness is for an exact separately reviewed app build. It checks the app,
framework and harness checkouts are clean; requires app source
`f6c4b40abbecd74b76a1fb459c360a104fd132dd`, GPUI source
`b28cff9a8a92a155e67421a397a1030dedac9301`, and a caller-supplied binary
SHA-256; then records all three source revisions separately. An empty output
directory is mandatory. It drives synthetic X11 keys into a nested Weston and
live IBus/Mozc and sends only sequence-bound, bounded control requests. The
Ubuntu application's own native policy must reject unproven releases.

Example, after independently reviewing the exact app and GPUI source pair:

```sh
mkdir /workspace/evidence/yami-release-live-new
export YAMI_RELEASE_OUT=/workspace/evidence/yami-release-live-new
export YAMI_RELEASE_APP_TREE=/workspace/yami-release-handoff
export YAMI_RELEASE_FRAMEWORK_TREE=/workspace/gpui-keymap-generation
export YAMI_RELEASE_BINARY=/workspace/yami-release-handoff-build-final/native/debug/build/f4ah6o/yami_kumo_native/examples/ubuntu/ubuntu.exe
export YAMI_RELEASE_BINARY_SHA256=b1b1b02ea557ba8535e5d7e70919682530895a0d5c973aef58424dfa6b197a0f
env PATH="/workspace/gpui-locked-profile/prefix/usr/bin:/workspace/linux-user-apt/root/usr/bin:/workspace/yami-tools/bin:$PATH" \
  LD_LIBRARY_PATH="/workspace/gpui-locked-profile/prefix/usr/lib/x86_64-linux-gnu/weston:/workspace/gpui-locked-profile/prefix/usr/lib/x86_64-linux-gnu:/workspace/linux-user-apt/root/usr/lib/x86_64-linux-gnu" \
  XKB_CONFIG_ROOT=/workspace/gpui-locked-profile/prefix/usr/share/X11/xkb \
  LIBGL_DRIVERS_PATH=/workspace/gpui-locked-profile/prefix/usr/lib/x86_64-linux-gnu/dri \
  WESTON_MODULE_MAP='x11-backend.so=/workspace/gpui-locked-profile/prefix/usr/lib/x86_64-linux-gnu/libweston-14/x11-backend.so;gl-renderer.so=/workspace/gpui-locked-profile/prefix/usr/lib/x86_64-linux-gnu/libweston-14/gl-renderer.so' \
  dbus-run-session -- xvfb-run --auto-servernum \
    --server-args='-screen 0 960x640x24 -nolisten tcp -ac +extension GLX +render' \
    /workspace/yami-release-harness/tests/native-ui/ime-harness/retained-release/session.sh
```

Any output is exploratory. An observed native release ACK or commit log is not
by itself model/geometry/cutoff proof, nor the full Shared Settings acceptance.
The script currently force-terminates an unresolved process after collecting
status, and records cleanup FAIL because in-memory ownership is lost; it does
not call that a safe host stop. A later result cannot be attributed to the app
head without the separately recorded app and binary hashes. No physical-keyboard,
accessibility, candidate-table oracle, clean registry, or macOS result is implied.
