# Windows native shared-UX conformance

- Status: open — partial Native Button exists; full platform UX, IME and
  external accessibility conformance unverified.
- Updated: 2026-10-16 (JST)
- Parent: [Shared UX across Kumo and gpui.mbt](20261005-kumo-gpui-shared-ux.md)

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

## Windows scope

Own Windows mappings and native evidence for parent slices 3–5. This records the
existing eventual Windows target; it does not schedule implementation or relax
project priority/environment gates.

gpui.mbt's experimental Win32/DirectWrite/D3D11 field foundation is merged
through [PR #39](https://github.com/gpui-mbt/gpui.mbt/pull/39). Real Japanese
IME and UI Automation remain unqualified. The merged
[palette follow-up #42](https://github.com/gpui-mbt/gpui.mbt/pull/42)
is tracking documentation, not host acceptance. Existing renderer/startup
passes do not qualify this shell. Recheck pins and capabilities before
adopting the native path.

## Acceptance

- [ ] One native shell completes the parent's starter task and shared
  navigation/tab/context/modal/state scenarios through maintained adapters.
- [ ] Publish Windows shortcut/focus mappings; verify disabled controls,
  cancellation, contained modal focus/restoration and one-shot actions.
- [ ] Actual Win32 keyboard/pointer and the declared Japanese IME exercise
  composition/commit/cancel and blur/reopen without background leak-through.
- [ ] Native frames/pixels and actual UI Automation role/name/value/state/focus/
  action evidence agree. Declare and test logical/physical coordinates at the
  claimed DPI; unrun display/GPU/version profiles remain unqualified.
- [ ] Record exact web/Kumo/gpui/generator/tool/font/app and Windows/SDK/DPI/GPU
  pins, scenario IDs and separate model/input/pixel/native-semantic results.
- [ ] Keep web checks and main/demo separation intact; template users require
  no Windows-native setup for ordinary web development.

Compilation, synthetic state and a successful standalone field are insufficient.
Close only for a declared Windows profile with the required framework gates.
