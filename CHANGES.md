# Changes

## Unreleased

### Added

- Added a pure MoonBit module for safe HTML rendering, the semantic AppShell, and a pinned subset of Kumo Button, Input, Text, and LayerCard components.
- Added a canonical parity gallery that mounts real React Kumo and the compiled MoonBit renderer independently across component matrices and interaction states.
- Added MoonBit-owned Input focus state behavior over narrow browser DOM primitives.

### Changed

- Pinned `@cloudflare/kumo` to `2.14.0` so generated class and stylesheet contracts remain reproducible.

### Fixed

### Deprecated

### Removed

### Security

- Escaped text and attribute values, restricted element and attribute names, and removed inline styles from generated button markup for strict Content Security Policy compatibility.

### Migration
