# Retained direct-input retirement and orderly close

This candidate starts at Yami #117 `585ff82109df0fa006f3031258476257d0b9cc86`
and GPUI #200 `53e42a5888167fd9203b27f6558deabaf5c54e4b`. It does not substitute
later Shared Settings branches for those baselines. The two source-CI pin files
identify the additional GPUI candidate. Published-package acceptance is separate.

## Evidence required before retirement

1. The retained native receipt must match its window, root/binding, portable and
   native epochs, monotonically contiguous native sequence, operation, and direct
   ordinal. A validated original-owner reservation is kept **before** ACK. An ACK
   failure keeps that reservation and immutable model value for an exact retry.
   A record rejected during admission cannot use the ACK-retry command.
2. Each direct insert or editing key must finish the original TextField delivery.
   Its frozen before/after field progress, expected document, original owner,
   extracted action and actual shared-model update must agree. The runner checks
   the entire sequence of effects, including edits which change no model text.
   It does not reconstruct text independently of TextField's undo/history path.
   The full model chain starts at the previous retired prefix and includes
   platform actions and `SaveFinished`; locally consistent but unrelated model
   effects cannot be joined to the completed scene.
3. A successful `present` and the corresponding `FrameCompleted` must cover the
   latest model, scene and owner progress. A later model transition invalidates
   the model fence even if its value is equal. An earlier in-flight frame may
   complete, but it cannot retire a later edit or an unpublished model action.
4. Native cutoff must succeed. Only then can the checked direct prefix be
   retired, the native binding released and the old field owner revoked. The
   global native watermark survives lease changes; per-lease direct ordinals and
   field progress are separate. A released epoch cannot receive late commits.
   Rebinding uses an explicit native predecessor certificate and the exact
   resolved ACK watermark. It requires the same window, focus and keymap
   generation, an empty native FIFO and no pressed keys or compose work. The
   ordinary begin gate and historical key-absence evidence are unchanged.
5. Tab, Enter, pointer/focus transitions and close remain owned boundary records
   until the preceding lease is resolved. Key releases retain their real UI
   effects: Space release can activate a button and Enter release clears its
   armed state. A close waits for admitted key releases and their completed model
   scene before requesting native destruction.
6. Host stop requires the actual `Destroyed` receipt to be ACKed and a native
   terminal seal. The seal checks the destroyed window/generation, final native
   sequence, empty FIFO, no binding/physical key/compose/IME work, then atomically
   forbids new window creation and callback admission. Local queue emptiness or
   text cutoff alone cannot make `can_stop()` true.

`retire_completed_publication` keeps its original restrictions. The new direct
lifecycle is selected only for the retained Linux direct-keyboard route with
the explicit lifecycle adapter. The retained Wayland IME route keeps its existing
fail-closed behavior.

The native ledger still has a 64-record bound. At 48 records the direct runner
requests a checkpoint while continuing to drain already-admitted direct input on
the same owner. If the native cutoff cannot be established before capacity is
exhausted, ownership is retained and execution suspends; the bound is not raised
and records are not silently discarded.
Proven passive character press/release edges preserve an already completed
scene; they cannot continually replace it with an identical in-flight frame.
After native release, completed platform-only prefixes are also reclaimed when
focus stays on buttons or a dialog. An uncertain rebind error retains its suffix
and cannot be retried automatically; only a side-effect-free native `Busy` is
eligible for another attempt.
If a printable key reaches the focused Name field before the new direct owner
exists, its original receipt stays unACKed. The runner neither reconstructs a
missing TextInput event nor treats that press as a completed no-op.

## Regression coverage

The focused native suites cover the actual press / TextInput / release shape,
Backspace, Tab and Enter, button Space release and repeated Enter, dialog
close/reopen, focus loss/return, multiple bounded leases, native input bursts,
close with queued releases (both a text owner and an unbound button), direct and
platform ACK failures, post-ACK recovery, pending actions, incomplete/stale
scenes, mismatched model effects/native identities, released epochs, and
cutoff/release/seal failures. UI tests separately cover immutable delivery
progress, owner identity and rejection of old leases after release.

Reproduce the local suites with the pinned MoonBit toolchain and source workspace:

```sh
GPUI_SOURCE=/path/to/pinned/gpui.mbt sh scripts/native_ui_workspace.sh sh -ec '
  moon test "$YAMI_NATIVE_MODULE_ROOT/ui" "$YAMI_NATIVE_MODULE_ROOT/examples/common" --target native --deny-warn --no-parallelize
  python3 "$YAMI_NATIVE_YAMI_ROOT/tests/native-ui/test_drive_settings.py"
  python3 "$YAMI_NATIVE_YAMI_ROOT/tests/native-ui/test_settings_control.py"
'
```

The PR records the final source SHAs, exact-head CI status, independent review,
fresh binary hashes and live results. Exploratory snapshots are not exact-head
acceptance. A forced process termination is not a successful safe stop.

## Scope and remaining gates

- This is a stacked **Draft** candidate, not Shared Settings P1 completion or
  merge approval. Full Linux live IBus/Mozc acceptance, registry-only consumers
  and Apple Silicon live acceptance are separate gates.
- The orderly close contract is `CloseRequested -> resolved input and scene ->
  destroy_window -> Destroyed ACK -> terminal seal -> stop`. A host already in
  `Stopping` (for example an earlier programmatic `request_exit`), a destroyed
  window with unpublished edits, or an uncertain native failure stays retained.
- Unsupported native records remain unACKed. In particular, this change does not
  introduce a policy for raw modifier keys. The inherited XKB compose/Ctrl/Meta
  issue reported on GPUI #200 is not fixed by ledger retirement.
- Native rebind deliberately rejects a changed focus/keymap/window generation.
  Focus loss with unresolved physical keys remains retained; a later real focus
  generation is not certified by the same-focus rebind API. Consumer fixtures
  cover a host-certified return and a refused return separately. They are not
  evidence that live focus-loss/reacquisition is fully accepted.
- Geometry/IME quiescence is not inferred from direct-keyboard results. Any live
  test that reaches preedit/commit delivery but not model/scene publication must
  report those stages separately and must not be marked PASS overall.
