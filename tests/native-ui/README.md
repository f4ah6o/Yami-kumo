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
local macOS script builds GPUI with `--test-hooks`; its test-only
`NSWindow.sendEvent:` click and Escape events are synthetic host events, not
physical hardware input.

On macOS, run `sh scripts/native_ui_macos.sh` from any directory with MoonBit,
Xcode command-line tools, and the Yami and GPUI worktrees as siblings. The
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
