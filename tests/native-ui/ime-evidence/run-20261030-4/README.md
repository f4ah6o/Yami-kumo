# Local live IME run: fenced cancel observation

This is the [preceding confirm/save diagnostic](../run-20261030-3/README.md)
repeated with driver/harness `ca66913459cc0873d95fe50608d8909a381974d1`.
Framework `8a171e72d5c7f0f84a48a4d4d5f74e2858b9fea4`, Yami app source
`d072d49de81abcf013a4c737ae3339f6325306cb` and binary SHA-256
`21f5e22d0aa2ce1e38a17677ffb061c2c3fe0fe1d481cd3bb30798b7e74b6420`
are unchanged. Dependency versions, local profile, OS/architecture, toolchain,
Mozc build and command are detailed in the preceding records; this run's local
session and logs are retained here. `run_url`: none (local).

The driver now consumes the empty-preedit marker after the second Escape
**before** taking the frame counter, then requires an empty-name frame beyond
that boundary. A counterexample fixture verifies a previously buffered frame
cannot satisfy that fence. The full fixed-profile sequence, including Japanese
commit, undo/redo, backdrop handling, focus restoration/reopen and confirm/save,
returned PASS in `result.json`. `SHA256SUMS` records retained artifact digests.

Candidate images and IBus trace remain manually correlated with ordered driver
steps; capture waits 300ms without a presentation acknowledgement. This is not
an automated PASS for gpui #155's candidate-table gate. Physical input,
accessibility, candidate geometry, restore-target disappearance, and
blur/stale-event handling are not qualified. This run uses the stated older
app/framework commits, not later combined HEADs.
