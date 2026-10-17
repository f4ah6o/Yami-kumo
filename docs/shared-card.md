# Shared Card: bounded YK-04 consumer

Contract fixed before implementation (2026-10-17): Card is a noninteractive,
ordered vertical container with a square 1 logical-pixel border, 16 logical-pixel
padding on every side, and 12 logical-pixel gaps between direct children. The
border is RGB(166,171,178), the interior RGB(245,247,250), matching existing native
neutral colors. No theme, radius, clipping, overflow policy or arbitrary style API
is introduced. DOM uses CSS pixels; native uses GPUI logical coordinates.
Geometry assertions allow at most 1 logical pixel for host snapping, fixed before
measurement. Text metrics and font-dependent outer dimensions are not compared
across hosts. Each host must measure all four content-envelope insets and direct child gaps.
The content envelope is the union of direct child bounds: its left/top/right/
bottom edges must be inset 17 (border 1 plus padding 16). Every child must stay
inside the Card. The existing native profile retains intrinsic child widths;
the DOM profile stretches flex children across the available content width.
Equal right edges for all native children are not part of the Card contract.

`card(key, children)` is a Column with private decoration metadata, observable via
`View.is_card()`. NodeKind remains Text/Button/Column/Row; existing exhaustive
matches compile. Card and plain Column with the same key retain their instance;
changing decoration does not change semantic identity or create an activation
handler. Old constructors, keys and Row/Column gaps remain unchanged (DOM 0,
native 12). Consumers rebuilding a decorated Column can preserve it by consulting
is_card(). Child arrays are copied exactly like existing containers.

`Model.view()` remains unchanged. `Model.card_view()` decorates the same counter
children and key, and both bootstraps import this single common view/model/update.
Native uses the existing pinned GPUI layout insets and scene quads; Card's outer
border and inset interior paint before its descendants, with IDs +1/+2 in its
existing reserved block of 8. Neither adapter adds input handling for Card.

Acceptance requires actual Chromium and Linux/Windows pointer counter fixtures,
retained measured geometry, scene/frame pixels, focus and nested Button actions,
as well as portable decoration/identity/nesting checks. Portable events are not
host runtime proof. macOS remains build-only; external AX, IME, hardware input,
Firefox/Safari, general layout parity, full YK-04, M2 and MVP remain unqualified.

DOM installation requires linking `styles/shared-ui.css` explicitly. Importing
the JS adapter injects no styles. Without this stylesheet, semantic content still
exists but Card geometry is not provided. The consumer fixtures load it under
self-only CSP. Selectors affect only the additive shared UI classes.

Geometry-changing decoration updates keep identity and eligible focus but retain
existing native held-gesture cancellation when Button bounds change. A repaint
with unchanged Card geometry preserves held state. This does not promise that a
gesture survives moving its target. Nested Card geometry is covered in portable
native layout and actual Chromium fixtures; the visible Linux/Windows fixture
covers one Card with three ordered children and actual pointer input.
