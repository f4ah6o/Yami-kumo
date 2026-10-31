# Preflight versus native-entered Busy fixture

Result **PASS, 8/8 native tests**. The retained FIFO and route are native code, while Wayland calls and IME callback injection are controlled mocks. This is not live IME, a production ACK policy, scene publication, safe shutdown, or main-goal acceptance.

- Framework production ancestor: GPUI #218 `9e92b72e885a0641a0b67e2e8ce4ea8556cab8c1`.
- Framework actually compiled: fixture-only GPUI #219 `f342c5b5a641faad61fca6c02d8d9e4b0ee97d82`, including FIFO injection and post-entry Busy injection.
- Consumer implementation ancestor: Yami #172 `ef68a54`.
- Test app source and harness: Yami #176 `c50bbee3d48d7772d2416ccce2adefa1eba14d14`.
- Dependency resolution: source workspace override, not registry. No package lock; product uses pinned framework revision #218 while this fixture compiles the distinct helper revision above.
- OS/profile: Linux x86_64 kernel 6.18.57; locked local Pango/Wayland build profile; mocked protocol, no real IME.
- Toolchain: moon 0.1.20261012 (748b63c), moonc v0.10.15+943464bfa, moonrun 0.1.20261012 (748b63c).
- Actual native test executable SHA-256: whitebox `17f905c9756601ccfdcfeb88d7d1d0e90a86e890b7430fc89428f67ff8d88706`; internal `abb4e86f89e5330ba7d626c8791f7ccfc9272f4ee4d4a65110a03bee5179cca8`; blackbox `72135cfbea93b6586b63b8427f0d0fb6d0ffd66cfc206f2c7d26a4f2af4721d1`. These are test executables, not an application binary.
- Run URL: none (local); raw log SHA-256 `5e8112d2bba4c7783b79156dcb703daf4e4f5fb9c90bc25602ec3add9e87d531`.

Protocol bindings were generated using the framework's `scripts/prepare_ubuntu.sh` with the locked local Wayland protocol package. Command:

```sh
env PATH=/workspace/yami-tools/bin:$PATH MOON_HOME=/workspace/yami-tools \
  GPUI_SOURCE=/workspace/gpui-preflight-recovery-native-fixture \
  PKG_CONFIG_PATH=/workspace/gpui-locked-profile/prefix/usr/lib/x86_64-linux-gnu/pkgconfig:/workspace/gpui-locked-profile/prefix/usr/share/pkgconfig \
  PKG_CONFIG_SYSROOT_DIR=/workspace/gpui-locked-profile/prefix \
  LD_LIBRARY_PATH=/workspace/gpui-locked-profile/prefix/usr/lib/x86_64-linux-gnu \
  YAMI_NATIVE_WORKSPACE_ROOT=/workspace/yami-preflight-recovery-native-work \
  sh ./scripts/native_ui_workspace.sh moon test \
  /workspace/yami-settings-preflight-native-fixture/native/examples/ubuntu \
  --target native --deny-warn --no-parallelize
```

The initial attempt failed before running tests because two fixture return values were not explicitly used; this PASS uses the corrected committed source. The fixture explicitly ACKs its controlled head to create the empty-FIFO retry condition; it does not establish how a real consumer can safely ACK that head. A post-entry Busy is latched as uncertain and is not retried by this adapter.
