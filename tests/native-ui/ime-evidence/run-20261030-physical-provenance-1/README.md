# Live physical release provenance observation — not acceptance

This local source-override diagnostic observes the previously blocking release
on a newly built application using the experimental public GPUI receipt API.
It does not ACK the release. On the original route, seq 6 Entered and seq 7
empty preedit were ACKed; seq 10 `ｎ` preedit was ACKed and the control socket
reported TextSession applied, with model and geometry not implied. Seq 11 is
`Unhandled(ForwardedReleased)` for keysym 110 and its read-only native physical
evidence reports key 49, focus generation 1, host-window generation 1,
claim-before-window true, prior `NoPressObservedSinceFocus`, native epoch 1,
seat 14 and proxy 1. Control reported suspended, original owner and host
retained, and pending receipt seq 11. Its stage was unavailable because it was
not ACKed. The result neither resolves all prior consumer event/action/model
stages nor proves the absence of other input owners; it does not authorize ACK.

IBus sent subsequent Japanese preedit and `commit_string(..., "日本")`, but
there is no app-side commit callback, host admission, or model application in
this run. The fixture sent SIGTERM to the still-running app (exit -15), not
`host.stop`; safe cleanup, resume, resize/close race and the complete Shared
Settings flow remain NOT_RUN. No candidate-table, physical keyboard, AX,
macOS or public-registry acceptance is established.

- Framework source: gpui #193 `f67cb002731b62ae47bdb5368ebf83a3c395a2cf`.
- Yami root/consumer/app source: `e8d9541bbaeda3e36254f8238f33d2ab29975b9d`.
- App binary SHA-256: `2bab9e628ddf74847360c4349445c297ac14becd73e524da73af9368211dbed7`.
- Harness source: `session.sh` and `drive.py` in this directory, introduced
  in the enclosing evidence commit, separate from app source. Run URL: none.
- Dependency: local GPUI source override; no dependency lock file. Candidate
  source pin in this branch is not a published registry package. `native/moon.mod`
  SHA-256 `b595be30e056da48775543ef1aa430d7e2ec93cbd9974d95c93d255628994b62`.
- Debian 13 x86_64, Linux 6.18.57; Moon `0.1.20261012 (748b63c)`; GCC
  `14.2.0-19`; local rootless sysroot and nested Xvfb/Weston x11,
  IBus/Mozc, software rendering; injected XTest events, no physical keyboard.
- Build: `GPUI_SOURCE=/workspace/gpui-window-incarnation` and
  `moon build <examples/ubuntu> --target native --deny-warn --target-dir
  /workspace/yami-physical-build` through `scripts/native_ui_workspace.sh`,
  with Moon and Pango/Wayland libraries in the local rootless sysroot.
- Run: `dbus-run-session -- xvfb-run --auto-servernum
  --server-args='-screen 0 960x640x24 -nolisten tcp -ac +extension GLX +render'
  /workspace/evidence/yami-physical-live-3/session.sh`, with PATH containing the
  locked profile and local sysroot, LD_LIBRARY_PATH containing its Weston and
  native library dirs, `XKB_CONFIG_ROOT`, `LIBGL_DRIVERS_PATH`, and
  `WESTON_MODULE_MAP` mapping x11-backend.so and gl-renderer.so to the locked
  profile. The scripts preserve the local paths used.

SHA-256:

```
c40aed588fe9409deb0caaeb9f4c3694597672bb6ca0323bae4bba72ab9667dc  session.sh
0c7dc43985701730777775ced6cb9257d1102a26a5a87051261a96c27a9f0d5b  drive.py
17576fef1d862e5fd43e9cfd36f931fe721d246c24572543dfe16ab6fa4db7a8  app.log
19703228b8c139d32d2c5d1fafcf977f6a0fc917479fbf2a66c2424092cd2b7d  ibus-ui-wayland.log
48dcf0e52f8214ea378df7c50226b395df21f63e2c93b0948083ff333d7b8ad2  result.json
8acea9272929c299481e3020de7951a7d0a56a4fce71f68a8958737b7df46f94  session.log
```

The preceding preparation attempts in local directories `yami-physical-live-1`
and `-2` failed before the compositor started due to missing Weston library
and module search paths respectively. They are not IME execution results.
