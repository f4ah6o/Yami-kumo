# Bounded local prefix compaction (scripted candidate)

A suspended owner may compact its latest completed frame observation only when
all its original receipt identities/stages and the current window, binding,
epoch, entered seat/proxy, field generation/revision, scene revision and
caret still match. The bounded summary keeps the original owner and monotonic
native watermark; later receipt sequences at or below that watermark and gaps
are refused. Existing snapshots captured before compaction become stale.
Unsupported-ACK receipts and their suffix are not eligible: the current record
holds no durable native policy proof suitable for retirement. No host cutoff or
shutdown follows from compaction.

If normal retained polling is blocked *before native peek* by the 64-entry
ledger, a successful eligible compaction can re-enable exactly one bounded
continuation generation; the original native queue was not read during the
failed attempt. The user must explicitly select the last completed candidate
watermark through the same-UID local control socket; stale/repeated requests
cannot apply to a later frame. Other failure causes are not automatically
resumed. This does not solve general ledger retirement or indefinite operation.

Against GPUI source candidate `b28cff9a8a92a155e67421a397a1030dedac9301`:

```sh
env TMPDIR=/workspace/scratch/yami-owned-tmp PATH="/workspace/yami-tools/bin:$PATH" MOON_HOME=/workspace/yami-tools GPUI_SOURCE=/workspace/gpui-keymap-generation sh scripts/native_ui_workspace.sh sh -c 'moon test "$YAMI_NATIVE_MODULE_ROOT/examples/common" "$YAMI_NATIVE_MODULE_ROOT/ui" --target native --deny-warn --no-parallelize'
python3 -m unittest discover -s tests/native-ui -p 'test_settings_control.py'
```

169/169 native UI/common tests and 11/11 socket tests passed; the UI/common
suite includes a characterization that reproduces an existing failure.
The `common-ui.log` SHA-256 is
`318e24f2496662a55de08ff3669d24d265899218b78b192b32c505dd8b68f577`.
An earlier Ubuntu build passed before the final extra regression/sequence-gap
and backpressure logic; it is not the final app build or a live result.

`FrameCompleted` is the existing single-outstanding host callback, not proof
of physical display. This candidate does not make scene, focus, measurement,
and native host updates atomic. It does not prove general live IME, candidate
lookup, cleanup, the normal entry's automatic recovery, or a source-override-
free registry consumer. Native/UI integration, exact-head independent review,
CI and live revalidation are outstanding.
