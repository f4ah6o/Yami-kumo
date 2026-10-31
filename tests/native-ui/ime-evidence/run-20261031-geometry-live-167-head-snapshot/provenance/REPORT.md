# Independent #166/#167 live diagnostic — no native head observed

This exact fresh-build run took a different suspension path from the preceding
#160/#162 run: the app logged `geometry_update_ok`, then suspended with
`ordered_text: native_failure: previous frame publication remains unresolved`.
The runner receipt query had no sequence. The new read-only `inspect-native`
command returned **no head observed**, and the driver stopped without recovery.

The snapshot is not proof of an empty or quiescent native FIFO, a durable owner
state, scene consistency, past-update success, or permission to ACK, dispatch,
retry or stop. This diagnostic does not establish recovery or acceptance. App
#166 is instrumentation based on #160/#142 and does not contain #154's P1 fix;
prior-run results do not carry over to these exact revisions.

## Exact provenance

| Role | Revision/value |
|---|---|
| App #166 | `e9fe5fe06111dce33be20f3f93d8be819194486f` |
| Framework #211 | `35b9041dfb3642b43ca37c604834942614eb50fb` |
| Harness #167 | `aa7c81288b81617a5e8a346347fe355e38d5b834` |
| Fresh executed binary SHA-256 | `d2950bb778e939dce9ad89d3e02a370de070a784726a769033e6c6f03becfb2c` |
| Original raw artifact-manifest SHA-256 | `a7457076e9b0a83b0a716e57efa14a965b63ee16326588d0c5cedb46d7d6fc9e` |
| Run location / URL | **Local**; no hosted run URL; raw `run_url` is null. |

The parent explicitly authorized launch after confirming both exact independent
reviews and both CI **7/7 SUCCESS**. Exact review URLs, revisions, command and
authorization are retained in `run-authorization.json`. Preparation metadata
records the earlier preflight state; authorization records the later CI clearance.

Independent detached app/framework/harness worktrees remained clean. Both
checked-in framework pins match the exact framework SHA. Dependency resolution
used a **source override**, not a registry-only consumer or package lock. The
session built in a new temporary Moon workspace before starting services; no
older binary or prebuild was used. `live/build.json` retains source/manifests,
command and toolchain (Moon 0.1.20261012, moonc v0.10.15+943464bfa). Build passed
50 native tasks; nonfatal generated-C warnings are preserved.

`preparation-provenance.json` records exact source/tree IDs and stable launcher
scripts, the framework generation script, both installed Wayland protocol XML
inputs, scanner **1.23.1** executable/version/hash, four regenerated C/header
hashes and runtime binary/tool hashes. Recorded sources, scripts, protocol and
runtime inputs were verified before launch and after exit. No author sources
or original raw `live/` artifacts were edited.

## Stage results

| Stage | Observation |
|---|---|
| Fresh native build | **PASS**; build/executed binary digests and original raw-manifest entries match. |
| Environment | Nested Xvfb/Weston **14.0.2** x11/pixman, live IBus **1.5.32**/Mozc `mozc-jp`; synthetic X11 `n` input. IBus Wayland input-method bind observed. No later `i` probe input was sent. |
| Initial preedit | Consumer empty and `ｎ` preedit markers observed. No commit marker. |
| Update and suspension | App logged `geometry_update_begin`, then `geometry_update_ok`; suspension reason was **previous frame publication remains unresolved** (`live/app.log:217–219`). This is distinct from the prior run's `retained_update: busy`. |
| Runner observation | `status`/`prefix`/`receipt` returned; prefix unresolved/unavailable and receipt sequence absent. A missing runner receipt does not prove absence at the native route. |
| Native inspection | `inspect-native` rc **0**, explicit message **none observed; not a quiescence proof**. One native-head marker at `live/app.log:220`, reproduced below. No head sequence or kind was established. |
| Guard/release/continuation/geometry | **NOT_RUN**; `geometry_guard_markers=[]`. No release resolution, generation, advance, geometry-submit, handoff or retry command was sent. |
| Driver stop | `RuntimeError('original unsupported receipt was not observable; native head inspection only')`. All **4** control attempts returned; no timeout. |
| Explicit stop request | **NOT_RUN**; no stop-refusal response was observed. |
| App-owner cleanup | Forced SIGTERM, app exit **-15**: **FAIL_FORCED_TERMINATION_OWNER_NOT_PERSISTED**. Session exit **0 is not acceptance success**. |
| Test-resource teardown | No tracked groups or visible writers reported; app PID, runtime directory and control socket independently observed gone, with no visible process referencing this run. No unrelated process was terminated. |
| Artifact limits | Raw/source/protocol/tool/build/executed-binary hashes match. Finalizer could not inspect **757 process FD directories**; writer cessation/long-term stability remain **UNVERIFIED_WRITERS_OR_GROUPS**. |

Exact native-route snapshot:

```json
{"present":false,"pending_geometry":false,"handoff":false,"owned":false,"reserved":false,"portable_epoch":1,"native_epoch":1,"owner_host_verified":true}
```

These fields describe one read-only observation. In particular,
`owner_host_verified:true` is the recorded local owner flag, not rendering or
scene/geometry acceptance proof. No targeted record was ACKed or dispatched by
the inspection. The driver stops after inspection and does not use the snapshot
as recovery authority.

Full live IME, commit/model reflection, intended scene/caret publication,
candidate selection, Dialog/focus, blur/resize/close races, physical keyboard,
registry consumer, macOS and Windows live IME remain **NOT_RUN**. An earlier
frame marker cannot prove the unresolved candidate was published. This run does
not exercise timeout suppression or establish the cause of unresolved frame
publication.

## Exact launch and retained evidence

```bash
YAMI_166_167_REVIEW_CI_CONFIRMED=aa7c81288b81617a5e8a346347fe355e38d5b834 \
  bash /workspace/review167-live-prep-agent/launch-after-confirmation.sh \
  > /workspace/review167-live-prep-agent/live-launch.log 2>&1
```

The launcher verifies exact clean source heads and prepared inputs, creates a
new empty `live/`, then invokes the exact session via `dbus-run-session --
xvfb-run --auto-servernum` with `-screen 0 960x640x24 -nolisten tcp -ac
+extension GLX +render`. The session builds the executable before live services.

Raw records are under `live/`: `app.log`, `result.json`, `build.json`, `build.log`,
`app.exe`, original `artifact-manifest.json`, and complete Mozc/IBus/Wayland/
Weston/engine logs. External provenance includes `env.sh`, exact launcher,
`run-authorization.json`, `preparation-provenance.json`, `live-launch.log`,
postflight artifact/source verification and independent cleanup observation.
`observe-cleanup.py` preserves the read-only observation code and terminates no
processes. The launch stream remained outside the raw directory during exact
harness finalization. Separate `archive-manifest.json` hashes the final records;
local matching hashes are not signed attestations or writer-cessation proof.
