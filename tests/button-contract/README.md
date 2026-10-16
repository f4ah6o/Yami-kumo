# Shared Button operation fixtures

`fixtures.json` is the versioned input for the real pinned Kumo component,
the existing public `NativeSample` consumer, and the isolated Linux host driver.
Each case starts with count zero, no focus and no held input. The same ordered
operations are used on both sides. Native controller semantics are not copied
into a JavaScript model or another controller.

## Run and evidence

1. Install the repository's pinned MoonBit toolchain, Node dependencies and
   Playwright Chromium (`pnpm install --frozen-lockfile`,
   `pnpm exec playwright install chromium`). Check out GPUI at the SHA in
   `tests/native-ui/gpui-revision.txt` and set `GPUI_SOURCE` to that checkout.
2. Run `node --test tests/button-contract/comparison.test.mjs` and
   `python -B tests/button-contract/test_driver.py` for comparator and driver
   rejection controls.
3. Run `node scripts/run-button-contract.mjs NEW_OUTPUT_DIRECTORY`. It builds
   the existing NativeSample consumer and launches an owned, headless Chromium.
   Preserve `report.json`, raw native stdout/stderr, build log and Web phase PNGs.
   The report records source hashes, fixture hash, revisions, toolchain/browser
   versions and native executable hash.
4. Run `sh scripts/native_ui_linux.sh` with the existing Wayland/Mesa/font/input
   prerequisites to additionally replay the `host: true` cases through the
   script-owned Xvfb/Weston session. It records host input sequence markers,
   presented Native scene/state, GPU PPMs and Button ROI hashes. The driver
   requires this isolated session; it is not a user-desktop input tool.
5. Set `YAMI_BUTTON_NATIVE_HOST_REPORT` to the resulting
   `button-contract-host/report.json` when running the Web comparison. Fixture,
   source file hashes, HEAD and pinned GPUI must match. CI does this in the
   `ubuntu-wayland` job and uploads all evidence even on failure.

## What is compared

Per phase: activation count and delta, the observed activation event's phase,
focus, focus-visible, hover, disabled/loading state, held/pressed state, Web computed style and
Native Button scene items. The Web trace retains trusted DOM event records,
including keyboard repeat, and real Kumo onClick actions. The native consumer
calls `handle_input`, `render` and `focus_changed`; deterministic text metrics
qualify neither OS font rendering nor native window presentation.

The pinned Kumo 2.14.0 primary Button has no independent pressed fill:
`:active` selects the same emphasis ring color as rest. Its decorative child
changes the gradient start on hover, and keyboard focus widens the ring from
1px to 2px. `pointer-hover` and `keyboard-focus` (ArrowLeft down/up) isolate
these changes before a press. Press, repaint and release must preserve an
otherwise unchanged surface. The observer records the decorative child's CSS
and a padded Button PNG, in addition to the parent style.

Native emphasis fills approximate the gradient's OKLCH midpoint with a solid
color, and the square ring is drawn outside the Button bounds. This qualifies
the **timing of visual feedback**, not gradient/radius/shadow/font or whole-image
equivalence. `matched-feedback` never means raster equivalence.

Ctrl/Alt/Meta-modified keys do not enter keyboard focus-visible mode; existing
keyboard focus remains visible. The consumer/Web `modifier-focus` case checks
this against trusted input. Host delivery of this case is not yet qualified.
Reclicking the same focused Button retains its keyboard ring; the shared
`focus-retained-click` host case checks that the ring does not flicker off.
Pointer exit in this suite means a delivered move outside Button bounds within
the same window. The pinned GPUI event API does not report window pointer leave,
so leaving the window directly may retain hover and remains unsupported.

`focus-loss` transfers DOM focus to the outside control and calls the public
NativeSample focus-loss method in the consumer profile. It does not establish
native window focus delivery. Pointer cancel means release outside the Button.
The host repaint phase uses an observed pointer move to request another frame;
the raw log distinguishes this from the Web's React repaint.

The Linux host profile covers hover, Enter down/up, keyboard focus,
Space down/repaint/up, pointer release outside, native window focus loss,
and disabled controls. The focus-loss driver transfers X11 keyboard focus from
the owned Weston window to the isolated Xvfb root and requires an actual
`YAMI_NATIVE_UI_FOCUS` event and a subsequent presented frame. It restores window
focus before sending the unmatched Space release; Button focus stays cleared.
This host path is distinct from the Web's element focus transfer.
Repeat, other unmatched-release scenarios, and loading remain explicitly `not-run` at this layer. Synthetic host
input is not physical hardware input. macOS/Windows host execution, physical
keyboards and external Accessibility are not qualified by these fixtures.

## Result and gate meanings

- An exit code of zero means the observation harness completed and supported
  activation/focus/disabled semantics matched. A mismatch on these fields,
  missing phase, stale host evidence, rejected repeat delivery or runtime error
  fails the command.
- This is deliberately not a full Button conformance gate. `report.status` is
  `partial` while any profile/phase is missing or a pressed/style difference is
  observed. `YAMI_BUTTON_REQUIRE_COMPLETE=1` returns exit code 2 for such a report.
- Native loading is `unsupported`: NativeSample has no loading API. It is not
  simulated by substituting a disabled Button.
- The feedback gate compares actual Web computed-style changes with Native
  Button scene changes, and, when supplied, padded GPU ROI changes. Frozen GPU
  pixels despite a changed scene, missing hover/focus feedback, invented
  Native-only pressed colors, and repaint/release regressions fail CI for the
  enabled profile. Both changing and preserving the surface are checked.
  GPU `gpu_button_sha256` hashes RGB pixels in Button bounds padded by 4 logical
  pixels to include the focus ring; `gpu_button_interior_sha256` retains the
  unpadded interior separately. Every phase retains the PPM SHA-256, ROI bounds
  and input/presentation sequence. The driver also compares scene versus GPU
  changes before writing successful evidence.
- Disabled style is separately `unsupported-disabled-style`. Browser `:active`
  can also be true for a disabled button while native held state is false; that
  is retained as `diverged`, not silently normalized into a match.
- Computed CSS, a Native scene, GPU readback, OS input delivery, physical input
  and Accessibility are separate observation layers. Similar screenshots or a
  successful controller test do not pass the other layers.

The normal CI gate protects supported semantic behavior and the evidence
collection/comparison implementation. CI Green is not a claim that all Button
UX parity gaps are fixed.
