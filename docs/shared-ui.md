# Shared UI source-workspace slice

This additive development API implements the bounded YK-01 lifetime model and
YK-02 Text/Button DOM path from the [four-platform roadmap](roadmaps/20261017-four-platform-gui/ROADMAP.md).
The [architecture decision](adr/0001-shared-ui-runtime.md) records what is
inherited from the legacy Kumo API and what remains a separate contract.

## What is implemented

- `ui/core`: immutable Text/Button/Column/Row View and semantic Activate values.
- `ui/runtime`: root-wide key validation, opaque root/incarnation ownership,
  atomic commits, queued activation, per-button disabled/loading cancellation,
  observed focus results and idempotent disposal.
- `examples/shared_counter`: one pure model/view/update, imported unchanged by
  standalone JS/native source consumers and the DOM bootstrap.
- `ui/dom`: explicit mount into an empty element, keyed text spans and native buttons,
  keyed updates, root overlap rejection, retained focus and owned cleanup.
- `styles/shared-ui.css`: optional layout-only row/column rules, without Kumo.

The common packages import only MoonBit core and each other. The DOM adapter is
JS-only and uses a thin browser FFI. No GPUI, React, Kumo or Zag runtime enters
this path. The repository's older demo/build tooling still has its own dev and
legacy runtime dependencies.

These packages are currently a source-workspace API. The existing `.moonignore`
allowlist, npm preview exports, package names and versions are unchanged. A
clean standalone source consumer proves the dependency boundary, not a new
registry release. Distribution is a later YK-09 gate.

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
and rejects activation in the common runtime. Loading does not create a new
keyboard controller or prove behavior for a future native adapter.

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

## Explicitly still open

The new native GPUI adapter and its visible-window proofs are YK-03 work.
Compiling a portable consumer on Linux is not a Linux native GUI pass, nor does
it qualify Windows or macOS. General themes/layout, Input/TextField, composition,
Dialog, external accessibility and packaged distribution are later gates.
Browser coverage in this slice is Chromium only; Firefox, WebKit, actual Safari,
real IME and assistive technology require their own measured profiles. The
existing GPUI Canvas backend and legacy native Button controllers are unchanged.
