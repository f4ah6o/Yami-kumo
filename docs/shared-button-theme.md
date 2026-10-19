# Shared Button theme: bounded YK-05 slice

The shared source-workspace API supports opt-in `Light` and `Dark` Button colors.
`ui/theme` is the single color source. The DOM adapter uses scoped CSS variables;
the native adapter maps the same ten slots to GPUI's `ButtonPaintPalette` and
calls the retained Button's `paint_items_with_palette`.

The per-Button palette API merged in PR #34 remains available with exactly its
existing RGB values. Its `ButtonPaletteToken.color` now reads `ui/theme`, so
both APIs share one numeric token table. An explicit `button_with_palette`
selection takes precedence over a root theme; an ordinary `button` uses the
root theme when present, otherwise its existing unthemed paint. Dark retains
the established GPUI standard colors. This selection chooses a palette only;
GPUI and the browser still own interaction state.

This slice changes Button color and theme selection. AppShell, themes for Text
or Card, general layout, automatic system appearance, arbitrary custom themes,
and full YK-05 remain separate work.

## Color contract

`Theme::button_colors()` returns immutable RGB byte tokens. Alpha is always one.
The ten roles are `normal_border`, `focused_border`, `disabled_border`,
`normal_fill`, `hovered_fill`, `pressed_fill`, `loading_fill`, `disabled_fill`,
`enabled_foreground`, and `disabled_foreground`.

GPUI owns state selection. Border uses disabled, then focused, then normal;
fill uses disabled, loading, pressed, hovered, then normal; foreground uses
disabled or enabled. Native label measurement is retained and the measured
label takes its color from the TextItem returned by GPUI painting. Yami does
not select a separate foreground priority or add a Button state machine.

DOM uses the browser's existing `:disabled`, `:focus`, `:active`, `:hover`, and
the existing `aria-busy` attribute. A themed focus border follows `:focus` to
match GPUI's focused palette slot. Explicit per-Button palettes retain their
existing `:focus-visible` behavior. Browser focus timing, Enter repeat and
Space activation remain browser behavior. Native GPUI continues to normalize
unreachable states, including clearing pressed state when loading or disabled.
The fixture records those observed booleans instead of fabricating a state.

## DOM API and CSS ownership

Import `f4ah6o/yami_kumo/ui/theme` and the existing `ui/dom` adapter. Include
`styles/shared-ui.css` once using an ordinary stylesheet link.

```moonbit
let root = @dom.mount("app", view, drain_actions, theme=Some(@theme.Light))
// After obtaining the mounted DomRoot:
mounted.set_theme(Some(@theme.Dark))
mounted.set_theme(None)
```

`mount` without a theme preserves the existing path. `set_theme` only changes
the mounted root's owned theme attributes. It never calls the View reconciler,
changes input gates, recreates a Button, or replaces a listener. Clearing the
theme restores the attributes present before opt-in. Disposal restores owned
root decorations; later host edits are checked rather than silently overwritten.

Color selectors require the themed `.yk-ui-root` and its owned `.yk-ui-button`
descendant. The stylesheet does not add body rules, inline style, a style
element, document-wide theme state, or a Kumo/Tailwind build dependency.
Independent mounted roots may select different themes. Existing Kumo
compatibility CSS and the npm preview's exports/assets are unchanged.
Root selectors exclude explicit per-Button palette classes, so changing or
clearing a root theme cannot overwrite a Button's explicit colors or focus
profile. Removing the explicit selection resumes the current root theme.

## Native API and commit behavior

```moonbit
let mounted = @ui.Mounted::new(window, theme=Some(@theme.Light))
let changed = mounted.set_theme(Some(@theme.Dark))
```

Call the existing prepare/commit presentation path after selecting a theme.
The setter records the requested theme and invalidates old prepared work; the
last accepted frame remains active until a new frame is successfully committed.
`Mounted::theme()` observes the requested theme; `Frame::theme()` observes the
accepted one. A failed prepare retains the previously accepted frame and input
geometry. `set_theme(None)` restores the legacy paint path for Buttons without
an explicit palette. Explicit per-Button selections remain active. Disposed or busy
roots reject changes.

Theme-only updates preserve the existing GPUI Button, item IDs, binding IDs,
focus, held input, cancellation and queued semantic actions. Existing
`Frame::button_palette` continues to observe explicit View metadata, while
`Frame::theme` observes the accepted root setting. No theme
configuration is added to the legacy `native/components` API.

