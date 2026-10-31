# Same-run native provenance and local prefix diagnostic

A new nested Xvfb/Weston/IBus/Mozc run uses the #98 local prefix diagnostic and
#194 native keymap uncertainty fix in one binary. On the retained owner:

- Seq 1 and 3 resize, seq 2 focus gain, and seq 5/8/9 frame completion reported
  locally handled; these stages do not prove scene or geometry publication.
- Seq 4 pointer move passed the local dispatch witness with no pending action.
  Seq 6 recorded Entered; seq 7 empty preedit and seq 10 `ｎ` preedit were
  applied with no model action. The `prefix` control query reported the
  locally recorded prefix resolved. Its result is a restricted diagnostic,
  **not** proof of other owners/input paths or permission to ACK.
- Seq 11 was `Unhandled(ForwardedReleased)` for keysym 110, physical key 49.
  The native receipt reported focus/window generations 1, claim-before-window,
  no physical press observed since focus, native epoch 1, seat 14 and proxy 1.
  It remained **unACKed** with original host and owner retained.

These two observations coexist in this run; they do not by themselves establish
absence of other input owners, completion of scene/caret/host geometry, or a
positive release policy. The independent #194 review also observed inherited
`NO_KEYMAP` behavior retaining a non-null old XKB pointer and potentially
emitting its old keysym with `direct_keymap_valid=0`; the tested press was
`PressAdmitted`, not a false absence. Real compositor impact is unverified.

IBus sent later Japanese `commit_string(..., "日本")`, but app-side commit
callback/admission/model application were not observed. The fixture sent
SIGTERM (exit -15), not host.stop or safe cleanup. The full live IME operation,
resize/close race, clean registry consumer, candidate-table automatic oracle,
physical keyboard, AX and macOS remain NOT_RUN. This is not a P1 fix.

- Framework `6105180bb705cd3f3cc73fb8f64d7442c115c31a` (gpui #194).
- Yami root/consumer/app source `3fc8e8d7f945657403599961992313e7b75b186f`,
  based on #98 `96ef4af6e00c303338224e6d4c11f751f6f02f17`.
- App binary SHA-256 `55576c8ee12faa2b3ce35155cb729dba71f82aae5c7df09484b621f29332b944`.
- Harness source: `session.sh`, `drive.py`, `wait_wayland_ready.py` in this
  directory, introduced by the enclosing evidence commit; distinct from app
  source. The helper is copied from framework 5cd2f231c6cbf529396cae633f6e5a0d6c9bea41;
  its byte SHA-256 is recorded below. No run URL.
- Source override, no dependency lock; `native/moon.mod` SHA-256
  `b595be30e056da48775543ef1aa430d7e2ec93cbd9974d95c93d255628994b62`.
  The source pin is not a published registry package.
- Debian 13 x86_64, Linux 6.18.57; Moon `0.1.20261012 (748b63c)`, GCC
  `14.2.0-19`; rootless sysroot, Weston x11, Xvfb, IBus/Mozc, llvmpipe, XTest.
- Build: local `GPUI_SOURCE=/workspace/gpui-keymap-proof`, via
  `scripts/native_ui_workspace.sh` and
  `moon build <examples/ubuntu> --target native --deny-warn --target-dir
  /workspace/yami-prefix-physical-build`, with the local Moon and Pango/Wayland
  sysroot. Both source trees were clean and at the revisions above.
- Run with the local locked libraries/profile and module mapping:

  ```sh
  env PATH="/workspace/gpui-locked-profile/prefix/usr/bin:/workspace/linux-user-apt/root/usr/bin:$PATH" \
    LD_LIBRARY_PATH="/workspace/gpui-locked-profile/prefix/usr/lib/x86_64-linux-gnu/weston:/workspace/gpui-locked-profile/prefix/usr/lib/x86_64-linux-gnu:/workspace/linux-user-apt/root/usr/lib/x86_64-linux-gnu" \
    XKB_CONFIG_ROOT=/workspace/gpui-locked-profile/prefix/usr/share/X11/xkb \
    LIBGL_DRIVERS_PATH=/workspace/gpui-locked-profile/prefix/usr/lib/x86_64-linux-gnu/dri \
    WESTON_MODULE_MAP='x11-backend.so=/workspace/gpui-locked-profile/prefix/usr/lib/x86_64-linux-gnu/libweston-14/x11-backend.so;gl-renderer.so=/workspace/gpui-locked-profile/prefix/usr/lib/x86_64-linux-gnu/libweston-14/gl-renderer.so' \
    dbus-run-session -- xvfb-run --auto-servernum \
      --server-args='-screen 0 960x640x24 -nolisten tcp -ac +extension GLX +render' \
      /workspace/evidence/yami-prefix-physical-live-1/session.sh
  ```

SHA-256:

```
8e7bc384a481c8e302f98287ac18c0e3e5148c10a03d2b45649b4d2cd0028b24  session.sh
8a0b2bd941cdbd1881241438bd8f86dadcf1194c868fcec30bb80dbd5cb94614  drive.py
cc2753dbf13becc32e79e116839c9feec12e56b6424860d52409d1121ef01f5d  wait_wayland_ready.py
00d6c7ffade7a99e17aef7aa363c375cc5e3b145dff6fe09d238ff751dcc0542  app.log
cb7c649d8ee088d0cd450cef173ca47fdc57f057489773a4908062e2d22b763e  ibus-ui-wayland.log
64c56c802b6e6e2756f87c6a48ceaaa556f3478a66a4820eefa39198c95d8c01  result.json
a73d7ec220216442ca5499e510480dd87434b76c3d3b3526239fce035fc81240  session.log
```
