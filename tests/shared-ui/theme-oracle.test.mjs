import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import test from 'node:test';
import { checkThemeColors } from './theme.mjs';

const fixture = JSON.parse(
  await readFile(new URL('../../fixtures/shared-ui/button-theme-v1.json', import.meta.url)),
);

test('shared theme oracle covers both palettes and every overlapping state', () => {
  assert.deepEqual(Object.keys(fixture.themes).sort(), ['dark', 'light']);
  assert.equal(fixture.states.length, 32);
  const stateKeys = ['disabled', 'loading', 'pressed', 'hovered', 'focused'];
  assert.equal(
    new Set(fixture.states.map((state) => stateKeys.map((key) => state[key]).join(','))).size,
    32,
  );
  const slots = [
    'normal_border',
    'focused_border',
    'disabled_border',
    'normal_fill',
    'hovered_fill',
    'pressed_fill',
    'loading_fill',
    'disabled_fill',
    'enabled_foreground',
    'disabled_foreground',
  ].sort();
  for (const [theme, palette] of Object.entries(fixture.themes)) {
    assert.deepEqual(Object.keys(palette).sort(), slots);
    for (const color of Object.values(palette)) {
      assert.equal(color.length, 3);
      for (const channel of color)
        assert.ok(Number.isInteger(channel) && channel >= 0 && channel <= 255);
    }
    for (const state of fixture.states) {
      for (const key of stateKeys) assert.equal(typeof state[key], 'boolean');
      const css = (slot) => `rgb(${palette[slot].join(', ')})`;
      const observation = {
        ...state,
        theme,
        border: css(state.border),
        fill: css(state.fill),
        foreground: css(state.foreground),
        retained: true,
      };
      assert.deepEqual(checkThemeColors(observation, fixture), {
        border: state.border,
        fill: state.fill,
        foreground: state.foreground,
      });
      for (const field of ['border', 'fill', 'foreground']) {
        assert.throws(
          () => checkThemeColors({ ...observation, [field]: 'rgb(255, 0, 255)' }, fixture),
          assert.AssertionError,
        );
      }
      assert.throws(
        () => checkThemeColors({ ...observation, retained: false }, fixture),
        assert.AssertionError,
      );
      assert.throws(
        () => checkThemeColors({ ...observation, theme: 'unknown' }, fixture),
        assert.AssertionError,
      );
    }
  }
});
