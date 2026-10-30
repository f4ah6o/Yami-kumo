# Local live IME run: confirm and save

This is a repeat of [the preceding diagnostic](../run-20261030-2/README.md)
with the additional final operation: field Enter opens the Dialog, Enter on
Confirm saves `日本`, and a frame reports `status=saved`, `focus=name`.
`result.json` records those fields as `field_open_to_confirm` and `saved`.

- `framework_sha`: `8a171e72d5c7f0f84a48a4d4d5f74e2858b9fea4`.
- `consumer_sha` / `app_source_sha`: `d072d49de81abcf013a4c737ae3339f6325306cb`.
- `harness_sha`: `fe352704672c987e9e469ccefd483a7f889759da`.
- `app_binary_sha256`: `21f5e22d0aa2ce1e38a17677ffb061c2c3fe0fe1d481cd3bb30798b7e74b6420`.
- `dependency_lock`, `profile`, `OS_arch`, `toolchain`, and `command` are
  the same as the preceding record; the same retained executable, locked
  gpui desktop prefix, separately built Mozc client, Weston, and local
  output paths were used. `session.sh` names this run's output directory.
- `result`: PASS for this fixed-profile live-IME sequence. Candidate images,
  background Save click and log semantics have the same manual-observation
  limits described in the preceding record. They are not #155's automated
  candidate gate. The post-cancel frame counter can include buffered earlier frames, so the driver does not independently fence frame freshness. Raw app logs place an empty-name frame after the empty preedit marker.
- `run_url`: none (local). `artifact_digest`: see `SHA256SUMS` for every
  retained raw log, screenshot, result and script.

Physical keyboard, AX, candidate geometry, restore-target disappearance,
blur/stale-event recovery, and combined latest HEADs remain unqualified.
