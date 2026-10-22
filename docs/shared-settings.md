# Shared Settings qualification

Status: one Settings consumer, four entry points. Web runs the full flow in CI.
The Linux/Windows lane drivers are checked in but run only when
`YAMI_SETTINGS_LANE=1`; their text paths are not qualified yet, so CI does not
claim them. macOS runs text composition and TextField AX, while its key-driven
dialog is `NOT_RUN` in the current GUI session.

## One source

`examples/shared_settings` owns the model, view and update. The DOM entry
(`examples/shared_settings_dom`) and the native entries import it unchanged;
hosts own no second name value or save state. `SaveFinished` is delivered by the
host tick (DOM timer, native frame) so both observe the same transitions.

## Lanes

| Lane    | Command                                                                  | What it proves                                                                                                             |
| ------- | ------------------------------------------------------------------------ | -------------------------------------------------------------------------------------------------------------------------- |
| Web     | `node --test tests/shared-ui/settings.test.mjs`                          | Real Chromium: validation, synthetic composition, dialog cancel/confirm, focus restore, simulated save, two roots, dispose |
| Linux   | `scripts/native_ui_linux.sh` (`drive_settings.py --platform linux`)      | Visible Wayland window, key-path text, Tab traversal, dialog, save                                                         |
| Windows | `scripts/native_ui_windows.ps1` (`drive_settings.py --platform windows`) | Visible HWND, SendInput text, Tab traversal, dialog, save                                                                  |
| macOS   | `--settings-e2e` native sample (manual)                                  | Composition entry, TextField AX; dialog input `NOT_RUN`                                                                    |

Native frame markers:

```
YAMI_NATIVE_UI_SETTINGS {"phase":"frame","name":"...","status":"editing|saving|saved","dialog":false,"focus":"name|save|confirm|cancel|other","error":""}
```

## Evidence

Each lane writes a `settings-lane/v1` report:

- Web: `_build/shared-ui/web/settings-web.json`
- Linux/Windows: `settings-<platform>.json` in the lane evidence directory

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
