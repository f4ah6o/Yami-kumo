---
name: yami-kumo-design
description: Design and review Yami-kumo interfaces for familiarity, transferability, and interaction quality without introducing unnecessary visual novelty.
---

# Yami-kumo design

Use this skill when designing, implementing, or reviewing UI built on Yami-kumo.

## Objective

Make the interface feel immediately familiar and transferable across applications. A user who has learned one Yami-kumo application should be able to predict another.

Visual novelty is not a goal. Interaction quality is.

## Rules

1. Start from the conventional pattern users already know for the task.
2. Preserve the semantic shell boundaries documented in `docs/UX.md`.
3. Reuse Kumo and existing Yami-kumo primitives before inventing new shared components.
4. Keep shared defaults neutral. Product branding belongs to product code.
5. Prefer improvements to focus, hover, pressed states, hit areas, motion, keyboard behavior, responsive behavior and system states over decorative redesign.
6. Prefer shared tokens and reusable behavior to page-specific CSS.
7. Keep the navigation model recognizable: durable navigation, local tabs, primary work in main content, optional contextual support.
8. Do not move required task controls into optional regions.
9. Respect `prefers-reduced-motion`; motion may clarify state but must not be required to understand it.
10. Do not add canvas, shader, WebGL/WebGPU or similarly decorative dependencies to the shared shell by default.

## Using external references

Reference sources are optional design-time inputs and must never become runtime dependencies.

When Mobbin is available, use it primarily for shipped-product patterns. Compare multiple examples and extract the common behavior rather than copying one product.

When 60fps.design is available, use it for interaction and motion references such as tabs, drawers, search, loading, show/hide, tooltips and toasts. Keep Yami-kumo motion restrained even when the reference is expressive.

Recent and Collect UI are useful for visual exploration, but gallery work is not proof that a pattern is usable in production. Treat it as a source of alternatives, not as a specification.

Canvas UI is opt-in product decoration, not a Yami-kumo shell primitive.

## Review checklist

For each change, verify:

- Can a first-time user predict what the control does?
- Does this behave like equivalent controls elsewhere in Yami-kumo?
- Are hover, pressed, selected, focus-visible and disabled states coherent?
- Is the pointer/touch target comfortable without unnecessarily increasing density?
- Can the task be completed with keyboard navigation where applicable?
- Does the layout degrade predictably on narrow desktop and phone widths?
- Does reduced-motion mode remain understandable?
- Is the change reusable across unrelated applications?
- Would removing product-specific copy/content still leave a sensible generic pattern?

If an improvement makes the UI more distinctive but less predictable, do not use it as a shared default.
