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
focus, disabled/loading state, held/pressed state, Web computed style and
Native Button scene items. The Web trace retains trusted DOM event records,
including keyboard repeat, and real Kumo onClick actions. The native consumer
calls `handle_input`, `render` and `focus_changed`; deterministic text metrics
qualify neither OS font rendering nor native window presentation.

`focus-loss` transfers DOM focus to the outside control and calls the public
NativeSample focus-loss method in the consumer profile. It does not establish
native window focus delivery. Pointer cancel means release outside the Button.
The host repaint phase uses an observed pointer move to request another frame;
the raw log distinguishes this from the Web's React repaint.

The Linux host profile currently covers Enter down/up, Space down/repaint/up,
pointer release outside, and disabled controls. Repeat, focus transfer, unmatched
release, and loading remain explicitly `not-run` at this layer. Synthetic host
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
- Native pressed scene items currently do not change. `gap-detected` records
  that missing feedback independently of activation parity. Browser `:active`
  can also be true for a disabled button while native held state is false; that
  is retained as `diverged`, not silently normalized into a match.
- Computed CSS, a Native scene, GPU readback, OS input delivery, physical input
  and Accessibility are separate observation layers. Similar screenshots or a
  successful controller test do not pass the other layers.

The normal CI gate protects supported semantic behavior and the evidence
collection/comparison implementation. CI Green is not a claim that all Button
UX parity gaps are fixed.
