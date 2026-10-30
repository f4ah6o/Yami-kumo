# Unhandled IME release: local exploratory run

This repeats the preceding local Xvfb → Weston → IBus/Mozc FIFO experiment
with extra raw-event classification. In the actual opt-in Yami process, native
seq 7 (empty preedit) and seq 10 (`ｎ` preedit) were peeked and ACKed; control
reported seq 10 as session applied. After a successful host geometry update,
seq 11 was peeked as an `Unhandled` native `TextSession` event:
`ForwardedReleased`, keysym 110 (`n`), no mapped key, native epoch 1, seat 14,
proxy generation 1 and non-stale flag. It remained unacknowledged. Control
reported the owner suspended, receipt sequence 11 and no stage for 11.

This identifies the blocking record but does not prove whether a corresponding
press was previously delivered to the consumer; therefore it does not authorize
ACKing or discarding the record. IBus sent later Japanese preedit and a
`commit_string(..., "日本")`, but the app log does not show their callbacks or
host admission. The fixture sent SIGTERM to the still-running process. That is
not host.stop, safe recovery or successful shutdown. Actual P1 resize/commit/
destroy contention and the end-to-end live goal remain NOT_RUN.

- GPUI `5cd2f231c6cbf529396cae633f6e5a0d6c9bea41`; Yami root / consumer /
  app source `a6fdf4327dbaa33f0393acb4fef7b4cadeffc650`.
- App binary SHA-256 `264e6a3dcc225e9341358444fabeb4c8d44c9f703495c5e832b13b4a5603a339`.
- Harness is `session.sh` and `drive.py` in this directory, introduced by the
  enclosing evidence commit, distinct from the app source.
- Local source-override workspace (not registry-only); `native/moon.mod`
  SHA-256 `b595be30e056da48775543ef1aa430d7e2ec93cbd9974d95c93d255628994b62`.
- Debian 13 x86_64; Moon `0.1.20261012 (748b63c)`, GCC `14.2.0-19`;
  rootless Wayland sysroot, Weston x11 backend, IBus/Mozc, software renderer.
- Build: source-override `moon build <examples/ubuntu> --target native
  --deny-warn` through `scripts/native_ui_workspace.sh`, GPUI source at the
  framework SHA above.
- Run: `dbus-run-session -- xvfb-run --auto-servernum
  --server-args='-screen 0 960x640x24 -nolisten tcp -ac +extension GLX +render'
  /workspace/evidence/yami-retained-fifo-3/session.sh` with the locked local
  profile PATH, libraries and module map. The scripts preserve the local paths
  used. Run URL: none.

SHA-256:

```
006cc1cda2cd1237a0cfcd405c9a1b6897a0111003876d08d769e20d146b12c1  session.sh
9edf969f1ca21ff55f4721a4c60542fa051eb20e34ce6294b76821dbcc176f45  drive.py
672f137c4739b9e6fd8ead5dd7504cb4182525214a9dbe49ecc7ec066e143c36  app.log
5533214e9794eeab579a93832f3ebcf470e2bd40b92075d1c06784f30b412eaa  ibus-ui-wayland.log
f9320102cfa0188a4fc8bdaef8349716ab5497d67d46ab60fb6743da5671bd7a  result.json
1425f3658de064935dd06a14173d548a29355dde34dce0b6fff530ca2425a265  session.log
```
