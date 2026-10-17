import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { runInNewContext } from 'node:vm';
import test from 'node:test';
import { palettes } from './palette.mjs';
const source = readFileSync(
  process.env.YAMI_PALETTE_DOM_SOURCE || new URL('../../ui/dom/dom.mbt', import.meta.url),
  'utf8',
);
const css = readFileSync(
  process.env.YAMI_PALETTE_CSS_SOURCE || new URL('../../styles/shared-ui.css', import.meta.url),
  'utf8',
);
const block = source.match(
  /extern "js" fn update_button_palette\([\s\S]*? =\n((?:  #\|.*\n)+)/,
)?.[1];
assert.ok(block);
const update = runInNewContext(`(${block.replace(/^  #\| ?/gm, '')})`);
test('production palette FFI changes only two opt-in classes and removes stale paint', () => {
  const classes = new Set(['host-class']);
  const node = {
    classList: {
      toggle(n, on) {
        if (on) classes.add(n);
        else classes.delete(n);
      },
    },
  };
  for (const token of [0, 1, 2, 0, 2, 1, 0]) {
    update(node, token);
    assert.deepEqual(
      [...classes].sort(),
      ['host-class', ...(token ? [`yk-ui-button-${token === 1 ? 'light' : 'dark'}`] : [])].sort(),
    );
  }
});
test('production CSS resolves every frozen role with paint-only scoped selectors', () => {
  const rules = [...css.matchAll(/([^{}]+)\{([^{}]*)\}/g)].filter((m) =>
    /^\.yk-ui-button-(?:light|dark)(?=[:\s]|\[|$)/.test(
      m[1].replace(/\/\*[\s\S]*?\*\//g, '').trim(),
    ),
  );
  assert.equal(rules.length, 12);
  for (const token of ['Light', 'Dark']) {
    const base = '.yk-ui-button-' + token.toLowerCase(),
      values = Object.fromEntries(
        palettes.roles.map((r, i) => [r, `rgb(${palettes[token][i].join(', ')})`]),
      );
    const expected = [
      [
        '',
        {
          'border-color': 'normal_border',
          'background-color': 'normal_fill',
          color: 'enabled_foreground',
        },
      ],
      [':hover', { 'background-color': 'hovered_fill' }],
      [':active', { 'background-color': 'pressed_fill' }],
      ['[aria-busy="true"]', { 'background-color': 'loading_fill' }],
      [':focus-visible', { 'border-color': 'focused_border' }],
      [
        ':disabled',
        {
          'border-color': 'disabled_border',
          'background-color': 'disabled_fill',
          color: 'disabled_foreground',
        },
      ],
    ];
    const actual = rules.filter((m) => m[1].includes(base));
    assert.equal(actual.length, 6);
    for (let i = 0; i < 6; i++) {
      assert.equal(
        actual[i][1]
          .replace(/\/\*[\s\S]*?\*\//g, '')
          .replaceAll("'", '"')
          .trim(),
        base + expected[i][0],
      );
      const declarations = Object.fromEntries(
        actual[i][2]
          .trim()
          .split(';')
          .filter((x) => x.trim())
          .map((x) => x.trim().split(/:\s*/)),
      );
      assert.deepEqual(
        declarations,
        Object.fromEntries(
          Object.entries(expected[i][1]).map(([prop, role]) => [prop, values[role]]),
        ),
      );
    }
  }
});
