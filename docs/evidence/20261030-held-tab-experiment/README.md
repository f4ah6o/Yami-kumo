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
  resize while retaining event order have not been implemented. Layout
  invalidation during a hold fails closed and has no recovery operation.
- A reentrant measurement that changes the owner now causes the TextSession
  transaction to reject before publication. A white-box fixture checks the
  committed document and delivery watermark remain unchanged; removing the
  guard makes that fixture fail. The hold remains poisoned, and recovery of
  the caller-retained observation is not implemented. Error is not converted
  to successful delivery.
- Safe resize recovery also needs a bounded owner-side event buffer and a way
  to preserve or drain previously queued model actions before re-staging. The
  current layout invalidation blocks `next_action`, the lease blocks stage and
  publish, and an active preedit cannot be rebound as an idle session. Do not
  release the lease and rebuild a stale model merely to unblock the UI.
- The operation is not wired into native Settings; OS lifecycle, Dialog,
  callbacks arriving after cutoff and actual IME behavior remain unqualified.
  No unconditional Tab/preedit discard policy is introduced.
- The added public methods need design and independent review before they can
  become a public consumer contract. The GPUI candidate APIs are not released.

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
