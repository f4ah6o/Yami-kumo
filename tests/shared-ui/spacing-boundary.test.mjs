import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { runInNewContext } from 'node:vm';
import test from 'node:test';
const source = readFileSync(
  process.env.SHARED_UI_SPACING_SOURCE || new URL('../../ui/dom/dom.mbt', import.meta.url),
  'utf8',
);
const block = source.match(/extern "js" fn update_spacing\([\s\S]*? =\n((?:  #\|.*\n)+)/)?.[1];
assert.ok(block);
const update = runInNewContext(`(${block.replace(/^  #\| ?/gm, '')})`);
test('production spacing FFI replaces closed classes without changing unrelated classes', () => {
  const classes = new Set(['yk-ui-row', 'user-class']);
  const node = {
    classList: {
      toggle(name, on) {
        if (on) classes.add(name);
        else classes.delete(name);
      },
    },
  };
  for (const value of [0, 4, 8, 12, 16, 24]) {
    update(node, value, value);
    assert.deepEqual(
      [...classes].sort(),
      ['yk-ui-row', 'user-class', `yk-ui-gap-${value}`, `yk-ui-padding-${value}`].sort(),
    );
  }
  update(node, -1, -1);
  assert.deepEqual([...classes].sort(), ['user-class', 'yk-ui-row']);
});

test('production spacing stylesheet has only scoped selectors and exact token declarations', () => {
  const css = readFileSync(new URL('../../styles/shared-ui.css', import.meta.url), 'utf8').replace(
    /\/\*[\s\S]*?\*\//g,
    '',
  );
  for (const match of css.matchAll(/([^{}]+)\{([^{}]*)\}/g)) {
    for (const selector of match[1].trim().split(/\s*,\s*/))
      assert.match(selector, /^\.yk-ui-[a-z0-9-]+$/);
  }
  for (const value of [0, 4, 8, 12, 16, 24]) {
    for (const property of ['gap', 'padding']) {
      assert.match(
        css,
        new RegExp(`\\.yk-ui-${property}-${value}\\s*\\{\\s*${property}: ${value}px;\\s*\\}`),
      );
    }
  }
});
