import assert from 'node:assert/strict';
import postcss from 'postcss';

const buttonSlots = new Set([
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
const shellSlots = new Set([
  'background',
  'panel',
  'subtle',
  'border',
  'strong-border',
  'text',
  'muted',
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
const shellRegionClasses = [
  'topbar',
  'brand-group',
  'navigation-trigger',
  'global-search',
  'header-end',
  'header-actions',
  'account-menu',
  'workspace',
  'rail',
  'sidebar',
  'main-column',
  'tabs',
  'main',
  'context-panel',
  'bottom-bar',
];
const normalize = (selector) => selector.trim().replace(/\s+/g, ' ').replaceAll('"', "'");
const shellSelector = (selector) =>
  /^\.yk-ui-shell(?:[\s:[.]|$)/.test(selector) ||
  new RegExp(`^\\.yk-ui-(?:${shellRegionClasses.join('|')})(?:[\\s:[.]|$)`).test(selector) ||
  /^\.yk-ui-root\[data-yk-theme(?:='(?:light|dark)')?\] \.yk-ui-shell \.yk-ui-(?:text|card)$/.test(
    selector,
  );

function checkDeclarations(rule) {
  for (const declaration of rule.nodes) {
    assert.equal(declaration.type, 'decl');
    assert.equal(Boolean(declaration.important), false);
  }
}

export function checkSharedStylesheetScope(css) {
  const sheet = postcss.parse(css);
  const buttonThemes = [];
  const shellThemes = [];
  const buttons = [];
  const explicitButtons = [];
  const visit = (rule, insideMedia = false) => {
    if (rule.type === 'comment') return;
    if (rule.type === 'atrule') {
      assert.equal(rule.name, 'media', 'shared CSS cannot import or introduce global at-rules');
      assert.equal(normalize(rule.params), '(max-width: 820px)');
      assert.equal(insideMedia, false, 'nested media queries are unsupported');
      for (const child of rule.nodes) visit(child, true);
      return;
    }
    assert.equal(rule.type, 'rule', 'shared CSS cannot import or introduce global at-rules');
    const selectors = postcss.list.comma(rule.selector).map(normalize);
    for (const selector of selectors) {
      if (/^\.yk-ui-(?:column|row|card|(?:gap|padding)-(?:0|4|8|12|16|24))$/.test(selector))
        continue;
      if (selector === rootSelector('light') || selector === rootSelector('dark')) {
        assert.equal(selectors.length, 1, 'a palette belongs to exactly one scoped root');
        const properties = new Set();
        const kinds = new Set();
        for (const declaration of rule.nodes) {
          assert.equal(declaration.type, 'decl');
          assert.equal(Boolean(declaration.important), false);
          if (declaration.prop.startsWith('--yk-button-')) {
            kinds.add('button');
            const slot = declaration.prop.slice('--yk-button-'.length);
            assert.ok(buttonSlots.has(slot), declaration.prop);
          } else {
            assert.ok(declaration.prop.startsWith('--yk-shell-'), declaration.prop);
            kinds.add('shell');
            const slot = declaration.prop.slice('--yk-shell-'.length);
            assert.ok(shellSlots.has(slot), declaration.prop);
          }
          assert.ok(
            !properties.has(declaration.prop),
            `duplicate palette token ${declaration.prop}`,
          );
          assert.match(declaration.value, /^rgb\(\d+, \d+, \d+\)$/);
          properties.add(declaration.prop);
        }
        assert.equal(kinds.size, 1, 'a root palette block must be one token family');
        const kind = [...kinds][0];
        const expected = kind === 'button' ? buttonSlots : shellSlots;
        assert.equal(properties.size, expected.size, `every ${kind} palette declares its tokens`);
        if (kind === 'button') buttonThemes.push(selector);
        else shellThemes.push(selector);
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
      if (shellSelector(selector)) {
        checkDeclarations(rule);
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
        assert.ok(buttonSlots.has(slot), `non-token Button color: ${declaration.value}`);
      }
      buttons.push(selector);
    }
  };
  for (const rule of sheet.nodes) visit(rule);
  assert.deepEqual(buttonThemes.sort(), [rootSelector('dark'), rootSelector('light')]);
  assert.deepEqual(shellThemes.sort(), [rootSelector('dark'), rootSelector('light')]);
  assert.deepEqual(buttons.sort(), [...buttonSelectors].sort());
  assert.deepEqual(explicitButtons.sort(), [...explicitButtonSelectors].sort());
}
