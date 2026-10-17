# Shared GPUI source revision qualification

This dependency-only step advances `tests/shared-ui/gpui-revision.txt` from
`a94837973eb0757aebc563e4b836d462db9947a0` to merged GPUI source revision
`4c2e525f02c00a9c1a560152a914f523a4c2fe47` (tree
`ed9386f350af8d63804b189f9b00853df6cf8c28`). The Yami baseline is
`5297084c8f6c45bf413efc05a06d84908424e056`.

The advance spans 18 commits including merges, covering grid/query, text
sessions, modal focus, anchor and paint palette work. Scene, primitives and
native renderer sources are unchanged across this advance, but element/layout
lifecycle and hit ordering changed. Existing consumer behavior therefore needs
fresh qualification; prior slice evidence remains historical, not proof of this
new dependency combination.

## Scope and preserved contracts

Only the shared source-workspace proof adopts this revision. No adapter, public
API, application model, fixture, oracle, stylesheet, workflow, package version or
compiler pin changes here. Existing bindings, geometry, paint and count
expectations remain the acceptance criteria. This does not adopt per-Button
palette behavior or implement theme support.

The separate legacy native proof retains
`tests/native-ui/gpui-revision.txt` at
`c7d9e393b7a6492484f72fbace873023647da8fb`. The published native dependency in
`native/moon.mod` remains `gpui@0.7.2`; a source-workspace result is not a new
published-package compatibility claim.

## Required qualification gates

Qualification requires green checks and an independent review of the exact
final candidate and retained artifacts, with no blocking findings:

- Actual adapter and shared-counter portable tests on JS, native, wasm and
  wasm-gc, in debug and release, using the new exact GPUI source revision;
  native host-package portable tests and Python native-oracle tests.
- Existing pure/common tests, independent JS/native source consumers, boundary,
  geometry, compile-negative, inert-import and CSP checks. The root CI compiler
  remains `0.10.14+7d59c7ec9` for unchanged common APIs/DOM; independent
  consumers compile only neutral packages, excluding GPUI. The advanced GPUI
  adapter/native host lanes use `0.10.15+943464bfa`. Local results with that
  compiler cannot replace the root compiler CI gate.
- Actual Chromium and all four shared fixtures on Linux Wayland and Windows
  D3D11: counter, disabled/loading Button, Card and stack spacing. Audit the
  exact Yami/GPUI provenance, counts, bindings, geometry, paint/scene evidence,
  real host input, frame artifacts and cleanup against existing assertions.
- The macOS shared build/portable-test lane, explicitly build-only for native
  window behavior, and the unchanged legacy native lane. All existing jobs in
  the three workflows must pass on the final candidate.

Local checks are preparation only. Actual-host and browser qualification is
pending final-head CI and independent artifact review; this note does not assert
those runs have passed. Local cloud Chromium is NOT_RUN under the established
sandbox restriction, without a local-browser workaround. Synthetic native events
and Python oracle tests are not OS runtime proof. macOS runtime, external
accessibility providers, IME, physical hardware, Firefox/Safari, general layout
parity, full YK-05, M2 and the four-platform MVP remain unqualified.
