# Scoped Linux live IME geometry probe, 2026-10-31

This is a **blocked exploratory result**, not Shared Settings or release
acceptance. The same-session build and live run used:

- Framework source: `35b9041dfb3642b43ca37c604834942614eb50fb` (gpui #211).
- Consumer/app source: `1a59626cf67910917c4d660dd6db8bedae55a722` (Yami #142).
- Harness: `f8022d251a52a198a5af01cc2ec9f7b757e277c1` (Yami #148).
- App binary SHA-256: `1e6d5050e5605b0415df978a07493ce5cb52a75749c46c9d0ce6d2ce88547b8c`.
- Dependency: source override, both checked-in framework pins match the SHA;
  no registry-only lock or consumer was exercised. Manifest hashes and Moon
  toolchain versions are in `build.json` and `result.json`.
- Profile: Linux x86_64, nested Xvfb/Weston 14.0.2, live IBus 1.5.32/Mozc,
  synthetic X11 keys. This is not a physical-keyboard test or macOS evidence.
- Command: the pinned harness `session.sh` under `dbus-run-session` and
  `xvfb-run` with the environment in the archived `launch.sh`. Run URL: none.

The live protocol log shows initial empty preedit and `ｎ` preedit (native
sequence 10). Sequence 11 was acknowledged by the release-specific policy;
this is a scoped ACK observation, not commit/model/scene completion. One
bounded advance handled native sequence 12; subsequent `geometry-submit`
returned `dirty_scene: original owner is not ready to stage`. The follow-up
handoff returned `geometry_pending_missing`. The log does **not** identify
which staging guard failed, and no Busy cause or geometry race is established.
A later Wayland `に` preedit appears in the transport log; the consumer did not
record its application in this run. No commit or model application was observed.

The stop request was refused and the harness sent SIGTERM; cleanup **FAIL**.
Candidate-table selection, scene/caret, Dialog/focus, blur/resize/close races,
registry consumer, macOS and Windows live IME are **NOT_RUN**. An earlier run's
success is not evidence for this revision.

`artifact-manifest.json` is the original harness manifest, whose SHA-256 is
`b4778105c885f4d9142cfd18d5b8e6782abffb0fa23506614637dc6d7ae3b7dd`.
The binary was stored as `app.exe.gz`; decompress it and check the original
manifest's `app.exe` hash before comparing. The original raw file hashes were
rechecked after the run and matched at that time. `/proc` reported 669
inaccessible processes, so writer cessation and long-term artifact stability
remain **UNVERIFIED**, despite no visible writers or surviving tracked groups.
The build and metadata are local observations, not signed attestations.
`launch.log` and `launch.sh` were archived separately after the run and are not
included in the original harness manifest. `archive-manifest.json` hashes the
files as committed here, including the compressed binary.
