# Controlled retained native FIFO fixture

Result: **PASS**, 12 native Ubuntu test cases. This is a controlled FIFO and mocked Wayland callback test, not a live compositor, real IME, rendered scene, candidate-table, Dialog, safe stop, or main-goal acceptance. GPUI and Yami fixture shims are test-only. The scene/host publication transaction remains unresolved; the tested owner remains suspended.

- Framework product ancestor: `35b9041dfb3642b43ca37c604834942614eb50fb` (gpui #211).
- Framework actually compiled (fixture-only injection helpers on that ancestor): `1b542f578df4018ad3b2bfef423c690667bd71fe`.
- Yami consumer/application implementation ancestor: `85b2fbc2226e24eb8101605442a667b48fe76cd6` (#157).
- Test harness and compiled Yami source: `5d19fb0bcb137e2917d4b2be28a83cac38371a9f` (#158).
- This is a Moon test binary, not the Shared Settings application binary. SHA-256: whitebox `821ea1a52ccb1f405486d5334c9d374fe93751435af5f00ceb4f5f51e08d8e32`, internal `b9120f17d968bb4a49cd3100746c9a597ad111938595dcb6c73b84ff771cf728`, blackbox `6e07f8dd6076ec51075148bcc71f95661619f087bb21fcb511d5bc77bb9c1ea9`.
- Dependency resolution: explicit source workspace override, no registry lock; no claim of clean published dependency.
- OS/profile: Linux x86_64, kernel 6.18.57; locked Pango headers/profile; native FIFO and mocked Wayland, no live IME.
- Toolchain: moon 0.1.20261012 (748b63c), moonc v0.10.15+943464bfa, moonrun 0.1.20261012 (748b63c).
- Run URL: none (local controlled run).
- Uncompressed raw log SHA-256: `a20a6c8075f9076d745e37fb727984d53cb4e0a6e1e77c1379e787eae5f8fa45`. The compressed bytes are retained alongside this manifest.

Command (paths refer to the producing workspace):

```sh
env PATH=/workspace/yami-tools/bin:$PATH MOON_HOME=/workspace/yami-tools \
  GPUI_SOURCE=/workspace/gpui-geometry-owned-apply-fixture \
  PKG_CONFIG_PATH=/workspace/gpui-locked-profile/prefix/usr/lib/x86_64-linux-gnu/pkgconfig:/workspace/gpui-locked-profile/prefix/usr/share/pkgconfig \
  PKG_CONFIG_SYSROOT_DIR=/workspace/gpui-locked-profile/prefix \
  LD_LIBRARY_PATH=/workspace/gpui-locked-profile/prefix/usr/lib/x86_64-linux-gnu \
  YAMI_NATIVE_WORKSPACE_ROOT=/workspace/yami-geometry-arrival-retry-native-work \
  sh ./scripts/native_ui_workspace.sh moon test \
  /workspace/yami-geometry-arrival-retry-native-fixture/native/examples/ubuntu \
  --target native --deny-warn --no-parallelize
```

The earlier native test attempt lacked runtime `LD_LIBRARY_PATH` and failed before executing tests; it is not counted as this PASS. The fixture's native sequence 3 corresponds to portable text sequence 2; the ledger records the commit at `ReceiptModelApplied`, while scene and caret remain unpublished. An extra queued native sequence is not used as evidence of application or completion.
