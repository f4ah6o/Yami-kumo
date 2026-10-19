# Shared TextField contract (YK-06)

Status: contract for implementation. No `ui/core` TextField, DOM adapter or
native adapter exists in this repository yet. This document fixes the API and
host behavior so the DOM and native work can proceed in parallel without a
second text model.

## Ownership

The application owns one committed value. `View` is controlled: a render passes
the model value into `text_field`, and the host reports committed changes as
semantic actions. The host owns the editing surface, selection, caret and IME
composition. The common layer does not run a second editor, history stack or
shaping engine.

`revision` identifies the application-owned value generation. A host may update
its editing surface from an external value only when the revision advances and
no composition is active. A stale revision is dropped; it is not silently
applied over newer local editing.

## Public API

```moonbit
pub struct TextFieldProps {
  value : String
  label : String
  description : String
  error : String?
  required : Bool
  disabled : Bool
  read_only : Bool
  revision : UInt64
}

pub fn text_field(NodeKey, TextFieldProps) -> View

pub(all) enum SemanticAction {
  // existing Activate(NodeKey)
  TextChanged(NodeKey, String)
  Submitted(NodeKey)
}
```

`TextChanged` carries the committed value only. A preedit is never published as
a `TextChanged` value. `Submitted` is emitted for an explicit submit action
(Enter where the host supports it); it is not inferred from focus loss.

The same action values are produced by the DOM and native adapters. The runtime
queues them in host order; the application updates its model and re-renders.

## DOM behavior

- Use a real `<input>` with a label, optional description and error relation.
- Track `compositionstart`, `compositionupdate`, `compositionend`, `input` and
  `beforeinput`. Do not write `.value` while a composition is active.
- Emit `TextChanged` once per committed change. A `compositionend` followed by
  an `input` event must not insert the same text twice.
- A non-cancelable `beforeinput` is not cancelled. Reconcile after the resulting
  `input` instead of cancelling the browser edit.
- External value updates apply only when not focused/composing and the revision
  advances. Never replace the value during a preedit.
- Disabled and read-only are enforced by the native input properties and by the
  common runtime; do not emulate them with key filtering alone.
- Preserve the existing `f4ah6o/yami_kumo/dom` Field reset/pristine/filled/
  touched regressions in the legacy path.

## Native behavior

- Render the value, selection, caret and preedit through the existing
  `controls/text_field` snapshot and paint helpers.
- Use `text_session.TextSession` for the live ownership, revisions and
  preview/commit/cancel order. Use `text_host.TextInputHost` for the OS
  transport when the host implements it.
- On focus loss, call `request_end(Blur)`, wait for the observed
  `Committed`/`Cancelled`, apply that result, then complete the blur. Do not
  rewrite an observed commit into a cancel.
- A stale target, foreign owner, stale epoch or revision mismatch is rejected
  before measurement or admission. A model-admission failure keeps the OS
  observation pending and does not acknowledge it.
- If the host has no text route, return `UnsupportedCapability`. Do not render a
  read-only `Text` and call it a TextField.

## Bounds and unsupported cases

The first contract is single-line LTR. Multiline, rich text, bidi editing,
grapheme-boundary movement and general shaping are separate gates. UTF-16 remains
the offset unit of `TextDocument`, `TextSelection` and the field API.

## Verification

- `moon test ui/core ui/runtime --target all --deny-warn`
- DOM: `pnpm run build:shared-ui && node --test tests/shared-ui/text-field.test.mjs`
- Native: adapter tests with a scripted text host; no physical IME claim.
- Fixtures cover committed-only updates, composition deduplication, external
  revision, stale host event rejection, disabled/read-only and focus/blur.
- A real Japanese IME result is a separate profile with exact host, IME, font and
  candidate-window evidence. Synthetic events are not that result.
