# Retained Entered callback: local exploratory run

This run establishes only that an actual Wayland text-input-v1 `enter` callback
from nested Weston and IBus/Mozc reached gpui's public retained ordered route,
was peeked, associated with the original Yami owner and ACKed. The raw app log
shows the callback followed by `entered_peek` and `entered_ack` with native
sequence 6, then an empty preedit observation. It does not establish Japanese
composition, commit, resize or close recovery, terminal cleanup or safe stop.
The fixture sent SIGTERM to the still-running process; this is not host.stop,
owner recovery, an accepted exit, or a full live IME pass.

- Framework source: `5cd2f231c6cbf529396cae633f6e5a0d6c9bea41` (gpui #186 candidate).
- Yami root / consumer / built app source: `b72056b28c5f7c3400acf5afce2c9b411cc0cfaf`.
- Harness source: `session.sh` and `drive.py` in this directory, introduced by
  the enclosing evidence commit; harness content SHA-256 values below. The
  harness is not the app source and is not a published conformance revision.
- Binary SHA-256: `4815ca2bfe264c7237d0f7e5aa4b21ead1c831ac786b581bbdb18248bfb8f346`.
- Dependency resolution: temporary Moon workspace members for Yami root,
  Yami native and local GPUI source; `native/moon.mod` SHA-256
  `b595be30e056da48775543ef1aa430d7e2ec93cbd9974d95c93d255628994b62`.
  No registry-only lock was used; clean published dependencies are NOT_RUN.
- Profile: Debian 13 x86_64, Xvfb + Weston x11 backend + IBus/Mozc, software
  renderer. Moon `0.1.20261012 (748b63c)`, GCC `14.2.0-19`. The application
  and Wayland libraries were built against the local rootless sysroot.
- Build command: `GPUI_SOURCE=/workspace/gpui-retained-route sh
  scripts/native_ui_workspace.sh sh -c 'moon build
  "$YAMI_NATIVE_MODULE_ROOT/examples/ubuntu" --target native --deny-warn
  --target-dir /workspace/yami-entry-retained-build'` with the rootless sysroot
  `PATH`, `PKG_CONFIG_SYSROOT_DIR`, `PKG_CONFIG_LIBDIR` and `LD_LIBRARY_PATH`
  from `/workspace/linux-user-apt/root`.
- Execution: `dbus-run-session -- xvfb-run --auto-servernum
  --server-args='-screen 0 960x640x24 -nolisten tcp -ac +extension GLX +render'
  /workspace/evidence/yami-retained-callback-724/session.sh`, with the locked
  profile's binaries and libraries, `WESTON_MODULE_MAP`, and
  `YAMI_TEST_SOURCE_SHA=b72056b28c5f7c3400acf5afce2c9b411cc0cfaf`. The scripts
  record the exact local paths used and require those paths when repeated.
- Run URL: none (local exploratory execution). Automated candidate-table,
  physical keyboard, assistive technology and production acceptance: NOT_RUN.

SHA-256:

```
542e52d12ca11e1ec763455be8b388b344107ca089e81f830696a2ec6c70c018  session.sh
87e7259f24cbd146b92c3ff86a8895e459deaa49ef9ae1dfff84ef0602a44d80  drive.py
995742fa434428dc279f3b80646e5b4e250cec32561c8b8dd38216ad7361d756  app.log
bf0b1fed327b131ccf88e57166473717cb582f4d9dff89ed597d1a8c1e714746  ibus-ui-wayland.log
4cc33bcdd596359ee478baf4da59d8db5b3fa341709a41c5414779e7c6cc7bf6  result.json
75cafe23888006109208b1a3e9a8b50c998bb9558a2f67c69f198e90ce70ffa5  session.log
```
