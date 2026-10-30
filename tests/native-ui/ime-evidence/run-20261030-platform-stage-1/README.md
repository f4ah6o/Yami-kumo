# Exploratory retained platform-stage observation — no release ACK

This run adds read-only platform-kind tracing to Yami #95's candidate stage
accounting and the GPUI #193 physical evidence. It is a **new** app and run;
no stage is inferred for any older app. It reports:

| Native sequence | Kind | Control observation |
| --- | --- | --- |
| 1, 3 | resize | locally handled; geometry not implied |
| 2 | focus gained | locally handled; geometry not implied |
| 4 | pointer moved | ACK only; owner application not implied |
| 5, 8, 9 | frame completed | locally handled; geometry not implied |
| 6 | Entered | target recorded, ACKed; scene/stop not implied |
| 7, 10 | empty / `ｎ` preedit | applied without model action; geometry not implied |
| 11 | raw `n` release | unhandled and **not ACKed**; stage unavailable |

The seq 11 native read-only evidence was physical key 49, window/focus
generations 1, claim-before-window true, no physical press observed since
focus, native epoch 1, seat 14 and proxy 1. These are host-local facts, not
proof that earlier application owners or input paths are resolved. In
particular, seq 4 lacks consumer completion evidence. No release policy or
owner-prefix proof follows from this result. #95's stage accounting is itself
an experimental source candidate and must be independently reviewed.

Control reports suspended with the original owner, host and seq 11 retained.
IBus sent Japanese `commit_string(..., "日本")`, but there is no app-side
commit callback, host admission or model application. The fixture sent SIGTERM
(exit -15), not host.stop or safe cleanup. Resize/close race, full live IME,
clean registry, candidate-table acceptance, physical keyboard, AX and macOS
remain NOT_RUN. The diagnostic does not establish the P1 fix.

- Framework: gpui #193 `f67cb002731b62ae47bdb5368ebf83a3c395a2cf`.
- Yami root/consumer/app source `0a614b49bcdd53c291b50bbb60759a02d151be46`;
  #95 source stack `222132d205459e5e4c071f5cb82433f5541838e7`.
- App binary SHA-256 `fa2c83a7e64e38838f8b080dff4dc86a924de40f03bfd1d77ff7ccae775b9977`.
- Harness is `session.sh` and `drive.py` in this directory, introduced by the
  enclosing evidence commit, separate from app source. No run URL.
- GPUI local source override, no dependency lock; `native/moon.mod` SHA-256
  `b595be30e056da48775543ef1aa430d7e2ec93cbd9974d95c93d255628994b62`.
- Debian 13 x86_64, Linux 6.18.57; Moon `0.1.20261012 (748b63c)`, GCC
  `14.2.0-19`; rootless sysroot and nested Xvfb/Weston x11, IBus/Mozc,
  software renderer, XTest events.
- Build: `GPUI_SOURCE=/workspace/gpui-window-incarnation` and
  `moon build <examples/ubuntu> --target native --deny-warn --target-dir
  /workspace/yami-platform-observe-build` via `scripts/native_ui_workspace.sh`
  with the local Moon and Pango/Wayland sysroot.
- Run: `dbus-run-session -- xvfb-run --auto-servernum
  --server-args='-screen 0 960x640x24 -nolisten tcp -ac +extension GLX +render'
  /workspace/evidence/yami-platform-live-1/session.sh`, with locked profile
  and local sysroot PATH/libraries, `XKB_CONFIG_ROOT`, `LIBGL_DRIVERS_PATH`,
  and `WESTON_MODULE_MAP` mapping x11-backend.so and gl-renderer.so to the
  locked profile. The scripts preserve local paths.

SHA-256:

```
9e3cb79037d3c986fecf2b823c31768a330d8037f94bde0bf4abe5d13fb0c063  session.sh
d64a6792d4c246fcbf99681aab78ebb4aa4c6736d1d4823c6df3fb96cecdd2f1  drive.py
e1b4cb8d2143a555cb82fff3c73a9479d250ca483473e0011df35d16c6e2bf78  app.log
53cd299da75411a0ae237ba025a194e14a202cf3632701fd052664aa0b069999  ibus-ui-wayland.log
e9eba8c21f2b400af035d0c3c6f01b1ad0e0cbfdbba8905453000b2b353ea6b9  result.json
8ac81e0b57871e717fea6915711b88a14dd83ff79b38b843b6992db706955570  session.log
```
