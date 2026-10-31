# Retained direct text: minimized consumer contract gap

These are **failure characterization** fixtures, not an implementation of
retained direct text:

1. A native-style `Platform(Input(TextInput("a")))` through the existing
   mounted path changes the field and yields `TextChanged`, which the model can
   apply. The previously captured `TerminalTextOwner` is then stale because its
   text-session progress was never advanced.
2. The same direct input during an existing preedit makes the GPUI TextField
   reject `CompositionActive`; it does not justify cancelling the preedit.
3. The current ordered runner ignores that platform-handler error, retains the
   input's native receipt at ACK-only stage, and can subsequently replace its
   in-flight slot with `Destroyed`. The raw receipt/host remain retained but no
   normal continuation processes the earlier input. The field is not publicly
   observable after layout invalidation; absence from a screen is not used to
   infer its document state.

Two candidate boundaries need review before a positive implementation:

- Have GPUI's retained host route publish an explicit direct `Insert` operation
  for only the native direct-keyboard TextInput record, with native sequence,
  window/root, original direct/portable epoch and a monotonic portable text
  ordinal in one receipt. Then a normal, long-lived original TextSession can
  apply `SessionOperation::Insert` once, separately from preedit `Commit`.
- Keep the platform event, and add an owner-bound mounted direct-delivery
  transaction that preserves the same native identity, existing GPUI field and
  extracted action across failure. It must reconcile owner revision/sequence
  without replay or a second edit history. Its relationship to the existing
  TextSession contract must be specified explicitly.

The first boundary aligns more directly with the existing `TextSession::Insert`
contract, but `text_host.TextInputEventKind` currently has no `Insert` variant;
a public enum/manifest change must be reviewed for consumer compatibility.
Existing Yami `held_text_input` already invokes `Insert` when not composing,
but it is a temporary Tab-transition owner that blocks normal frame/focus and
requires host cutoff; creating/releasing it for each input is not an acceptable
continuous editing solution. Neither option maps unknown replacement/delete or
native IME commit into a direct Insert. Composition, blur and cutoff remain
separate.

The following source-only command passed 166/166 scripted UI/common tests,
including these known-failure characterizations, against gpui
`b28cff9a8a92a155e67421a397a1030dedac9301`:

```sh
env TMPDIR=/workspace/scratch/yami-owned-tmp PATH="/workspace/yami-tools/bin:$PATH" MOON_HOME=/workspace/yami-tools GPUI_SOURCE=/workspace/gpui-keymap-generation sh scripts/native_ui_workspace.sh sh -c 'moon test "$YAMI_NATIVE_MODULE_ROOT/examples/common" "$YAMI_NATIVE_MODULE_ROOT/ui" --target native --deny-warn --no-parallelize'
```

`common-ui.log` SHA-256
`b9099d8c57cb6cbc0e80c7cb383c93ac8795132b9754705e188b6f5271b34cd4`.
GPUI #196 had separate focus/keymap/error ownership findings at this time;
these tests do not integrate or qualify that candidate. No live IME, safe
shutdown, registry consumer or product P1 success is claimed.
