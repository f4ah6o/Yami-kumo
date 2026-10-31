# Independent #160/#162 live diagnostic — stopped before guard observation

The exact fresh-build session stopped before the staging-guard probe. Initial
consumer empty/`ｎ` preedit was observed, but the application suspended on
`retained_update: busy`. The harness could not observe its expected unsupported
receipt and exited with `original unsupported receipt was not observable`.
**No geometry-guard marker was emitted.** The guard flags, release policy,
bounded `に` probe and geometry commands are **NOT_RUN** for this session.

This is diagnostic evidence. App #160 is #142 plus a rejected-stage marker; it
does not contain #154's P1 fix. No post-fix, scene/model/caret, shutdown or full
live-IME acceptance is claimed, and prior #142/#156 observations do not carry
over to this source pair.

## Exact provenance

| Role | Revision/value |
|---|---|
| App #160 | `cfa87adb6214f7ba50fa3a91075ca6e4eafddb9d` |
| Framework #211 | `35b9041dfb3642b43ca37c604834942614eb50fb` |
| Harness #162 | `bc5ea9398abbdcc11147aac0a1b7cf92c90d6e92` |
| Fresh executed binary SHA-256 | `e3b6b44e98cf828e65d45aa608e32bec223ec76a1e0a51c5fdf4ee7cc3522ff4` |
| Original raw artifact-manifest SHA-256 | `79b891cc66855a285e162cd952f5e8da3155cb5aead8c62a720c66439698b874` |
| Run location / URL | **Local**, no hosted run URL; raw `run_url` is null. |

Launch followed the parent's explicit confirmation that both exact source heads
had independent review and **CI 7/7 SUCCESS**. Review links and the exact launch
authorization are in `run-authorization.json`.

Independent detached `app/`, `framework/` and `harness/` worktrees remained
clean. Both checked-in dependency pins match the exact framework SHA. Resolution
used a **source override**, not a registry-only consumer or package lock. The
session built in a new temporary Moon workspace before starting services; no
prebuild or older binary was used. `live/build.json` retains the source triplet,
manifest hashes, command and Moon 0.1.20261012 / moonc v0.10.15+943464bfa versions.
The fresh build passed 50 tasks; nonfatal generated-C warnings are retained.

`preparation-provenance.json` records exact source/tree IDs, protocol-generation
script, both installed Wayland XML inputs, scanner **1.23.1** executable/version/
hash, all four freshly generated C/header hashes, runtime binary/tool hashes
and nonsecret environment. Stable preparation scripts, sources, XML, scanner,
generated protocol and runtime inputs were checked before launch and after exit.
No app/framework/harness author files or raw `live/` files were edited.

## Stage observations

| Stage | Result |
|---|---|
| Fresh build | **PASS**; built/executed binary and manifest hashes verified. |
| Environment | Nested Xvfb/Weston **14.0.2** x11/pixman, IBus **1.5.32**/Mozc `mozc-jp`, synthetic X11 input. IBus Wayland input-method bind observed. |
| Initial preedit | Raw consumer empty marker at native sequence **7**, `ｎ` at sequence **9**. |
| Suspension | Native sequence **10** logged as platform and acknowledged. Later `geometry_update_begin` failed with `retained_update: busy`; controlled state became active with that reason. No `unhandled_forwarded_release` marker was observed. The exact cause of Busy is not established. |
| Read-only control | Three commands (`status`, `prefix`, `receipt`) returned. Prefix reported unresolved/unavailable; receipt reported no native sequence. No command timed out. |
| Harness stop condition | `RuntimeError('original unsupported receipt was not observable')`. |
| Release / continuation / `に` | **NOT_RUN**; no release-resolution or advance command was sent. |
| Geometry guard / submit / handoff | **NOT_RUN**; `geometry_guard_markers=[]`. No guard flags can be inferred from their absence. |
| Commit/model/scene/caret | **NOT_RUN**. No commit marker. A logged frame before suspension does not prove the intended candidate's scene/caret publication. |
| Explicit stop request | **NOT_RUN** because the driver failed earlier. This session did not observe a stop-refusal reply. |
| App-owner cleanup | Forced SIGTERM, exit **-15**: **FAIL_FORCED_TERMINATION_OWNER_NOT_PERSISTED**. Session exit 0 is not acceptance. |
| Test-resource teardown | Exact finalizer reports no tracked groups remaining and no visible writers. Independent check found app PID, runtime directory and private control socket gone; no visible process referenced this run. No unrelated process was terminated. |
| Artifacts | Original raw-manifest entries and built/executed binary digests all match; original raw files remain unchanged. |
| Artifact stability | **UNVERIFIED_WRITERS_OR_GROUPS**: finalizer could not inspect **727 process FD directories**. Visible absence of writers does not exclude inaccessible/escaped writers or establish future stability. |

Candidate selection, Dialog/focus, blur/resize/close races, physical keyboard,
registry consumer, macOS and Windows live IME are **NOT_RUN**. The unexercised
timeout suppression path is not validated by this live result.

## Exact command and retained records

```bash
YAMI_160_162_REVIEW_CI_CONFIRMED=bc5ea9398abbdcc11147aac0a1b7cf92c90d6e92 \
  bash /workspace/review162-live-prep-agent/launch-after-confirmation.sh \
  > /workspace/review162-live-prep-agent/live-launch.log 2>&1
```

The launcher validates the exact clean source heads and recorded inputs, creates
a new empty `live/`, then executes the exact harness session under
`dbus-run-session -- xvfb-run --auto-servernum` with
`-screen 0 960x640x24 -nolisten tcp -ac +extension GLX +render`.

Raw records: `live/app.log`, `live/result.json`, `live/build.json`,
`live/build.log`, `live/app.exe`, `live/artifact-manifest.json`,
`live/ibus-ui-wayland.log`, `live/ibus-ui-dbus.log`, `live/ibus-daemon.log`,
`live/mozc-server.log`, `live/weston.log`, `live/weston-stdio.log` and
`live/engine.log`.

External records: `env.sh`, `launch-after-confirmation.sh`,
`run-authorization.json`, `preparation-provenance.json`, `live-launch.log`,
`postflight-artifact-verification.json`, `postflight-source-verification.log`
and `postflight-cleanup-observation.json`. The launch stream stayed outside the
raw directory while the exact harness finalized it. The separate
`archive-manifest.json` hashes these final representations; matching local
hashes are observations, not signed attestations or writer-cessation proof.
