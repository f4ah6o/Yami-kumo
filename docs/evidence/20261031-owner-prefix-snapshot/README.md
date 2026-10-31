# Opaque local unsupported-prefix snapshot

The consumer can capture an opaque observation bound to the original suspended
SettingsRunOwner, its unsupported native receipt identity, its field lease
progress, and the exact ordered local receipt prefix. Rechecking refuses a
changed binding/epoch/focus/token, changed payload/scale or sequence, pending
action, buffered work and advanced field revision. The snapshot contains no
native physical-key proof, does not authenticate an adapter, and exposes no
operation to acknowledge a receipt. A `true` recheck can coexist with active
preedit and unpublished scene/geometry. It must never be used alone as proof
that an unsupported release is harmless.

Against explicit GPUI source `5cd2f231c6cbf529396cae633f6e5a0d6c9bea41`:

```sh
env TMPDIR=/workspace/scratch/yami-owned-tmp PATH="/workspace/yami-tools/bin:$PATH" MOON_HOME=/workspace/yami-tools GPUI_SOURCE=/workspace/gpui-retained-route sh scripts/native_ui_workspace.sh sh -c 'moon test "$YAMI_NATIVE_MODULE_ROOT/examples/common" "$YAMI_NATIVE_MODULE_ROOT/ui" --target native --deny-warn --no-parallelize'
```

154/154 scripted native UI/common tests passed, including an existing test
whose PASS characterizes a failure. The local log
`/workspace/scratch/yami-scoped-prefix-final.log` has SHA-256
`3c4e0f8d4331428431fbbf27ee8e56eb5d493c7d037fde0142bd1247fd0bbeb2`.
`moon info` regenerated the native UI API snapshot. No live run, release ACK,
original product P1 resolution, clean registry consumer, or host stop is
claimed. The native keymap validity/provenance issue remains separate.