The shared proof already pins GPUI at
`4c2e525f02c00a9c1a560152a914f523a4c2fe47`, the merged palette API revision.
This PR keeps that pin. The separate legacy native proof and published
`native/moon.mod` dependency remain unchanged. The shared API still requires
the documented source workspace; this change makes no new published-package
compatibility claim.

## One fixture and generated assets

`examples/shared_button_theme` is the same immutable model/view/update imported
by DOM and native. It owns only a counter, theme and disabled/loading
configuration. It delegates interaction state and admission to the existing
host Button and common runtime. `increment` and `theme-toggle` have constant
keys and labels, so a theme switch cannot hide a lifecycle or label update.

`fixtures/shared-ui/button-theme-v1.json` contains both token palettes and an
explicit 32-row overlapping-state paint oracle. Native and Chromium compare
actual border, fill and foreground to this fixture. The native runner also
checks completed-frame pixel samples and retains the actual scene items.

Regenerate color assets from compiled MoonBit without Kumo:

```sh
pnpm run generate:shared-theme
pnpm run check:shared-theme
```

The generator updates only its marked CSS variable region and the fixture's
token values. It preserves the independently reviewed state table. CI rejects
stale generated assets and changes to the established per-Button RGB contract.
Common tokens and the example compile on JS, native,
Wasm and WasmGC.

## Validation and qualification limits

The Chromium fixture exercises normal, hover, focus, pressed, disabled,
loading, overlaps, both themes and mixed roots. It switches themes while Space
and a pointer are held, checks cancellation through gate changes and an outside
release, and verifies fresh and already-queued activations. It also checks
strict CSP, keyed DOM identity, focus, root ownership and disposal.

The native fixture uses real host keys and pointer events, captures the same
shared model in both themes, and checks retained bindings, focus, controller
state, scene colors, framebuffer pixels and activation counts. Linux uses
XTest through Xvfb/Weston/Wayland; Windows uses Win32 SendInput/D3D11. Each result
binds the exact clean Yami SHA, GPUI revision, relevant source hashes, actual
toolchain, command, timing, native logs, scenes and frame artifacts. The theme
result is separate from the five existing shared fixtures, including PR #34's
per-Button palette fixture and its delivered-input trace.

```sh
moon test ui/theme examples/shared_button_theme --target all --deny-warn
pnpm run test:shared-ui
export GPUI_SOURCE=/path/to/pinned/gpui.mbt
export YAMI_SHARED_UI_NATIVE=1
export YAMI_SHARED_UI_CANDIDATE_SHA="$(git rev-parse HEAD)"
sh scripts/native_ui_linux.sh
# Windows: scripts/native_ui_windows.ps1 -SharedCounter
```

**macOS real-window rendering and input are unverified.** The macOS workflow
builds and runs portable tests; it cannot qualify a native-window theme switch.
Hosted software GPU results also do not qualify physical hardware, IME,
assistive technology, Firefox/Safari, or identical font rasterization across
operating systems. See the PR's exact-head test results for executed PASS/FAIL
and any remaining NOT_RUN profiles; documentation of a check is not evidence
that it ran.

### Native pointer receipt barrier

The native theme test host arms each pointer-move operation with a fresh request
and acknowledges the window, current phase, scale, target and arm sequence.
The driver then injects movement once and waits for the corresponding actual
adapter-dispatch receipt before sending any following input or capture key.
Receipts carry the request, window, phase, arm/event sequence, dispatch witness,
scale and delivered coordinates. Wrong, stale or missing receipts cannot advance
a capture; the existing marker deadline fails closed. Window/lifetime changes
interrupt an outstanding request. Unrelated movement does not clear it.

Windows requests non-coalesced zero-relative movement after positioning the
cursor, including repeated same-position operations. OS API success alone never
satisfies the receipt barrier. The additional arm keys are test-host controls;
they do not change the shared model or the capture phase. All 36 expected states,
scene checks and pixel assertions remain unchanged. Portable receipt tests do
not qualify real Windows/Linux host delivery or macOS runtime behavior.

Linux sends one two-point motion command: an interior point two physical pixels left of the target, followed by the exact target. This requests fresh motion even when the pointer already occupies the target. Both points must remain strictly inside the intended button or root region, and only the final dispatched receipt permits capture. There is no click, retry, timeout fallback, or relaxed state assertion.
