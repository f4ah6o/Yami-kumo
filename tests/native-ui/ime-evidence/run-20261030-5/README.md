# Local live IME run: integrated gpui candidate

This is the [fenced diagnostic](../run-20261030-4/README.md) repeated after
building the application against the combined gpui candidate. It uses the
legacy split text/platform consumer route. It does not qualify the new ordered
consumer or pending-commit ownership across focus changes.

- `framework_sha`: `a645aa3acfda4420c9558a12795187d71bb96003` (gpui PR #169).
- `consumer_sha` / `app_source_sha`: `7d9b920a7e435e0e9fcd3dfcc24013782ca1e16d`
  (Yami source checkout used to build; runtime code is based on `d072d49`).
- `harness_sha`: the driver in the checkout is byte-identical to commit
  `ca66913459cc0873d95fe50608d8909a381974d1`; driver SHA-256
  `726a055b11a6b8b1fdfc4482f0f22bafe7abc418b8ca7e1f7e82d1864a21fe0a`.
  The separate Weston readiness helper is from gpui
  `cfc66b872bfd9613e2a81b499cac0602c84d653b`, SHA-256
  `cc2753dbf13becc32e79e116839c9feec12e56b6424860d52409d1121ef01f5d`.
- `app_binary_sha256`: `f47c2274288150c10e1e808134849b8d177e082c3945c5b2e3723c8a4ebd42d7`,
  locally retained at `/workspace/evidence/yami-ime-caret-fix/app-combined.exe`.
- `dependency_lock`, `profile`, `OS_arch`, `toolchain` and `command`: as in
  the preceding record, with this new source checkout and binary. The source
  workspace uses these checked-out modules rather than registry packages; no
  MoonBit lockfile is present. The exact local session script is retained.
- `result`: PASS for the fixed-profile sequence in `result.json`, including
  preedit, fenced cancellation, one Japanese commit, undo/redo, backdrop,
  Dialog focus and confirm/save. Raw app/IBus/Weston logs and screenshots are
  retained; `SHA256SUMS` lists their digests. `run_url`: none (local).

The selected candidate screenshots and IBus lookup state still require manual
correlation and use timed capture; this is not the automated #155 candidate
gate. Physical keyboard, AX, candidate geometry, restore-target disappearance,
blur/stale-event recovery and the ordered consumer remain unqualified. This
result names the exact tested source commits and does not transfer to newer
HEADs.
