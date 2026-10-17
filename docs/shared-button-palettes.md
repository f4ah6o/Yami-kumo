# Explicit per-Button palettes (bounded YK-05 slice)

`ui/core.button_with_palette(key, label, Light|Dark, disabled~, loading~)`
adds immutable per-Button metadata. `View.button_palette()` returns that token;
legacy `button()` returns `None`. No `NodeKind`, existing `Model` or
`SpacingModel` definition changes. Other nodes cannot accept palette metadata.
The closed `ButtonPaintRole` and opaque `ButtonPaletteColor` expose the exact ten
roles in `fixtures/shared-ui/button-palettes.json`; every channel is fixed and
alpha is 255. There is no public color constructor or arbitrary style setter.
Dark matches GPUI's standard palette. Light is explicitly specified in that
fixture; neither follows system appearance.

## Paint and state ownership

Native maps the neutral table into `ButtonPaintPalette`, then delegates to
`paint_items_with_palette`. `None` uses the unchanged `paint_items` entry.
Both paths take the returned `TextItem` foreground and recolor the existing
measured `NativeText`; no RGB decoding or second precedence controller exists.
Core still validates all three items (including long labels) before the adapter
publishes anything. IDs, ordering, text measurement/origin, layout, and the
core's existing 1/2-pixel normal/focused inset are unchanged. Palette-only
updates retain binding IDs, runtime tokens, held presses, eligible focus,
queued activation and existing transactional staging rules.

DOM adds/removes only `yk-ui-button-light` and `yk-ui-button-dark`. Import remains
inert. The host explicitly links `styles/shared-ui.css`, as for existing Card
and stack tokens. Its new selectors set only color, background-color and
border-color on those individual controls. No style injection, inline styles,
root/body theme, new listeners, dimensions, fonts, border widths or radii.
Unrelated classes/attributes and roots are preserved; None removes both owned
classes. Existing Card/stack/default CSS is unchanged.

The browser owns `:hover`, `:active`, and `:focus-visible`; native GPUI owns its
hovered, pressed and focused flags. Native focused paint includes pointer focus;
browser focus-visible remains heuristic. These are separate profiles, not a
promise of matching state recognition or geometry. CSS precedence mirrors role
intent: disabled over focus-visible border; disabled, loading, active, hover,
normal fill. Native precedence remains solely in core. The separate legacy
native Kumo `Theme` and its alpha policy are not changed.

## Shared fixture and qualification boundary

`PaletteModel` composes one unchanged `SpacingModel`, which contains the only
counter. Both bootstraps use this same owner and palette view/update. Stable
labels/keys and layout cycle None → Light → Dark → None through actual actions:
Increment, Palette, Increment, Palette, Palette. Domain counts are
`[0,1,1,2,2,2]`; the strict v1 count schema remains separate from detailed traces.

Portable tests freeze all ten opaque roles, every gate/input overlap, measured
foreground, metadata reconstruction, identities, held release, queued actions,
and failed/stale preparation behavior. Executed negative controls distinguish
assertion rejection from compilation failures. The independent native palette
oracle is state-aware and does not relax the older settled-frame assertions.
Its synthetic tests are not actual host evidence.

The new native fixture captures only settled enabled/nonloading states. Hover,
focus, pressed, gates, both explicit tokens and revision come from the same
accepted frame as the canonical scene; the existing presentation acknowledgment
binds that scene to a retained completed PPM. State is never inferred from RGB.
Both Button border/fill/real measured text-run foreground and corresponding
pixels are checked, with retained IDs/bounds, token removal and host cleanup.
Pressed and custom disabled/loading colors are portable-only unless separate
actual captures explicitly establish them. Browser captures additionally test
real held Space with a programmatic application palette toggle; that auxiliary
probe is not part of the real-pointer six-phase domain trace.

Qualification requires final-head actual Chromium, Linux Wayland and Windows
D3D11 artifacts; all previous six DOM/four native fixtures; all eleven existing
CI jobs; and fresh independent review. Local preparation does not establish
those results. The root common/DOM compiler pin remains 0.10.14+7d59c7ec9;
advanced GPUI source lanes remain 0.10.15+943464bfa. Shared GPUI revision remains
4c2e525f02c00a9c1a560152a914f523a4c2fe47, and legacy pins stay unchanged.
macOS remains build/portable-only; actual macOS windows, AX providers, IME,
physical hardware, general theming/layout, AppShell, full YK-05, M2 and the
four-platform MVP are unqualified.
