# Publish Yami-kumo as a consumable JavaScript/TypeScript npm package

- Status: published; registry install verified; trusted publishing exercised for `0.1.0-preview.2`.
- Tracking: repository Markdown issue packet; GitHub Issues is currently disabled for this repository.
- Repository: `f4ah6o/Yami-kumo`.
- Inspected baseline: [`955c5bbc31f279976049a6b14a02424410010c6d`](https://github.com/f4ah6o/Yami-kumo/tree/955c5bbc31f279976049a6b14a02424410010c6d).
- Preview package name: `@f12o/yami-kumo`; registry scope access and publishing permissions still require verification.

## Trusted Publishing preparation — 2026-10-20

- `npm-publish.yml` adds manual main-only validation and optional OIDC publishing
  of the exact packed artifact after JS/TS/browser/React consumer acceptance.
- Publishing defaults to false; only the publish job has `id-token: write` and
  uses GitHub environment `npm`. Releases remain explicit preview versions.
- See [setup and bootstrap instructions](../../docs/npm-trusted-publishing.md).
  npm publisher registration, scope ownership, first registry publication and
  registry-installed acceptance remain pending. Registry lookup returned E404.

## Implementation checkpoint — 2026-10-16

- [PR #23](https://github.com/f4ah6o/Yami-kumo/pull/23) merged the installable `@f12o/yami-kumo@0.1.0-preview.1` tarball implementation into `main` (merge commit `3dd5dba259318afcbe460ebce33c41f3154c25c3`).
- The packed artifact exposes ESM, TypeScript declarations, DOM and React entries, CSS, and applicable licenses. The private starter, Mooncakes module, and native code remain separate.
- On PR #23 HEAD `73e66ca585b98fe38c6c2c9256a0624a75737e42`, [CI](https://github.com/f4ah6o/Yami-kumo/actions/runs/38857614457) and [Native UI proof](https://github.com/f4ah6o/Yami-kumo/actions/runs/38857614583) completed with 6/6 jobs successful. Tests include packed-tarball JS/TS/browser/React consumers and existing Button checks.
- The package is **not confirmed published to the npm registry**: name/scope ownership, authentication, explicit release version, and registry-installed consumer verification remain open. Tarball completion is not a registry release.
- This PR updates a documentation issue only. The sections below preserve the design and acceptance contract; completed preview requirements are marked separately from the remaining release gate.

## Automation checkpoint — 2026-10-23

- GitHub environment `npm` allows only `main`; the npm trusted publisher is
  registered for `f4ah6o/Yami-kumo`, workflow `npm-publish.yml`, environment
  `npm`.
- `publish=true` run <https://github.com/f4ah6o/Yami-kumo/actions/runs/39861636099>
  published `0.1.0-preview.2` without an OTP.
- A clean registry install of `0.1.0-preview.2` passes root, `/dom` and
  `/react` smoke checks; npm reports SLSA provenance.
- `latest` and `preview` both point at `0.1.0-preview.2` (moved 2026-10-23).

## Publication checkpoint — 2026-10-23

- The `@f4ah6o` npm organization does not exist for the authenticated account
  (`Scope not found` on publish), so the preview moved to `@f12o`.
- Bootstrap publish: `@f12o/yami-kumo@0.1.0-preview.1`, tarball SHA-256
  `1dcd2afa6cf4fc1c69790b4cb5ee501a9f2ad36a426830ae576a9264760a7899`.
- Registry lookup returns 200 and `npm view` reports `0.1.0-preview.1`.
- Clean consumer (`npm install --save-exact @f12o/yami-kumo@0.1.0-preview.1`)
  passes root, `/dom` and `/react` smoke checks; `styles.css` and `BUILD.json`
  are present.
- Later releases still need the GitHub `npm` environment and npm trusted
  publisher registration; the bootstrap OTP flow is not a release automation.

## Validation checkpoint — 2026-10-23

- Trusted-publishing workflow `publish=false` completed/success on main:
  <https://github.com/f4ah6o/Yami-kumo/actions/runs/39809538188>
- Artifact `npm-release`: `f12o-yami-kumo-0.1.0-preview.1.tgz`,
  SHA-256 `e36f25edb350de769b3df5ca00d08d0d599180912864e7f8aa2464be75430880`.
- `npm-consumers.json` status `PASS` for JavaScript, TypeScript, React and
  browser consumers; `npm publish --dry-run` passed.
- Registry publication remains blocked: `npm whoami` returns E401 (no
  authenticated maintainer in this environment), the package lookup returns
  E404, and trusted publishing cannot create a nonexistent package. The first
  version still needs an interactive maintainer bootstrap as described in
  `docs/npm-trusted-publishing.md`. Registry-installed acceptance is `NOT_RUN`.

## Historical problem (2026-10-11 baseline)

At the inspected baseline, Yami-kumo could be copied as an application starter and its MoonBit library could be consumed through Mooncakes, but JavaScript/TypeScript applications could not yet install a supported npm library with stable imports, declarations, and packaged styles.

Publishing the existing application manifest alone would not have solved this:

- `package.json` has `private: true`, application dependencies, and no library `exports` or declaration entry.
- `browser/moon.pkg` already builds a MoonBit foreign library as JavaScript ESM, but `browser/parity.mbt` exports `renderParityCase` and `enhanceYamiKumo` for the comparison gallery rather than a general component API.
- `src/shell/AppShell.tsx` is reusable React source, but has no packaged JS/declaration entry.
- `src/styles.css` combines shell rules with starter-wide `body`, `#root`, and other global styling.
- Generated Kumo CSS and its upstream license are checked in, but no npm artifact contract guarantees their inclusion.

## Goal

A consumer installs the published package and uses it from normal JS or TS without installing MoonBit, copying this repository, running its generators, or compiling `.mbt` source. Both plain browser applications and React applications can reuse Yami-kumo's existing supported Web UI.

MoonBit remains the implementation of the existing framework-independent HTML validation, escaping, components, and field-state policy. The npm package distributes production-compiled JS and a small JS/TS-facing boundary. The existing Mooncakes module remains supported.

## Scope and decisions

1. Add a dedicated publishable package manifest/build output while keeping the starter application's root manifest private. The starter and `demo` branch remain usable.
2. Ship ESM JS, TypeScript declarations, external CSS, README, project license, and the applicable Kumo license/acknowledgements. CommonJS is outside the first release.
3. Keep the default entry React-independent. Export the existing React `AppShell` through a separate `/react` subpath with React as an optional peer dependency, externalized from the build.
4. Use only the currently supported component subset: Button, Input, Text, LayerCard, and semantic AppShell. npm publication does not claim full Kumo compatibility.
5. Keep GPUI hosts, native libraries, native build tools, parity fixtures, and showcase content outside the npm runtime and tarball.
6. Treat package preparation and actual registry publication as separate checkpoints. This document PR changes documentation only; the preview implementation landed separately in #23.

## Proposed public surface

These paths describe the original proposed contract. PR #23 now provides them in a tested preview tarball, not a published registry release.

| Import path                  | Contract                                                                                                                  |
| ---------------------------- | ------------------------------------------------------------------------------------------------------------------------- |
| `@f12o/yami-kumo`            | React-independent node/component composition and safe HTML rendering, usable in Node for rendering and in browser bundles |
| `@f12o/yami-kumo/dom`        | Explicit browser enhancement after markup insertion; importing the module does not initialize listeners                   |
| `@f12o/yami-kumo/react`      | Existing `AppShell` and `AppShellProps`, preserving semantic slots and responsive behavior                                |
| `@f12o/yami-kumo/styles.css` | Ordered, prebuilt Kumo/component/shell styles; no consumer Tailwind build or source scanning required                     |

### JavaScript/TypeScript boundary

- Expose typed component props and composition for `text`, `button`, `input`, `textComponent`, `layerCard`, `appShell`, and `renderHtml`; finalize signatures against the existing MoonBit contract before implementation.
- Keep MoonBit runtime representations and generated symbol names private. Consumers must not depend on `_build` paths, fixture JSON, or `renderParityCase`.
- Accept ordinary JS strings, booleans, supported variants, props, and children. Validate runtime inputs as well as declaring their TS types.
- Preserve HTML escaping, URL/attribute validation, the lack of a raw-HTML/inline-style escape hatch, and stable caller-provided Input IDs.
- Preserve field label/help/error references and native input state transitions supported by the existing DOM adapter.
- Keep public declarations consistent with actual compiled exports; the facade translates values rather than reimplementing MoonBit component behavior.
- Default-entry imports and rendering must work without `window` or `document`. DOM enhancement runs only when explicitly called in a browser.

### React and dependency boundaries

- The `/react` entry packages the existing `AppShell` implementation, including its props and shell layout contract; it does not substitute string-rendered HTML for React children.
- Keep React/JSX runtime imports external and require a compatible consumer React installation only for `/react`. Exercise the currently used React 19 line before declaring a supported version range.
- Do not make `react-dom`, icon packages, Vite+, TypeScript, the MoonBit compiler, or the React Kumo package required production dependencies of the framework-independent entry.
- Kumo remains pinned to the inspected `2.14.0` contract until a deliberate upstream update. Any Kumo code needed for extraction stays build-time only for this first package surface.
- Consumers needing additional React Kumo components install Kumo explicitly; blanket Kumo re-exports are outside this issue.

### CSS and artifact contract

- Build a distributable stylesheet from the pinned `styles/kumo-standalone.css`, `styles/yami-kumo-components.css`, and reusable shell styles in the required order.
- Extract shell styling from starter-specific page styling. Importing the package stylesheet must not require a host element named `#root`, overwrite host `body` layout/background, or import the starter/demo app.
- Document any remaining global Kumo theme/reset selectors and how the host supplies or overrides theme tokens. Verify behavior in an existing page as well as a full-window shell.
- Package CSS through an explicit export, and mark CSS as side-effectful so consumer bundlers retain an intentional stylesheet import.
- Include `LICENSE`, `licenses/cloudflare-kumo-LICENSE`, and applicable acknowledgements in the tarball.
- Restrict `files`/exports to supported artifacts; omit `.mbt` build inputs, native outputs, gallery data, source checkout dependencies, and accidental application assets.
- Resolve all runtime imports and any auxiliary generated JS from inside the tarball or declared dependencies. No consumer compilation, postinstall download, or `moon` invocation is permitted.

## Implementation slices

### 1. Public bridge and declarations

Create a production JS export bridge separate from the parity module, add the typed JS/TS facade, and package the existing React shell. Test supported values, invalid input behavior, HTML escaping, stable IDs, and Node rendering through the public entry points.

### 2. Package build and styles

Add the dedicated publishable manifest with `exports`, declaration mappings, CSS side-effect metadata, dependency boundaries, and a files allowlist. Build release JS and declarations before `npm pack`, package CSS/licenses, and keep starter/parity builds working.

### 3. Consumer acceptance from the packed artifact

Install the `.tgz` in isolated fixtures outside the source checkout. Fixtures must not resolve workspace files, aliases, root `node_modules`, or `_build` output. Include a JS-only consumer, a TypeScript consumer, a browser/Vite consumer, and a React consumer.

### 4. Release automation and documentation

Document install/import/style examples and the exact supported Web subset. Use explicit version releases, verify registry name/scope/authentication, run packed-consumer checks before publishing, and record the package version, source SHA, compiler/core pin, and Kumo contract version. Build tooling requirements belong to maintainers, not package consumers.

Keep the npm package version in the release manifest. If it differs from the Mooncakes module version, document the mapping rather than silently coupling release numbers.

## Acceptance criteria

Checked entries below are evidenced by PR #23's packed-artifact CI and consumer tests, not by a published registry version. Future releases must rerun the same gates.

- [ ] The intended npm name is available or an agreed replacement is recorded; publishing access is verified.
- [x] `npm pack --dry-run --json` contains all supported JS/declaration/CSS/license files and excludes starter/demo/native/parity artifacts.
- [x] A JS-only fixture installs the `.tgz`, imports the default entry, renders a shell and supported components, and has no MoonBit compiler or source checkout available.
- [x] The framework-independent fixture imports/renders with React, React DOM, and `@cloudflare/kumo` absent; `npm ls --all` succeeds for its installed dependency graph.
- [x] A Node fixture imports the default entry and renders without browser globals or automatic DOM enhancement.
- [x] The TypeScript fixture passes `tsc --noEmit` against installed declarations and rejects unsupported props/variants.
- [x] A browser/Vite fixture imports the installed JS and `styles.css`, builds without Tailwind source scanning, and displays the supported shell/components.
- [x] A React fixture imports `/react`, uses `AppShellProps`, preserves React children/event handlers, and uses the consumer's React instance.
- [x] Browser checks cover Input focus/dirty/filled/touched/validity markers, multiple-field references, Button variants, and desktop/phone shell regions from the supported subset.
- [x] Importing `styles.css` preserves an unrelated host page's body/root layout; documented Kumo theme/reset effects are explicit.
- [x] Hostile text/attribute/URL inputs retain existing validation/escaping, and strict external-stylesheet CSP behavior remains supported.
- [x] Consumer installs execute no MoonBit compilation or postinstall fetching; exported entries resolve entirely from the packed artifact.
- [x] Existing starter and parity checks remain green alongside package-consumer checks.
- [x] Documentation clearly distinguishes installable Web functionality, React requirements, supported Kumo subset, and native UI support.
- [ ] An explicit-version npm release is published only after preparation/authentication checks pass, and a clean install of that registry version passes the consumer smoke checks.

## Validation plan

These are requirements for the implementation; they have not been run by this documentation-only proposal.

| Target            | Evidence                                                                                                                      |
| ----------------- | ----------------------------------------------------------------------------------------------------------------------------- |
| Source regression | Existing `pnpm run moon:build`, `vp check`, `vp exec tsc --noEmit`, `vp test`, `vp build`, and `pnpm run build:parity` checks |
| Package contents  | `npm pack --dry-run --json` and `npm pack` artifact manifest, with export/declaration/license resolution checked              |
| JS and SSR        | Isolated installed-tarball Node smoke test with no browser globals/MoonBit/React dependencies                                 |
| TypeScript        | Installed-tarball `tsc --noEmit` fixture, including invalid-prop assertions                                                   |
| Browser and React | Installed-tarball browser build, rendered UI/interaction evidence, and React dependency graph                                 |
| Release           | Versioned tarball/source metadata and the same smoke tests after installing the published registry version                    |

## Risks and release blockers

- At the inspected baseline, JS exports were parity-oriented. PR #23 added the separate public bridge and declarations for the preview artifact.
- Separating shell CSS may expose assumptions about viewport sizing or global theme tokens. Check embedding in an unrelated existing application, not only the starter page.
- Optional React peers and declaration resolution must be proven with both React-free and React fixtures; importing `/react` without React should give an actionable dependency error.
- Scope/name availability and publishing credentials remain unverified. Do not describe the preview artifact as already published to the registry.
- A Kumo/toolchain update may change generated classes, output ABI, or behavior; pin and rerun parity/packed-consumer checks for each release.

## Inspected sources

- [Application manifest](https://github.com/f4ah6o/Yami-kumo/blob/955c5bbc31f279976049a6b14a02424410010c6d/package.json)
- [MoonBit ESM build configuration](https://github.com/f4ah6o/Yami-kumo/blob/955c5bbc31f279976049a6b14a02424410010c6d/browser/moon.pkg)
- [Current parity exports](https://github.com/f4ah6o/Yami-kumo/blob/955c5bbc31f279976049a6b14a02424410010c6d/browser/parity.mbt)
- [React AppShell](https://github.com/f4ah6o/Yami-kumo/blob/955c5bbc31f279976049a6b14a02424410010c6d/src/shell/AppShell.tsx)
- [Starter/shell styles](https://github.com/f4ah6o/Yami-kumo/blob/955c5bbc31f279976049a6b14a02424410010c6d/src/styles.css)
- [MoonBit component documentation](https://github.com/f4ah6o/Yami-kumo/blob/955c5bbc31f279976049a6b14a02424410010c6d/README.mbt.md)
- [Existing CI](https://github.com/f4ah6o/Yami-kumo/blob/955c5bbc31f279976049a6b14a02424410010c6d/.github/workflows/ci.yml)
- [npm package manifest reference](https://docs.npmjs.com/cli/v11/configuring-npm/package-json/)
- [TypeScript declaration publishing](https://www.typescriptlang.org/docs/handbook/declaration-files/publishing.html)
