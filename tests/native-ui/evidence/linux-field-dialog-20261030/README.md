# Shared Settings: Linux field-origin Dialog, 2026-10-30 UTC

This is a local Linux x86_64, Debian 13 rootless Weston/Xvfb run using software
rendering and injected XTest keys. It is **not** a live IME, Japanese composition,
physical keyboard, candidate-table or accessibility acceptance. The native
`settings.ime` and `settings.ax` claims remain `NOT_RUN`.

- Framework source: gpui `cfc66b872bfd9613e2a81b499cac0602c84d653b`.
- Consumer and executed app source: Yami `e4bb9ac5fdcc1a5bde0c98d4953e6b3723d9e8b5`.
- Harness source: Yami `34bd5287482087668dc7a38affbd56d09757604e`. The app was built before this driver-only commit, then the retained binary was executed by this harness; these revisions must not be conflated.
- App binary SHA-256: `9f4def827fcd40922a49c152df4becf2c5e18eb9e4293d993cd36d8036822be6` (local path `/workspace/evidence/yami-linux-e4bb9ac-attempt2/app.exe`; not stored in Git).
- Dependencies: Yami native manifest specifies `gpui@0.10.6` and `yami_kumo@0.2.3`; the actual build used the source checkouts above via `moon.work`, not registry-resolved packages. There is no MoonBit lockfile in this source workspace. SHA-256 of native `moon.mod`: `b595be30e056da48775543ef1aa430d7e2ec93cbd9974d95c93d255628994b62`; root `moon.mod`: `922ca99baf05f1be96567b06097486b2ea24a919397ab7e0c5e7c69723893e6f`; gpui `moon.mod`: `242a6f7d6cb99fa78fa10840a37d163b8446d658f07650548f69bebe552b7734`.
- Profile: Debian 13 x86_64, kernel 6.18.57, Weston 14.0.2 X11 backend, Xvfb, xdotool XTest, Mesa llvmpipe; moonc `0.10.15+943464bfa`, moon `0.1.20261012 (748b63c)`, Python 3.12.14. Packages were downloaded from the signed Debian trixie repository and extracted without root; their local checksum inventory SHA-256 is `e5236c089381d7e7adfe4bf28395889614951009f74082752f1636294099e2fe` (local `/workspace/linux-user-apt/packages.sha256`). Some libraries resolve to the host system.
- Command: `xvfb-run --auto-servernum --server-args='-screen 0 800x600x24 -nolisten tcp -ac +extension GLX +render' ./run-session.sh`, with PATH, `LD_LIBRARY_PATH`, `WESTON_DATA_DIR`, and `WESTON_MODULE_MAP` pointing at that extracted profile. The retained script contains the Weston, readiness check and driver invocations; its absolute workspace paths describe this run and must be adapted for another machine.
- Result: **PASS** for direct keyboard `abc`, Enter on the input opens the Dialog, Shift-Tab and Tab traverse cancel/confirm, Escape restores the input, reopen and cancel restore it again, then Save opens/cancels/reopens/confirms and saves. Each step waits for a fresh presented frame. The retained `settings-linux.json` and `settings-linux.log` contain the observed frames and events.
- Run URL: none (local). Report SHA-256 `17d1bb2a15af4473e3f6498b8b787cea99b9fc14652bf82600bb0b2c256d18e4`; log SHA-256 `3776a58a1b8a21984941bec9cc21b92305a12290ba74f0b6651c4da761a86710`. The Weston log SHA-256 is `9b82a49db5941d48c628a251a39d0931db4917318042d338bfbee2f5d664c85e` (local only).
