# Ordered Settings runner experiment — DO NOT MERGE

This draft wires the Ubuntu Settings lane to the candidate GPUI ordered route
and its drained cutoff. Other native sample lanes retain the legacy route. In
scripted tests a forwarded Tab is held while the old owner receives queued text;
a Busy cutoff is retried, then the existing FocusScope receives the Tab. A
repeated text observation is rejected; an active preview received while held
waits for an observed commit. A Tab arriving with an existing preview is
rejected explicitly and is never rewritten as OS cancellation.

The selected source is the unpublished GPUI candidate
`74d182c6368ca382f697023c5d3690b6c0c2dfbf`; the root Yami runtime and GPUI
registry versions declared by `native/moon.mod` do not contain all candidate
APIs. Source-based verification is not a clean published-consumer build.

**P1 / do not merge:** while a Tab is held, resize/scale/destroy/close or a
full 64-event buffer returns an explicit error. The current outer native entry
then stops the host. The native queue and any admitted but not yet delivered
commit can be lost; this is not a safe recovery, and the error must not be
reported as successful acceptance. The active-preedit/resize path remains open.
An existing preedit at Tab also returns an error, and the resulting host stop
is not a qualified IME resolution. These cases need a bounded event buffer,
model-action drain/re-stage and a host/owner recovery protocol that retains
unacknowledged events before this can run as a product flow.

When layout is already invalid, ordinary input is bounded until a frame
completion; a structural event behind it errors rather than silently
reordering. The code must still be independently reviewed for ordered buffering,
returned cutoff authority, stale events, renderer callbacks and all error paths.
No live IME, candidate table, real macOS, or final-head CI claim is made here.

## Local scripted checks

With `GPUI_SOURCE` pointing to the candidate SHA above, the native workspace
wrapper ran `moon test native/examples/common --target native --deny-warn`:
13/13 PASS. The captured output has SHA-256
`417c35138b19d03ef1fe439aa141af69a97e357e5c33c8061de5ffd544a014e7`.
`moon check native/examples/ubuntu --target native --deny-warn` passed; its
captured output has SHA-256
`72bdbe91a7c575f2f7f0d22ae9108215874f6ff759534084c494e9be5d546bb5`.
These are fake-host fixture results on Debian x86_64, not OS IME acceptance.
The test inputs explicitly include duplicate commit, delayed observed commit,
existing composition, resize and bounded-buffer exhaustion. The failure tests
establish the current error and retained fake-host queue before the outer
entrypoint stops; they do not establish production recovery.

## Active preedit and structural recovery boundary

The native UI regression fixture `invalidated held preedit cannot be released
as an idle retry` now checks both an observed Commit and Cancel after layout
invalidation: neither is accepted, and finish, retry release, and a new hold all
fail. With the candidate source the native UI suite passed 95/95; the captured
output digest is
`e8c3491f657c3d7c3fa738e0f3121a22e50009707e32bf6612941f17191d89a2`.
This is a demonstration of the blocker, not successful recovery.

The existing `TextSession::new` and `rebind` reject a composing field. A held
session also blocks ordinary stage/publish. Therefore recreating a session or
restaging the view as currently implemented cannot safely retain the same
composition and its owner. A recovery design must retain the original session
and any observation not acknowledged by it, drain already accepted model
actions in FIFO order, and revalidate window, binding generation, revision and
focus while obtaining new geometry without replacing the editing authority.
The renderer and host geometry update must succeed before retrying the retained
observation exactly once. Target disappearance, close, and reentrant invalidation
still need explicitly tested terminal or retry behavior; treating them as OS
cancel or silently discarding input is not supported.

The outer entrypoint calls `host.stop()` on every runner result. Returning an
error before that call does not preserve a queued native event. Equally, simply
waiting with a bounded in-memory queue cannot guarantee progress under an
unbounded stream of later events. A complete solution needs an owner/host
protocol that specifies retention and overload handling, and covers lifecycle
termination without asserting that undispatched OS callbacks have arrived.
The present tests do not establish that such a protocol exists or is live-safe.

A white-box exploratory fixture uses private `prepare` after invalidation,
with the field shifted by adding a preceding view. The prepared candidate
retains the composing value and has new bounds, while the single live
TextSession still has its old bounds and revision; ordinary public `stage`
rejects the hold. Native UI 96/96 PASS; output digest
`b5a7605ea91bd68f9052895f4fa35cbad1f93ee96f65f2c3d0a2d63f80f93e8d`.
This demonstrates a staging primitive, not an authorized publish, resize
recovery, native rendering, or scale change.

One candidate protocol would prepare a bounds-only change on the existing
TextSession without publishing, prepare the scene using that exact field, then
validate one owner/epoch/binding/focus/revision and commit both under the UI
thread's single mutation guard. Reentrant callbacks and failures at *either*
publication must leave both old states unchanged. The retained host observation
must not be treated as a newly accepted text event; only after the atomic
publication may it be retried with a freshly captured session target, and its
host sequence must still be checked exactly once. Existing `publish` includes
runtime and focus-scope mutations that can fail, so a Session-only setter
cannot supply this atomicity. Bounds-only does not solve a font/scale change
requiring new measurement of both current preview and original rollback
snapshot. The contract and fixture do not yet implement this proposal.
