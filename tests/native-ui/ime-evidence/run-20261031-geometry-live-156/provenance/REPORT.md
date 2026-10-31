# Independent #156 Linux live diagnostic — geometry still blocked

The fresh exact-source run observed consumer `に` preedit after two bounded continuations. Geometry submission then failed with `dirty_scene: native_failure: original owner is not ready to stage`; handoff failed with `geometry_pending_missing: stale_handle`. The precise failed staging guard and any geometry-race cause are **not established** by this app's log.

This is a diagnostic of the next blocker. App #142 does not contain #154's P1 fix, so this is **not post-fix acceptance**. Full live acceptance, commit/model application and scene/caret completion remain **NOT_RUN**.

## Exact provenance

| Role | Exact source |
|---|---|
| App #142 | `1a59626cf67910917c4d660dd6db8bedae55a722` |
| Framework #211 | `35b9041dfb3642b43ca37c604834942614eb50fb` |
| Harness #156 | `acd14b8788e7ece8ce5100348bfd6703186d2e75` |
| Executed fresh binary SHA-256 | `333f6faf7ba449b8aa6e24a3c06df5465c964725b654f06a99da9c8b32ba52c5` |
| Raw harness artifact-manifest SHA-256 | `bf2e92b8b9d1988c00ba121b7a9128c5703f15f02e07e2c09e58a577a13a652c` |

Executed only after the parent explicitly confirmed exact #156 scoped review and CI **7/7 SUCCESS**. Review URL: https://github.com/f4ah6o/Yami-kumo/pull/156#pullrequestreview-5720980913 .

Three separate detached worktrees are retained under this directory as `app/`, `framework/`, `harness/`; all remained clean. Both checked-in framework pins match the exact framework SHA. This uses a source override, not a registry-only consumer or package lock.

The exact session built the app in a new temporary Moon workspace before starting live services, ran 50 native build tasks, and retained its fresh `app.exe`, complete `build.log` and `build.json` under `live/`. The previous #153 preparation binary and older #151 evidence binary were not used. Toolchain is Moon 0.1.20261012, moonc v0.10.15+943464bfa; build warnings were nonfatal generated-C warnings.

`preparation-provenance.json` records the exact framework generation script, both Wayland protocol XML hashes, scanner 1.23.1 executable/version/hash, all four freshly generated C/header hashes, and runtime tool/binary hashes. Recorded source, XML, scanner, generated protocol and runtime inputs were reverified after the run. No author source files or raw `live/` artifacts were edited by this reviewer.

## Observed stages

| Stage | Result and evidence |
|---|---|
| Fresh build | **PASS**; `live/build.json` source triplet and executed binary digest match. |
| Environment | Nested Xvfb/Weston 14.0.2 x11/pixman; IBus 1.5.32 engine `mozc-jp`; live Mozc; synthetic X11 `n`, then `i` keys. IBus Wayland input-method bind and keyboard grab observed. |
| Initial consumer preedit | Empty at native sequence 7, `ｎ` at sequence 9; application preedit markers recorded. |
| Release policy | **PASS_SCOPED** for native sequence 10, with separate ledger-stage reply. This is an ACK observation. |
| Consumer `に` preedit | **OBSERVED_CONSUMER_PREEDIT** after exact continuation generations 1 and 2; native platform sequence 11 and preedit sequence 12 acknowledged. Application marker at `live/app.log:224`. |
| Geometry submit | **BLOCKED**; response rc 2, `original owner is not ready to stage` at `live/app.log:225`. |
| Geometry handoff | **BLOCKED**; response rc 2, `geometry_pending_missing` at `live/app.log:226`; no geometry retry occurred. |
| Timeout path | All 14 control attempts returned; none timed out. This run does not exercise #156's timeout suppression path. |
| Commit/model/scene/caret | **NOT_RUN**; no commit marker. The preedit marker is not scene/caret or model-completion evidence. |
| Stop and app-owner cleanup | Stop rc 2, `host ownership is unresolved`; app required SIGTERM, exit -15. **FAIL_FORCED_TERMINATION_OWNER_NOT_PERSISTED**. Shell/session rc 0 is not acceptance. |
| Test-resource teardown | Exact harness reports no tracked groups remaining and no visible log writers. Independently observed app PID gone, temporary runtime directory gone, private control socket gone, no visible process referencing this run. No unrelated process was terminated. |
| Raw artifacts | Every raw manifest entry rehashed and matched; source/build/executed binary digest equality verified. |
| Long-term artifact stability | **UNVERIFIED_WRITERS_OR_GROUPS** because the finalizer could not inspect 712 process FD directories; visible absence of writers cannot exclude inaccessible writers. |

Candidate table selection, Dialog/focus, blur/resize/close races, physical keyboard input, registry consumer, macOS and Windows live IME were **NOT_RUN**. A rendered idle frame elsewhere in the log does not establish publication of this preedit or the failed candidate.

## Exact command and evidence

```bash
YAMI_156_REVIEW_CI_CONFIRMED=acd14b8788e7ece8ce5100348bfd6703186d2e75 \
  bash /workspace/review156-live-prep-agent/launch-after-confirmation.sh \
  > /workspace/review156-live-prep-agent/live-launch.log 2>&1
```

The launcher sources `env.sh`, validates exact clean source HEADs plus recorded generated/tool inputs, creates a fresh empty `live/`, then executes:

```bash
dbus-run-session -- xvfb-run --auto-servernum \
  --server-args='-screen 0 960x640x24 -nolisten tcp -ac +extension GLX +render' \
  /workspace/review156-live-prep-agent/harness/tests/native-ui/ime-harness/retained-release/session.sh
```

Raw files: `live/app.log`, `live/result.json`, `live/build.json`, `live/build.log`, `live/ibus-ui-wayland.log`, `live/ibus-ui-dbus.log`, `live/ibus-daemon.log`, `live/mozc-server.log`, `live/weston.log`, `live/weston-stdio.log`, `live/engine.log`, `live/app.exe`, `live/artifact-manifest.json`.

Additional independent records: `run-authorization.json`, `preparation-provenance.json`, `live-launch.log`, `postflight-artifact-verification.json`, `postflight-source-verification.log`, `postflight-cleanup-observation.json`. The launch stream stayed outside `live/` while the exact harness finalized raw artifacts. `archive-manifest.json` separately hashes the final raw artifacts and these external records; its matching hashes are observations, not signed attestations or proof of future stability.

The previous #151 run lacked consumer `に` evidence after its one continuation. This run establishes that specific preedit observation, while reproducing the remaining geometry-staging blocker. It does not identify the internal guard or establish a successful geometry handoff, reservation race, scene publication or safe app shutdown.
