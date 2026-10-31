# Retained frame publication watermark (scripted candidate)

A frame callback can arrive after additional records were admitted. This draft
captures a bounded, consecutive receipt prefix before `host.present`, with
its original window/field/epoch, field generation/revision/text sequence,
caret and immutable scene revision. A matching current frame callback may only
record that captured watermark; it cannot retroactively cover newer records.
The prefix and original owner are rechecked before recording a completion.
Duplicate or changed receipt identities, an owner/scene/geometry change, an
unknown geometry update, or an error from `host.present` leave the candidate
uncompleted. A present callback that performs a side effect and then reports an
error is tested; no success is inferred. The record ledger is never retired.

Run with an explicit unpublished source override:

```sh
env TMPDIR=/workspace/scratch/yami-owned-tmp PATH="/workspace/yami-tools/bin:$PATH" MOON_HOME=/workspace/yami-tools GPUI_SOURCE=/workspace/gpui-retained-route sh scripts/native_ui_workspace.sh sh -c 'moon test "$YAMI_NATIVE_MODULE_ROOT/examples/common" "$YAMI_NATIVE_MODULE_ROOT/ui" --target native --deny-warn --no-parallelize'
```

Framework source `5cd2f231c6cbf529396cae633f6e5a0d6c9bea41`; 158/158 scripted
native UI/common tests passed, including a known-failure characterization.
`common-ui.log` SHA-256 `2f6cc8f47ecc9bad820834dda93fdebe5684c17194947829dec76c14b405b678`.
An Ubuntu source build against the same framework passed before the final
test-only edit; binary SHA-256
`fa84e3473b3b0da96dc4bbb37371d27b42679778c274012f2a9943c247aa5406`, local
build log SHA-256 `4bf67230083d7dcbb81353fc487cc0a3bf87f927f7c3a3cd7e3082d0594bbb19`.
No live IME or physical display measurement used this binary.

This is observational and deliberately fail-closed. A stale or failed
candidate remains owned and blocks the next observed presentation until an
explicit recovery policy exists. Frame completion is a host callback, not
proof of visible pixels. This does not make mounted scene publication, focus,
measurement and native host updates atomic; the existing sequence can still
leave different layers at different states on failure. It neither retires a
receipt nor proves host cleanup, seq11 release ACK, public registry consumer,
or the full product P1 fix.
