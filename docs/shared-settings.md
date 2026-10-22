# Shared Settings qualification

Status: one Settings consumer, four entry points. Web runs the full flow in CI.
The Linux lane is qualified: `settings-linux.json` records `status: pass` with
`name: "abc"`, `dialog: true` and `status: saved`, typed through the compositor
key path (`route: "direct-keyboard"` — Weston advertises no
`zwp_text_input_manager_v1`, so the runner arms the host's direct
keyboard-text mode instead of a text-input-v1 session; the marker/report show
which route carried the text). The Windows lane driver is checked in but runs
only when `YAMI_SETTINGS_LANE=1`; its text path is not qualified yet, so CI
does not claim it. macOS runs text composition and TextField AX, while its
key-driven dialog is `NOT_RUN` in the current GUI session.

## One source

`examples/shared_settings` owns the model, view and update. The DOM entry
(`examples/shared_settings_dom`) and the native entries import it unchanged;
hosts own no second name value or save state. `SaveFinished` is delivered by the
host tick (DOM timer, native frame) so both observe the same transitions.

## Lanes

| Lane    | Command                                                                  | What it proves                                                                                                             |
| ------- | ------------------------------------------------------------------------ | -------------------------------------------------------------------------------------------------------------------------- |
| Web     | `node --test tests/shared-ui/settings.test.mjs`                          | Real Chromium: validation, synthetic composition, dialog cancel/confirm, focus restore, simulated save, two roots, dispose |
| Linux   | `scripts/native_ui_linux.sh` (`drive_settings.py --platform linux`)      | Weston+Xvfb output window focus, key-path text via direct keyboard mode, Tab traversal, dialog, save                         |
| Windows | `scripts/native_ui_windows.ps1` (`drive_settings.py --platform windows`) | Visible HWND, SendInput text, Tab traversal, dialog, save                                                                  |
| macOS   | `--settings-e2e` native sample (manual)                                  | Composition entry, TextField AX; dialog input `NOT_RUN`                                                                    |

Native frame markers:

```
YAMI_NATIVE_UI_SETTINGS {"phase":"frame","name":"...","status":"editing|saving|saved","dialog":false,"focus":"name|save|confirm|cancel|other","error":""}
YAMI_NATIVE_UI_SETTINGS {"phase":"key","key":"character|tab|enter|..."}
YAMI_NATIVE_UI_SETTINGS {"phase":"text","status":"key-path|session|unavailable","route":"direct-keyboard|text-input-v1|none"}
```

The `phase":"text"` marker records which transport carried the text so the
report can distinguish the compositor key path (`direct-keyboard`) from a
portable session (`text-input-v1`); `unavailable` means neither exists. The
Linux driver also logs the X windows it enumerated, the `windowfocus` /
`windowactivate` results and `getwindowfocus` before/after, and the session
script saves the compositor's `wayland-info` advertisement list into the
evidence directory.

## Evidence

Each lane writes a `settings-lane/v1` report:

- Web: `_build/shared-ui/web/settings-web.json`
- Linux/Windows: `settings-<platform>.json` in the lane evidence directory,
  alongside `settings-linux.log` (driver X-focus diagnostics + markers),
  `wayland-info.log` and `weston.log`

Aggregate them after downloading the lane artifacts into one directory:

```sh
node tests/shared-ui/matrix.mjs --dir <evidence-dir> --candidate-sha <sha>
```

The matrix fails when a required flow row is missing or not passing, when a
declared `NOT_RUN` row has no reason, when a lane is undeclared, or when a
candidate SHA differs. `NOT_RUN` rows never satisfy a required row.

## Not claimed

Ubuntu/Windows real IME and accessibility providers, macOS key-driven dialog,
AX set-value and dialog actions are outside this qualification. A build-only,
marker-only or synthetic-composition result is not an IME or AX pass.
