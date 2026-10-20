# Changes

## native-0.2.9 - 2026-10-20

### Changed

- Replace the adapter-local modal filter in the native Dialog with the live
  `element.FocusScopeSession`. Input admission, Tab trapping, dismissal and
  opener restoration now come from the session; a rebuilt frame adopts its new
  tree while keeping the open scope, so a Dialog survives a view topology change
  without losing focus. Removing the Dialog from the view restores the opener
  and cancels a removed field's composition through the session boundary hook.
- Pin GPUI `0.10.3`.

## native-0.2.8 - 2026-10-20

### Added

- Add a bounded native Dialog overlay: second root, backdrop and panel paint,
  initial focus, dialog-local Tab, Escape/backdrop dismissal, background
  filtering and opener restoration. Nested Dialogs remain unsupported and real
  OS IME and accessibility remain `NOT_RUN`.

## 0.1.1 - 2026-10-13

### Added

- Added bounded property-based tests for text and title-attribute HTML escaping.

### Fixed

- Resolve the compiled renderer URL directly so the Windows smoke handles drive-letter paths.
- Keep generated Kumo contract code in MoonBit's canonical formatted layout.
- Format the package README example as valid MoonBit code blocks.

## native-0.2.7 - 2026-10-20

### Fixed

- Include `ui/` in the native Mooncakes archive. Native `0.2.6` omitted the
  TextField adapter package that its own examples and consumers import.

## 0.2.2 - 2026-10-20

### Fixed

- Include the `examples/shared_counter` and `examples/shared_button_theme`
  packages in the Mooncakes archive so the native module can resolve them.

## 0.2.1 - 2026-10-20

### Fixed

- Include the `ui/` packages in the Mooncakes archive. `0.2.0` omitted them,
  so the native module could not resolve `f4ah6o/yami_kumo/ui/core`.

## 0.2.0 - 2026-10-20

### Added

- Added the shared `TextField` semantic View, a DOM `<input>` adapter with
  committed-value-only composition handling, and a native adapter with a
  measured single-line field, click/focus, focus restoration on blur, caret
  movement, editing, submit, host composition events, focus restoration and a
  host-drained clipboard request seam through `controls/text_field`. Native
  Dialog remains rejected with `UnsupportedCapability`. Real OS IME and accessibility
  qualification remain `NOT_RUN`; `text_session` ownership is not wired yet.
- Added the shared `Dialog` semantic View and DOM `<dialog>` adapter with
  top-layer modal behavior, Escape dismissal, initial focus and native focus
  restoration. A non-dismissible dialog ignores Escape, and the native adapter
  returns `UnsupportedCapability`.
- Added the additive shared AppShell region model, DOM semantic wrappers, GPUI
  flex layout, compact stacked layout, shell surface/text/Card theme tokens, and
  bounded DOM/native tests. Local macOS visible wide/compact rendering, CGEvent
  pointer activation and AXPress on the main Increment Button passed; CI also
  passed Linux Wayland and Windows SendInput shell pointer/render fixtures.
  Physical hardware input and a complete shell AX tree remain unverified.
- Added a focused Mooncakes archive and package README for installing the pure MoonBit module `f4ah6o/yami_kumo`.
- Added a pure MoonBit module for safe HTML rendering, the semantic AppShell, and a pinned subset of Kumo Button, Input, Text, and LayerCard components.
- Added a canonical parity gallery that mounts real React Kumo and the compiled MoonBit renderer independently across component matrices and interaction states.
- Added an independent native MoonBit UI module for measured Text, interactive Button, Card, and semantic AppShell components across macOS, Linux, and Windows GPUI hosts.
- Added Kumo Input disabled, focus, dirty, filled, touched, and Enter-triggered validity states, with dynamic state decisions kept in MoonBit over narrow browser DOM primitives.
- Included the upstream Kumo license alongside the redistributed standalone stylesheet.

### Changed

- Pinned `@cloudflare/kumo` to `2.14.0` so generated class and stylesheet contracts remain reproducible.
- Bumped the native module to `0.2.6` against GPUI `0.10.2` and pure MoonBit module `0.2.2`; the native adapter now paints and edits a measured TextField and consumes host composition events. The macOS sample runner revalidates the target before each event, bounds AX/helper lifetimes, and uses zero-modifier input. The external input route remains runtime-unqualified.
- Made the macOS native UI runner fail closed on locked or unknown console sessions and record blocked preflight evidence before launching the sample.
- Expose the native Button's pressed phase on sample frames and keep held pointer/key state through same-bounds repaint; focus loss and layout changes still cancel.
- Align native Button keyboard phases with pinned Kumo: focused enabled Enter activates on every key-down, including repeats, while Space stays pressed through repaint and activates on matching key-up.

### Fixed

- Make guarded macOS input cleanup preserve pending event ownership and report teardown failures instead of passing qualification after an incomplete release.

### Deprecated

### Removed

### Security

- Escaped text and attribute values, restricted element and attribute names, and removed inline styles from generated button markup for strict Content Security Policy compatibility.
- Revalidate the full macOS target snapshot before every global input post, bound AX queries and helper lifetime, and clear inherited modifier flags in the native UI sample helper.

### Migration

- Native `ButtonInteraction::key_down` now returns `Bool`; callers must handle `true` as an immediate Enter activation. `NativeSample::handle_input` and Web APIs are unchanged.

## native-0.2.4 - 2026-10-13

### Changed

- Bumped `f4ah6o/yami_kumo_native` to `0.2.4` against GPUI `0.7.1` and pure MoonBit module `f4ah6o/yami_kumo` `0.1.1`; native APIs and platform proof scope are unchanged.

## native-0.2.3 - 2026-10-11

### Added

- Added a Windows copied Button accessibility projection with source-owner and layout-generation revalidation; native UI Automation transport remains unsupported.

### Changed

- Bumped native module `f4ah6o/yami_kumo_native` to `0.2.3` against GPUI `0.7.0`.

## native-0.2.2 - 2026-10-11

### Added

- Added a macOS accessibility action to the native sample Button; AXPress updates the sample's existing click counter.

### Changed

- Bumped the native MoonBit module `f4ah6o/yami_kumo_native` to `0.2.2` against GPUI `0.5.0`.

### Fixed

- Made the Windows native UI runner select Git for Windows Bash, preserve shell-script LF endings, and check for usable Python 3.11+ and MSVC tools before building.

## native-0.2.0 - 2026-10-10

### Added

- Added a hosted macOS build and portable-test lane for the native MoonBit module; it builds the example without launching a GUI.

### Changed

- Released native MoonBit module `f4ah6o/yami_kumo_native` at `0.2.0` against GPUI `0.3.0`; its package README and MIT license originate in upstream PR #9.
- The macOS native runner invokes GPUI's Bash-shebang build script with `bash`.
- Native/LLVM builds require Python 3 for GPUI's macOS framework-link prebuild; resulting applications have no Python runtime dependency.
