# Changes

## Unreleased

### Added

- Windows Settings lane: run the shared model through `windows.TextHostRoute`
  with `--settings-e2e`, and record the text transport (`imm32` commit or the
  WM_CHAR key path), host environment and exit reason in
  `settings-windows.json`/`.log`. IME and UIA stay `NOT_RUN`.

### Fixed

- The Windows Settings driver builds Win32 `INPUT`/`KEYBDINPUT` records for
  `SendInput` and reuses the native UI driver's foreground guard, so `abc`,
  Tab and Enter reach the sample window.
- Re-commit the Settings frame after a resize or scale event. The invalidation
  cleared the layout-ready state, so the following IMM32 commit was rejected
  before it could reach the focused field.

- Qualify the Shared Settings Linux lane key-input path on Weston + Xvfb.
  `settings_runner` now falls back to the host's direct keyboard-text mode
  when `begin_text_session` fails (Weston advertises no
  `zwp_text_input_manager_v1`), drains queued actions before committing a
  frame so typed text cannot be reverted by a field rebuild, and retries the
  scope focus until it reports the `name` field. The Linux driver waits on
  the compositor output window, logs X focus diagnostics (`windowfocus`,
  `windowactivate`, `getwindowfocus`), and the report records which text
  transport carried the input (`direct-keyboard` vs `text-input-v1`), keeping
  `settings.ime` and `settings.ax` as `NOT_RUN`. The integrated candidate must retain a passing `settings-linux.json`
  before the lane is qualified.

## native-0.2.14 - 2026-10-21

### Changed

- Move to GPUI `0.10.6`, which replaces the Python macOS prebuild hook with a
  MoonBit `.mbtx` script and the Linux C toolchain wrappers with POSIX shell
  scripts. Native builds now require only the MoonBit toolchain, with a `moon`
  that supports `.mbtx` prebuild scripts.
- Remove the Windows `python3` forwarder from the native UI runner. The test
  lanes still execute the Python drivers, but the build no longer needs an
  interpreter.

## native-0.2.13 - 2026-10-21

### Added

- Run the shared Settings model on macOS: `native/examples/common/settings_runner.mbt`
  drives text input, focus, the simulated save, TextField AX and Dialog AX, and
  the macOS entry builds the dialog port from `Host::publish_dialog_accessibility`.
  The DOM entry imports the same `examples/shared_settings` package.
- Move to GPUI `0.10.5` and `f4ah6o/yami_kumo` `0.2.3`, which publishes the
  Settings model.

### Fixed

- A committed string without a preedit (plain ASCII or a direct input-method
  commit) was applied through `commit_composition` and failed with
  `NoComposition`, aborting the host loop. It now replaces the selection, and
  Cancel without a preedit is a no-op.

## 0.2.3 - 2026-10-21

### Added

- Publish `examples/shared_settings`, the single model/view/update source for
  the four-profile Shared Settings consumer. The model owns the draft name,
  validation, confirmation dialog, simulated save and completion; the DOM and
  native entries import it unchanged.

## native-0.2.12 - 2026-10-21

### Fixed

- Publish `TextChanged` from a portable `Commit` when the committed value
  changes even if it equals the preedit preview. Many input methods commit the
  already-converted preview; comparing the visible document dropped the commit
  and the next frame recreated the field from the stale application value.
- Do not restart a text session immediately after `FocusLost`/`Cancel` while the
  field still has focus; wait for the window focus to return.
- Focus the proof sample's only field after the first frame so the harness does
  not depend on AppKit's key-view traversal.

### Changed

- The macOS IME driver discovers the sample's actual window/PID instead of the
  `moon run` wrapper, retries Enter after conversion, and recognizes an
  in-process candidate panel that appears only during composition. Live Kotoeri
  preedit, commit, committed document and candidate visibility now PASS; the
  physical-keyboard claim remains `NOT_RUN`.

## native-0.2.11 - 2026-10-21

### Added

- Publish the focused TextField's role, value, focus and frame through
  `platform/macos.Host::publish_text_field_accessibility` while a portable text
  session is active, and revoke it on focus/session end. The shared runner gains
  `NativeTextAXPort`; hosts without an AX projection ignore it.
- Add `--text-ax-proof`: a dedicated AXUIElement client verifies the TextField
  role, value, focus and frame; the driver focuses the field with the IME
  helper's Tab post. A locked console, missing AX window or untrusted
  observation records `NOT_RUN`/`UNSUPPORTED`; a mismatch is `FAIL`. AX
  set-value and actions remain out of scope.

## native-0.2.10 - 2026-10-21

### Added

