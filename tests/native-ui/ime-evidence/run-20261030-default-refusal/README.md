# Default Settings entry refuses ordered input: local reproduction

The opt-in retained-control run and this default entry are separate paths. On
this local nested Wayland profile, `ubuntu.exe --settings-e2e` exited with
signal 6 and printed `ordered_text: native_failure: ordered input requires a
retained owner`. The one-shot ordered runner is coded to reject before creating
a Settings window or fetching an ordered record; this protects against that
specific owner loss but leaves normal Settings operation unavailable.

The separate GitHub Actions run
[41144405351, ubuntu-wayland job 124365984720](https://github.com/f4ah6o/Yami-kumo/actions/runs/41144405351/job/124365984720)
reported `Settings sample exited early (exit=-6)` at Yami `4d659a5`. Its job
log does not include the child error text, and downloading that run's artifact
returned HTTP 403. The matching exit is consistent with this local reproduction,
but the CI child's actual error is **unconfirmed**. This local run does not
show a successful retained operation, a live Japanese composition or a clean
public dependency consumer.

- Framework: gpui `5cd2f231c6cbf529396cae633f6e5a0d6c9bea41`.
- Yami consumer and executed app source:
  `c8ce64da8b566e0672d1ae92851da811b8e151ae`.
- Executed binary SHA-256:
  `a1be81ae9c28bea57b71cf1fbe4026e4c1194f9fafa2654aa1d9f7e5e94f12e4`.
- Harness source: `session.sh` and `drive.py` here, added by the enclosing
  evidence commit; it is not the executed application source revision.
- Dependencies: local source override workspace; `native/moon.mod` SHA-256
  `b595be30e056da48775543ef1aa430d7e2ec93cbd9974d95c93d255628994b62`.
  Registry-only resolution remains NOT_RUN.
- Environment: Debian 13 x86_64, Moon `0.1.20261012 (748b63c)`, GCC
  `14.2.0-19`, rootless Wayland sysroot; Xvfb, Weston x11 and IBus/Mozc.
- Build: `GPUI_SOURCE=/workspace/gpui-retained-route sh
  scripts/native_ui_workspace.sh sh -c 'moon build
  "$YAMI_NATIVE_MODULE_ROOT/examples/ubuntu" --target native --deny-warn
  --target-dir /workspace/yami-entry-retained-build'` with rootless sysroot
  compiler and pkg-config paths. Run: `dbus-run-session -- xvfb-run
  --auto-servernum --server-args='-screen 0 960x640x24 -nolisten tcp -ac
  +extension GLX +render' /workspace/evidence/yami-default-refusal-c8/session.sh`
  with locked profile libraries and Weston module map. The harness records
  the exact local paths used. Run URL: none for this local reproduction.

SHA-256:

```
b95ad5ac0ec7fc1172dde63d4443449445fa57cf16e6364dab593685ed766b94  session.sh
8add9ba95bd288459ca9664e8428cf1f2a9608f81b166355c9c341bf181cfc63  drive.py
17e22a09d0b3f43df872729845f2af873a8e249a17d53dafaafe08e76401fb88  app.log
f54f056369706b5bbd5f9733861a2a829ccf9eb80bc0261e8ea7b8792c8f93ef  result.json
3ae732b0cc4ef23da36448bea789ead76f81870f0402f7335ff0f60a8b852ac5  session.log
```
