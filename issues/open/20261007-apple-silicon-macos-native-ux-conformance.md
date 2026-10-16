# Apple Silicon macOS native shared-UX conformance

Status: open — partial Native Button exists; full platform UX, IME and external accessibility conformance unverified  
Updated: 2026-10-16 (JST)  
Parent: [Shared UX across Kumo and gpui.mbt](20261005-kumo-gpui-shared-ux.md)

## Basis and shared dependencies

The original parent [PR #3](https://github.com/f4ah6o/Yami-kumo/pull/3)
snapshot `b78a32ed9e129dfc4d2d1a6433fadddc6cb953d8` predates merged
Button [PR #24](https://github.com/f4ah6o/Yami-kumo/pull/24).
The parent's current evidence checkpoint records only a partial Button slice.
Full shared UX acceptance, the generator and platform Input/IME/AX support
remain open; passing builds cannot substitute for native interaction evidence.

Complete the parent's common pins, web reference and maintained adapter/scenario
contracts before qualifying this OS. Keep Kumo extraction, generated definitions
and update policy there; consume gpui.mbt public primitives without moving
Kumo-specific logic into the framework. A missing native capability is BLOCKED
or UNSUPPORTED, not a passing placeholder.

## macOS scope

**Apple Silicon / arm64 only; Intel is excluded.** Own native host mappings and
evidence for parent slices 3–5 on a named macOS/AppKit/Metal/SDK/font profile.

gpui.mbt's field [PR #40](https://github.com/gpui-mbt/gpui.mbt/pull/40)
remains open/draft; [palette follow-up #42](https://github.com/gpui-mbt/gpui.mbt/pull/42)
is merged as documentation, not proof of completed native UX. Resolve field/runner findings in their
existing work; do not duplicate them here. Native AX remains a framework gate.

## Acceptance

- [ ] An arm64 native shell completes the parent's starter task and shared
  navigation/tab/context/modal/state scenarios using maintained adapters.
- [ ] Publish macOS primary-shortcut mappings and verify focus containment/
  restoration, disabled controls, cancellation and one-shot actions without
  losing ordinary native text-editing behavior.
- [ ] An unlocked logged-in host exercises actual AppKit/Kotoeri
  composition/commit/cancel, blur/reopen and no IME confirmation/dismissal leak.
  Restore any app-owned input-source change and retain cleanup evidence.
- [ ] Native presentation/pixels and actual AX role/name/value/state/focus/action
  observations agree. Verify Retina logical/backing-pixel mapping; unrun display
  profiles remain unqualified.
- [ ] Record exact web/Kumo/gpui/generator, arm64/macOS/SDK/tool/font/app pins,
  scenario IDs and separate model/input/pixel/native-semantic results.
- [ ] Web checks and main/demo separation remain intact with no native setup
  dependency for ordinary template use.

An arm64 run does not qualify every macOS version or another OS. Missing AX or
other required UX capability cannot be substituted by a synthetic passing tree.
