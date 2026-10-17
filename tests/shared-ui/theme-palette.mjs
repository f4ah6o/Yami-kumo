import assert from 'node:assert/strict';
import { checkPalette } from './palette.mjs';
import { checkThemeColors } from './theme.mjs';

export async function exerciseThemePaletteOverride(page, observe, fixture, screenshot) {
  const initialListeners = await page.evaluate(() => window.ownedButtonListeners);
  await page.evaluate(() => {
    const section = document.createElement('section');
    section.id = 'theme-mixed-fixture';
    section.innerHTML =
      '<button type="button" id="theme-mixed-before">Before mixed theme</button>' +
      '<div id="theme-mixed"></div><button type="button" id="theme-mixed-legacy">Legacy</button>';
    document.body.prepend(section);
  });
  assert.equal(await page.evaluate(() => api.mountThemeFixture('theme-mixed', 'light')), 'mounted');
  await page.evaluate(() => {
    window.themeMixedNodes = new Map(
      Array.from(document.querySelectorAll('#theme-mixed [data-yk-key]'), (node) => [
        node.getAttribute('data-yk-key'),
        node,
      ]),
    );
  });
  const root = page.locator('#theme-mixed');
  const button = root.locator('[data-yk-key="increment"]');
  const before = page.locator('#theme-mixed-before');
  const colorTuple = (node) =>
    node.evaluate((element) => {
      const style = getComputedStyle(element);
      return [style.borderTopColor, style.backgroundColor, style.color];
    });
  const legacy = await colorTuple(page.locator('#theme-mixed-legacy'));
  const call = async (method, value) => {
    assert.equal(
      await page.evaluate(([method, value]) => api[method]('theme-mixed', value), [method, value]),
      'updated',
    );
  };
  let explicit = null;
  const palette = async (value) => {
    await call('setThemeFixturePalette', value);
    explicit = value === 'none' ? null : value[0].toUpperCase() + value.slice(1);
  };
  const theme = async (value) => {
    await call('setThemeFixtureTheme', value);
  };
  const observations = [];
  const capture = async (phase, count) => {
    await page.evaluate(() => new Promise((resolve) => requestAnimationFrame(resolve)));
    assert.equal(await page.evaluate(() => api.themeFixtureValue('theme-mixed')), count);
    const currentTheme = await root.getAttribute('data-yk-theme');
    const nodes = await root.evaluate((root) =>
      Object.fromEntries(
        Array.from(root.querySelectorAll('button'), (node) => {
          const style = getComputedStyle(node),
            bounds = node.getBoundingClientRect();
          return [
            node.dataset.ykKey,
            {
              classes: node.className,
              border: style.borderTopColor,
              fill: style.backgroundColor,
              foreground: style.color,
              disabled: node.disabled,
              loading: node.getAttribute('aria-busy') === 'true',
              focused: document.activeElement === node,
              focusVisible: node.matches(':focus-visible'),
              hovered: node.matches(':hover'),
              pressed: node.matches(':active'),
              bounds: [bounds.x, bounds.y, bounds.width, bounds.height],
              retained: Array.from(window.themeMixedNodes).every(
                ([key, retained]) => root.querySelector(`[data-yk-key="${key}"]`) === retained,
              ),
            },
          ];
        }),
      ),
    );
    for (const [key, node] of Object.entries(nodes)) {
      const token = key === 'increment' ? explicit : null;
      checkPalette({ [key]: node }, token);
      assert.equal(node.retained, true, `${phase}: keyed identity`);
      if (!token) {
        if (currentTheme) checkThemeColors({ ...node, theme: currentTheme }, fixture);
        else assert.deepEqual([node.border, node.fill, node.foreground], legacy);
      }
      if (observations.length) assert.deepEqual(node.bounds, observations[0].nodes[key].bounds);
    }
    observations.push({ phase, rootTheme: currentTheme, explicitPalette: explicit, count, nodes });
    return nodes;
  };

  await before.click();
  await palette('light');
  await capture('root-light-explicit-light', 0);
  await theme('dark');
  await capture('root-dark-explicit-light', 0);
  await palette('dark');
  await capture('root-dark-explicit-dark', 0);
  await theme('light');
  await capture('root-light-explicit-dark', 0);
  await button.click();
  const pointer = await capture('explicit-pointer-focus', 1);
  assert.equal(pointer.increment.focused, true);
  assert.equal(pointer.increment.focusVisible, false);
  await before.click();
  await page.keyboard.press('Tab');
  const keyboard = await capture('explicit-keyboard-focus', 1);
  assert.equal(keyboard.increment.focused, true);
  assert.equal(keyboard.increment.focusVisible, true);
  await theme('dark');
  await capture('root-switch-retains-explicit-focus', 1);
  await page.keyboard.down('Space');
  await palette('light');
  await capture('explicit-switch-while-space-held', 1);
  await theme('light');
  await capture('root-switch-while-space-held', 1);
  await call('clearThemeFixtureTheme');
  await capture('root-clear-while-space-held', 1);
  await page.keyboard.up('Space');
  await capture('root-clear-retained-after-activation', 2);
  assert.equal(await root.getAttribute('data-yk-theme'), null);
  await screenshot('theme-explicit-override.png');

  await theme('dark');
  await call('setThemeFixtureMode', 'loading');
  await capture('explicit-loading-root-dark', 2);
  await theme('light');
  await capture('explicit-loading-root-light', 2);
  await page.keyboard.press('Enter');
  await page.keyboard.press('Space');
  await call('setThemeFixtureMode', 'disabled-loading');
  await capture('explicit-disabled-loading', 2);
  await palette('dark');
  await call('clearThemeFixtureTheme');
  await capture('explicit-disabled-loading-root-clear', 2);
  await call('setThemeFixtureMode', 'normal');
  await before.click();
  await theme('light');
  await capture('explicit-dark-root-restored', 2);
  await palette('none');
  await capture('explicit-clear-falls-back-to-root', 2);
  await call('clearThemeFixtureTheme');
  await capture('root-and-explicit-cleared', 2);
  assert.equal(
    await page.evaluate(() => api.setThemeFixturePalette('theme-mixed', 'sepia')),
    'invalid-palette',
  );
  assert.equal(await page.evaluate(() => api.disposeThemeFixture('theme-mixed')), 'disposed');
  assert.equal(await root.textContent(), '');
  assert.equal(await root.getAttribute('data-yk-theme'), null);
  assert.equal(await root.getAttribute('class'), null);
  await page.evaluate(() => {
    document.getElementById('theme-mixed-fixture').remove();
    delete window.themeMixedNodes;
  });
  assert.equal(await page.evaluate(() => window.ownedButtonListeners), initialListeners);
  observe('palette-root-theme-overrides', {
    phases: observations.length,
    observations,
    finalCount: 2,
    explicitFocusPolicy: 'native Chromium focus-visible',
    rootFallbackFocusPolicy: 'focused',
    retainedIdentity: true,
  });
}
