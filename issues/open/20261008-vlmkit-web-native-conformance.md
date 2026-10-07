# Make vlmkit usable for Kumo-to-gpui.mbt qualification

Status: open — implementation specification, not an implemented integration
Updated: 2026-10-08
Parent: [Shared UX across Kumo and gpui.mbt](20261005-kumo-gpui-shared-ux.md)

## 1. Decision

Develop vlmkit as part of the Kumo-to-MoonBit pipeline, rather than limiting the
pipeline to whichever vlmkit capabilities happen to work today. Missing generic
observation, input, evidence or comparison capabilities belong in vlmkit; missing
native application primitives belong in gpui.mbt. Yami-kumo owns the Kumo-specific
contracts, fixtures, adapters and orchestration.

The first pipeline is upstream change collection, AI-assisted implementation,
shared qualification and an update PR. Successful translations subsequently
become deterministic conversion rules. A failing qualification must send useful
evidence back to the implementation agent. Fix maintained adapters, framework
primitives or conversion rules instead of patching generated output alone.

## 2. Inspected starting point

These are source observations, not newly executed tests or qualified dependency
pins. Reinspect the relevant revisions before implementation.

1. [vlmkit PR #2](https://github.com/f4ah6o/vlmkit/pull/2) is open and draft at
   `5583afe207456ca0d0a74ab0a85ac2c8a3fc6a96`. Its scope already includes native
   interaction sessions, grounding, interactions, snapshots, portable flows and
   a black-box GPUI/gpui.mbt acceptance runner. Reuse and complete this work; do
   not build a competing native driver.
2. The [native README at that revision](https://github.com/f4ah6o/vlmkit/blob/5583afe207456ca0d0a74ab0a85ac2c8a3fc6a96/native/macos/README.md)
   documents stable-id and role/name locators, distinct semantic and physical
   actions, screenshot/AX coordinates and `gpui_acceptance.mjs`.
3. The PR's restack report records portable validation, but explicitly leaves
   macOS live integration, real GPUI and multi-display qualification unresolved.
   Neither that report nor this specification qualifies physical input safety.
4. The parent Yami-kumo design PR was inspected at
   `b78a32ed9e129dfc4d2d1a6433fadddc6cb953d8`. It contains no implemented native
   generator or web/native conformance pipeline. Its historical gpui.mbt status
   observations must not be treated as a fresh capability audit.

## 3. Ownership

1. **vlmkit:** reusable browser/native execution boundaries, target capability
   reports, safe input, screenshot and semantic evidence, deterministic gates,
   normalized results and machine-readable failure reports. No Kumo or GPUI
   runtime dependency is introduced into the generic driver.
2. **Yami-kumo:** pinned web/native fixtures, component and scenario inventory,
   logical-to-target locator mappings, reviewed behavioral contracts, paired-run
   orchestration, allowed platform differences and conversion feedback.
3. **gpui.mbt:** public layout, drawing, text/IME, input, focus and accessibility
   primitives needed by actual native controls. Native acceptance must not be
   replaced by testing the original Kumo inside a browser or web view.

## 4. Shared scenario and evidence contract

Define a versioned, declarative scenario format. This section proposes an
interface; it does not claim an existing vlmkit CLI or schema supports it.

1. Each scenario has stable component, state, scenario and step IDs; reviewed
   preconditions and expected outcomes; required capabilities; and explicit
   web/native locator and logical-key mappings. Coordinates alone do not identify
   a control across targets. Ambiguous or missing targets stop that action.
2. Execute the same user intent against an isolated, pinned React/Kumo fixture
   and a real gpui.mbt native fixture. Reset fixture state for each run. The web
   path must independently satisfy the contract before it serves as a reference;
   two implementations making the same mistake must not qualify each other.
3. At checkpoints, capture the selected window or browser fixture, observable
   roles/names/values/states, focus owner, and observable action results/counts.
   Store screenshots, semantic observations and action evidence together.
   Semantic activation and physical pointer/keyboard execution are separate
   evidence lanes; one cannot stand in for the other.
4. A result records schema/contract/scenario hashes; Kumo package/source and
   dependency pins; Yami-kumo, gpui.mbt, vlmkit and generator revisions; platform,
   permissions and display profile; actual commands; step results; artifacts;
   and any observed environment error. Missing required evidence never passes.
5. Every failing step produces machine-readable location, expected and observed
   values, evidence references and a candidate repair owner. Distinguish an
   observed failure from a suspected cause. Candidate causes are not facts.

## 5. Comparison and qualification policy

Compare task outcomes, activation counts, selected/disabled state, focus and
accessibility semantics against reviewed expectations. Compare each target with
its own approved visual baseline; additionally compare declared cross-target
geometry, theme tokens and layout relationships with explicit tolerances.

Do not demand raw pixel equality between browser and native rendering. Browser
screenshots themselves can vary with OS, fonts and execution environment; see
[Playwright visual comparison guidance](https://playwright.dev/docs/test-snapshots).
Pin the relevant capture environment and record any intentional differences.
Do not hide a missing control or broken behavior behind a global image threshold.

Deterministic checks decide required behavior gates. Vision-model analysis may
explain a visual discrepancy or propose a repair; a model's similarity judgment
alone cannot make an unexecuted, incomplete or failing gate pass. Keep this
analysis optional so the deterministic lane does not require model API keys.

Use the parent's `PASS`, `FAIL`, `UNRUN`, `BLOCKED` and `UNSUPPORTED` states per
required lane. Only an explicit, complete set of passing required lanes can
qualify a target. Unknown output, missing artifacts, unsupported required input,
partial captures and timeouts prevent qualification. A retry retains evidence
of previous failures instead of silently converting flakiness into success.

## 6. Native safety and environment prerequisites

Before admitting native physical-input results as release evidence, demonstrate
that input reaches the selected window, not merely the right process. Exercise
another application's covering window, another window in the same application,
a non-key/background target, target movement/resize/exit and multi-display scale
changes. Either safely establish and verify the required target or fail closed;
never report a global event posting as proof that the target received it.

Run GUI input in a dedicated, serialized desktop session. Capture only explicit
fixture targets. Report Accessibility/Screen Recording permission failures,
missing helpers or missing browsers as environment failures; do not silently
request new permissions or fall back to another desktop/window. Missing
application accessibility is reported separately from a driver failure.

macOS is the first native paired target for this packet. Other platform lanes
retain their own capability and qualification status, rather than inheriting a
macOS pass or claiming equivalence from observation-only support.

## 7. Implementation order and acceptance

1. **Qualify the existing vlmkit native driver.** Build on PR #2, resolve remaining
   input-targeting and product review gates, and retain deterministic plus real
   macOS/GPUI/multi-display evidence. A draft source implementation is not enough.
2. **Run a Button pair end to end.** Use stable fixture IDs and controlled state.
   Verify one activation for pointer and keyboard input, no activation while
   disabled/loading, visible loading feedback and focus. Save both targets'
   evidence and deliberately introduce a defect to demonstrate a failing gate.
3. **Run a Dialog pair.** Verify open, modal focus containment, blocked background
   actions, Escape/close behavior, no click-through and focus restoration.
   Add Input/IME and shell scenarios only with their required capabilities.
4. **Integrate the candidate-update loop.** Pin inputs, run portable checks and
   isolated GUI lanes, retain artifacts, and return structured failures to the
   implementation agent. Repair the appropriate rule/adapter/primitive and rerun
   the same contract. Show one actual upstream candidate update being tested.
5. **Grow the converter from qualified patterns.** Unsupported syntax or behavior
   produces an explicit task; it is never silently omitted. The repair loop must
   not change expected outcomes, suppressions or approved baselines merely to
   obtain green results. Such changes require their own reviewed justification.

The smallest usable delivery is a real Web/native Button scenario with evidence
and a demonstrated regression failure, not a screenshot-only demo, a generated
placeholder, a passing mock or a new configuration file by itself. Ordinary web
starter checks must remain independent of a local native toolchain.

## 8. Validation of this change

This change adds the implementation requirement to the existing design branch.
It does not modify runtime code, add a CI workflow, launch an agent, merge PR #2,
publish a package or qualify any native target.

Application tests, paired scenarios and native GUI tests: **UNRUN** for this
specification. Historical PR-reported results in section 2 were not rerun here.
