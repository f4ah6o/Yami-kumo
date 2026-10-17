import assert from 'node:assert/strict';
import postcss from 'postcss';

const slots = new Set([
  'normal-border',
  'focused-border',
  'disabled-border',
  'normal-fill',
  'hovered-fill',
  'pressed-fill',
  'loading-fill',
  'disabled-fill',
  'enabled-foreground',
  'disabled-foreground',
]);
const rootSelector = (theme) => `.yk-ui-root[data-yk-theme='${theme}']`;
const scope = `:where(${rootSelector('light')}, ${rootSelector('dark')}) .yk-ui-button:not(.yk-ui-button-light):not(.yk-ui-button-dark)`;
const buttonSelectors = new Set(
  ['', ':hover', ':active', ':focus', "[aria-busy='true']", ':disabled'].map(
    (state) => scope + state,
  ),
);
const explicitButtonSelectors = new Set(
  ['light', 'dark'].flatMap((theme) =>
    ['', ':hover', ':active', ':focus-visible', "[aria-busy='true']", ':disabled'].map(
      (state) => `.yk-ui-button-${theme}${state}`,
    ),
  ),
);
const normalize = (selector) => selector.trim().replace(/\s+/g, ' ').replaceAll('"', "'");

export function checkSharedStylesheetScope(css) {
  const sheet = postcss.parse(css);
  const themes = [];
  const buttons = [];
  const explicitButtons = [];
  for (const rule of sheet.nodes) {
    if (rule.type === 'comment') continue;
    assert.equal(rule.type, 'rule', 'shared CSS cannot import or introduce global at-rules');
    const selectors = postcss.list.comma(rule.selector).map(normalize);
    for (const selector of selectors) {
      if (/^\.yk-ui-(?:column|row|card|(?:gap|padding)-(?:0|4|8|12|16|24))$/.test(selector))
        continue;
      if (selector === rootSelector('light') || selector === rootSelector('dark')) {
        assert.equal(selectors.length, 1, 'a palette belongs to exactly one scoped root');
        const properties = new Set();
        for (const declaration of rule.nodes) {
          assert.equal(declaration.type, 'decl');
          assert.equal(Boolean(declaration.important), false);
          assert.ok(declaration.prop.startsWith('--yk-button-'), declaration.prop);
          assert.ok(slots.has(declaration.prop.slice('--yk-button-'.length)), declaration.prop);
          assert.ok(
            !properties.has(declaration.prop),
            `duplicate palette token ${declaration.prop}`,
          );
          assert.match(declaration.value, /^rgb\(\d+, \d+, \d+\)$/);
          properties.add(declaration.prop);
        }
        assert.equal(properties.size, slots.size, 'every Button palette declares its ten tokens');
        themes.push(selector);
        continue;
      }
      if (explicitButtonSelectors.has(selector)) {
        for (const declaration of rule.nodes) {
          assert.equal(declaration.type, 'decl');
          assert.equal(Boolean(declaration.important), false);
          assert.ok(
            ['border-color', 'background-color', 'color'].includes(declaration.prop),
            declaration.prop,
          );
          assert.match(declaration.value, /^rgb\(\d+, \d+, \d+\)$/);
        }
        explicitButtons.push(selector);
        continue;
      }
      assert.ok(
        buttonSelectors.has(selector),
        `unscoped or unsupported shared selector: ${selector}`,
      );
      for (const declaration of rule.nodes) {
        assert.equal(declaration.type, 'decl');
        assert.equal(Boolean(declaration.important), false);
        assert.ok(
          ['border-color', 'background-color', 'color'].includes(declaration.prop),
          declaration.prop,
        );
        const slot = declaration.value.match(/^var\(--yk-button-([a-z-]+)\)$/)?.[1];
        assert.ok(slots.has(slot), `non-token Button color: ${declaration.value}`);
      }
      buttons.push(selector);
    }
  }
  assert.deepEqual(themes.sort(), [rootSelector('dark'), rootSelector('light')]);
  assert.deepEqual(buttons.sort(), [...buttonSelectors].sort());
  assert.deepEqual(explicitButtons.sort(), [...explicitButtonSelectors].sort());
}
