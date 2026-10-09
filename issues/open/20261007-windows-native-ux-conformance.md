# Windows native shared-UX conformance

Status: open — native adapters and UX conformance not implemented  
Updated: 2026-10-07 (JST)  
Parent: [Shared UX across Kumo and gpui.mbt](20261005-kumo-gpui-shared-ux.md)

## Basis and shared dependencies

Parent [PR #3](https://github.com/f4ah6o/Yami-kumo/pull/3), inspected head
`b78a32ed9e129dfc4d2d1a6433fadddc6cb953d8`, remains an unmerged design.
Its passing checks/tests/build do not establish the parent's rendered web
reference or native scenarios. Generation and native adapters remain unimplemented.

Complete the parent's common pins, web reference and maintained adapter/scenario
contracts before qualifying this OS. Keep Kumo extraction, generated definitions
and update policy there; consume gpui.mbt public primitives without moving
Kumo-specific logic into the framework. A missing native capability is BLOCKED
or UNSUPPORTED, not a passing placeholder.

## Windows scope

Own Windows mappings and native evidence for parent slices 3–5. This records the
existing eventual Windows target; it does not schedule implementation or relax
project priority/environment gates.

gpui.mbt's experimental Win32/DirectWrite/D3D11 field foundation is merged through
[PR #39](https://github.com/gpui-mbt/gpui.mbt/pull/39). Its real Japanese IME,
UI Automation and [palette follow-up](https://github.com/gpui-mbt/gpui.mbt/pull/42)
remain unqualified. Existing renderer/startup passes do not qualify this shell.
Recheck framework pins and capabilities before adopting the native path.

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
