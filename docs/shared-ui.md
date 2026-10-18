# Shared UI source-workspace slice

This additive development API implements the bounded YK-01 lifetime model and
YK-02 Text/Button DOM path from the [four-platform roadmap](roadmaps/20261017-four-platform-gui/ROADMAP.md).
The [architecture decision](adr/0001-shared-ui-runtime.md) records what is
inherited from the legacy Kumo API and what remains a separate contract.

## What is implemented

- `ui/core`: immutable Text/Button/Column/Row View, additive fixed Card decoration, semantic Activate values, and the host-neutral AppShell region model.
- `ui/runtime`: root-wide key validation, opaque root/incarnation ownership,
  atomic commits, queued activation, per-button disabled/loading cancellation,
  observed focus results and idempotent disposal.
- `ui/theme`: light/dark semantic Button and AppShell surface/text colors shared
  by generated CSS and GPUI paint palettes; see
  [shared-button-theme.md](shared-button-theme.md) and
  [shared-app-shell.md](shared-app-shell.md).
- `examples/shared_counter`: one pure model/view/update, imported unchanged by
  standalone JS/native source consumers, the DOM bootstrap, and the App/Entity native bootstrap.
- `ui/dom`: explicit mount into an empty element, keyed text spans and native buttons,
  keyed updates, root overlap rejection, retained focus and owned cleanup; the
  same adapter renders the semantic AppShell skeleton and scoped CSS.
- `styles/shared-ui.css`: scoped row/column rules and required fixed Card geometry, without Kumo.
- `examples/shared_button_theme`: one immutable Button-theme fixture model,
  imported unchanged by DOM and native host runners.
- `native/ui`: explicit GPUI Text/Button/Column/Row and AppShell adapter with
  private native IDs, common lifetime tokens, staged geometry/scene publication
  and one GPUI Button controller per live Button.
- `native/examples/shared_counter`: one App Entity owning the unchanged common
  Model, plus thin Linux/Windows/macOS entrypoints.

The common packages import only MoonBit core and each other. The DOM adapter is
JS-only and uses a thin browser FFI. No GPUI, React, Kumo or Zag runtime enters
this path. The repository's older demo/build tooling still has its own dev and
legacy runtime dependencies.

These packages are currently a source-workspace API. The new native examples
are explicitly excluded from the existing native publication allowlist because
their common packages are also unpublished. Existing published contents, npm
preview exports, package names and versions remain unchanged. A
clean standalone source consumer proves the dependency boundary, not a new
registry release. Distribution is a later YK-09 gate.

See [the bounded Card contract](shared-card.md) for `card`/`is_card`,
`Model.card_view()` and the explicit stylesheet requirement. See
[the bounded AppShell contract](shared-app-shell.md) for shell regions,
breakpoint, visibility/focus rules and theme behavior. Existing counter view
and Row/Column behavior remain unchanged.

## Identity and thread confinement

All common runtime, DOM mount and native mount access, including token and
capability comparisons, must stay on the owning UI thread. These APIs do not
provide cross-thread synchronization.

Private runtime identities and native epochs use an independent mutable marker
for observable alias identity. A comparison saves both markers, writes the left
marker to the opposite of the right's original value, observes whether the right
changed, then restores both originals. There is no callback, suspension or user
code inside the probe, and the separate lifecycle `live` bits are never touched.
Copied capabilities share identity, including after disposal; distinct roots,
mount incarnations, gates, requests and preparations do not become equal merely
because their keys, labels, numeric IDs or other fields match.

This is a portability-contract fix: the pinned MoonBit core documents
`physical_equal` as an optimization facility whose result must not determine
program semantics and may vary by backend or optimization setting. No previous
Yami runtime failure was observed. Identity, restoration and lifecycle regressions
run in debug and release on JS, native, Wasm and Wasm-GC in the existing portable
CI jobs. Package APIs, versions, compiler/dependency pins and host behavior are
unchanged.

## Use the model and DOM host

The application keeps one `Model` value. Pass `model.view()` to
`@dom.mount(root_id, view, on_actions)`. The callback runs in a coalesced
microtask after browser event dispatch. Drain one `mounted.next_action()`, apply
`model.update(action)`, then call `mounted.update(model.view())` before draining
the next action.
`examples/shared_counter_dom/bridge.mbt` is the complete runnable bootstrap;
its additional mode/label exports are bounded regression-test controls.

