# Isolated published Settings audit — 2026-10-30 21:33 UTC

This is a scripted baseline and a negative compatibility test, not validation of the new runner or a GUI/IME run. Source SHAs cannot be inferred from registry version strings.

## Inputs and isolation

- Fixture/harness: `f4ah6o/Yami-kumo` Git commit `66e1af1c307400e95256e4857d19ee8eab64de02`, `tests/published-settings/settings_test.mbt` SHA-256 `aca7ab6594011babb5ef9c9ac801b2f6bffa3a01e602ceef367dbfee5b3be50d`. This fixture has the same bytes as the previously recorded main fixture.
- Copied only `moon.mod`, `moon.pkg`, `settings_test.mbt` to a new standalone directory. In its manifest select the existing CI matrix pair `gpui@0.10.6`, `yami_kumo_native@0.2.14`; no `moon.work` or source override.
- Separate MOON_HOME `/workspace/registry-audit-clean/moon` began without a `registry` directory; only `bin`, `lib`, `include`, `share` symlink to pinned installed toolchain. `moon update` cloned a fresh registry index and test output says it downloaded all three archives, not `Using cached`.
- Resolved package list: gpui `0.10.6`, Yami root `0.2.3`, Yami native `0.2.14`. All three index entries are not yanked. This fixture does not generate a dependency lockfile; `dependencies.log`, exact manifest and downloaded archive checksums are the recorded resolution.
- OS Linux Debian 13, kernel `6.18.57`, x86_64. Moon `0.1.20261012 (748b63c)`, moonc `0.10.15+943464bfa`. Tool SHA-256: moon `a31026b83410607909ebae469fa19e46c32201cfe403be6099e1da961a5ebf0f`; moonc `fb950cbc125168c49523ef554d2649effd66499c596dafcb15c80b561d45fd8c`; moonrun `ba44070aa78d89c2c6da6524d2aa782e46b18cb4a42dd31cd13bf588107089cf`.

## Exact resolved registry archives

| Package                   | Version  | Downloaded zip SHA-256                                             |
| ------------------------- | -------- | ------------------------------------------------------------------ |
| `f4ah6o/gpui`             | `0.10.6` | `1f525737423f7ca83410fd23184f9bdea0a8eda81e7711b6e6dee968d7ab8b88` |
| `f4ah6o/yami_kumo`        | `0.2.3`  | `1c46f9f144bd972db7d9dc839aa409a84f389a407d175e5dd751e1d93e3f2b0d` |
| `f4ah6o/yami_kumo_native` | `0.2.14` | `d76663c866f6c8845b5a9c5211799e2ccb537647a1b5b1667d37092547c4eb14` |

These hashes match the cloned registry index. The index version and repository SHA correspondence were not independently established.

## Commands and outcomes

The following setup repeats the isolation. `AUDIT_TOOLCHAIN` must point to the recorded MoonBit toolchain; `AUDIT_REPO` must contain the specified commit. `mktemp` creates an empty directory and the registry is populated only by the subsequent `moon update` and test:

```sh
AUDIT_TOOLCHAIN=/workspace/yami-tools
AUDIT_REPO=/workspace/yami-ordered
AUDIT_ROOT=$(mktemp -d)
mkdir -p "$AUDIT_ROOT/moon" "$AUDIT_ROOT/consumer" "$AUDIT_ROOT/candidate"
for part in bin lib include share; do ln -s "$AUDIT_TOOLCHAIN/$part" "$AUDIT_ROOT/moon/$part"; done
git -C "$AUDIT_REPO" archive 66e1af1c307400e95256e4857d19ee8eab64de02 tests/published-settings | tar -x -C "$AUDIT_ROOT/consumer" --strip-components=2
python3 - "$AUDIT_ROOT/consumer/moon.mod" <<'PYCODE'
from pathlib import Path
import sys
path = Path(sys.argv[1])
path.write_text(path.read_text().replace('gpui@0.10.5', 'gpui@0.10.6').replace('yami_kumo_native@0.2.13', 'yami_kumo_native@0.2.14'))
PYCODE
export MOON_HOME="$AUDIT_ROOT/moon"
export PATH="$MOON_HOME/bin:$PATH"
cd "$AUDIT_ROOT/consumer"
```

Then run:

```
moon version --all
moon update
moon test --target native --deny-warn
moon tree
```

- Published fixture: **PASS, 1/1**, scripted backend. `test.log` SHA-256 `e83a0086bac0a37758c1ef76421b14cd4eaac56489ba60b29a633b044fa9dcf8`; manifest SHA-256 `b35ea7ff34d8d68a02ead4b61a0f0b914187e1c63029c847a407eb959368fdf3`; binary SHA-256 `97fc9b82c5394a00cccbf0b2e0d84271590e8223df476e56f313ec1bfdff5022` (blackbox), `92662943c7b788ada43f65bf3cd4b20ec71c5d908ff7afbfc036751c59e654d5` (internal). They are test binaries, not a live app.
- Negative compatibility: `git archive 66e1af1c307400e95256e4857d19ee8eab64de02 native` to a separate directory; with the same downloaded registry archives and no workspace override run `moon check ui --target native --deny-warn` from its `native` directory. **FAIL as expected, 4 errors**: GPUI `SessionOperation::Insert` and Yami root `Runtime::has_pending_actions`/`next_text_changed_for` are absent. `candidate-check.log` SHA-256 `ad51aa4be35a1eebc13cccc0690460aba25e75113c4bd944205280a02fd2b73d`. The cached messages in this second command refer only to the just-downloaded isolated archives, not pre-existing workspace cache.

No run URL; raw logs and archive bytes remain in this local directory. The first result covers the older published implementation. It does not establish recovery of the accepted commit, exact PR source integration, live IME, Web, or macOS.

The raw command logs are retained here as deterministic `.log.gz` files. The hashes above refer to their uncompressed bytes; the standalone workspace originally contained the plain logs.
