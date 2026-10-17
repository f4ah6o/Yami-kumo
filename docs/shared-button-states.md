# Shared Button state contract (bounded YK-04 slice)

This specifies the additive `ui/core.button` path, with one browser-native
Button in `ui/dom` or one existing GPUI Button in `native/ui`. It does not change
legacy Kumo HTML, legacy `native/components.ButtonInteraction`, or their Enter
repeat behavior. No third activation controller is introduced.

## Common semantic contract

- Enabled means `!disabled && !loading`. Only an enabled, current Button can
  deliver `Activate(key)`. Common runtime admission and dequeue both check it.
- Either gate changing revokes queued activation, including
  enabled → loading/disabled → enabled before the queue drains. Already delivered
  actions are not undone.
- Loading alone retains eligible focus. It does not focus a previously unfocused
  Button. Disabled removes focus eligibility, including when both flags are set.
  Re-enabling does not automatically restore lost focus. New common API focus
  requests are rejected while either gate is set; loading preserves existing
  host focusability/traversal rather than promising a new focus request succeeds.
- Same key/kind retains the DOM node/private native identity. Literal label content is never
  parsed as HTML. Removing, retyping, disposing or recreating a key cannot revive
  its old callbacks, queued actions or held input.
- A focus request and an observed focus result remain separate. Focus retention
  does not by itself mean keyboard-style focus-visible painting.

## Declared host profiles

| State or operation               | DOM / Chromium fixture                                                                                                                | GPUI native adapter at the checked-in pin                                                                                                 |
| -------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------- |
| Enabled primary click            | Browser `click` produces one queued Activate                                                                                          | GPUI in-bounds primary down/up produces one queued Activate                                                                               |
| Disabled                         | Native `disabled`; cannot be focused or activate                                                                                      | Nonfocusable/non-hit-testable; clears focus, hover and held state                                                                         |
| Loading                          | `aria-busy=true`, `aria-disabled=true`; not native disabled, so retained focus survives; no Activate                                  | GPUI loading gate retains focus, clears hover/held state, rejects Activate                                                                |
| Both flags                       | Native disabled wins focus/activation; busy state remains exposed                                                                     | Disabled wins focus/activation; loading remains set                                                                                       |
| Retained focus and focus-visible | Browser `:focus-visible` heuristic; keyboard Tab and pointer-focus observations are separate                                          | Existing GPUI paints its focus border whenever focused, including pointer-obtained focus. No browser focus-visible equivalence is claimed |
| Hover                            | Browser `:hover`, including an unavailable button physically under the pointer                                                        | GPUI hover follows delivered PointerMoved; loading/disabled clears it; enabling needs a new pointer observation                           |
| Unchanged repaint                | Retains node, focus and browser-held input                                                                                            | Retains Button, focus, hover and held input                                                                                               |
| Label change                     | Retains the native DOM node and browser default behavior, including held Space                                                        | Recreates the label-bearing GPUI Button while retaining eligible tree focus; cancels press/hover and old pending callbacks                |
| Enter/repeat                     | Browser-native click on Enter and its repeats while enabled; no key-generated Activate                                                | First nonrepeat key-down only; repeats never activate                                                                                     |
| Space/repeat                     | Browser-native click on release; repeated keydown does not add activation                                                             | Matching release of the first held activation key activates once                                                                          |
| Interrupted loading/disabled     | A gate change cancels an observed pending primary pointer gesture or held activation key; re-enable before release does not revive it | Existing GPUI with_enabled/with_loading cancels held state on transitions                                                                 |
| Blur and removal                 | Browser defaults plus local blur cancellation; removed listeners and revoked instance token                                           | Focus loss/removal cancels GPUI held input and old capabilities                                                                           |
| Geometry/resize                  | Browser owns hit testing and default cancellation; no custom resize observer or cross-host resize parity claim                        | Changed accepted bounds, viewport or scale cancels input; invalidated geometry rejects dispatch until a successful commit                 |
| Default action                   | `type=button` never implicitly submits an enclosing form; unavailable/canceled activation defaults are prevented synchronously        | Focused loading Enter/Space is consumed without activation. No form-submit/default-button API exists in this slice                        |
| Mixed pointer/Space              | Browser default ordering; no universal mixed-input equivalence                                                                        | Existing GPUI may emit one Space activation and one pointer activation                                                                    |