A key is unique across the whole root, including nested containers. Empty and
duplicate keys reject the entire update before the current View changes.
Each Text owns a span containing literal text, so adjacent Text children remain
separate flex items in Row and Column. No HTML is parsed from labels.
Same-key/same-kind updates preserve the mounted node and callback. Removal or a
kind change revokes its old token; recreating the same key does not revive it.
Queued actions are rechecked when drained. Even an enabled → loading → enabled
transition invalidates previously queued activation.

Use real `click` as the DOM activation input. Pointer, keyboard and accessibility
activation therefore share one browser-native route; the adapter never emits a
second Activate from keydown/keyup. Disabled uses the native disabled property.
Loading sets `aria-busy` and `aria-disabled`, preserves the existing node/focus,
and rejects activation at the DOM boundary and common runtime. A gate change
also cancels observed pending browser input before re-enable can revive it.
The cancellation-only listeners do not generate activation. See the
[bounded Button state contract](shared-button-states.md) for focus-visible, hover,
label, repeat, default-action and interruption fixtures and profile differences.

A focus request and its host observation are separate. `mounted.focus(key)`
reports whether the DOM actually focused that current button; the corresponding
result can be drained through `next_focus_result()`. The runtime also represents
Rejected and Unsupported outcomes. It never calls an unimplemented host a
successful focus change.

Only empty roots can be mounted. Two independent roots are supported; owning an
ancestor and descendant at once is rejected. Do not move owned nodes out of a
mounted root: a later update fails with `HostTreeChanged`. Dispose still revokes
its listener but does not remove the moved node from unrelated host DOM. Dispose
is idempotent and makes queued callbacks inert. No resize observers, timers or
window-global listeners are installed by this slice.

## Verification

```sh
pnpm run build:shared-ui
node --test tests/shared-ui/evidence.test.mjs
node scripts/check-shared-ui-consumers.mjs
pnpm exec playwright install chromium
node --test tests/shared-ui/dom.test.mjs
moon test ui/core ui/runtime examples/shared_counter --target all --deny-warn
moon test ui/core ui/runtime examples/shared_counter --target all --deny-warn --release
```

The independent consumer runner compiles the same source packages in separate
external JS/native MoonBit workspaces. The browser test uses the compiled
MoonBit bootstrap in real Chromium and retains raw trace, screenshot, source
identity and browser version under `_build/`. `SHARED_UI_EVIDENCE_DIR` selects
the browser output directory. `SHARED_UI_CHROMIUM_EXECUTABLE` may select an
already installed test browser; its actual version is recorded.

The browser cases include native pointer/Enter/Space activation, literal hostile
labels, distinct adjacent text layout, keyed identity/focus, loading/disabled gates, atomic rejection, queued
staleness, removed/retyped nodes, root isolation/overlap, 100 mount/dispose cycles,
external DOM moves and actual owned-listener cleanup. That repeated test is not
a proof that no application can ever leak memory.

[Fixtures](../fixtures/shared-ui/contract-v1.json) fix expected domain traces.
The [executable evidence schema](../tests/shared-ui/evidence.mjs) rejects missing,
stale or unsupported-as-pass records and checks retained artifact hashes.
Dirty local source may pass behavior assertions but cannot qualify an exact
commit. CI runs these checks and retains `shared-ui-evidence` separately from
legacy npm/native UI evidence.

## Native App/Entity host

The native adapter imports the same `ui/core`, `ui/runtime`, and
`examples/shared_counter` source packages. `NativeCounter` owns exactly one
`App` Entity containing `Model`; it does not keep a second counter state.
`handle_event` only routes the owned window's monotonically sequenced events and
queues semantic actions. After dispatch returns, `drain_one` stages the next
layout and scene, updates the Entity through `App.update`/`Context.set`/`notify`,
and publishes the next view before another action drains. App notifications are
pumped only after that publication; disposal also drains Entity release work
so shutdown reaches Stopped. Measurement failure leaves the model and accepted
scene unchanged.

`native/ui.Mounted` maps root-wide keys to private, nonzero native IDs and common
runtime incarnation tokens. Same-key/same-kind updates preserve identity.
Removal/retype, viewport or scale invalidation, changed Button bounds/label,
loading/disabled transitions, focus loss and disposal revoke the relevant old
input. Foreign-window events cannot consume the owned window's sequence.
Geometry/scene preparation finishes before common runtime publication; stale,
foreign and already-published preparations fail closed.

