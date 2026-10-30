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
