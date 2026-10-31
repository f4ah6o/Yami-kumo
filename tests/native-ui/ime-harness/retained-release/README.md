# Pinned intent / handoff exploratory harness

This prepares a bounded live IBus/Mozc probe for Yami source
`1a59626cf67910917c4d660dd6db8bedae55a722` (#142) and GPUI source
`35b9041dfb3642b43ca37c604834942614eb50fb` (#211). The app binary must be
built from that exact source pair and its digest supplied separately. The
harness rejects dirty app/framework/harness trees, mismatched source SHAs and
mismatched binary digest. A source override is used; this is not a registry
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
retry. A successful handoff plus retry is a **scoped receipt and held-record
observation**, not model/scene/caret, full IME, candidate table, physical
keyboard, focus/dialog, resize/blur/close or safe shutdown acceptance. If the
initial submit succeeds without Busy, the race is NOT_RUN. A refused handoff is
recorded as blocked without claiming its cause from an error code alone.

Set `YAMI_RELEASE_OUT` to a new empty directory, `YAMI_RELEASE_APP_TREE` and
`YAMI_RELEASE_FRAMEWORK_TREE` to the clean exact source trees, and
`YAMI_RELEASE_BINARY` and `YAMI_RELEASE_BINARY_SHA256` to the independently
built executable and its digest. Run `session.sh` with the local Xvfb, Weston,
IBus/Mozc and library environment used for the profile. `result.json` records
source revisions, binary hash, dependency manifests, commands, outcomes and
scope; raw logs are listed in `artifact-manifest.json` after all child processes
stop. Run URL is null for a local run.

The harness may force SIGTERM if the owner cannot stop. That teardown destroys
in-process ownership and is recorded as cleanup **FAIL**, never as safe stop.
No publication, app build or live run is implied by this harness branch.
