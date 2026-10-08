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

### Fixed

### Deprecated

### Removed

### Security

- Escaped text and attribute values, restricted element and attribute names, and removed inline styles from generated button markup for strict Content Security Policy compatibility.

### Migration
