# Retained FIFO head: local exploratory run

A local Xvfb → Weston → IBus/Mozc run exercised the opt-in Yami Settings
entry with real Wayland callbacks. It identified a retained native FIFO head
that stops the runner. This is **not** a full live IME or resize/close race
acceptance, and it does not prove what happened to an unobserved commit.

The app received and ACKed the empty preedit at native sequence 7 and the
`ｎ` preedit at sequence 10. The sequence-10 receipt reports session applied;
that report does not imply model or geometry publication. Its geometry update
returned success. The next receipt was peeked at native sequence 11 and
classified `unhandled`; it was not ACKed. The process entered suspended
control mode with the owner and host retained. `status`, `receipt`,
`generation` and `stage` responses are preserved in `result.json`: pending
native sequence 11, no continuation generation, no ACKed stage for 11, and
session-applied stage for 10. This occurred before the 64-receipt limit; no
`dispatch_retained` Busy result was observed. The exact native subtype of 11
is not established by this run.

IBus subsequently sent `preedit_string(..., "日本", ...)` and
`commit_string(..., "日本")`; the app log does not show those callbacks or a
model update. Sending at the IBus side is not host admission or application.
The fixture finally sent SIGTERM to the still-running process. This is not
host.stop, recovery, successful termination or evidence that a pending owner
survives process exit.

- Framework source `5cd2f231c6cbf529396cae633f6e5a0d6c9bea41`; Yami root,
  consumer and built app source `e4b80e72440e90250c518e5edef4ea97b32b1f71`.
- Harness: `session.sh` and `drive.py` here, introduced by the enclosing
  evidence commit. This revision is distinct from the app source revision.
- App binary SHA-256 `b314bd1195fec595bf1b9d669c62c07620ff262318f446cb23f764e0a733ae9b`.
- Dependencies: local source workspace, not a registry-only resolution;
  `native/moon.mod` SHA-256
  `b595be30e056da48775543ef1aa430d7e2ec93cbd9974d95c93d255628994b62`.
- Debian 13 x86_64, Moon `0.1.20261012 (748b63c)`, GCC `14.2.0-19`, rootless
  Wayland sysroot; Xvfb, Weston x11, IBus/Mozc and software renderer.
- App build: source-override `moon build <examples/ubuntu> --target native
  --deny-warn` in the temporary workspace from `scripts/native_ui_workspace.sh`.
- Run: `dbus-run-session -- xvfb-run --auto-servernum
  --server-args='-screen 0 960x640x24 -nolisten tcp -ac +extension GLX +render'
  /workspace/evidence/yami-retained-fifo-2/session.sh` with the locked profile
  PATH, libraries and Weston module map shown in the parent session. Scripts
  retain the exact local paths used. Run URL: none (local exploratory run).
- Result: initial Entered peek/ACK PASS; seq 11 unsupported-head suspension
  reproduced; Japanese commit into the host/model, physical keyboard,
  candidate selection, resize/close race and registry consumer NOT_RUN.

SHA-256:

```
17f972f9f661f2059508b9de47f28e60c20974958249613ba4a5e56bd3ffd98c  session.sh
79c6912575eeef5c7827a7db8f90482f5469f8456e4029698ee178e04dd428f4  drive.py
a0aaaaf9de8a5e6f6168c46168c0bc9b431a7d79deda6f70bb6b78ecef4dbecb  app.log
7b78fe5ed08aa104729dc616c1a6f0b6df9a06a683659bb2d0afb0103e4bc7e6  ibus-ui-wayland.log
e85786c894368fd52687656dc4fd6bed9c956099bb7a1740f1e9400189759e95  result.json
6280023c1056224cc4267a9f6f4593146d25f8ee8c92f456e2d2daa5dc756771  session.log
```
