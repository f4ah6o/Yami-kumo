# Local live IME run: final-output duplicate fence

This repeats the [integrated validation and Dialog run](../run-20261030-6/README.md)
with harness `e3b4250cd0c29b714cb55bbd63aacab95729216c`. The driver now joins
its stdout reader after terminating the app, drains all remaining markers, and
requires exactly one commit (`日本`) before it reports success. A subprocess
fixture rejects a duplicate buffered until the final drain.

- `framework_sha`: `a645aa3acfda4420c9558a12795187d71bb96003`.
- `consumer_sha` / `app_source_sha`: `7d9b920a7e435e0e9fcd3dfcc24013782ca1e16d`.
- `harness_sha`: `e3b4250cd0c29b714cb55bbd63aacab95729216c`; the separate
  Weston readiness helper remains from gpui `cfc66b872bfd9613e2a81b499cac0602c84d653b`.
- `app_binary_sha256`: `f47c2274288150c10e1e808134849b8d177e082c3945c5b2e3723c8a4ebd42d7`.
- `dependency_lock`, `profile`, `OS_arch`, `toolchain`: as in
  [the preceding integrated run](../run-20261030-5/README.md). This source
  workspace uses checked-out modules and has no MoonBit lockfile.
- `command`: the retained `session.sh`, launched with `dbus-run-session --
xvfb-run --auto-servernum --server-args='-screen 0 960x640x24 -nolisten tcp
-ac +extension GLX +render' ./session.sh`. `PATH` selected the locked profile
  `prefix/usr/bin`, followed by the extracted Linux test tools;
  `LD_LIBRARY_PATH` selected the locked `weston` and `x86_64-linux-gnu`
  libraries, followed by extracted Linux test libraries. `WESTON_MODULE_MAP`
  selected the locked profile's `libweston-14/x11-backend.so` and
  `XKB_CONFIG_ROOT` its `usr/share/X11/xkb`. `YAMI_IME_OUT`, `YAMI_IME_APP`,
  `YAMI_IME_FRAMEWORK_SHA`, `YAMI_IME_APP_SHA`, and
  `YAMI_IME_BACKGROUND_POINT=150,285` selected the stated output, binary and
  source identities. Adapt local paths on another machine.
- `result`: PASS for the fixed-profile sequence in `result.json`; final output
  contains exactly one `日本` commit. Raw logs, screenshots and artifact digests
  are retained alongside this file. `run_url`: none (local).

The consumer still uses the legacy split route. Ordered/pending-commit ownership,
restore-target disappearance, blur/stale-event recovery and acceptance of newer
combined HEADs remain open. Candidate screenshots use delayed capture and manual
correlation with IBus state; they do not satisfy the automated #155 candidate
oracle. XTest is synthetic OS input to a live IME, not physical-keyboard input.
Candidate geometry, AX and production readiness remain separate and unqualified.

`app.log.gz` retains the unmodified app output in deterministic gzip form; the
uncompressed log SHA-256 is
`9b2a7a6c655acc8ef46f9a0ba4a854d98b1cae8683418d4977239c41280e864c`.