The adapter uses existing GPUI Element/flex/focus/Scene and measured NativeText.
Each Button uses exactly one existing `gpui/controls/button.Button`. It does not
also dispatch to legacy Yami `ButtonInteraction`. The audited native policies
remain visible: Enter repeat is ignored; the first held activation key owns the
keyboard gesture; matching Space release activates; pointer-plus-Space can
produce two activations; loading retains enabled focus while cancelling presses;
Button bounds must be at least 24 by 24. These are not silently normalized into
browser policy. See GPUI's `docs/shared-ui-host-contract.md` at the pinned source.
Row/Column are a bounded flex subset with fixed system-sans text; general themes,
Box, grids, text editing and IME are not part of this adapter.

The opt-in `Shared UI native proof` workflow uses its own pinned GPUI
revision in `tests/shared-ui/gpui-revision.txt` and MoonBit toolchain. Existing
legacy native jobs keep their old pins and default runners. Linux and Windows
run five fixed shared fixtures with actual host-delivered pointer input:
plain counter `[0, 1, 2]`, disabled/loading `[0, 0, 0, 1]`, and Card counter
`[0, 1, 2]`, plus the two-button spacing demo `[0, 1, 1, 2, 2]`. The latter
measures changed gap/padding, stable bindings and retained focus while the
common application model toggles spacing. Card additionally checks measured content insets/gaps, border paint
and actual focus after each click. The disabled/loading fixture starts disabled, advances to loading
only after the first actual primary release, then enabled after the second;
the third click increments the unchanged model. These test-only props are not
an alternate model or synthetic Button recognizer.
The explicit per-Button palette fixture from PR #34 adds the count trace
`[0, 1, 1, 2, 2, 2]` and records delivered native input alongside accepted frames.
The separate root Button-theme fixture adds 36 captures, including held input,
state overlaps, theme changes and cancellation; see
[shared-button-theme.md](shared-button-theme.md).

The driver retains exact source and GPUI revisions, source hashes, raw build and
host logs, real completed-frame PPM captures, scene/geometry/action traces and
teardown. It rejects dirty or changed source, missing phases, incorrect gates,
blank text regions, unchanged final counter pixels and incomplete destruction.
Linux input uses an isolated Xvfb/Weston session; Windows input checks the exact
visible foreground HWND/title. Frame evidence is emitted after completion, once
per settled phase in the five existing fixtures. The theme fixture deliberately
captures held pressed states before release. macOS CI builds the same
bootstrap and runs portable tests, but reports runtime and AX as `not-run`.

```sh
# Set GPUI_SOURCE to the clean revision in tests/shared-ui/gpui-revision.txt.
export YAMI_SHARED_UI_CANDIDATE_SHA=$(git rev-parse HEAD)
YAMI_SHARED_UI_NATIVE=1 sh scripts/native_ui_linux.sh
# Windows Developer PowerShell:
# ./scripts/native_ui_windows.ps1 -SharedCounter
# macOS build and portable tests only:
sh scripts/native_ui_macos.sh --shared-counter-build-and-test
```

Actual host qualification is the result of the exact candidate's CI artifacts,
not the existence of these commands. The new driver does not claim external
accessibility, keyboard parity, arbitrary window placement on Linux or physical
hardware input. The native platform API has no general pointer-leave event;
this slice does not claim to fix hover after an unreported window exit.

## Explicitly still open

The bounded YK-03 adapter is present, but macOS visible-window execution remains
unqualified. Compiling a portable consumer or macOS bootstrap is not a native
GUI pass. M1 is not complete without all required platform evidence. The
bounded AppShell slice adds semantic regions and portable native layout. A
local macOS host run additionally verified visible wide/compact shell rendering
and AXPress on the main Increment Button; Linux/Windows visible windows,
synthetic shell pointer input, a complete shell AX tree, drawer overlays,
general layout, Input/TextField, composition, Dialog and packaged distribution
remain later gates. Browser coverage in this slice is Chromium only; Firefox, WebKit, actual
Safari, real IME and assistive technology require their own measured profiles.
The existing GPUI Canvas backend and legacy native Button controllers are
unchanged.

## Explicit stack-spacing slice

The additive closed-token Row/Column gap/padding API and shared two-button demo
are specified in [shared-stack-spacing.md](shared-stack-spacing.md). Legacy
constructors and fixed Card geometry remain unchanged. This does not qualify
AppShell, general layout or full YK-05. The separate
[Button theme slice](shared-button-theme.md) adds opt-in light/dark Button
colors and verifies theme switching without replacing the existing controller.
