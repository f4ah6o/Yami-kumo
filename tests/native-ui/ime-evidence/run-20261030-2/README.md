# Local Shared Settings IME run: candidate and backdrop observation

This is a second local diagnostic using the same source, binary and environment
as [the preceding run](../run-20261030/README.md), but driver/harness commit
`ec0b85168713a5cda24a8d2f7647bfc70fc9c443`. Framework is gpui
`8a171e72d5c7f0f84a48a4d4d5f74e2858b9fea4`, app source is Yami
`d072d49de81abcf013a4c737ae3339f6325306cb`, and the retained executable SHA-256
is `21f5e22d0aa2ce1e38a17677ffb061c2c3fe0fe1d481cd3bb30798b7e74b6420`.
The user-space Mozc client and server, source workspace and dependency versions,
OS/arch and toolchain, and command are the same as the preceding record. The
extra environment variable is `YAMI_IME_BACKGROUND_POINT=150,285`. `session.sh`
uses local absolute paths; adapt them to reproduce. `run_url`: none (local).

`result.json` is PASS for the marker assertions: an empty-name frame is observed after preedit
cancellation, but the frame counter does not fence buffered earlier frames; later Japanese preedit converts and
commits once, undo/redo restore empty/日本, and the Dialog focus and key path
work. The click at (150,285) was visually over the background Save button
(`dialog.png`); the dismissible backdrop closed the Dialog, returning focus to
the input with name `日本` and status `editing`, without an observed reopen or
save during the 300ms observation. The driver then reopened from the field. This
is one fixed geometry/profile; it is not a general pointer proof.

The fixed input sequence and screenshots show a 9-row table with second row
`にほん` selected (`candidates.png`), then Up selects the first row `日本`
(`candidate-selected.png`), and the table is absent after Return
(`after-commit.png`). In `ibus-ui-dbus.log`, the corresponding
`UpdateLookupTable` records contain the same leading row values and cursor
positions 1 then 0, followed by `HideLookupTable`; app protocol/markers record
`日本` as the actual commit. In the separate cancel sequence, first Escape
returns from the conversion table to the prediction list
(`after-candidate-cancel.png`); second Escape clears preedit and removes that
list (`after-preedit-cancel.png`), with an empty-name frame whose freshness is not independently fenced. See the raw
logs for event order.

Screenshots are taken after a 300ms delay and correlated by the driver's ordered
steps and log inspection, not by an independent presentation-acknowledged
candidate-table oracle. This is **not** a PASS for gpui #155's candidate gate,
all scale/placement profiles, physical keyboard, AX, or a latest-HEAD combined
app. Restore-target disappearance and stale event rejection across blur/close
remain outside this run. `SHA256SUMS` records each retained artifact digest.
