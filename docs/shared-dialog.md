# Shared Dialog contract (YK-07)

Status: contract for implementation. No `ui/core` Dialog, DOM dialog adapter or
native modal adapter exists in this repository yet. The contract keeps the
application's open state authoritative and maps it to the browser top layer or
the GPUI focus-scope controller.

## Ownership

The application owns `open`. `Dismissed` and `Confirmed` are requests from the
host, not state changes: the application validates the request, updates its
model, and re-renders. The host must not report a closed dialog as open or
invent a confirmation.

One dialog is the MVP. Nested overlays, menus and popovers are separate work.
Dialog is a root-level overlay: it does not consume flex layout space and is
painted after the main content.

## Public API

```moonbit
pub struct DialogProps {
  open : Bool
  title : String
  dismissible : Bool
  initial_focus : NodeKey?
}

pub fn dialog(NodeKey, DialogProps, Array[View]) -> View

pub fn app_shell(
  // existing parameters...
  overlay? : View,
) -> View

pub(all) enum SemanticAction {
  // existing Activate / TextChanged / Submitted
  Dismissed(NodeKey)
  Confirmed(NodeKey)
}
```

`initial_focus` must name a live, focusable node inside the dialog. If it is
absent, the first focusable child is used. A dialog with no focusable child and
no explicit initial target is rejected at commit; it is not opened with focus
left on the background.

The opener is captured by the host when `open` transitions false to true. It is
the preferred restore target. If it is gone, the host uses the dialog's fallback
target, then the first surviving global tab stop, then clear focus.

## DOM behavior

- Use a native `<dialog>` and `showModal`; do not reimplement the top layer with
  absolute CSS.
- `cancel` (Escape) and `close` are separate observations. Prevent the browser
  default only where the application must decide, and emit exactly one
  `Dismissed` or `Confirmed`.
- While a composition is active, the first Escape cancels the composition and
  must not dismiss the dialog. The next Escape may dismiss it.
- Background content is inert while the modal is open; do not forward pointer or
  key events into the background tree.
- Restore focus to the opener after close, using the browser's observed focus
  result. Do not report a focus request as a successful focus change.
- A programmatic close caused by the application's own model update must not
  emit a second `Dismissed`.

## Native behavior

- Use `element.FocusScopeSession::open_scope` with the dialog root, initial and
  fallback targets, and the cancellation hook.
- Route pointer/key input through `dispatch_input_with` while the scope is open.
  Background input must not reach the main tree.
- `close_scope` removes the dialog roots and restores focus. A stale or foreign
  scope target is rejected before dispatch.
- Paint the scrim and panel as an overlay after the main scene. The dialog panel
  bounds are derived from the window/root; they are not a flex child.
- Publish the dialog and its focusable descendants into the accessibility model
  with role/name/state. The native OS provider may remain `UnsupportedCapability`
  in M3; the model must still be correct.
- If the host cannot provide modal focus isolation, return
  `UnsupportedCapability` and do not show a non-modal imitation.

## Failure and edge cases

- Opener removed while open: use the explicit fallback, then the first tab stop,
  then clear focus. Never restore to a removed node.
- Asynchronous open result after unmount: drop it; do not open a new root.
- Double confirmation or double dismissal: one action only.
- Escape during composition: composition first, dialog second.
- Dialog unmount: dispose the scope and any listeners exactly once.

## Verification

- `moon test ui/core ui/runtime --target all --deny-warn`
- DOM: `node --test tests/shared-ui/dialog.test.mjs` (new fixture)
- Native: focus-scope adapter tests with a scripted host; `NOT_RUN` for a real
  screen reader until an exact-source profile exists.
- Cases: open/cancel/confirm, initial focus, focus restore, composition Escape,
  background input suppression, opener removal, stale request, double action.
- Visual/pixel checks are not a substitute for the semantic focus and action
  results.
