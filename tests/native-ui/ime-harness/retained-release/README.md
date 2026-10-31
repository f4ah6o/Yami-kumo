# Exploratory retained-release harness

This harness is for an exact separately reviewed app build. It checks the app,
framework and harness checkouts are clean; requires app source
`585ff82109df0fa006f3031258476257d0b9cc86`, GPUI source
`53e42a5888167fd9203b27f6558deabaf5c54e4b`, and a caller-supplied binary
SHA-256; then records all three source revisions separately. An empty output
directory is mandatory. It drives synthetic X11 keys into a nested Weston and
live IBus/Mozc and sends only sequence-bound, bounded control requests. The
Ubuntu application's own native policy must reject unproven releases.

Example, after independently reviewing the exact app and GPUI source pair:

```sh
mkdir /workspace/evidence/yami-release-live-new
export YAMI_RELEASE_OUT=/workspace/evidence/yami-release-live-new
export YAMI_RELEASE_APP_TREE=/workspace/yami-transport-key-union
export YAMI_RELEASE_FRAMEWORK_TREE=/workspace/gpui-post-cutoff
export YAMI_RELEASE_BINARY=/workspace/yami-117-exact-build/_build/native/debug/build/f4ah6o/yami_kumo_native/examples/ubuntu/ubuntu.exe
export YAMI_RELEASE_BINARY_SHA256=8355c8c861faa784fe3c0a94ae663caad04c41a5d7fb2b35354f4c29f0f5b7f6
env PATH="/workspace/gpui-locked-profile/prefix/usr/bin:/workspace/linux-user-apt/root/usr/bin:/workspace/yami-tools/bin:$PATH" \
  LD_LIBRARY_PATH="/workspace/gpui-locked-profile/prefix/usr/lib/x86_64-linux-gnu/weston:/workspace/gpui-locked-profile/prefix/usr/lib/x86_64-linux-gnu:/workspace/linux-user-apt/root/usr/lib/x86_64-linux-gnu" \
  XKB_CONFIG_ROOT=/workspace/gpui-locked-profile/prefix/usr/share/X11/xkb \
  LIBGL_DRIVERS_PATH=/workspace/gpui-locked-profile/prefix/usr/lib/x86_64-linux-gnu/dri \
  WESTON_MODULE_MAP='x11-backend.so=/workspace/gpui-locked-profile/prefix/usr/lib/x86_64-linux-gnu/libweston-14/x11-backend.so;gl-renderer.so=/workspace/gpui-locked-profile/prefix/usr/lib/x86_64-linux-gnu/libweston-14/gl-renderer.so' \
  dbus-run-session -- xvfb-run --auto-servernum \
    --server-args='-screen 0 960x640x24 -nolisten tcp -ac +extension GLX +render' \
    /workspace/yami-117-live-harness/tests/native-ui/ime-harness/retained-release/session.sh
```

Any output is exploratory. An observed native release ACK or commit log is not
by itself model/geometry/cutoff proof, nor the full Shared Settings acceptance.
The script currently force-terminates an unresolved process after collecting
status, and records cleanup FAIL because in-memory ownership is lost; it does
not call that a safe host stop. A later result cannot be attributed to the app
head without the separately recorded app and binary hashes. No physical-keyboard,
accessibility, candidate-table oracle, clean registry, or macOS result is implied.

This pin prepares the #117 source pair only. Run only after exact-head review and required CI; it is an exploratory first Japanese commit, not the dialog, resize/blur/close race, candidate oracle, or safe cleanup acceptance. The local build log is `/workspace/evidence/yami-117-exact-build.log` (SHA-256 `e21fb73cc051452d5bdc2f8cae75946ccb387a622158e76af9c1bd1c2a288a8c`).
