# Pinned intent / handoff exploratory harness

This prepares a bounded live IBus/Mozc probe for Yami source
`1a59626cf67910917c4d660dd6db8bedae55a722` (#142) and GPUI source
`35b9041dfb3642b43ca37c604834942614eb50fb` (#211). The app binary must be
built by the harness in a new temporary workspace from that exact source pair.
The harness rejects dirty app/framework/harness trees, mismatched source SHAs,
and dependency pins that differ from the framework. It records build.json,
build.log, and the resulting executable and digest together. This local build
record is evidence of the observed build process, not a signed attestation. A source override is used; this is not a registry
consumer check.

Do not execute as an acceptance run until the same app and framework heads
have required CI and independent review. No binary or result from an older
revision may be substituted. The expected app source includes the experimental
geometry control CLI and reservation-retry union from #142; updating that source requires repinning and
rebuilding.

The driver uses X11 synthetic keys through nested Weston and live IBus/Mozc. It
observes the original release, applies the existing strict release policy,
then sends one more key and one bounded continuation. It tries `geometry-submit`;
if that is refused, it tries exactly one supported `geometry-handoff` and one
retry. Successful handoff and retry replies are recorded as observations only. They
do not by themselves establish that the first failure was Busy or that a
specific later record was retained; they are not model/scene/caret, full IME, candidate table, physical
keyboard, focus/dialog, resize/blur/close or safe shutdown acceptance. If the
initial submit succeeds without Busy, the race is NOT_RUN. A refused handoff is
recorded as blocked without claiming its cause from an error code alone.

Set `YAMI_RELEASE_OUT` to a new empty directory, `YAMI_RELEASE_APP_TREE` and
`YAMI_RELEASE_FRAMEWORK_TREE` to the clean exact source trees, and
provide a toolchain capable of the native build. The harness sets
`YAMI_RELEASE_BINARY` and `YAMI_RELEASE_BINARY_SHA256` from its own build. Run `session.sh` with the local Xvfb, Weston,
IBus/Mozc and library environment used for the profile. `result.json` records
source revisions, binary hash, dependency manifests, commands, outcomes and
scope. On any failure after a valid empty output directory is accepted, the
harness records a result and artifact manifest. Tracked process groups receive
bounded TERM/KILL shutdown and `/proc` is scanned for visible artifact writers
before the manifest is written. Inaccessible processes, surviving groups, or
visible writers mark stability unverified; even a clear scan is an observation,
not proof against escaped processes or later modification. Run URL is null for a local run.

The harness may force SIGTERM if the owner cannot stop. That teardown destroys
in-process ownership and is recorded as cleanup **FAIL**, never as safe stop.
No publication, app build or live run is implied by this harness branch.
