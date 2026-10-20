# Changes

## 0.1.1 - 2026-10-13

### Added

- Added bounded property-based tests for text and title-attribute HTML escaping.

### Fixed

- Resolve the compiled renderer URL directly so the Windows smoke handles drive-letter paths.
- Keep generated Kumo contract code in MoonBit's canonical formatted layout.
- Format the package README example as valid MoonBit code blocks.

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
- Bumped the native module to `0.2.6` against GPUI `0.10.1` and pure MoonBit module `0.2.0`; the native adapter now paints and edits a measured TextField and consumes host composition events. The macOS sample runner revalidates the target before each event, bounds AX/helper lifetimes, and uses zero-modifier input. The external input route remains runtime-unqualified.
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
