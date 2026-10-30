# Retained platform stages — scoped scripted validation

These fixtures distinguish a validated Entered notification, locally handled
non-input platform events, and owned text observations that require no model
action. A pending application action blocks ordered resize or terminal layout
invalidation; focus handler errors or rejection suspend with the original
platform event still owned. A mismatched payload or ambiguous sequence cannot
advance a platform stage. These facts do not certify scene or host geometry,
ordinary input dispatch, model completion, release acknowledgement, terminal
cutoff, safe stop, or live IME acceptance.

Against explicitly checked-out GPUI candidate
`5cd2f231c6cbf529396cae633f6e5a0d6c9bea41` (source override), the following
command passed 150/150 native UI and common scripted tests, including the
existing characterization fixture whose PASS demonstrates a known failure:

```sh
env TMPDIR=/workspace/scratch/yami-owned-tmp PATH="/workspace/yami-tools/bin:$PATH" MOON_HOME=/workspace/yami-tools GPUI_SOURCE=/workspace/gpui-retained-route sh scripts/native_ui_workspace.sh sh -c 'moon test "$YAMI_NATIVE_MODULE_ROOT/examples/common" "$YAMI_NATIVE_MODULE_ROOT/ui" --target native --deny-warn --no-parallelize'
```

The checked-in `common-ui.log` SHA-256 is
`09fb5aed8b0054d29345d1db9c19ed9bc87600f9a81f3a42deaf325d0839521e`.
The control socket unittest passed 9/9. Ubuntu native example source build
also passed using `/workspace/linux-user-apt/root` sysroot and GPUI source
above, producing binary SHA-256
`747c7ebd487e19251c8350fa1960cc80de07ffd27f526e25e2e5901eb9b8d90d`;
this binary was not used for a live IME run. Local build log is
`/workspace/scratch/yami-platform-resume-build.log`, SHA-256
`23bdc4079bf1c931d06d9dec79b7b33985c75efa2da1f6300c5186e1056f3011`.

All work is a draft stacked on #91. The GPUI source is unpublished; the clean
registry consumer and the default Settings entrypoint remain blocked. Native
sequence 11 remains unsupported and unacknowledged without additional evidence.
