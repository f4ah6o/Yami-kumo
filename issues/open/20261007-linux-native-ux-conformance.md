# Linux native shared-UX conformance

Status: open — partial Native Button exists; full platform UX, IME and external accessibility conformance unverified  
Updated: 2026-10-07 (JST)  
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

## Linux scope

Own the Linux implementation/evidence for parent slices 3–5. Name the actual
compositor, protocol/input method, renderer, toolkit/font and scale profile;
X11, XWayland and Wayland results are separate.

The gpui.mbt Linux field/IME foundations are bounded. Yami-kumo
[PR #24](https://github.com/f4ah6o/Yami-kumo/pull/24) produced 6 Linux-host
cases/48 phases for the enabled Primary Button subset, not complete native
keyboard/IME, external AT-SPI or device-profile evidence. Its reusable palette
[PR #41](https://github.com/gpui-mbt/gpui.mbt/pull/41) is merged, but does
not by itself qualify complete Yami-kumo UX. Native AT-SPI and broader controls are separate
framework prerequisites. Recheck reviewed pins when integration starts.

## Acceptance

- [ ] One real native shell completes the parent's declared starter task and
  shared navigation/tab/context/modal/state scenarios through maintained adapters.
- [ ] Publish Linux shortcut mappings and verify focus containment/restoration,
  disabled controls, cancellation, one-shot activation and safe resize/scale edits.
- [ ] Actual native keyboard/pointer and the named Japanese IME exercise
  composition/commit/cancel, blur/reopen and no confirmation/dismissal leak.
- [ ] Retained pixels and actual AT-SPI role/name/value/state/focus/action evidence
  agree with observable behavior. Portable semantics alone cannot pass this gate.
- [ ] Record exact web/Kumo/gpui/generator/tool/runtime/font pins and scenario IDs,
  commands and evidence levels. Keep X11/Wayland/scale coverage and
  PASS/FAIL/UNRUN/BLOCKED/UNSUPPORTED distinct.
- [ ] Web checks and the main/demo boundary remain intact; ordinary template
  development does not require native setup.

No Linux, framework or full-UX support claim follows from compilation or the
standalone palette alone. Close only for the declared native profile.
