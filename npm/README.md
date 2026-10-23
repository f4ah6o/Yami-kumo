# Yami-kumo for JavaScript and TypeScript

Preview tarball for the supported Web subset of Cloudflare Kumo 2.14.0:
Button, Input, Text, LayerCard and semantic AppShell. Native UI is not included.
The package contains release-compiled MoonBit ESM; consumers need neither a
source checkout nor a MoonBit compiler. CommonJS is not supported.

```sh
# Published preview (dist-tag `preview`)
npm install @f12o/yami-kumo@preview

# Or from a packed tarball
npm install ./f12o-yami-kumo-0.1.0-preview.2.tgz
```

`0.1.0-preview.2` is published as `@f12o/yami-kumo` through GitHub OIDC trusted
publishing with SLSA provenance. Both `latest` and `preview` point at
`0.1.0-preview.2`. The npm version is independent of Mooncakes; `BUILD.json`
records the actual Mooncakes source version.

```js
import { appShell, button, fragment, input, renderHtml, textComponent } from '@f12o/yami-kumo';
import { enhanceYamiKumo } from '@f12o/yami-kumo/dom';
import '@f12o/yami-kumo/styles.css';

document.querySelector('#app').innerHTML = renderHtml(
  appShell({
    brand: 'My workspace',
    children: fragment([
      textComponent('Account', { variant: 'heading' }),
      input({
        id: 'account-email',
        label: 'Email',
        description: 'For notifications',
        attrs: { type: 'email' },
      }),
      button('Save', { variant: 'primary' }),
    ]),
  }),
);
enhanceYamiKumo();
```

The default entry also works in Node without browser globals or React.
Nodes are opaque handles. Strings in children become escaped text; use
`fragment` to compose them. `element(tag, attrs, children)` uses MoonBit's
existing safe HTML tag/attribute/URL validation. There is no raw HTML or inline
style escape hatch. Invalid JS props throw `TypeError`; unsafe HTML is rejected
by `renderHtml`. Input IDs are caller-owned and must be unique in the document.
Supply ordinary HTML properties such as `value`, `name`, `type`, `aria-label`
through `attrs` (string or boolean values). The existing MoonBit attribute merge
policy also applies to `attrs`, including overrides of component attributes.

`enhanceYamiKumo()` explicitly installs idempotent document-level listeners for
Input focus, dirty, filled, touched and validity state. Importing `/dom` does
not install listeners. It is a no-op outside a browser. Button uses browser
native semantics. AppShell is a controlled layout: applications own drawer
state, trigger/scrim handlers, focus containment and dismissal; importing `/dom`
does not add shell controllers. The preview does not claim full Kumo parity.

```tsx
import { AppShell, type AppShellProps } from '@f12o/yami-kumo/react';
import '@f12o/yami-kumo/styles.css';

const props: AppShellProps = {
  brand: 'Workspace',
  children: <button onClick={() => alert('Saved')}>Save</button>,
};
export const App = () => <AppShell {...props} />;
```

`/react` packages the existing React AppShell and preserves real React children
and callbacks. Install React 19 yourself (`react`, and `react-dom` for browser
mounting); TypeScript React consumers also install `@types/react`. React and its
types are optional peers and are absent from framework-independent installs.
No Kumo React components, icons, React DOM or build tools are runtime dependencies.

## Styles and embedding

Import the stylesheet once; no Tailwind build or source scanning is needed.
AppShell receives its own layout and theme defaults. Wrap standalone components
in `<div class="yk-scope">` to opt into Kumo's scoped preflight. The generated
package stylesheet scopes reset rules to `.yk-scope` and `.yk-shell` using CSS
`@scope`; use a modern browser with `@scope`, cascade layers and color-mix support.
It does not set host `body`/`#root` dimensions, background, margin or layout.
The starter still imports its existing full-page globals separately.

Kumo/Tailwind theme custom properties on `:root`/`:host`, `[data-theme=kumo]`
and `[data-mode=dark]`, utility class names, `@property` registrations and
keyframe names remain global. This is not Shadow DOM isolation. Hosts with
another Tailwind/Kumo installation should review token/class collisions. Supply
Kumo token overrides on the component wrapper and override `--yk-*` defaults on
`.yk-shell`. The shell retains the starter's viewport-sized responsive geometry;
embedded apps can override its width, height and margin in their own stylesheet.

## Maintainers

From the repository: `pnpm install --frozen-lockfile`, `pnpm run build:npm`,
`pnpm run test:npm`. `pnpm run pack:npm` builds then runs `npm pack` in
`dist/npm`; tarballs land in `dist/`. Packed artifacts have no lifecycle scripts,
compiler invocation or postinstall downloads. CI uploads the tested tarball.
`BUILD.json` records source SHA/dirty state, toolchain and pinned input hashes.
CI uses the repository's MoonBit/compiler-core pin; see `.github/workflows/ci.yml`.

Before any registry release: agree an explicit version/name, confirm scope
ownership with authenticated `npm whoami`/access checks, inspect `npm pack
--dry-run --json`, and pass all isolated consumer tests and independent review
on that source SHA. The manual `npm-publish.yml` workflow defaults to validation
only and can publish the exact tested tarball using OIDC after one-time npm
Trusted Publisher setup. See the repository's
[release setup guide](https://github.com/f4ah6o/Yami-kumo/blob/main/docs/npm-trusted-publishing.md)
for registration fields, first-publication bootstrap and release steps.

MIT project license and upstream Kumo, Tailwind and MoonBit core notices are
included under `LICENSE` and `licenses/`. Generated CSS is adapted only by
scoping reset rules. MoonBit core is compiled into the ESM under its bundled
Apache-2.0 license.
