# Explicit stack spacing: bounded YK-05 slice

Contract fixed before implementation (2026-10-17). This adds gap and uniform
padding to plain Row/Column only. It does not implement theme, AppShell,
grow/shrink, alignment, min/max, responsive layout, clipping or overflow policy.

## API and compatibility

`SpacingToken` is a closed enum: `Zero`, `Four`, `Eight`, `Twelve`, `Sixteen`,
`TwentyFour`. `pixels()` returns exactly 0/4/8/12/16/24 logical pixels.
`StackSpacing::new(gap, padding)` takes two tokens; its fields are private and its
`gap()`/`padding()` accessors return tokens. Arbitrary numbers, negative values,
NaN, infinity and unsupported token values cannot be passed to this API.

`row_with_spacing(key, children, spacing)` and
`column_with_spacing(key, children, spacing)` copy children and attach private
metadata, observable with `View.spacing()`. There is no generic setter that can
apply spacing to a Text, Button or fixed Card. `NodeKind` is unchanged, so old
exhaustive matches still compile. Old `row`, `column` and `card` constructors
retain their exact contracts; `spacing()` returns None for them. In particular,
legacy Row/Column gaps remain DOM 0/native 12. Card remains a Column with its
separate fixed border 1/padding 16/gap 12 contract. Rebuilders should preserve
both spacing metadata and Card decoration rather than drop either silently.

No runtime stylesheet injection or inline styles are used. Applications must
explicitly load `styles/shared-ui.css`, as before. Scoped token classes set only
gap/padding; they are removed when returning to a legacy container. The adapter
uses no Kumo, React or Zag runtime. GPUI and compiler pins are unchanged.

## Geometry and host limits

DOM CSS pixels and native GPUI logical coordinates use the same exact tokens.
Direct children remain ordered and nonwrapping. Production sizing/alignment are
unchanged: DOM uses existing block-level flex/auto width/default stretch, while
native retains intrinsic child sizes and its existing flex settings. An ordinary
DOM Row may keep extra available width. The public API makes no promise of
intrinsic outer width or equal font metrics across hosts.

Padding describes the content-box inset, separate from the fixed Card border.
In a nonoverflowing layout each child is at least padding away from the stack
edge. Extra host-allocated space can exceed that minimum. Negative free space,
clipping and overflowing content are outside this slice, not silently qualified
as general layout parity. Gap is the separation of adjacent direct children.

Before measurements, the tolerance is fixed at at most 1 logical pixel for each
measured gap/inset. It is not increased for failures. Font-dependent outer sizes
are measured per host and never compared across hosts.

The browser fixtures explicitly load a separate self-only
`tests/shared-ui/spacing-fixture.css`. It gives only the named fixture mounts
`display: inline-flex`, shrink-wrapping their contents. This test-host constraint
is not a public View sizing feature or a change to ordinary consumer alignment.
In this intrinsic fixture domain, all four edges of the union of direct-child
bounds must be inset by the declared padding (or border+padding for Card).
Individual native children need not extend to that union's right edge.

`spacing_geometry_view()` is the same font-independent tree on both hosts:
empty padded containers supply intrinsic 16/32-pixel boxes, nested inside an
explicit Row/Column and a fixed Card. Native sizes stay intrinsic; browser Row
stretch may increase a child's cross-axis height. Tests assert the correct host
profile and content envelope, never infer that every stretched box is 16×16.
The shared fixture's outer intrinsic size is 116×130 logical pixels.

## One application owner and input

The existing `Model` source and its `view`, `card_view`, `update` (including
unknown-action behavior) are unchanged. `SpacingModel` composes one Model and
owns an expanded boolean. Both bootstraps import its same `view` and `update`;
no driver copies the counter or toggled application mode.

The demo has Increment and Spacing buttons, an explicit Column, a nested Row and
a fixed Card. Compact outer gap/padding are 0/4, expanded 12/16; the Row changes
4/0 to 16/8. Increment, toggle, increment, toggle produces counts `[0,1,1,2,2]`.
The native App Entity owns this common state. Legacy bootstrap paths delegate to
the unchanged counter view/update. Conflicting Card/spacing fixture modes are
rejected rather than overriding Card.

Same-key/kind spacing changes retain semantic tokens, actual DOM elements and
native bindings, plus eligible focus. `Frame.binding_id()` is read-only evidence,
not an input capability. No Button controller is added. Unchanged geometry keeps
held input. Changed native Button bounds preserve the existing cancellation
policy; browser geometry/held-key behavior remains browser-owned. Fresh actions
must still succeed after moving targets.

## Acceptance and evidence boundaries

Portable tests cover tokens, copying, legacy compatibility, fixed-size geometry,
empty stacks, nesting, literal text, Card isolation, identity/focus/held input and
independent source consumers. Compile-negative tests reject invalid values,
private-field forging and unsupported targets. Executed production mutations
must be rejected by geometry/spacing/identity assertions, not merely by a linter.

Actual Chromium and Linux/Windows window fixtures are mandatory final-head CI
gates. They retain per-phase geometry, exact source provenance, stylesheet bytes,
scene/frame evidence, pointer actions and cleanup. The browser also exercises
actual Space input and multiple roots. Strict domain evidence schema remains
counts-only; detailed geometry and identity observations are retained separately.

Local cloud Chromium is NOT_RUN because of the established sandbox restriction;
there is no local-browser workaround. Portable native events and synthetic
oracle tests are not OS runtime proof. macOS remains build-only; external AX,
IME, physical hardware, Firefox/Safari, general layout parity, full YK-05, M2 and
the four-platform MVP remain unqualified.
