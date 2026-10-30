# Shared Settings: ordered ingress and focus boundary

On 2026-10-30, the candidate framework source was gpui.mbt
[`c699b9f44e480c65c7e5f712d1a7ce8cca41ee9e`](https://github.com/gpui-mbt/gpui.mbt/pull/169),
combining the Ubuntu ordered-ingress, accepted-record and shortcut candidates.
The Yami source before this evidence/test change was
`0aad6f88d89b4ccd7fc586425a2c341b4c4971fd`, which includes #83 and the two
#85 caret commits. Tests used a temporary `moon.work` explicitly selecting
that framework checkout and the Yami source, with moonc `0.10.15+943464bfa`
on Debian 13 Linux x86_64. This is candidate-source testing, not a registry
release, OS IME run, or a build of an application binary.

The new `Settings applies an observed commit before a later window blur`
scripted regression delivers a preedit and commit to the focused Shared
Settings field, applies the semantic action to the shared model, rejects a
replayed record, and then delivers window blur. It passed against that
framework candidate. This isolates the adapter/model half of the desired
commit-before-blur behavior. It does **not** connect the application runner to
`OrderedTextHostRoute` or show that the host delivered this sequence.

The following separate expected-correctness regression **fails** against the
same source pair. Append [tab-owner-repro.mbt.txt](tab-owner-repro.mbt.txt) to
`native/ui/ui_test.mbt` and run through the candidate workspace:

```sh
GPUI_SOURCE=/workspace/gpui-integration sh scripts/native_ui_workspace.sh \
  moon test /workspace/yami-ordered/native/ui --target native --deny-warn \
  --filter 'observed old-owner commit survives Tab focus transfer'
```

It starts a preedit on the name field, dispatches Tab, and supplies a same-epoch
commit for that original field. The adapter returns `false` for the commit after
the focus moved. The captured [FAIL log](tab-owner-fail.log.txt) has SHA-256
`30fd33fd2a3ddfbc3b4a3db6b87a551c9f9f9bc0dd963efe7cf1330ace8f88af`;
the fixture digest is
`dcf76881b654aa4a20625d8ee8d3f6bf6b0ee3b653c76010037ed4fb9e978987`.
The fixture models an observed old-owner commit after Tab; it does not assert
that a particular real IME generates that order. A later unobserved callback
must not be invented or treated as a valid commit merely because the epoch was
once active.

## Remaining integration boundary

The ordered API supplies one sequence of records already returned by the
Ubuntu editor ingress. A Settings integration needs to capture the exact
window, binding incarnation and epoch when beginning a text session, then
process each observed text event for that owner and publish the shared-model
action before dispatching the next focus-changing record. The GPUI native
accepted-record change separately covers its bounded keyboard-leave case. No
new guarantee is implied for macOS or Windows.

For Tab, pointer focus changes, Dialog opening, close and target replacement,
the current adapter calls `TextField::with_focus(false)` in `sync_focus`, which
ends the preedit before any later observation is resolved. The runner then
calls host cancel/end, which can discard unread observations. An empty ordered
poll is not an end or quiescence signal. Correct completion requires an
explicit host/adapter boundary: hold the original binding and pending focus
intent; obtain and apply any already-observed commit or cancellation exactly
once to the old owner; resolve `TextSession`'s pending end; only then publish
the focus change and revoke the epoch. The protocol must reject late callbacks
and define what happens when it cannot establish an ending. The existing
ordered poll alone supplies no such acknowledgement.

The Settings presentation gate adds a separate ordering problem: after layout
invalidation, a text record can precede the `FrameCompleted` needed to make
the gate ready. A correct bounded buffer must keep text and user input in
order while safely handling presentation completion and resource limits;
waiting at the first text record can deadlock. Neither that buffer nor the
host end-boundary contract has been implemented or qualified here. The
application remains on its legacy route until those behaviors can be tested;
this record does not claim an ordered-route or live-IME PASS.
