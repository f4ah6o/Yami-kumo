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
(`python3`) on `PATH`. GPUI 0.7.1 runs a Python prebuild during compilation to
propagate macOS CoreText framework link settings. Python is needed only while
building; the resulting application has no Python runtime dependency.

Windows native builds also require the Visual C++ compiler and SDK on `PATH`.
Run the build from a Visual Studio Developer PowerShell, or initialize the
environment with `VsDevCmd.bat -arch=x64 -host_arch=x64` before running the
Windows validation script. The script locates Git Bash from Git for Windows,
checks for an importable Python 3.11 or newer interpreter, and ignores Windows
Store execution aliases. Set `YAMI_GIT_BASH` to `bash.exe` if automatic Git
discovery cannot find it. Set `YAMI_PYTHON_PATH` to the executable when it is
not on `PATH`; the script temporarily provides a `python3` forwarder so Moon's
prebuild uses that interpreter without relocating it. Pass `-TestsOnly` to run
the native package tests without opening the visible sample window.
The runner checks argument boundaries, stdout, stderr, and exit status through the forwarder before running native tests.

The module source is MIT licensed; the package includes [LICENSE](LICENSE).

The first native slice provides measured plain `NativeText`, square `NativeButton`
surfaces and interaction state, a rectangular `NativeCard`, and a semantic
`NativeAppShell` with header and main layout slots. The shared sample, Entity
state, Flex layout, hit testing, pointer and keyboard activation are common to
all three host entrypoints in `examples/`.

## Platform status

| Host    | Text measurement and display                                 | Native UI proof                                                                                                                                                                                                                                                                       |
| ------- | ------------------------------------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| macOS   | CoreText measurement and Metal scene presentation            | Local pointer E2E uses a test-only synthetic NSEvent through the owned NSWindow. The separate `--ax-proof` checks the sample Button's AXPress action and same-owner counter update through `AXUIElement`; neither proof covers general widget accessibility or text input.            |
| Linux   | Pango system-sans measurement and the GPUI Wayland host      | Passed hosted E2E: XTest input is delivered through Xvfb and Weston's X11 backend, with completed-frame readback. The runner pins both generic sans aliases to the same DejaVu Sans file for matching measurement and rendering.                                                      |
| Windows | DirectWrite `Segoe UI` measurement and the GPUI Windows host | Passed hosted E2E: Win32 `SendInput` targets the uniquely titled visible HWND, with completed-frame readback. The sample also tests a copied Button projection with owner/layout freshness checks; no UI Automation provider or assistive-technology action transport is implemented. |

The hosted macOS lane builds GPUI's test-hook library, runs the CoreText and
shared native package tests, and compiles the Yami macOS sample. It does not
launch a window or exercise runtime rendering or input, so it is build and
portable-test evidence rather than a hosted native UI proof.

The earlier local macOS pointer proof passed on Yami `086cfd1` with approved
GPUI candidate `ae45429`; its tree is identical to merged GPUI revision
`2c6e9a3df469922f79d7b2b8eb977a0524086486`. Hosted Linux and Windows proofs
passed in [native UI CI run 37808645019](https://github.com/f4ah6o/Yami-kumo/actions/runs/37808645019)
on those same source trees, qualifying native `0.2.0`. Native `0.2.3` used
GPUI `0.7.0`; its hosted proofs remain tied to the exact source revisions
recorded by their CI run. Native `0.2.4` updates the module dependencies to
GPUI `0.7.1` and the pure MoonBit module `f4ah6o/yami_kumo` `0.1.1`. The native
UI workflows now pin the merged GPUI `0.7.1` source at
[`gpui-revision.txt`](../tests/native-ui/gpui-revision.txt). This
dependency-only release does not change the component API or expand the
platform proof scope documented here.

These checks cover labeled Text and Button rendering, readback of a completed
native frame, and a host-delivered click that changes the sample's App Entity
and counter text. Headless tests and cross-compilation alone do not count as a
native UI pass. The macOS input is a GPUI test-hook NSEvent, while Linux and
Windows use host-delivered XTest and Win32 `SendInput`; none of these checks
claims physical-hardware input coverage. They do not qualify a native text
editor or an Input component. The browser `Input` API remains separate.

The macOS AX proof is an additional sample-only lane: the current Button
snapshot is published with its enabled state and activation count, and an
`AXPress` request increments the same sample-owned App Entity. Snapshot owner
and layout generations reject requests from another sample or an invalidated
layout. This is not a general accessibility API for `NativeButton`, and it
does not qualify VoiceOver interaction quality or text/IME support.

The Windows sample copies its current Button semantics through GPUI's
transport-free `AccessibilityProjection`; its fixture checks immutable node
data, supported Invoke actions, owner freshness and layout-generation
revalidation before the same sample-owned App Entity can change. The Windows
adapter has no UI Automation provider and returns no host requests, so this is
contract coverage rather than an assistive-technology proof.

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

The GPUI host capabilities differ by platform. The [macOS host guide](https://github.com/gpui-mbt/gpui.mbt/blob/1ec90dfad7a3bc9f8ffbfad80928eaba737ab0bd/docs/macos-native.md)
covers bounded single-line measurement and drawing; a native editor and IME
are not implemented. The [Ubuntu text-field guide](https://github.com/gpui-mbt/gpui.mbt/blob/1ec90dfad7a3bc9f8ffbfad80928eaba737ab0bd/docs/linux-text-field.md)
documents an experimental single-line LTR field with caret, selection, undo,
and a private direct-keyboard route. Public `TextInput` and IME transport are
not supported; the [Wayland IME transport](https://github.com/gpui-mbt/gpui.mbt/blob/1ec90dfad7a3bc9f8ffbfad80928eaba737ab0bd/docs/ubuntu-ime.md)
is private opt-in work and is not qualified. The [Windows host guide](https://github.com/gpui-mbt/gpui.mbt/blob/1ec90dfad7a3bc9f8ffbfad80928eaba737ab0bd/docs/windows-native.md)
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
GPUI_SOURCE=/path/to/gpui.mbt sh "$YAMI_SOURCE/scripts/native_ui_macos.sh" --ax-proof
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
