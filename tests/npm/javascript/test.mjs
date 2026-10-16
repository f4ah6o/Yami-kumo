import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
import {
  appShell,
  button,
  input,
  text,
  textComponent,
  element,
  fragment,
  layerCard,
  layerCardPrimary,
  layerCardSecondary,
  renderHtml,
} from '@f4ah6o/yami-kumo';
const require = createRequire(import.meta.url);
for (const name of ['react', 'react-dom', '@cloudflare/kumo'])
  assert.throws(() => require.resolve(name));
assert.equal(typeof globalThis.document, 'undefined');
assert.equal(typeof globalThis.window, 'undefined');
assert.equal(renderHtml(text('<script>"&\'')), '&lt;script&gt;&quot;&amp;&#x27;');
const markup = renderHtml(
  appShell({
    brand: text('Workspace'),
    rail: 'Primary',
    sidebar: 'Navigation',
    tabs: 'Tabs',
    contextPanel: 'Details',
    contextPanelOpen: true,
    bottomBar: 'Ready',
    children: layerCard(
      fragment([
        layerCardSecondary('Details'),
        layerCardPrimary(
          fragment([
            textComponent('Heading', { variant: 'heading', as: 'h2' }),
            button('Save', { variant: 'primary', size: 'lg' }),
            input({ id: 'first', label: 'First', description: 'Help' }),
            input({
              id: 'second',
              label: 'Second',
              description: 'Hidden help',
              error: 'Invalid',
              required: false,
            }),
          ]),
        ),
      ]),
      { layered: true },
    ),
  }),
);
assert.match(markup, /<main class="yk-main">/);
assert.match(markup, /aria-describedby="first-description"/);
assert.match(markup, /aria-describedby="second-error"/);
assert.doesNotMatch(markup, /Hidden help| style=/);
const ids = [...markup.matchAll(/\bid="([^"]+)"/g)].map((m) => m[1]);
assert.equal(ids.length, new Set(ids).size);
for (const [, references] of markup.matchAll(
  /(?:for|aria-labelledby|aria-describedby)="([^"]+)"/g,
)) {
  for (const id of references.split(' ')) assert.ok(ids.includes(id), id);
}
for (const variant of [
  'primary',
  'secondary',
  'ghost',
  'destructive',
  'secondary-destructive',
  'outline',
]) {
  for (const size of ['xs', 'sm', 'base', 'lg']) {
    assert.match(renderHtml(button(variant, { variant, size, disabled: true })), /disabled=""/);
  }
}
for (const variant of [
  'heading',
  'body',
  'secondary',
  'success',
  'error',
  'mono',
  'mono-secondary',
]) {
  assert.match(
    renderHtml(textComponent('<text>', { variant, bold: true, truncate: true })),
    /&lt;text&gt;/,
  );
}
assert.equal(renderHtml(element('br')), '<br>');
assert.match(
  renderHtml(element('a', { href: 'https://example.com/?a=1&b=2', title: '"quoted"' }, 'Link')),
  /&amp;b=2/,
);
for (const attrs of [
  { onclick: 'bad()' },
  { style: 'color:red' },
  { href: 'JaVaScRiPt:alert(1)' },
  { src: 'data:text/html,bad' },
  { srcdoc: '<script>' },
]) {
  assert.throws(() => renderHtml(element('a', attrs, 'Unsafe')), TypeError);
}
assert.throws(() => renderHtml(element('script', {}, 'bad()')), TypeError);
assert.throws(() => renderHtml(element('input', {}, 'bad child')), TypeError);
assert.throws(() => renderHtml(textComponent('bad', { as: 'script' })), TypeError);
assert.throws(() => button('bad', { variant: 'unknown' }), TypeError);
assert.throws(() => button('bad', { disabled: 'false' }), TypeError);
assert.throws(() => button('bad', { loading: true }), TypeError);
assert.throws(() => button({ kind: 'text', value: 'forged' }), TypeError);
assert.throws(() => renderHtml({}), TypeError);
assert.throws(() => input({ id: '' }), TypeError);
assert.throws(() => input({ id: 'two words' }), TypeError);
const attrs = { title: 'before' };
const immutable = button('Snapshot', { attrs });
attrs.title = 'after';
assert.match(renderHtml(immutable), /title="before"/);
let listeners = 0;
globalThis.document = { addEventListener: () => listeners++ };
const { enhanceYamiKumo } = await import('@f4ah6o/yami-kumo/dom');
assert.equal(listeners, 0);
enhanceYamiKumo();
enhanceYamiKumo();
assert.equal(listeners, 6);
delete globalThis.document;
console.log(
  'PASS JavaScript: SSR, React-free graph, components, safe HTML, runtime validation, explicit DOM',
);
