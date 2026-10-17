import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import test from 'node:test';
import { checkSharedStylesheetScope } from './theme-stylesheet.mjs';

const css = readFileSync(new URL('../../styles/shared-ui.css', import.meta.url), 'utf8');
const scopedButton =
  ":where(.yk-ui-root[data-yk-theme='light'], .yk-ui-root[data-yk-theme='dark']) .yk-ui-button";

test('shared CSS permits scoped palettes without admitting global selectors or theme geometry', () => {
  checkSharedStylesheetScope(css);
  for (const [name, before, after] of [
    ['global palette', ".yk-ui-root[data-yk-theme='light']", ':root'],
    ['unscoped Button', scopedButton, '.yk-ui-button'],
    ['global selector in a group', scopedButton, `${scopedButton}, button`],
    [
      'unscoped branch inside where',
      scopedButton,
      scopedButton.replace(".yk-ui-root[data-yk-theme='dark']", 'body'),
    ],
    ['theme changes geometry', `${scopedButton} {`, `${scopedButton} { padding: 24px;`],
  ]) {
    assert.ok(css.includes(before), `negative control found: ${name}`);
    assert.throws(
      () => checkSharedStylesheetScope(css.replace(before, after)),
      assert.AssertionError,
      name,
    );
  }
  assert.throws(
    () => checkSharedStylesheetScope(`${css}\n@import url('/unscoped.css');`),
    assert.AssertionError,
  );
});
