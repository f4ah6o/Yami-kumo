# Native MoonBit UI preview

`native/` is an independent MoonBit module named `f4ah6o/yami_kumo_native`.
It imports the existing `f4ah6o/yami_kumo` enums and the portable layout,
element, text-measurement, and scene APIs from gpui. The root Web module does
not depend on this module, and its HTML/CSS APIs are unchanged.

The first native slice provides measured plain `NativeText`, square `NativeButton`
surfaces and interaction state, a rectangular `NativeCard`, and a semantic
`NativeAppShell` with header and main layout slots. The shared sample, Entity
state, Flex layout, hit testing, pointer and keyboard activation are common to
all three host entrypoints in `examples/`.

## Platform status

| Host | Text measurement and display | Input proof |
| --- | --- | --- |
| macOS | CoreText measurement and Metal scene presentation | Local E2E sends a test-only NSEvent through the owned NSWindow's normal `sendEvent:` route. This is synthetic native input, not physical hardware. |
| Linux | Pango system-sans measurement and the GPUI Wayland host | Configured CI proof sends input through XTest, Xvfb and Weston's X11 backend. |
| Windows | DirectWrite `Segoe UI` measurement and the GPUI Windows host | Configured CI proof sends input to the uniquely titled visible HWND with Win32 `SendInput`. |

The local macOS end-to-end proof passed for this change. The hosted Linux and
Windows proof jobs are configured, but their runs for this change are still
pending.

These checks cover labeled Text and Button rendering, readback of a completed
native frame, and a host-delivered click that changes the sample's App Entity
and counter text. They do not qualify a native text editor or an Input
component. The browser `Input` API remains separate.

## Kumo visual subset

Colors are derived from the pinned `styles/kumo-standalone.css` generated from
Kumo `2.14.0`. OKLCH tokens are converted through OKLab to linear sRGB, gamma
encoded, clamped, and rounded to the nearest 8-bit channel. Alpha is rounded
separately; the light control-line token's 10% opacity becomes alpha 26.

| Role / source token | Light RGBA | Dark RGBA |
| --- | --- | --- |
| Base canvas: white / `kumo-neutral-925` at 17% | `(255,255,255,255)` | `(15,15,15,255)` |
| Elevated surface: `kumo-neutral-75` at 98% / `kumo-neutral-975` at 12% | `(248,248,248,255)` | `(6,6,6,255)` |
| Default text: `neutral-900` at 20.5% / `neutral-100` at 97% | `(23,23,23,255)` | `(245,245,245,255)` |
| Subtle text: `neutral-500` / `neutral-400` | `(115,115,115,255)` | `(161,161,161,255)` |
| Link and generated `TextVariant::Success` mapping: `blue-800` / `blue-400` | `(25,60,184,255)` | `(81,162,255,255)` |
| Error and `SecondaryDestructive` text: `red-700` / `red-400` | `(193,0,7,255)` | `(255,100,103,255)` |
| Destructive control fill: `red-500` / `red-600` | `(251,44,54,255)` | `(231,0,11,255)` |
| Brand fill: `kumo-brand` | `(5,109,255,255)` | `(0,90,235,255)` |
| Hairline: `kumo-neutral-150` / `neutral-800` | `(233,233,233,255)` | `(38,38,38,255)` |
| Control line: black at 10% / `kumo-neutral-750` | `(10,10,10,26)` | `(51,51,51,255)` |

The native renderer uses plain system sans text and solid quads. It intentionally
does not claim Kumo gradients, rounded corners, shadows, font-weight variants,
or the browser's color-mix compositing. The fixed system-sans text pipeline
rejects `Mono` and `MonoSecondary` instead of measuring with one font and
rendering with another. Measured text items keep the complete copied
`TextMeasurement` and use the union of logical and ink bounds, including
negative glyph overhangs.

Component IDs are caller-owned. A Text uses its ID. A Card reserves `id..id+4`
for its fill and border; a Button reserves `id..id+5` for its background,
label, and border. Keep those ranges disjoint from every other scene item in a
snapshot.

## Input and IME follow-up

Button activation is implemented in MoonBit: a matching primary down/up pair
activates once; Enter/Space use matching key-down/key-up while the Button owns
focus. Disabled controls, an outside primary release, focus loss, and layout
invalidation cancel pending gestures. This does not establish text editing or
IME behavior.

The GPUI host capabilities differ by platform. The [macOS host guide](https://github.com/gpui-mbt/gpui.mbt/blob/31c6d86530fb8c99545484a92d15eb85170629d3/docs/macos-native.md)
covers bounded single-line measurement and drawing; a native editor and IME
are not implemented. The [Ubuntu text-field guide](https://github.com/gpui-mbt/gpui.mbt/blob/31c6d86530fb8c99545484a92d15eb85170629d3/docs/linux-text-field.md)
documents an experimental single-line LTR field with caret, selection, undo,
and a private direct-keyboard route. Public `TextInput` and IME transport are
not supported; the [Wayland IME transport](https://github.com/gpui-mbt/gpui.mbt/blob/31c6d86530fb8c99545484a92d15eb85170629d3/docs/ubuntu-ime.md)
is private opt-in work and is not qualified. The [Windows host guide](https://github.com/gpui-mbt/gpui.mbt/blob/31c6d86530fb8c99545484a92d15eb85170629d3/docs/windows-native.md)
describes a focused single-line field and a private, default-off IMM32 session;
real Japanese IME and candidate-window behavior are not qualified.

Before exposing `NativeInput`, Yami needs shared focus and edit ownership plus
per-platform committed-text, composition, and caret integration with separate
tests. The native Button click/frame proof above does not qualify text input or
IME support.

## Checks

The cross-platform native UI scripts create a temporary Moon workspace that
links the Yami and gpui checkouts without adding a local workspace manifest to
either repository. From the Yami-kumo repository root, set `GPUI_SOURCE` when
the GPUI checkout is not the sibling `../gpui.mbt`:

```sh
YAMI_SOURCE=$PWD
GPUI_SOURCE=/path/to/gpui.mbt sh "$YAMI_SOURCE/scripts/native_ui_workspace.sh" \
  sh "$YAMI_SOURCE/scripts/native_ui_tests.sh"
GPUI_SOURCE=/path/to/gpui.mbt sh "$YAMI_SOURCE/scripts/native_ui_macos.sh"
GPUI_SOURCE=/path/to/gpui.mbt sh "$YAMI_SOURCE/scripts/native_ui_linux.sh"
```

On Windows, run `scripts/native_ui_windows.ps1` from PowerShell with the native
MoonBit toolchain and Visual C++ build tools installed. The host-specific E2E
scripts build and run `examples/{macos,ubuntu,windows}`; they save native PPM
captures and logs in `_build/native-ui/<platform>` by default. The Linux run
requires Xvfb, Weston, XTest/`xdotool`, and the GPUI Wayland dependencies;
macOS requires Xcode command-line tools.
