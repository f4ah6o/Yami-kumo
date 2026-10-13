# Changes

## Unreleased

### Added

- Added a focused Mooncakes archive and package README for installing the pure MoonBit module `f4ah6o/yami_kumo`.
- Added a pure MoonBit module for safe HTML rendering, the semantic AppShell, and a pinned subset of Kumo Button, Input, Text, and LayerCard components.
- Added a canonical parity gallery that mounts real React Kumo and the compiled MoonBit renderer independently across component matrices and interaction states.
- Added an independent native MoonBit UI module for measured Text, interactive Button, Card, and semantic AppShell components across macOS, Linux, and Windows GPUI hosts.
- Added Kumo Input disabled, focus, dirty, filled, touched, and Enter-triggered validity states, with dynamic state decisions kept in MoonBit over narrow browser DOM primitives.
- Included the upstream Kumo license alongside the redistributed standalone stylesheet.

### Changed

- Pinned `@cloudflare/kumo` to `2.14.0` so generated class and stylesheet contracts remain reproducible.
- Bumped the native module to `0.2.4` against GPUI `0.7.1`; its macOS sample now waits for guarded external host input instead of in-process test events.
- Made the macOS native UI runner fail closed on locked or unknown console sessions and record blocked preflight evidence before launching the sample.

### Fixed

### Deprecated

### Removed

### Security

- Escaped text and attribute values, restricted element and attribute names, and removed inline styles from generated button markup for strict Content Security Policy compatibility.

### Migration

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
