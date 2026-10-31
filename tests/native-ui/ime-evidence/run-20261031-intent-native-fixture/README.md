# Controlled native FIFO intent fixture, 2026-10-31

This is a controlled test, not a Linux live IME or GUI acceptance. The test-only GPUI backend wrapper uses its real native queue, decoder, route and exact ACK, but mocks Wayland protocol requests and creates a fake host. It is not used by the product source.

Independent audit of the original evidence head [#135](https://github.com/f4ah6o/Yami-kumo/pull/135#pullrequestreview-5720670169) verified the packaged digests and the cited source relationships. The raw test/build logs do **not** contain embedded source SHA or toolchain stamps. Their hashes alone cannot independently authenticate which revisions or toolchain actually produced the earlier execution; the revision and toolchain fields below are recorded execution metadata, not self-authenticating provenance. No app binary was retained for independent comparison.

| Field | Value |
| --- | --- |
| framework source | `6f7fbd20c4e916e64f13aaeaf58aaa410a1e9d20` (candidate #210) |
| product candidate / baseline root | `3039ff9d996854703aec6c31c2f35f95db7e0536` (candidate #134; tested separately from the controlled fixture) |
| executed test source / Yami harness | `61abf307b0e92b5bdc25d4ad9f7b97a2522f9952` |
| GPUI test wrapper source | `b714dce0d285f434becc258a224068767ff956f5` (test-only modification based on framework above) |
| profile / OS / arch | controlled native FIFO; Linux 6.18.57, x86_64; protocol requests mocked |
| toolchain | moon 0.1.20261012 (748b63c), moonc v0.10.15+943464bfa, moonrun 0.1.20261012 (748b63c) |
| native libraries | Pango 1.56.3, FreeType 26.2.20, HarfBuzz 10.2.0, Wayland client 1.23.1, xkbcommon 1.7.0; configured sysroot at `/workspace/linux-user-apt/root` |
| dependency lock | source override; Yami `moon.mod` SHA-256 `922ca99baf05f1be96567b06097486b2ea24a919397ab7e0c5e7c69723893e6f`, `native/moon.mod` SHA-256 `b595be30e056da48775543ef1aa430d7e2ec93cbd9974d95c93d255628994b62`. No clean registry resolution was tested. |
| run URL | none; local run |
| executed app source / binary SHA-256 | NOT_APPLICABLE / not captured: this was a test executable, not an independently exercised app; temporary test and build workspaces were removed. |

Product-source checks with `GPUI_SOURCE` pointing to the framework source used `scripts/native_ui_workspace.sh` to run Moon native UI, common and Ubuntu tests: **99/99, 119/119, 6/6 PASS**. An Ubuntu application build also passed. These are source-override checks and their complete logs are included below.

The controlled integration command, from the Yami harness checkout, used the test-only GPUI wrapper checkout as `GPUI_SOURCE`:

```sh
GPUI_SOURCE=/path/to/gpui-test-wrapper sh scripts/native_ui_workspace.sh \
  sh -c 'moon test "$YAMI_NATIVE_MODULE_ROOT/examples/ubuntu" --target native --deny-warn --no-parallelize'
```

Result: **8/8 PASS**. The additional test reserved the original synthetic Shared Settings owner, received native FIFO commit sequence 2 / portable text ordinal 1, held the same geometry intent across Busy, transferred the exact native head into the route-owned slot, and submitted that intent. The returned host receipt was current; the later commit remained owned and unapplied, the shared model was still empty, and cutoff/stop remained unavailable. The fixture explicitly frees its fake host; that is not a successful product shutdown.

The integration test and GPUI wrapper are in the two *test-only* revisions above. Their helper APIs and backend substitutions are not dependencies of #134. Live IBus/Mozc, visible scene/caret, action/model application, Dialog, resize/blur/close race, physical keyboard, macOS, clean registry consumer and safe cleanup are **NOT_RUN** here.

Original decompressed log SHA-256 values:

- controlled test: `983829842040009e268006b15f3514497df900b54685f9f4c2a4fefb104444e8`
- product tests: `99f7e8177ca516bd7ef1151f57f9188d137ec9747060f2a2269eb56297a882da`
- product build: `500a19eacf1734f00e290357b3eaaf3101a6dae2c9b32d387ebd53bec8fcd03b`

`artifacts.sha256` records the packaged files. `gzip -dc <file> | sha256sum` reproduces each original log digest.
