# Held-Tab owner experiment (not integrated)

This draft explores a bounded ownership transfer for a noncomposing focused
TextField. `Mounted` temporarily holds a GPUI `TextSession`; accepted text
observations update that session and the binding snapshot, while the existing
`FocusScopeSession` keeps focus. Other event delivery, focus, view publication,
paste, activation and theme changes are rejected during the hold. An active
preedit blocks release: neither Tab nor focus change is treated as OS cancel.

The scripted Shared Settings fixture applies a direct `日本` commit to the
original owner, publishes the model action once, rejects a duplicate, simulates
successful host cutoff, then dispatches Tab through the existing focus scope.
GPUI source is the candidate `74d182c6368ca382f697023c5d3690b6c0c2dfbf`
(#177, stacked on #172/#175/#176), selected explicitly by `moon.work`.
The noncomposing fixture is not a live host or IME acceptance.

**DO NOT MERGE / unresolved:**

- `finish_held_text` relies on the caller to establish a cutoff. No capability
  binds that call to the host result, and the real runner still uses split polls.
- The ordered input buffer and `FrameCompleted` handling needed to survive
  resize while retaining event order have not been implemented.
- A reentrant measurement that changes the owner now causes the TextSession
  transaction to reject before publication. A white-box fixture checks the
  committed document and delivery watermark remain unchanged; removing the
  guard makes that fixture fail. A limited retry release is available only if
  no held operation was accepted, no action is queued, the field/focus and
  generation are unchanged, and the session watermark is zero. The caller
  must retain the exact unacknowledged event and focus intent, keep the host
  session armed, re-stage and retry. A fixture covers that sequence. Error is
  not converted to successful delivery.
- Recovery after an earlier accepted committed insertion is tested when the
  field is no longer composing: an owner-specific FIFO drain yields its queued
  `TextChanged` while layout is invalid, the caller updates the model, then
  release / re-stage / retry applies the retained unacknowledged observation
  once. The fixture verifies undo still reaches the preceding document. A
  different owner's live action is left queued and blocks this drain. The
  method relies on the caller actually applying drained actions to the model.
  Recovery with active preedit is still rejected. The bounded ordered-event
  buffer and real runner re-stage path remain unimplemented. Do not release
  the lease and rebuild a stale model merely to unblock the UI.
- The operation is not wired into native Settings; OS lifecycle, Dialog,
  callbacks arriving after cutoff and actual IME behavior remain unqualified.
  No unconditional Tab/preedit discard policy is introduced.
- The added public methods need design and independent review before they can
  become a public consumer contract. The GPUI candidate APIs are not released.
- Source-based native and shared UI CI pins use the exact GPUI candidate SHA
  `74d182c6368ca382f697023c5d3690b6c0c2dfbf`. The published
  `native/moon.mod` still requests GPUI `0.10.6`, which does not provide the
  required `SessionOperation::Insert`; a registry-only consumer therefore
  cannot build this draft. No unreleased version is represented as published.
  Publishing or changing the production dependency requires the reviewed GPUI
  candidate to be released first, followed by clean-consumer verification.

Local candidate-source checks, Debian 13 x86_64 with moonc
`0.10.15+943464bfa`: `moon test native/ui --target native --deny-warn`
**90/90 PASS**; `moon test native/examples/common --target native --deny-warn`
**8/8 PASS**, both via `scripts/native_ui_workspace.sh` and explicit
`GPUI_SOURCE`. These are headless/scripted tests. Locally retained logs are
`/workspace/evidence/yami-held-tab/ui.log` (SHA-256
`9bc6a76b7d7d5e0f14a0d2b351fa7dfb060b446838cbe2b3b49380ccde1f090f`)
and `common.log` (SHA-256
`5e37471f47803b1ee42a119a3a0d161e5a472217b58e9cd5042ac1ac20a21571`).

After the reentrancy guard, the same candidate-source UI suite passed 91/91
and the common suite passed 8/8. The guard-removal negative control failed as
expected: without the guard the delivery watermark changed from 0 to 1 while
the owner was being invalidated. Local logs are under
`/workspace/evidence/yami-held-tab/`; this is not an OS or runner acceptance.

The retry candidate adds a non-consuming runtime pending-action query and an
owner-specific text-action drain. It refuses to start a hold while any action
record is queued, refuses release until queued actions are drained, and refuses
release while a preview remains active. Candidate-source native UI tests and
the portable runtime tests remain scripted; runner buffering and a real host
cutoff are not wired.

On the candidate source pair, native UI tests passed **95/95**, Settings common
tests **8/8**, and runtime tests **19/19** on each of native, JS, Wasm and
WasmGC. The recovery fixture covers a committed `前`, a second unacknowledged
`後` interrupted by layout invalidation, draining and applying `前`, re-stage,
one-time retry of `後`, and undo to `前`. Additional tests reject active
preedit and preserve an unrelated earlier action in the runtime FIFO. These
checks do not execute the Settings runner's ordered host route.
