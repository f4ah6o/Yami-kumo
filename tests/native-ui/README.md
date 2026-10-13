# Native UI proof

The proof builds the independent `native/` module against the GPUI revision in
[`gpui-revision.txt`](gpui-revision.txt), runs the shared component/controller
tests, then opens the same Text-and-Button sample on each host. The runner waits
for native frame 0, sends one host input, waits for MoonBit state 1 and native
frame 1, and independently checks both PPM captures for visible regions and
changed counter pixels. It also requires the app to report native window
destruction before the process exits.

The Ubuntu job runs Weston’s X11 backend in a private 800×600 Xvfb display.
`xdotool` sends an XTest pointer event through Weston into the Wayland client;
the sample marker is only produced after the ordinary event queue and button
dispatch receive it. The Windows job uses `SendInput` against the visible
sample HWND and fails if that window cannot become the foreground window. The
historical native `0.2.0` local macOS pointer proof used GPUI's test hook to
deliver a synthetic `NSEvent` through the sample's owned `NSWindow`. The
current local macOS script instead builds an external input helper. After
checking that Accessibility permission is already granted and the console
session is on-console and unlocked, that helper is designed to post synthetic
mouse and Escape events through `CGEventPost(kCGHIDEventTap)`. It sends input
only when the launched PID, unique window title, focused AXWindow, visible
WindowServer window, and point-tested sample AXButton all match. A locked or
unknown session fails before the sample launches. The external-helper route
remains runtime-unqualified: the latest preflight found a locked session and
refused before launching the sample, so no native event was sent. These events
are host input, not physical hardware input.

The hosted macOS job runs the CoreText and shared native package tests,
builds the macOS sample, and compiles the external Objective-C host-input
helper. It does not launch the sample window, so it verifies macOS compilation
and portable behavior, including inert helper guard fixtures, without claiming
runtime UI proof.

The Windows tests also compile and exercise the sample's copied Button
accessibility projection, including stale owner/layout rejection before its
App Entity effect. Windows UI Automation transport is not implemented; these
checks do not claim screen-reader or assistive-technology interaction.

The local macOS `--ax-proof` mode launches the same sample and uses a separate
`AXUIElement` client to verify the launched process's registered bundle
identity, then finds an `AXWindow` owned by that exact PID and its named Button.
The requested unique title is preferred; if macOS reports another title, the
client accepts only a sole AXWindow owned by that PID and records the observed
title and whether it matched. The client verifies the Button's enabled state
and `AXPress` action, presses it, and reads activation count 1 from the same
sample-owned accessibility element before closing the window. This proves the
sample adapter and its counter routing only; it does not establish
VoiceOver quality, accessibility coverage for other widgets, text editing, or
IME behavior. macOS may require the terminal or test runner to be allowed to
control the sample in Privacy & Security settings.

For the external macOS input route, the helper takes a fresh, shared-deadline
snapshot before each global down or release. The snapshot includes the unlocked
session, exact frontmost PID, focused AXWindow, unique visible WindowServer
window ID and frame, and (for clicks) the current enabled Button identity and
frame, topmost window owner, and AX hit ancestry. Each AX object gets its own
short messaging timeout. The helper records down ownership before posting; if
the release snapshot changes, it may send only a zero-modifier release to that
same PID. A click with a refused global release remains a failed run. Escape
can use the PID-targeted release only after the original window is confirmed
gone or its process has exited, and the driver still requires the sample's
completion marker. The runner bounds helper execution, requests termination
and reaps it on timeout, then writes a failed report before and after sample
cleanup. `--guard-fixtures` exercises stale target states, overlays,
expiration, modifier clearing, and pending-release cleanup through fake event
posters; it sends no native input and does not qualify a live run.

On macOS, run `sh scripts/native_ui_macos.sh` from any directory with MoonBit,
Xcode command-line tools, and the Yami and GPUI worktrees as siblings. The
hosted build and portable-test subset is `sh scripts/native_ui_macos.sh --build-and-test`;
it compiles the sample without launching it. The sample-only native accessibility
proof is `sh scripts/native_ui_macos.sh --ax-proof`. The default local macOS UI
proof uses the guarded external host-input helper and requires an already
unlocked console session; it does not open permission prompts. The
Linux launcher is `sh scripts/native_ui_linux.sh` and requires Xvfb, Weston,
xdotool, Wayland development packages, PangoFT2, and the configured fonts. On
Windows, run `./scripts/native_ui_windows.ps1` in a PowerShell session with the
MSVC developer environment enabled. Each launcher writes frames, logs, and a
machine-readable report beneath `_build/native-ui/<platform>/` by default.

The workspace helper writes `moon.work` only in a fresh temporary directory or
an explicitly supplied empty/compatible workspace, uses absolute module
members, and copies GPUI's compiler helper scripts into that temporary root for
Moon's cwd-relative native compiler lookup. It removes only files it created
and only when their contents are unchanged.
