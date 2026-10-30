# Retained platform input and local prefix snapshot

This draft adds a pointer-motion stage only after the exact original event
passed the mounted dispatch boundary (including an unconsumed `Ok(false)`),
with no pending application action before or after. A rejected/failed event,
pending action, changed sequence or mismatched window/scale/coordinates cannot
advance the stage. The event remains held on error. A read-only prefix snapshot
also checks consecutive retained native identities, locally observed stages,
current text lease generation/token/revision/focus, and absence of pending
work. Its `prefix` control reply reports this snapshot only: it is **not**
physical-key provenance, an ACK capability, scene/geometry publication, or a
proof that another consumer/previous focus resolved its input.

Against GPUI candidate source `5cd2f231c6cbf529396cae633f6e5a0d6c9bea41`:

```sh
env TMPDIR=/workspace/scratch/yami-owned-tmp PATH="/workspace/yami-tools/bin:$PATH" MOON_HOME=/workspace/yami-tools GPUI_SOURCE=/workspace/gpui-retained-route sh scripts/native_ui_workspace.sh sh -c 'moon test "$YAMI_NATIVE_MODULE_ROOT/examples/common" "$YAMI_NATIVE_MODULE_ROOT/ui" --target native --deny-warn --no-parallelize'
python3 -m unittest discover -s tests/native-ui -p 'test_settings_control.py'
```

Native UI + common: 154/154 PASS, including one characterization test that
reproduces an existing failure rather than proving a fix. The checked-in log
SHA-256 is `3c4e0f8d4331428431fbbf27ee8e56eb5d493c7d037fde0142bd1247fd0bbeb2`.
Socket unittest: 9/9 PASS. An earlier test run against unpublished GPUI #193
source `f67cb002731b62ae47bdb5368ebf83a3c395a2cf` passed 153/153 before the
last extra test. It did not validate native provenance. The source-based Ubuntu
build against `5cd2f23` passed; its binary SHA-256 was
`8dd5e8c373f148cbf93c40b24944be7d57b887154eb929057b1d51a3dac2bf23`, build log
SHA-256 `cba8db43a2774d4514a69cf019f566b40926112aef0a2e031a1e079c2e683039`.
That build preceded a final additional test-only edit. No live IME run used it.

The pointer fixture is scripted; actual sequence 4 must be observed and checked
on a build of the integrated candidate. The unsupported sequence 11 continues
to be held and its ACK remains refused. Positive release policy, model/scene/
geometry transaction, safe host lifetime and clean registry dependency are
unresolved. This is not a product P1 fix.
