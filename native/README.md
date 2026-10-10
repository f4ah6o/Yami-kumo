# Native MoonBit UI components

`f4ah6o/yami_kumo_native` is an independent MoonBit module. It imports the
existing `f4ah6o/yami_kumo` enums and the portable layout,
element, text-measurement, and scene APIs from gpui. The root Web module does
not depend on this module, and its HTML/CSS APIs are unchanged.

Install the native module with:

```sh
moon add f4ah6o/yami_kumo_native
```

Building this module for MoonBit's native/LLVM targets requires Python 3
(`python3`) on `PATH`. GPUI 0.3.0 runs a Python prebuild during compilation to
propagate macOS CoreText framework link settings. Python is needed only while
building; the resulting application has no Python runtime dependency.

The module source is MIT licensed; the package includes [LICENSE](LICENSE).

The first native slice provides measured plain `NativeText`, square `NativeButton`
surfaces and interaction state, a rectangular `NativeCard`, and a semantic
`NativeAppShell` with header and main layout slots. The shared sample, Entity
state, Flex layout, hit testing, pointer and keyboard activation are common to
all three host entrypoints in `examples/`.

## Platform status

| Host    | Text measurement and display                                 | Native UI proof                                                                                                                                                                                                                  |
| ------- | ------------------------------------------------------------ | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| macOS   | CoreText measurement and Metal scene presentation            | Previously passed local E2E: a test-only synthetic NSEvent goes through the owned NSWindow's normal `sendEvent:` route; frame readback confirms the count update, and the lifecycle marker confirms window destruction.         |
| Linux   | Pango system-sans measurement and the GPUI Wayland host      | Passed hosted E2E: XTest input is delivered through Xvfb and Weston's X11 backend, with completed-frame readback. The runner pins both generic sans aliases to the same DejaVu Sans file for matching measurement and rendering. |
| Windows | DirectWrite `Segoe UI` measurement and the GPUI Windows host | Passed hosted E2E: Win32 `SendInput` targets the uniquely titled visible HWND, with completed-frame readback.                                                                                                                    |

The hosted macOS lane builds GPUI's test-hook library, runs the CoreText and
shared native package tests, and compiles the Yami macOS sample. It does not
launch a window or exercise runtime rendering or input, so it is build and
portable-test evidence rather than a hosted native UI proof.

The local macOS proof passed on Yami `086cfd1` with approved GPUI candidate
`ae45429`; its tree is identical to merged GPUI revision
`2c6e9a3df469922f79d7b2b8eb977a0524086486`. Hosted Linux and Windows proofs
passed in [native UI CI run 37808645019](https://github.com/f4ah6o/Yami-kumo/actions/runs/37808645019)
on those same source trees.

These checks cover labeled Text and Button rendering, readback of a completed
native frame, and a host-delivered click that changes the sample's App Entity
and counter text. Headless tests and cross-compilation alone do not count as a
native UI pass. The macOS input is a GPUI test-hook NSEvent, while Linux and
Windows use host-delivered XTest and Win32 `SendInput`; none of these checks
claims physical-hardware input coverage. They do not qualify a native text
editor or an Input component. The browser `Input` API remains separate.

## Kumo visual subset

Colors are derived from the pinned `styles/kumo-standalone.css` generated from
Kumo `2.14.0`. OKLCH tokens are converted through OKLab to linear sRGB, gamma
encoded, clamped, and rounded to the nearest 8-bit channel. Alpha is rounded
separately; the light control-line token's 10% opacity becomes alpha 26.

| Role / source token                                                        | Light RGBA          | Dark RGBA           |
| -------------------------------------------------------------------------- | ------------------- | ------------------- |
| Base canvas: white / `kumo-neutral-925` at 17%                             | `(255,255,255,255)` | `(15,15,15,255)`    |
| Elevated surface: `kumo-neutral-75` at 98% / `kumo-neutral-975` at 12%     | `(248,248,248,255)` | `(6,6,6,255)`       |
| Default text: `neutral-900` at 20.5% / `neutral-100` at 97%                | `(23,23,23,255)`    | `(245,245,245,255)` |
| Subtle text: `neutral-500` / `neutral-400`                                 | `(115,115,115,255)` | `(161,161,161,255)` |
| Link and generated `TextVariant::Success` mapping: `blue-800` / `blue-400` | `(25,60,184,255)`   | `(81,162,255,255)`  |
| Error and `SecondaryDestructive` text: `red-700` / `red-400`               | `(193,0,7,255)`     | `(255,100,103,255)` |
| Destructive control fill: `red-500` / `red-600`                            | `(251,44,54,255)`   | `(231,0,11,255)`    |
| Brand fill: `kumo-brand`                                                   | `(5,109,255,255)`   | `(0,90,235,255)`    |
| Hairline: `kumo-neutral-150` / `neutral-800`                               | `(233,233,233,255)` | `(38,38,38,255)`    |
| Control line: black at 10% / `kumo-neutral-750`                            | `(10,10,10,26)`     | `(51,51,51,255)`    |

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

The GPUI host capabilities differ by platform. The [macOS host guide](https://github.com/gpui-mbt/gpui.mbt/blob/2c6e9a3df469922f79d7b2b8eb977a0524086486/docs/macos-native.md)
covers bounded single-line measurement and drawing; a native editor and IME
are not implemented. The [Ubuntu text-field guide](https://github.com/gpui-mbt/gpui.mbt/blob/2c6e9a3df469922f79d7b2b8eb977a0524086486/docs/linux-text-field.md)
documents an experimental single-line LTR field with caret, selection, undo,
and a private direct-keyboard route. Public `TextInput` and IME transport are
not supported; the [Wayland IME transport](https://github.com/gpui-mbt/gpui.mbt/blob/2c6e9a3df469922f79d7b2b8eb977a0524086486/docs/ubuntu-ime.md)
is private opt-in work and is not qualified. The [Windows host guide](https://github.com/gpui-mbt/gpui.mbt/blob/2c6e9a3df469922f79d7b2b8eb977a0524086486/docs/windows-native.md)
describes a focused single-line field and a private, default-off IMM32 session;
real Japanese IME and candidate-window behavior are not qualified.

Before exposing `NativeInput`, Yami needs shared focus and edit ownership plus
per-platform committed-text, composition, and caret integration with separate
tests. The native Button click/frame proof above does not qualify text input or
IME support.

## Maintainer checks

These checks use scripts in the Yami source repository and are for maintainers;
they are not required when consuming the published module. The cross-platform
native UI scripts create a temporary Moon workspace that
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

The hosted macOS build and portable checks can be run locally without opening
the sample window:

```sh
GPUI_SOURCE=/path/to/gpui.mbt sh "$YAMI_SOURCE/scripts/native_ui_macos.sh" --build-and-test
```

On Windows, run `scripts/native_ui_windows.ps1` from PowerShell with the native
MoonBit toolchain and Visual C++ build tools installed. The host-specific E2E
scripts build and run `examples/{macos,ubuntu,windows}`; they save native PPM
captures and logs in `_build/native-ui/<platform>` by default. The Linux run
requires Xvfb, Weston, XTest/`xdotool`, and the GPUI Wayland dependencies;
macOS requires Xcode command-line tools.
