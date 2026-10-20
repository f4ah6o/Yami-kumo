# M3 status — 2026-10-20

States below describe `main`. Rows whose implementation PRs are still open name
the candidate PR; `PR pending` is not current `main` behavior.

This file is the current-state companion to the 2026-10-17 four-platform plan.
`manifest.json` is the frozen planning snapshot from that date and still records
every packet as `proposed / not_started / not_run`. Do not read that snapshot as
the current implementation state; use this file and the linked code/tests.

## gpui-mbt repositories

| Repository                                                           | Role                                        | M3 involvement                                    |
| -------------------------------------------------------------------- | ------------------------------------------- | ------------------------------------------------- |
| [`gpui.mbt`](https://github.com/gpui-mbt/gpui.mbt)                   | MoonBit engine and native hosts             | Primary: text host seam, OS text routes, focus/AX |
| [`gpui-conformance`](https://github.com/gpui-mbt/gpui-conformance)   | differential fixtures and retained evidence | Primary: `text-field` / `ime` / `dialog` layers   |
| [`gpui-mbt-app-demo`](https://github.com/gpui-mbt/gpui-mbt-app-demo) | real macOS/Web/Windows consumer             | Primary: Linux lane and Shared Settings screen    |
| [`MZed`](https://github.com/gpui-mbt/MZed)                           | Zed native-island experiment                | Post-M3; not a blocker                            |
| [`turtles.mbt`](https://github.com/gpui-mbt/turtles.mbt)             | MoonBit mutation testing                    | Scoped mutation for new text packages             |
| [`hotpath.mbt`](https://github.com/gpui-mbt/hotpath.mbt)             | profiling toolkit                           | Post-M3; no performance claim                     |
| [`raden.mbt`](https://github.com/gpui-mbt/raden.mbt)                 | CPU 2D vector-graphics port                 | Out of M3; independent                            |
| [`container.mbt`](https://github.com/gpui-mbt/container.mbt)         | Docker/Apple Container port                 | Optional test environment; not IME/GPU evidence   |
| [`mp4.mbt`](https://github.com/gpui-mbt/mp4.mbt)                     | MP4 mux/demux port                          | Out of M3; independent                            |
| [`deepseek-harness`](https://github.com/gpui-mbt/deepseek-harness)   | TypeScript reference fork                   | Out of M3; no MoonBit/GPUI dependency             |

## Yami packets

| ID    | Current state        | Evidence                                                                                                                                                                                                                                                                                                                                                                                     |
| ----- | -------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| YK-00 | Partial              | [ADR](../../adr/0001-shared-ui-runtime.md), [fixture](../../../fixtures/shared-ui/contract-v1.json), [evidence schema](../../../tests/shared-ui/evidence.mjs). Enter-repeat, loading/focus, composition/external-value and Dialog-Escape decisions are not yet frozen in one table.                                                                                                          |
| YK-01 | Implemented, bounded | `ui/core`, `ui/runtime`, [consumer check](../../../scripts/check-shared-ui-consumers.mjs), CI `shared-ui` job. `ui/components/` was not split out; `View` lives in `ui/core`.                                                                                                                                                                                                                |
| YK-02 | Implemented, bounded | `ui/dom` mount/update/focus/dispose, real-Chromium DOM tests. Firefox/WebKit are not covered.                                                                                                                                                                                                                                                                                                |
| YK-03 | Bounded candidate    | `native/ui` plus Ubuntu/Windows/macOS entrypoints. macOS visible-window and AXPress proof is local, not CI.                                                                                                                                                                                                                                                                                  |
| YK-04 | Partial              | Button states and fixed Card; general Text semantics/style/error contract is missing.                                                                                                                                                                                                                                                                                                        |
| YK-05 | Partial              | Theme, spacing, AppShell and compact mode; general layout, drawers and full shell AX remain open.                                                                                                                                                                                                                                                                                            |
| YK-06 | Bounded DOM + native | DOM `<input>` and native `TextField` with composition, focus restoration and clipboard requests are merged. The adapter consumes `platform.EventKind::Composition` today and exposes `Mounted::text_input` for portable `text_host` observations; no sample drives the host begin/update/end cycle yet. OS IME and AX are `NOT_RUN`. [Shared TextField contract](../../shared-textfield.md). |
| YK-07 | Bounded DOM + native | DOM `<dialog>` plus a native overlay whose input admission, Tab trapping, dismissal and opener restoration come from the live `element.FocusScopeSession`; a rebuilt frame adopts its tree without closing the scope. Nested Dialogs remain open. [Shared Dialog contract](../../shared-dialog.md).                                                                                          |
| YK-08 | Not started          | Harness pieces exist (`evidence.mjs`, native drivers, palettes); no Shared Settings matrix.                                                                                                                                                                                                                                                                                                  |
| YK-09 | Published, bounded   | Published `f4ah6o/yami_kumo@0.2.2` and `f4ah6o/yami_kumo_native@0.2.8` (GPUI `0.10.2`). `0.2.0`/`0.2.1` and native `0.2.6` are superseded packaging failures; use `0.2.2`/`0.2.8`.                                                                                                                                                                                                           |

## GPUI packets

| ID                   | Current state           | Evidence                                                                                                                                                                                                                 |
| -------------------- | ----------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| GP-00                | Implemented             | [Shared UI host audit](https://github.com/gpui-mbt/gpui.mbt/blob/main/docs/shared-ui-host-contract.md) and paired headless fixtures.                                                                                     |
| GP-01A               | Implemented             | `text_session/` ownership, revisions, preview/commit/cancel and observed end. Headless tests only.                                                                                                                       |
| GP-01B               | Implemented             | `text_host/` is implemented by `platform/macos.Host` over AppKit with an epoch-tagged ordered queue; Linux and Windows keep host-local sessions. Yami native adapter consumption is pending. Real IME remains `NOT_RUN`. |
| GP-01-GEOMETRY       | Partial                 | Caret/hit measurement exists per OS; candidate-rectangle capability is not advertised.                                                                                                                                   |
| GP-02-L              | Experimental            | Ubuntu text-input-v1 route behind `GPUI_FIELD_WAYLAND_IME=1`; real composition/candidate panel not qualified.                                                                                                            |
| GP-02-W              | Experimental            | Default-off IMM32 route; real Japanese IME and UIA are `NOT_RUN`.                                                                                                                                                        |
| GP-02-M              | Bounded transport       | `NSTextInputClient` composition transport merged (#121, `0.10.0`); candidate caret API exists. Real Kotoeri acceptance `NOT_RUN`; #89/#107 remain draft evidence.                                                        |
| GP-03-FOCUS          | Portable + native wired | `element.FocusScopeSession` is portable-tested and the native Dialog now uses the live session for admission, Tab, dismissal, opener restore and frame adoption. Nested Dialogs remain open.                             |
| GP-03-SEMANTICS / AX | Partial                 | Portable model and macOS Button AXPress only; TextField value/selection and native providers are missing.                                                                                                                |

## Dependency pins

| Consumer           | GPUI reference       | State                                   |
| ------------------ | -------------------- | --------------------------------------- |
| gpui.mbt published | `0.10.0` (`7f62b92`) | Current release; #121 merged            |
| Yami shared source | `e2c8bd5`            | Source workspace; merged via #38/#39    |
| Yami native module | `0.10.0` / `e2c8bd5` | Source workspace; merged via #40        |
| app-demo           | `0.9.0`              | macOS/Web/Windows preview               |
| gpui-conformance   | `0.7.2` (`b16210d9`) | Baseline pin; candidate overrides exist |
| M3 target          | `0.10.0`             | Reached for the bounded text slice      |

## Boundaries

- M3 changes `gpui.mbt`, `Yami-kumo`, `gpui-conformance` and `app-demo`.
- `MZed`, `hotpath.mbt`, `raden.mbt`, `container.mbt`, `mp4.mbt` and the
  `deepseek-harness` fork are not M3 dependencies.
- `dsh.mbt` is a late consumer canary; it does not import
  `controls/text_field`, so it is not a TextField testbed.
- A build-only, synthetic-input or model-only result is not a native IME or
  accessibility pass. `UNSUPPORTED` and `NOT_RUN` stay visible.
