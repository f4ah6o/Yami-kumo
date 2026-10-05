# Shared UX across Kumo and gpui.mbt

Status: open — design and implementation plan; generation and native UX conformance are not implemented
Updated: 2026-10-05
Related: [Familiarity-first design workflow](20261003-familiarity-first-design-workflow.md), [UX guide](../../docs/UX.md)

## 1. Outcome

Make the UX learned in a Yami-kumo web application transferable to an application
built with [gpui.mbt](https://github.com/gpui-mbt/gpui.mbt). The user explicitly
identified **shared UX** as the goal.

Yami-kumo will own the automation that follows Cloudflare Kumo and maintains the
gpui.mbt implementation. Applications can keep their React or MoonBit code while
sharing component meaning, interaction rules, shell roles, state feedback and
qualification scenarios.

The observable contract covers:

1. where users navigate, work and find contextual support;
2. what each action does and how selection/state are preserved;
3. keyboard, pointer, focus, dismissal and text-entry behavior;
4. loading, empty, error, success, disabled and selected feedback;
5. accessible names, roles, values and state changes;
6. predictable adaptation to viewport size, input device and OS conventions.

Typography, colors, spacing and motion support that contract. Platform fonts,
native window chrome, display scale and the primary shortcut modifier can differ
through explicit platform mappings. The task outcome and discoverability remain
consistent. Screenshot similarity alone cannot establish shared UX.

## 2. Inspected baseline

These are source observations, not new dependency pins or completed acceptance
results. Recheck them when implementation starts.

| Repository | Inspected revision | Relevant observation |
| --- | --- | --- |
| Yami-kumo | `de8e3a3e167df2d721273f6a8f12c5df961d636d` | React `AppShell`; Kumo `Button`, `Input`, `LayerCard`; shell navigation/tabs and styles are locally authored |
| cloudflare/kumo | `3d9331280781bf9ea67bb6c38321a7c6b98b0cee` | Source package version `2.14.0`; theme config, component registry generation and exported variant/default definitions |
| gpui-mbt/gpui.mbt | `bf965aebbeb1dfdfed26373d4a7a58bb51a5ad01` | Headless elements, flex, focus/events and quad scenes; text/IME/accessibility and broader rendering remain incomplete |

Yami-kumo currently declares `@cloudflare/kumo: "latest"` and has no committed
package-manager lockfile at this revision. The inspected Kumo source version
does not identify what a previous Yami-kumo installation resolved.

The existing shell is a starting point, not a completed interaction oracle.
`AppShell.tsx` exposes content slots and dismissal callbacks; it does not own a
complete drawer focus/inertness/keyboard lifecycle. `layout.test.ts` currently
checks a region list, not rendered UI behavior. The web reference must be
qualified against the shared contract before it can qualify native output.

Sources:

- [Yami-kumo dependency declaration](https://github.com/f4ah6o/Yami-kumo/blob/de8e3a3e167df2d721273f6a8f12c5df961d636d/package.json)
- [Yami-kumo starter](https://github.com/f4ah6o/Yami-kumo/blob/de8e3a3e167df2d721273f6a8f12c5df961d636d/src/App.tsx), [shell](https://github.com/f4ah6o/Yami-kumo/blob/de8e3a3e167df2d721273f6a8f12c5df961d636d/src/shell/AppShell.tsx), [layout tests](https://github.com/f4ah6o/Yami-kumo/blob/de8e3a3e167df2d721273f6a8f12c5df961d636d/src/shell/layout.test.ts)
- [Kumo package](https://github.com/cloudflare/kumo/blob/3d9331280781bf9ea67bb6c38321a7c6b98b0cee/packages/kumo/package.json), [registry schema](https://github.com/cloudflare/kumo/blob/3d9331280781bf9ea67bb6c38321a7c6b98b0cee/packages/kumo/src/registry/types.ts), [Button variants and implementation](https://github.com/cloudflare/kumo/blob/3d9331280781bf9ea67bb6c38321a7c6b98b0cee/packages/kumo/src/components/button/button.tsx)
- [gpui.mbt status](https://github.com/gpui-mbt/gpui.mbt/blob/bf965aebbeb1dfdfed26373d4a7a58bb51a5ad01/docs/status.md), [scene commands](https://github.com/gpui-mbt/gpui.mbt/blob/bf965aebbeb1dfdfed26373d4a7a58bb51a5ad01/scene/scene.mbt)

## 3. Ownership and repository boundaries

| Owner | Responsibility |
| --- | --- |
| Cloudflare Kumo | Upstream web components, variants, design tokens and web behavior |
| Yami-kumo | Shared UX contract, shell policy, upstream extraction, generated definitions, native component adapters, fixtures and update reports |
| gpui.mbt | Reusable layout/rendering/input/text/IME/accessibility/platform primitives |
| Application | Domain state/actions, content, labels, chosen optional shell regions and product branding |

Keep Kumo-specific knowledge in Yami-kumo. Its native adapter consumes gpui.mbt's
public API; gpui.mbt's core does not acquire a React, Kumo or Yami-kumo dependency.
Build-time extraction can use the existing JavaScript/TypeScript toolchain.
Native runtime code is MoonBit plus the framework's supported host boundary.

Preserve the existing copy-ready `main` and richer `demo` split. Proposed
generation tools, fixtures and native output should have explicit entry points
so web template users do not need a native toolchain for ordinary checks/builds.
Repository CI can run the native qualification jobs separately.

The gpui.mbt module name at the inspected revision is `f4ah6o/gpui`, version
`0.1.0` ([moon.mod](https://github.com/gpui-mbt/gpui.mbt/blob/bf965aebbeb1dfdfed26373d4a7a58bb51a5ad01/moon.mod)). Resolve package imports from the pinned module and package declarations, not the GitHub repository name.

## 4. Shared interaction contract

Maintain a small versioned contract with stable component/action/scenario IDs.
It describes observable behavior rather than serializing React nodes or an
application's complete screen tree. Each entry records its Kumo/source evidence,
required capabilities, state transitions, semantic outputs, permitted platform
differences and corresponding verification scenarios.

Generated variant/token facts and reviewed behavior rules have separate owners:
upstream data updates cannot silently rewrite reviewed UX expectations.

### Shell roles

Preserve the meanings in `docs/UX.md`:

- rail/sidebar: durable location and navigation;
- tabs: sibling views within one working context;
- main: required controls, the task, errors and primary results;
- context panel: optional support for the current task/selection;
- bottom bar: ambient status.

Optional regions remain optional. Required task controls stay available when
optional regions are absent. Stable IDs preserve selection and focus intent
when an equivalent region changes between docked and overlay presentations.

### Required scenarios

| Scenario | Shared observable outcome |
| --- | --- |
| Open navigation in compact layout | Navigation becomes visible and operable; focus enters an appropriate item; an open context drawer is dismissed |
| Choose a navigation destination | The active destination and main content agree; the compact drawer closes; focus moves to an appropriate destination target |
| Open/close contextual support | Main task state is preserved; overlay close/Escape restores focus to its trigger or a documented fallback if the trigger disappeared |
| Open/dismiss a modal overlay | While open, Tab/Shift+Tab stay within the modal and background controls cannot activate; an allowed outside interaction dismisses without click-through; visible close control and Escape have consistent semantics; hidden content cannot retain keyboard interaction; docked panels use nonmodal rules |
| Switch tabs | Focus and selection are distinguishable; arrow navigation and activation follow a documented policy on both targets; unrelated main-task state is preserved |
| Activate a control | A pointer or keyboard sequence emits the intended action once; disabled controls emit none; cancellation does not activate it |
| Submit asynchronous work | Pending state is visible; duplicate submission follows the declared policy; errors and retry stay with the task; success is perceivable without relying only on color |
| Edit text with IME | Composition, selection and committed input remain distinct; IME confirmation does not also submit a form; cancelling composition does not also dismiss its containing overlay |
| Resize or change display scale | Main content remains usable; selection is preserved; focus transfers safely if its presentation changes; hidden/removed controls cannot keep stale focus |
| Reduce motion or change theme | State remains understandable; nonessential animation respects preferences; focus/selection/error remain distinguishable |

Choose tab activation policy per declared pattern and latency requirements;
do not assume every tab set has the same automatic/manual activation behavior.
Translate logical actions such as primary-shortcut activation to platform keys
and publish those mappings in the fixture. An OS difference must be observable
and intentional rather than an unrecorded divergence.

## 5. Automated Kumo-to-gpui.mbt pipeline

1. **Pin the inputs.** Record exact Kumo package version and package integrity,
   verified source revision, package-manager lock, gpui.mbt revision/module
   version and generator/toolchain versions. Record the actual relation between
   the package artifact and source; matching version strings alone are
   insufficient. Keep package, registry-schema and UX-contract versions distinct.
2. **Extract upstream facts.** Use the shipped/generated component registry,
   theme config and `KUMO_*_VARIANTS` / `KUMO_*_DEFAULT_VARIANTS`; inventory actual
   exports and compound parts. Include relevant source/style/dependency hashes
   so behavior changes are noticed even when registry JSON is unchanged.
3. **Normalize and classify.** Retain token namespaces, theme and source
   provenance. Join extracted facts with reviewed behavior rules and a target
   capability map. Unknown selectors, units, props, compound parts and behavior
   changes produce explicit diagnostics and a compatibility task.
4. **Generate supported output.** Produce MoonBit enums/defaults/theme values,
   bindings to maintained native behavior adapters, fixture cases and a coverage
   report. Keep generated files separate from hand-maintained adapters. A clean
   regeneration must be deterministic and must not overwrite manual work.
5. **Verify both paths.** Exercise pinned React/Kumo and the actual native
   adapter with the same user-intent scenarios. Compare state, action counts,
   focus and semantic outputs; validate representative rendering separately.
6. **Prepare an update.** Package input pins, generated changes, additions or
   removals, behavior changes and evidence in a reviewable update PR. Reuse an
   existing candidate for the same input pair. Preserve the last qualified
   baseline while a new candidate fails or requires a capability not yet ready.

Upstream-update discovery may select a candidate automatically. Ordinary builds
must use committed pins without resolving `latest`. Scheduled checks belong to
the repository's automation once implemented.

### Extraction limits that affect correctness

Kumo's registry contains useful props, classes and state metadata, but it is not
a complete specification of browser or Base UI behavior. Optional/fallback
metadata and complex CSS require checking the real pinned implementation.
Focus management, popup dismissal, text editing and native accessibility need
maintained native adapters and observed qualification evidence.

Preserve `text` and `color` token namespaces, light/dark themes, CSS binding
resolution and color-space conversions. Do not infer complete styles from a
single class string. Document numeric color/unit conversion and any accepted
rendering tolerance; unsupported state selectors must remain visible in reports.

Relevant upstream inputs:

- [Theme configuration](https://github.com/cloudflare/kumo/blob/3d9331280781bf9ea67bb6c38321a7c6b98b0cee/packages/kumo/scripts/theme-generator/config.ts)
- [Binding CSS](https://github.com/cloudflare/kumo/blob/3d9331280781bf9ea67bb6c38321a7c6b98b0cee/packages/kumo/src/styles/kumo-binding.css)
- [Registry generator](https://github.com/cloudflare/kumo/blob/3d9331280781bf9ea67bb6c38321a7c6b98b0cee/packages/kumo/scripts/component-registry/index.ts), [variant parser](https://github.com/cloudflare/kumo/blob/3d9331280781bf9ea67bb6c38321a7c6b98b0cee/packages/kumo/scripts/component-registry/variant-parser.ts)

Preserve applicable upstream copyright/license notices alongside copied or
derived material and record provenance in generated output. Inspect each
redistributed dependency or asset's notices as part of adding that output.

## 6. Implementation slices and dependencies

| Slice | Deliverable | Completion evidence |
| --- | --- | --- |
| 1. Contract and web reference | Input pinning, inventory of actual Yami-kumo usage, shared scenario definitions, qualification of existing web shell behavior | Deterministic dependency install; rendered web interactions satisfy documented expectations; existing checks/build pass |
| 2. Extraction and generation foundation | Upstream manifest, explicit mapping/diagnostics, generated MoonBit tokens/variants and headless layout/event fixtures | Deterministic regeneration, drift detection, MoonBit compilation and headless conformance; reported as foundation only |
| 3. Usable native shell | Visible text and core controls; common shell roles; navigation, tabs, contextual support, focus and state feedback on one qualified native target | A real user can complete the same starter task on web and native; physical input and native semantics are verified |
| 4. Text and compound interactions | Input/IME, editable forms, dialogs, menus, selection controls and async feedback as real applications need them | Scenario-by-scenario web/native evidence including composition, cancellation, accessibility and recovery |
| 5. Continuous qualification | Automated upstream candidate PRs, capability/coverage reports, regression preservation, additional native platforms | One real upstream update is reproduced and qualified end to end; each advertised target has its own passing evidence |

Start component coverage with actual starter needs (`Button`, `Input`,
`LayerCard`, plus Yami-kumo's own shell controls). Add shared patterns when two
realistic applications need them, following the familiarity-first issue. This
order does not imply that Input/IME is available for the initial headless slice.

At the inspected gpui.mbt revision, the current native scene cannot supply a
complete text-bearing Kumo control. A rectangular placeholder or a passing
headless model must not mark a native Button/Input or usable AppShell complete.
Generation foundation work can proceed while framework capabilities develop.

Framework work stays linked to existing gpui.mbt packets:

- [0004: native/rendering/text/IME/accessibility boundaries](https://github.com/gpui-mbt/gpui.mbt/blob/bf965aebbeb1dfdfed26373d4a7a58bb51a5ad01/issues/open/0004-platform-rendering-and-native-boundaries.md)
- [0009: browser backend](https://github.com/gpui-mbt/gpui.mbt/blob/bf965aebbeb1dfdfed26373d4a7a58bb51a5ad01/issues/open/0009-browser-backend.md)
- [0011: hosted migration](https://github.com/gpui-mbt/gpui.mbt/blob/bf965aebbeb1dfdfed26373d4a7a58bb51a5ad01/issues/open/0011-electron-tauri-migration.md)
- [0019: native coexistence proof, currently planning only](https://github.com/gpui-mbt/gpui.mbt/blob/bf965aebbeb1dfdfed26373d4a7a58bb51a5ad01/issues/open/0019-mzed-native-coexistence-proof.md)

A standalone native Yami-kumo implementation does not require a same-window
island. A browser fixture that hosts original Kumo in a DOM island only qualifies
that web path; it cannot qualify generated native widgets.

## 7. Conformance and evidence

Track coverage by **target/platform + component/part + variant/state + scenario**.
Separate definition extraction, compilation, model/headless checks, rendering,
physical interaction and semantic accessibility evidence.

Each result records both upstream pins, contract/generator versions, scenario
ID, commands, actual result and artifact references. Use `PASS`, `FAIL`,
`UNRUN`, `BLOCKED` and `UNSUPPORTED` with explicit meanings. A planned or skipped
test is never `PASS`; a missing capability names its framework issue. An
unsupported required UX scenario prevents that target from being advertised as
qualified for the pattern.

Use several complementary checks:

1. **Contract properties:** generate action sequences for drawer exclusion,
   disabled controls, cancellation, duplicate activation, selection preservation
   and focus ownership, including modal focus containment and suppression of
   background activation. Check reviewed invariants independently of generated
   implementation expectations.
2. **Rendered web reference:** verify actual Kumo/DOM events and semantic roles,
   state and focus against the contract. A regression in the web implementation
   is a defect to fix, not a new native expectation.
3. **Native execution:** verify real window input and observable state/semantics,
   including resize, display scale, close/reopen and text composition as covered.
   Headless MoonBit tests remain a separate evidence level.
4. **Visual checks:** use deterministic geometry and screenshot comparisons with
   declared tolerances for fonts/antialiasing. Optional vlmkit checks can assess
   affordances but do not replace assertions for focus, action counts or IME.
   Record actual native driver/platform capability before using such a tool.
5. **Update fault cases:** exercise an added variant, removed prop, changed
   default and a behavior/dependency change without a registry change. Confirm
   that unsupported requirements are diagnosed and the qualified baseline stays
   reproducible.

## 8. Acceptance checklist

- [ ] Exact inputs and actual Yami-kumo component usage are recorded reproducibly.
- [ ] Shared shell/interaction scenarios are versioned and pass on the web reference.
- [ ] Regeneration produces the same output from the same inputs and preserves hand-maintained adapters.
- [ ] Unmapped behavior/props/style and missing framework capabilities are visible and cannot receive a false passing result.
- [ ] One native application completes the same declared starter task, with usable text, controls, focus and semantic feedback.
- [ ] Input is qualified only after text editing and Japanese IME scenarios pass on the advertised target.
- [ ] The update pipeline handles a real upstream candidate through extraction, generation, web/native verification and a reviewable PR.
- [ ] The compatibility report distinguishes platform, component, state and evidence level.
- [ ] `main` remains copy-ready, ordinary web development stays independent of native setup, and showcase changes stay on `demo`.
- [ ] Existing web checks/tests/build pass; native checks identify the commands and platforms actually exercised.

All implementation checkboxes are intentionally open in this planning change.
