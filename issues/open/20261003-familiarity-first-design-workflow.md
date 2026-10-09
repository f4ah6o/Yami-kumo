# Familiarity-first design workflow

## Goal

Yami-kumo should deliberately look and behave like a familiar application shell.

The target is not visual novelty. The target is transfer learning:

- a first-time user can predict how the UI works from conventions they already know;
- applications built with Yami-kumo feel related enough that learning one reduces the cost of learning another;
- product teams can reuse the shell and common patterns without inventing application-specific chrome;
- interaction quality can improve without making the shell visually distinctive or fashionable.

## Design invariant

**Familiarity is a feature.**

When choosing between an unusual but attractive interaction and a conventional interaction that users already understand, prefer the conventional interaction unless the product task requires otherwise.

Yami-kumo should optimize for:

1. predictable placement;
2. predictable state changes;
3. consistent interaction feedback;
4. transferable component behavior;
5. restrained defaults that work across many products.

## What may change

Improvements that preserve the above invariant are encouraged:

- hover, pressed, selected, disabled and focus-visible states;
- hit areas and touch targets;
- motion timing and easing;
- drawer / sidebar / popover / tab transitions;
- loading, empty, error and success states;
- keyboard navigation and search / command affordances;
- spacing, typography and border/radius tokens;
- responsive collapse rules;
- accessibility and reduced-motion behavior.

## What should not change by default

Do not optimize the starter for visual novelty.

Avoid making these part of the shared shell unless a product explicitly opts in:

- decorative shader / WebGL effects;
- unusual navigation models;
- experimental gestures that replace conventional controls;
- product-specific visual identity;
- large animated transitions whose purpose is primarily spectacle;
- one-off dashboard compositions that cannot transfer to other applications.

## Reference-driven workflow

External references are design inputs, never runtime dependencies.

### Shipped-product references

Use Mobbin when available to inspect established product patterns. Prefer comparisons across multiple products instead of copying one screen. Extract conventions such as hierarchy, placement, state treatment and interaction sequence.

The official Mobbin MCP is a hosted remote MCP endpoint and requires user authorization. It must remain optional; contributors without it must still be able to work on Yami-kumo.

### Motion references

Use 60fps.design when motion behavior is the question. Search by interaction type (tabs, drawer, search, loading, toast, show/hide, etc.) and extract timing / sequencing principles rather than product branding.

### Visual exploration

Recent and Collect UI can be used for visual exploration, but references from design galleries should be treated as inspiration rather than evidence of a proven shipped interaction.

### Creative components

Canvas UI is explicitly out of the default shell path. GPU / canvas effects may be useful to applications built on top of Yami-kumo, but should not become a shared-shell dependency or default visual language.

## Agent / skill contract

A Yami-kumo design skill should apply this order:

1. Identify the user task and the conventional UI pattern that already solves it.
2. Reuse existing Yami-kumo / Kumo components before adding new primitives.
3. If a reference source is available, compare at least 3 relevant examples where practical.
4. Extract common structure and behavior; do not reproduce a specific product's branding or composition verbatim.
5. Preserve the semantic shell boundaries in `docs/UX.md`.
6. Prefer token-level changes over page-specific CSS.
7. Check pointer, touch, keyboard, narrow desktop and phone behavior.
8. Check `prefers-reduced-motion` for non-essential motion.
9. Keep `main` neutral and copy-ready. Richer demonstration content belongs on `demo`.
10. When a proposed improvement makes Yami-kumo more distinctive but less predictable, reject it by default.

## Shared vocabulary to add incrementally

The shell already standardizes high-level regions. The next reusable layer should be a small vocabulary rather than a large component framework:

- `PageHeader`
- `Toolbar`
- `Section`
- `Status`
- `EmptyState`
- `DataList` / row pattern
- common loading / error / success treatment
- context-panel heading / section treatment

These should be introduced only when at least two realistic application examples need the same pattern.

## First implementation slice: interaction polish

Apply to the `demo` branch first without changing information architecture or visual identity.

### Tokens

Introduce shared tokens for:

- fast / normal motion duration;
- standard easing;
- focus ring;
- hover / pressed surface;
- minimum interactive target size where layout allows.

### States

Ensure interactive controls have consistent:

- hover;
- active / pressed;
- focus-visible;
- selected state that is not hover-only;
- disabled treatment where applicable.

### Motion

Use restrained transitions for shell state changes. Avoid animating layout-heavy properties when a transform/opacity treatment is sufficient. Respect `prefers-reduced-motion`.

### Accessibility

Keyboard focus must be visible throughout the shell. Drawers retain explicit close affordances and overlays remain dismissible. Motion must not be required to understand state.

## Acceptance criteria

- [ ] `main` remains visually neutral and copy-ready.
- [ ] `demo` keeps the same navigation model and recognizable dashboard composition.
- [ ] Common interactive controls have visible keyboard focus.
- [ ] Pointer hover and pressed feedback are consistent across rail, sidebar, tabs and icon controls.
- [ ] Non-essential transitions are disabled or minimized under `prefers-reduced-motion`.
- [ ] Motion values come from shared tokens rather than unrelated one-off durations.
- [ ] No Canvas/WebGL dependency is added to the shared shell.
- [ ] Mobbin / 60fps / Recent / Collect UI remain optional design-time references, not build or runtime dependencies.
- [ ] `docs/UX.md` is updated when a new reusable interaction rule graduates from experiment to contract.
- [ ] Existing checks/tests/build remain green.

## Later slices

After the interaction-polish slice has been exercised by real applications:

1. standardize empty/loading/error/success states;
2. add a transferable page-header / toolbar pattern;
3. add row/list conventions for common CRUD and settings surfaces;
4. evaluate command/search behavior;
5. add visual regression / interaction fixtures for the shared vocabulary.

Rechecked against main at 9bb6527 (2026-10-09): still open — the first interaction-polish slice landed on `demo` via #2 (merge 57c80e0), but shared vocabulary items and later slices are not started, and `main` has no shared motion/focus tokens yet.