- Support nested and sibling native Dialogs as a scope stack ordered by view
  preorder. Each level paints its own backdrop and panel, keeps an independent
  `element.FocusScopeSession` scope and restores its enclosing focus once when
  removed. Only the innermost level admits input, focus and semantic actions;
  a non-dismissible inner level consumes Escape and backdrop presses without
  dismissing an outer level.
- Assign each binding the deepest Dialog level that contains it and paint main
  content before level 0, then each deeper level. Add regression tests for
  nested focus, Tab containment, staged Escape/backdrop dismissal,
  non-dismissible trapping, outer removal with an open child, sibling stacking
  and inner composition cancellation.
- Add `Mounted::focused_text`, a read-only observation of the focused editable
  field's committed document, caret, binding identity and composing flag. Hosts
  use it as the owner state for a portable text-input session.
- Add the `text_sample` fixture and `examples/common` text runner. It begins a
  `text_host` session for the focused field, republishes document/caret updates,
  applies ordered `Preedit`/`Commit`/`Cancel`/`FocusLost` observations through
  `Mounted::text_input`, drains `TextChanged` before the next frame so a commit
  is not replaced by a stale owning value, and cancels/ends on focus loss. The
  macOS entrypoint supplies the port from `platform/macos.Host`.
- Add unit coverage for the sample view/action mapping and for the runner's
  begin/update/commit/focus-loss sequence with a scripted backend and a fake
  text-input port.
- Pin GPUI `0.10.4` (`70c5818`).
- Add the local `--text-ime-proof` mode for the native text-field sample. It
  selects a live Japanese input source, restores the previous source, activates
  the app, posts key codes with `CGEventPostToPid`, waits for a Japanese
  preedit and a commit, and probes on-screen windows for an input-method
  candidate window. Claims are recorded per item; a locked console session, a
  missing Japanese source or untrusted Accessibility posting records
  `NOT_RUN`/`UNSUPPORTED`. Physical-keyboard input and candidate anchoring
  remain `NOT_RUN`. `--text-ax-proof` records `NOT_RUN` until the sample
  publishes TextField AX.

### Fixed

- Include `text_sample` in the published module archive so the shared runner's
  import resolves after installation.
- Keep a Dialog's overlay root id stable while the same key occupies a level.
  Previously a rebuilt open Dialog changed the root id, frame adoption revoked
  its live scope, and only the adapter's `in_dialog` filters still blocked
  background input; now the session scope survives a rebuild and continues to
  own admission.

## native-0.2.9 - 2026-10-20

### Changed

- Replace the adapter-local modal filter in the native Dialog with the live
  `element.FocusScopeSession`. Input admission, Tab trapping, dismissal and
  opener restoration now come from the session; a rebuilt frame adopts its new
  tree while keeping the open scope, so a Dialog survives a view topology change
  without losing focus. Removing the Dialog from the view restores the opener
  and cancels a removed field's composition through the session boundary hook.
- Add `Mounted::text_input` for portable `text_host.TextInputEvent` observations.
  It applies preedit/commit/cancel to the focused editable field, rejects stale
  epochs and replayed records, and leaves the host begin/update/end cycle to the
  runner.
- Pin GPUI `0.10.3`.

## native-0.2.8 - 2026-10-20

### Added

- Add a bounded native Dialog overlay: second root, backdrop and panel paint,
  initial focus, dialog-local Tab, Escape/backdrop dismissal, background
  filtering and opener restoration. Nested Dialogs remain unsupported and real
  OS IME and accessibility remain `NOT_RUN`.

## 0.1.1 - 2026-10-13

### Added

- Added bounded property-based tests for text and title-attribute HTML escaping.

### Fixed

- Resolve the compiled renderer URL directly so the Windows smoke handles drive-letter paths.
- Keep generated Kumo contract code in MoonBit's canonical formatted layout.
- Format the package README example as valid MoonBit code blocks.

## native-0.2.7 - 2026-10-20

### Fixed

- Include `ui/` in the native Mooncakes archive. Native `0.2.6` omitted the
  TextField adapter package that its own examples and consumers import.

## 0.2.2 - 2026-10-20

### Fixed

- Include the `examples/shared_counter` and `examples/shared_button_theme`
  packages in the Mooncakes archive so the native module can resolve them.

## 0.2.1 - 2026-10-20

### Fixed

- Include the `ui/` packages in the Mooncakes archive. `0.2.0` omitted them,
  so the native module could not resolve `f4ah6o/yami_kumo/ui/core`.

## 0.2.0 - 2026-10-20

### Added

- Added the shared `TextField` semantic View, a DOM `<input>` adapter with
  committed-value-only composition handling, and a native adapter with a
  measured single-line field, click/focus, focus restoration on blur, caret
  movement, editing, submit, host composition events, focus restoration and a
  host-drained clipboard request seam through `controls/text_field`. Native
  Dialog remains rejected with `UnsupportedCapability`. Real OS IME and accessibility
  qualification remain `NOT_RUN`; `text_session` ownership is not wired yet.
