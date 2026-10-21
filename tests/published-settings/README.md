# Published Settings contract

This independent consumer tests the **published** native module, without a
`moon.work`, GPUI source checkout, or Yami source override. It runs an in-memory
`ScriptedBackend`; it never opens an AppKit window or sends OS input.

From this directory, run:

```sh
moon update
moon test --target native --deny-warn
```

The fixture pins `f4ah6o/gpui@0.10.5` and
`f4ah6o/yami_kumo_native@0.2.13`. The `Published Settings contract` workflow
also tests `0.10.6` / `0.2.14`, on Linux and macOS. Both pairs resolve the shared
model from published `f4ah6o/yami_kumo@0.2.3`.

## What the test verifies

- A preedit-free Japanese commit reaches the Settings model.
- Enter opens the confirmation Dialog; Escape cancels it; a later Enter
  confirms the reopened Dialog and the runner reaches the saved state.
- TextField and Dialog AX ports never expose both projections together.
- Dialog title, nonempty bounds, new/update token use, revoke tokens, and
  TextField focus publication follow the port contract.
- Text sessions resume after both closures and keep the committed document.
- Destroying the host while a third Dialog is open revokes its projection;
  every begun text session has ended and neither AX token remains live.

These are model/port contract assertions. AppKit AX tree observation, real
window activation, OS IME, physical keyboard input, and OS-driven Cancel or
Confirm remain **NOT_RUN** by this test. The `Macos` runner selector does not
turn the scripted backend into an actual macOS backend.

## Dependency audit: 2026-10-22 JST

- [GPUI #145](https://github.com/gpui-mbt/gpui.mbt/pull/145) merged as
  `c72a6bec0f126e06004d4dde4d76aca392f6414a`; its final PR HEAD
  `45a35d9fe97a0a47144487c233d394287ae93a99` has six completed/success workflows.
- [Yami #57](https://github.com/f4ah6o/Yami-kumo/pull/57) merged as
  `4f557def7171cbfd23ca6e728e014ce5db37ea4c`; its final PR HEAD
  `05602a603390b2b7e035478cb0f849acdb8f9cd6` has three completed/success workflows.
- [Yami #59](https://github.com/f4ah6o/Yami-kumo/pull/59) resolved the original
  dependency by pinning GPUI `0.10.5` and wiring the macOS entry's
  `Host::publish_dialog_accessibility` and `Host::revoke_dialog_accessibility`.
  Its final HEAD `e81f9d41858200e3c6c7d2ab8e4bf927b7846d8a` has three
  completed/success workflows. The macOS job is build/portable-test evidence,
  not GUI input evidence.
- [Yami #63](https://github.com/f4ah6o/Yami-kumo/pull/63) subsequently advanced
  the dependency to GPUI `0.10.6` and native `0.2.14` to remove Python from the
  build path. This audit does not downgrade that dependency.
- GitHub review submissions and merged discussion timelines returned no
  entries for #145 and #57. #59 review submissions were also empty.
  **Independent review completion is unverified**, regardless of green CI.

`moon update` fetched the registry index. The index lists GPUI `0.10.5` and
`0.10.6`, native `0.2.13` and `0.2.14` as published and not yanked. Downloaded
archives were SHA-256 checked against the index:

| Archive | SHA-256 |
| --- | --- |
| gpui 0.10.5 | `fd263202a731411a13b7c929ff2475a98c8da4a584651e9b34b87ac51888c104` |
| gpui 0.10.6 | `1f525737423f7ca83410fd23184f9bdea0a8eda81e7711b6e6dee968d7ab8b88` |
| yami_kumo 0.2.3 | `1c46f9f144bd972db7d9dc839aa409a84f389a407d175e5dd751e1d93e3f2b0d` |
| yami_kumo_native 0.2.13 | `b22334465b36ca873839a4a00c1d590c934f9c7c5067ee576b64eda119c9dbeb` |
| yami_kumo_native 0.2.14 | `d76663c866f6c8845b5a9c5211799e2ccb537647a1b5b1667d37092547c4eb14` |

The release API is a bounded copied Dialog projection: title, logical frame,
focus, and a revocable token, exposed as an AX group with AXDialog subrole.
It does not implement Dialog AX actions or field value writes. GPUI 0.10.5
also includes AlignSelf, authored root-box sizing and flow-relative
JustifyContent start/end; these are independent of the Dialog transport.

Local audit environment: Linux, moon `0.1.20261020`, moonc
`0.10.16+b1a0e846e`. CI uses its explicit `0.10.15+943464bfa` pin.

| Command / target | Observed result |
| --- | --- |
| This standalone consumer, published 0.10.5 / 0.2.13 | PASS, 1/1 |
| The same consumer with published 0.10.6 / 0.2.14 | PASS, 1/1 |
| Native `moon test ui --target native --deny-warn`, #59 source with published 0.10.5 | PASS, 86/86 |
| Native `moon check examples/macos --target native --deny-warn`, #59 source | PASS; Linux type checking, not a macOS link/runtime test |
| Native `moon test ui --target native --deny-warn`, main `8d793337894584132e0e03180367378a7de31bdd` with published 0.10.6 | PASS, 86/86 |
| GPUI main `cfc66b872bfd9613e2a81b499cac0602c84d653b`, `moon test platform/macos --target all` | PASS, 14 each wasm/wasm-gc/JS, 15 native; Linux host |
| GPUI `python3 scripts/check_contracts.py` | PASS; production release evidence remains pending |
| Real macOS Settings input and AX tree proof in this audit | NOT_RUN; this execution environment is Linux |

The historical window-activation limitation has not been re-tested here.
No result in this audit establishes that it has been resolved or persists.
