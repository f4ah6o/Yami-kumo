# Local live IME run: validation and fenced Dialog actions

This repeats [the integrated gpui diagnostic](../run-20261030-5/README.md)
with driver/harness `d0968295f433ff97c064930918fec0245b511ac6`. The
application source, framework source, executable, dependency setup, OS,
toolchain, profile and command are the same as that preceding record:

- `framework_sha`: `a645aa3acfda4420c9558a12795187d71bb96003`.
- `consumer_sha` / `app_source_sha`: `7d9b920a7e435e0e9fcd3dfcc24013782ca1e16d`.
- `app_binary_sha256`: `f47c2274288150c10e1e808134849b8d177e082c3945c5b2e3723c8a4ebd42d7`.
- `harness_sha`: `d0968295f433ff97c064930918fec0245b511ac6`. The Weston
  readiness helper remains from gpui `cfc66b872bfd9613e2a81b499cac0602c84d653b`.
- `run_url`: none (local); raw artifact digests are in `SHA256SUMS`.

`result.json` records PASS for the fixed-profile sequence. A field Enter with an
empty name first produced `Enter a name before saving.` and left the Dialog
closed; a fresh frame after Japanese preedit still contained an empty committed
name. The run then canceled preedit with an observation fence, committed `日本`
once, undid and redid it, exercised backdrop/key/Tab behavior, restored focus,
reopened and confirmed saving the value. For each keyboard-driven Dialog step,
the driver now consumes the matching key marker before setting the frame fence.

The consumer still uses the legacy split route; ordered/pending-commit ownership
and blur/stale-event recovery remain open. Screenshots are manually correlated
with IBus state and input steps after a 300ms capture delay; this does not satisfy
#155's automated candidate-table gate or qualify physical input, AX, or geometry.