- Added the shared `Dialog` semantic View and DOM `<dialog>` adapter with
  top-layer modal behavior, Escape dismissal, initial focus and native focus
  restoration. A non-dismissible dialog ignores Escape, and the native adapter
  returns `UnsupportedCapability`.
- Added the additive shared AppShell region model, DOM semantic wrappers, GPUI
  flex layout, compact stacked layout, shell surface/text/Card theme tokens, and
  bounded DOM/native tests. Local macOS visible wide/compact rendering, CGEvent
  pointer activation and AXPress on the main Increment Button passed; CI also
  passed Linux Wayland and Windows SendInput shell pointer/render fixtures.
  Physical hardware input and a complete shell AX tree remain unverified.
- Added a focused Mooncakes archive and package README for installing the pure MoonBit module `f4ah6o/yami_kumo`.
- Added a pure MoonBit module for safe HTML rendering, the semantic AppShell, and a pinned subset of Kumo Button, Input, Text, and LayerCard components.
- Added a canonical parity gallery that mounts real React Kumo and the compiled MoonBit renderer independently across component matrices and interaction states.
- Added an independent native MoonBit UI module for measured Text, interactive Button, Card, and semantic AppShell components across macOS, Linux, and Windows GPUI hosts.
- Added Kumo Input disabled, focus, dirty, filled, touched, and Enter-triggered validity states, with dynamic state decisions kept in MoonBit over narrow browser DOM primitives.
- Included the upstream Kumo license alongside the redistributed standalone stylesheet.

### Changed

- Pinned `@cloudflare/kumo` to `2.14.0` so generated class and stylesheet contracts remain reproducible.
- Bumped the native module to `0.2.6` against GPUI `0.10.2` and pure MoonBit module `0.2.2`; the native adapter now paints and edits a measured TextField and consumes host composition events. The macOS sample runner revalidates the target before each event, bounds AX/helper lifetimes, and uses zero-modifier input. The external input route remains runtime-unqualified.
- Made the macOS native UI runner fail closed on locked or unknown console sessions and record blocked preflight evidence before launching the sample.
- Expose the native Button's pressed phase on sample frames and keep held pointer/key state through same-bounds repaint; focus loss and layout changes still cancel.
- Align native Button keyboard phases with pinned Kumo: focused enabled Enter activates on every key-down, including repeats, while Space stays pressed through repaint and activates on matching key-up.

### Fixed

- Make guarded macOS input cleanup preserve pending event ownership and report teardown failures instead of passing qualification after an incomplete release.

### Deprecated

### Removed

### Security

- Escaped text and attribute values, restricted element and attribute names, and removed inline styles from generated button markup for strict Content Security Policy compatibility.
- Revalidate the full macOS target snapshot before every global input post, bound AX queries and helper lifetime, and clear inherited modifier flags in the native UI sample helper.

### Migration

- Native `ButtonInteraction::key_down` now returns `Bool`; callers must handle `true` as an immediate Enter activation. `NativeSample::handle_input` and Web APIs are unchanged.

## native-0.2.4 - 2026-10-13

### Changed

- Bumped `f4ah6o/yami_kumo_native` to `0.2.4` against GPUI `0.7.1` and pure MoonBit module `f4ah6o/yami_kumo` `0.1.1`; native APIs and platform proof scope are unchanged.

## native-0.2.3 - 2026-10-11

### Added

- Added a Windows copied Button accessibility projection with source-owner and layout-generation revalidation; native UI Automation transport remains unsupported.

### Changed

- Bumped native module `f4ah6o/yami_kumo_native` to `0.2.3` against GPUI `0.7.0`.

## native-0.2.2 - 2026-10-11

### Added

- Added a macOS accessibility action to the native sample Button; AXPress updates the sample's existing click counter.

### Changed

- Bumped the native MoonBit module `f4ah6o/yami_kumo_native` to `0.2.2` against GPUI `0.5.0`.

### Fixed

- Made the Windows native UI runner select Git for Windows Bash, preserve shell-script LF endings, and check for usable Python 3.11+ and MSVC tools before building.

## native-0.2.0 - 2026-10-10

### Added

- Added a hosted macOS build and portable-test lane for the native MoonBit module; it builds the example without launching a GUI.

### Changed

- Released native MoonBit module `f4ah6o/yami_kumo_native` at `0.2.0` against GPUI `0.3.0`; its package README and MIT license originate in upstream PR #9.
- The macOS native runner invokes GPUI's Bash-shebang build script with `bash`.
- Native/LLVM builds require Python 3 for GPUI's macOS framework-link prebuild; resulting applications have no Python runtime dependency.