The browser fixture uses actual Playwright keyboard/mouse input. Its
`detail=0` cases are explicitly synthetic or programmatic AT-like admission
checks, not evidence of an external assistive technology. Native portable tests
route platform events into the real adapter; they do not qualify native keyboard,
external accessibility, or physical hardware input.

## DOM cancellation boundary

`click` is the sole Activate entry. Small node-local listeners observe Enter,
Space and primary pointer sequences only to cancel a browser default or reject
an obsolete click. They never synthesize clicks/actions, implement repeat,
set pointer capture, stop propagation, or manage application state. Gate changes
are applied before changing the native disabled property. Key cancellation is
synchronous at keydown/keyup; a canceled Space release cannot defer its
`preventDefault` decision until the action queue drains.

Pointer cancellation follows the browser's PointerEvent `pointerType` and
`pointerId`, retaining only the latest primary gesture per pointer type. Foreign
non-primary downs/cancels cannot reset another pointer's cancellation; mouse and
pen/touch identities do not collide. A new primary down replaces an older
sequence whose release the browser delivered elsewhere. Independent
`detail=0` clicks are always eligible when current/enabled, including while a
canceled key/pointer sequence is pending; they do not require a prior key event.
This boundary does not infer that such a click came from an actual AT provider.

The six owned node listeners are click, keydown, keyup, pointerdown, pointercancel
and blur. All are removed on removal, kind change and disposal, including nodes
moved out of the owned root. No global listener, timer or resize observer is
introduced. An unchanged update does not cancel input. Label/geometry changes
continue using browser behavior rather than pretending to mirror GPUI.

## Executable fixtures and evidence limits

`fixtures/shared-ui/contract-v1.json` adds `button-interrupted-loading` and
`button-interrupted-disabled` without changing either existing counter fixture.
Each starts at zero and observes `[0, 0, 0, 1, 1, 2]`:

1. Initial zero
2. Held Space, gate on/off, release: zero
3. Held primary pointer, gate on/off, release: zero
4. Fresh Enter down: one
5. Gate on/off, stale Enter repeat/release: still one
6. Fresh primary click: two

The native adapter's portable tests assert the same sequence on all four compiler
targets in debug/release. The Chromium runner emits exact-candidate evidence
records for the new fixtures alongside the original counter records. Additional
raw trace cases cover focus-visible versus retained focus, hover, label repaint,
repeat, default submission, independent detail=0 clicks and held removal/retype/
disposal. Its click-only baseline negative control must demonstrate two obsolete
activations (held Space and pointer across a loading cycle); this measures the
old admission policy in the same browser, not execution of an old compiled SHA.

`button-boundary.test.mjs` evaluates the exact checked-in JavaScript FFI against
Node EventTarget. This checks cancellation/admission and listener disposal; it is
not a substitute for real browser defaults. Five isolated source-mutation controls
require these assertions to reject missing gate cancellation, key-generated extra
activation, detail=0 rejection, foreign-pointer cancellation and listener leaks.
Evidence-schema tests reject wrong
counts or missing fixture/profile records. Existing Linux/Windows real-pointer
counter jobs and macOS build-only job remain unchanged; the new native held-key
fixtures are portable host-contract tests only.

Local cloud Chromium execution remains NOT_RUN because of the verified sandbox
block. Do not relabel static checks, Node EventTarget tests, native model tests,
or previous-SHA screenshots as fresh browser/native-window evidence. Draft-PR
CI must establish browser execution and exact-candidate native host regressions.
Root CI retains MoonBit 0.10.14 and native CI 0.10.15. No package/dependency pin
is changed. This is not completion of YK-04 Text/Card, M2, M1's outstanding
macOS visible-window gate, external AX, IME, or the four-platform MVP.
