# Distribution channels and staged migration

Status: Mooncakes and the npm preview tarball are usable; the npm registry
release is pending a maintainer bootstrap. Native OS input and accessibility
claims remain bounded by the Settings qualification.

## Channels

| Channel               | Artifact                                    | Notes                                                                                |
| --------------------- | ------------------------------------------- | ------------------------------------------------------------------------------------ |
| MoonBit               | `f4ah6o/yami_kumo@0.2.3`                    | Library plus published `examples/shared_settings`; `moon add f4ah6o/yami_kumo@0.2.3` |
| Native                | `f4ah6o/yami_kumo_native@0.2.14`            | GPUI `0.10.6`; macOS/Linux/Windows samples                                           |
| JavaScript/TypeScript | `@f12o/yami-kumo@0.1.0-preview.1` tarball | Release-compiled ESM plus declarations; no compiler at install time                  |
| Web                   | built `web/` output                         | Deployed on Pages; no MoonBit toolchain required to serve it                         |

The npm package is not yet on the registry. The trusted-publishing workflow
validates a packed tarball, but the first publication needs a maintainer login
and scope ownership because trusted publishing cannot create a nonexistent
package. Treat "tarball install passes" and "registry install passes" as
separate states.

## Choosing a migration path

| Current use                                  | Move to                     | Keeps working                                                |
| -------------------------------------------- | --------------------------- | ------------------------------------------------------------ |
| MoonBit application using `f4ah6o/yami_kumo` | the same module at `0.2.3`  | imports, `ui/core`, `ui/runtime`, `html`, `dom`              |
| Native application using `yami_kumo_native`  | `0.2.14` with GPUI `0.10.6` | `Mounted`, TextField, Dialog, focus scopes                   |
| JavaScript or TypeScript app                 | the npm tarball             | no MoonBit checkout, compiler, Tailwind or React requirement |
| React app using the starter `AppShell`       | `@f12o/yami-kumo/react`   | real React children and callbacks                            |
| App that only serves the demo                | the built `web/` directory  | static hosting                                               |

## Staged migration

1. Keep the current imports. The MoonBit module and the native module remain
   supported; no rename is required for a first step.
2. Move one screen at a time. For JS/TS, import `renderHtml`,
   `textComponent`, `button`, `input` and `appShell` from the package root, or
   the React `AppShell` from `/react`. Import `styles.css` once.
3. Keep HTML validation and escaping in the library. There is no raw-HTML or
   inline-style escape hatch; unsafe markup is rejected instead of sanitized.
4. Call `enhanceYamiKumo()` only in the browser, after inserting markup. It
   installs idempotent listeners and is a no-op elsewhere.
5. Keep input IDs caller-owned and unique. Field label/help/error references
   and native input state transitions remain the same contract.
6. Verify the screen with the consumer checks below before deleting the old
   path. Rollback is reverting the screen's import, not reinstalling a global
   toolchain.

## Compatibility boundaries

- CommonJS is not packaged. Use ESM or a bundler that consumes ESM.
- React is an optional peer for `/react`; the root entry has no React runtime
  dependency.
- The package ships the supported Web subset (Button, Input, Text, LayerCard,
  semantic AppShell) and does not claim full Cloudflare Kumo parity.
- Native OS text input, IME and accessibility remain separately qualified; a
  package release does not promote them.
- The npm version is independent of Mooncakes. `BUILD.json` records the
  Mooncakes source version used for the artifact.

## Verification

```sh
# Tarball consumers: JS, TypeScript, React, browser, packed artifact
node scripts/build-npm.mjs
node scripts/test-npm-consumers.mjs

# MoonBit source consumers without copies
node scripts/check-shared-ui-consumers.mjs

# Published packages, scripted host contract
cd tests/published-settings && moon update && moon test --target native --deny-warn
```

`scripts/test-npm-consumers.mjs` puts a failing `moon` stub first on `PATH`, so a
passing run proves the consumers did not invoke the compiler.

## Release gates

1. Pack and inspect the tarball (`npm-release` artifact).
2. Publish only an unused `X.Y.Z-preview.N` version from a reviewed main
   revision, through the trusted-publishing workflow and the `npm` environment.
3. Install the exact registry version into a clean consumer and rerun the
   relevant smoke test.
4. Record the registry version, provenance and run URL. Until then the npm
   channel stays `NOT_RUN`.
