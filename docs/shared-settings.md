# Shared Settings qualification

Status: one Settings consumer, four entry points. Web and Windows run the full
flow in CI. The Linux lane is now enabled in this change; its full flow must
pass on the candidate CI run before qualification is claimed. macOS runs text composition and
TextField AX, while its key-driven dialog is `NOT_RUN` in the current GUI
session.

## One source

`examples/shared_settings` owns the model, view and update. The DOM entry
(`examples/shared_settings_dom`) and the native entries import it unchanged;
hosts own no second name value or save state. `SaveFinished` is delivered by the
host tick (DOM timer, native frame) so both observe the same transitions.

## Lanes

| Lane    | Command                                                                  | What it proves                                                                                                                  |
| ------- | ------------------------------------------------------------------------ | ------------------------------------------------------------------------------------------------------------------------------- |
| Web     | `node --test tests/shared-ui/settings.test.mjs`                          | Real Chromium: validation, synthetic composition, dialog cancel/confirm, focus restore, simulated save, two roots, dispose      |
| Linux   | `YAMI_SETTINGS_LANE=1 scripts/native_ui_linux.sh`                        | Weston direct keyboard text, Tab focus, Dialog cancel/reopen/confirm, save; candidate CI evidence required                      |
| Windows | `scripts/native_ui_windows.ps1` (`drive_settings.py --platform windows`) | Visible HWND, IMM32 text route (WM_CHAR key path when unavailable), Tab traversal, dialog, save; the report names the transport |
| macOS   | `--settings-e2e` native sample (manual)                                  | Composition entry, TextField AX; dialog input `NOT_RUN`                                                                         |

Native frame markers:

```
YAMI_NATIVE_UI_SETTINGS {"phase":"frame","name":"...","status":"editing|saving|saved","dialog":false,"focus":"name|save|confirm|cancel|other","error":""}
YAMI_NATIVE_UI_SETTINGS {"phase":"key","key":"character|tab|enter|..."}
YAMI_NATIVE_UI_SETTINGS {"phase":"text","status":"key-path|unavailable","route":"direct-keyboard|none"}
```

### Windows text transport

`native/examples/windows` builds a `windows.TextHostRoute` and passes it to the
Settings runner for `--settings-e2e`. When the name field gains focus the
runner starts the opt-in IMM32 session and records which path delivered text:

```
YAMI_NATIVE_UI_SETTINGS {"phase":"text","status":"started","transport":"imm32","epoch":1}
YAMI_NATIVE_UI_SETTINGS {"phase":"text","status":"unavailable","operation":"begin_text_input","error":"..."}
YAMI_NATIVE_UI_SETTINGS {"phase":"commit","text":"a","epoch":1}
YAMI_NATIVE_UI_SETTINGS {"phase":"key","key":"character"}
YAMI_NATIVE_UI_SETTINGS {"phase":"exit","reason":"window-closed|tick-limit","ticks":1200}
```

The driver records `textTransport` as `imm32-commit` only after a commit
marker; a WM_CHAR `Character` delivery is recorded as `key-character` and is
never relabelled as IMM. `settings.ime` and `settings.ax` stay `NOT_RUN`.

Measured 2026-10-22 JST on Windows 11 (10.0.26200) with Microsoft IME and ATOK
installed: `abc` arrived as IMM32 commits, Tab focused Save, Enter opened and
confirmed the dialog, and the simulated save completed. The Windows CI job
re-runs this lane and retains `settings-windows.json` in the
`yami-native-ui-windows` artifact; the report records name `abc`, dialog `true`,
status `saved`, the transport, and the host environment. The CI result is the
qualifying artifact; the local run above is the same contract.

## Evidence

Each lane writes a `settings-lane/v1` report:

- Web: `_build/shared-ui/web/settings-web.json` (retained in the
  `shared-ui-evidence` artifact)
- Linux/Windows: `settings-<platform>.json` in the lane evidence directory

The native report also records `result` (`name`, `dialog`, `status`),
`textTransport`, `textMarkers` and the host `environment`.

Aggregate them after downloading the `yami-native-ui-windows`,
`yami-native-ui-ubuntu` and `shared-ui-evidence` artifacts from the same
candidate run into one directory:

```sh
node tests/shared-ui/matrix.mjs --dir <evidence-dir> --candidate-sha <sha>
```

The matrix fails when a required flow row is missing or not passing, when a
declared `NOT_RUN` row has no reason, when a lane is undeclared, or when a
candidate SHA differs. `NOT_RUN` rows never satisfy a required row.

## Not claimed

Ubuntu/Windows real IME and accessibility providers, macOS key-driven dialog,
AX set-value and dialog actions are outside this qualification. A build-only,
marker-only or synthetic-composition result is not an IME or AX pass, and the
Windows WM_CHAR key path is not an IME qualification.

## Linux delivery and integration

On Weston without text-input-v1, the runner enables the host's direct keyboard
text route. The driver focuses the compositor's X output window (the Wayland
surface is not an X window). Pending TextChanged actions are applied before
rendering, preventing stale props from resetting the caret. Initial focus is
retried only until observed, so Tab and modal focus are preserved afterward.
The text session marker identifies IMM32 on Windows and text-input-v1 on Linux;
direct keyboard fallback is recorded separately and does not qualify IME.

Both native drivers require name `abc`, an observed Save focus, Dialog cancel
with focus restoration, reopening and confirmation, and saved name `abc`.
Each step waits for a new frame. Missing input or transport evidence fails the
lane. IME and accessibility remain NOT_RUN because these drivers do not exercise
an IME engine or inspect native accessibility providers.

Frame markers are emitted after host presentation completes (synchronously on
macOS, on FrameCompleted on Linux/Windows). Layout uses current window metrics,
including scale, and stale resize completions are discarded.
