import assert from 'node:assert/strict';

const booleanState = (observation) => ({
  disabled: observation.disabled,
  loading: observation.loading,
  pressed: observation.pressed,
  hovered: observation.hovered,
  focused: observation.focused,
});

export function checkThemeColors(observation, fixture) {
  const state = booleanState(observation);
  const expected = fixture.states.find((row) =>
    Object.entries(state).every(([key, value]) => row[key] === value),
  );
  assert.ok(expected, `missing shared theme state: ${JSON.stringify(state)}`);
  const palette = fixture.themes[observation.theme];
  assert.ok(palette, `missing shared theme: ${observation.theme}`);
  const css = (slot) => `rgb(${palette[slot].join(', ')})`;
  assert.equal(observation.border, css(expected.border), 'Button border token');
  assert.equal(observation.fill, css(expected.fill), 'Button fill token');
  assert.equal(observation.foreground, css(expected.foreground), 'Button foreground token');
  assert.equal(observation.retained, true, 'theme change preserves every keyed DOM identity');
  return { border: expected.border, fill: expected.fill, foreground: expected.foreground };
}

export async function exerciseTheme(page, observe, fixture, screenshot) {
  const beforeListeners = await page.evaluate(() => window.ownedButtonListeners);
  await page.evaluate(() => {
    const section = document.createElement('section');
    section.id = 'theme-fixture';
    section.innerHTML =
      '<button type="button" id="theme-before">Before theme</button>' +
      '<div id="theme-a"></div><div id="theme-b"></div>' +
      '<div id="theme-legacy"></div>' +
      '<button type="button" class="yk-ui-button" id="theme-unrelated">Unrelated button</button>' +
      '<div id="theme-cleanup" class="host-root yk-ui-root" data-yk-theme="host-theme"></div>' +
      '<div id="theme-host-change" class="host-root"></div>';
    document.body.prepend(section);
    window.themeBaseline = (() => {
      const node = document.getElementById('theme-unrelated');
      const style = getComputedStyle(node);
      return [style.borderTopColor, style.backgroundColor, style.color];
    })();
  });
  const mount = (id, theme) =>
    page.evaluate(([id, theme]) => api.mountThemeFixture(id, theme), [id, theme]);
  assert.equal(await mount('theme-a', 'light'), 'mounted');
  assert.equal(await mount('theme-b', 'dark'), 'mounted');
  assert.equal(await page.evaluate(() => api.mountCounter('theme-legacy')), 'mounted');
  const button = page.locator('#theme-a [data-yk-key="increment"]');
  const other = page.locator('#theme-b [data-yk-key="increment"]');
  const count = () => page.evaluate(() => api.themeFixtureValue('theme-a'));
  const nextFrame = () =>
    page.evaluate(() => new Promise((resolve) => requestAnimationFrame(resolve)));
  const expectCount = async (expected) => {
    await nextFrame();
    assert.equal(await count(), expected);
  };
  const mode = async (name) => {
    assert.equal(
      await page.evaluate((name) => api.setThemeFixtureMode('theme-a', name), name),
      'updated',
    );
  };
  const colors = (locator) =>
    locator.evaluate((node) => {
      const style = getComputedStyle(node);
      return [style.borderTopColor, style.backgroundColor, style.color];
    });
  const scoped = async () => {
    assert.deepEqual(
      await colors(page.locator('#theme-unrelated')),
      await page.evaluate(() => window.themeBaseline),
    );
    assert.deepEqual(
      await colors(page.locator('#theme-legacy button')),
      await page.evaluate(() => window.themeBaseline),
    );
    assert.equal(await page.locator('#theme-legacy').getAttribute('data-yk-theme'), null);
  };
  const setTheme = async (name) => {
    const before = await button.evaluate((node) => ({
      focused: document.activeElement === node,
      hovered: node.matches(':hover'),
      pressed: node.matches(':active'),
    }));
    const otherColors = await colors(other);
    const otherTheme = await page.locator('#theme-b').getAttribute('data-yk-theme');
    assert.equal(
      await page.evaluate((name) => api.setThemeFixtureTheme('theme-a', name), name),
      'updated',
    );
    assert.deepEqual(
      await button.evaluate((node) => ({
        focused: document.activeElement === node,
        hovered: node.matches(':hover'),
        pressed: node.matches(':active'),
      })),
      before,
      'paint-only switch preserves browser focus, hover and active state',
    );
    assert.deepEqual(await colors(other), otherColors, 'other root palette is independent');
    assert.equal(await page.locator('#theme-b').getAttribute('data-yk-theme'), otherTheme);
    await scoped();
  };
  await page.evaluate(() => {
    window.themeNodes = new Map(
      Array.from(document.querySelectorAll('#theme-a [data-yk-key]'), (node) => [
        node.getAttribute('data-yk-key'),
        node,
      ]),
    );
  });
  const phases = [];
  const capture = async (name, expectedCount) => {
    await expectCount(expectedCount);
    const observation = await button.evaluate((node) => {
      const style = getComputedStyle(node);
      return {
        theme: document.getElementById('theme-a').getAttribute('data-yk-theme'),
        disabled: node.disabled,
        loading: node.getAttribute('aria-busy') === 'true',
        focused: document.activeElement === node,
        hovered: node.matches(':hover'),
        pressed: node.matches(':active'),
        focusVisible: node.matches(':focus-visible'),
        border: style.borderTopColor,
        fill: style.backgroundColor,
        foreground: style.color,
        retained: Array.from(window.themeNodes).every(
          ([key, retained]) =>
            document.querySelector(`#theme-a [data-yk-key="${key}"]`) === retained,
        ),
      };
    });
    const expectedSlots = checkThemeColors(observation, fixture);
    const phase = { name, count: expectedCount, ...observation, expectedSlots };
    phases.push(phase);
    observe(`theme-${name}`, { phase: name, count: expectedCount, ...observation, expectedSlots });
    return phase;
  };
  const outside = async () => page.locator('#theme-before').hover();
  const pointerDown = async () => {
    const box = await button.boundingBox();
    assert.ok(box);
    await page.mouse.move(box.x + box.width / 2, box.y + box.height / 2);
    await page.mouse.down();
  };

  await page.locator('#theme-before').focus();
  await outside();
  await capture('normal-light', 0);
  await setTheme('dark');
  await capture('normal-dark', 0);
  await button.hover();
  await capture('hover-dark', 0);
  await setTheme('light');
  await capture('hover-light', 0);
  await button.focus();
  await capture('focus-hover-light', 0);
  await setTheme('dark');
  await capture('focus-hover-dark', 0);
  await outside();
  await capture('focus-dark', 0);
  await setTheme('light');
  await capture('focus-light', 0);

  await page.keyboard.down('Space');
  assert.equal(await button.evaluate((node) => node.matches(':active')), true);
  await capture('space-held-light', 0);
  await setTheme('dark');
  await capture('space-held-dark', 0);
  await page.keyboard.up('Space');
  await capture('space-released-dark', 1);
  await pointerDown();
  await capture('pointer-held-dark', 1);
  await setTheme('light');
  await capture('pointer-held-light', 1);
  await page.mouse.up();
  await capture('pointer-released-light', 2);
  await screenshot('theme-light.png');

  await mode('loading');
  await capture('loading-focus-light', 2);
  await setTheme('dark');
  await capture('loading-focus-dark', 2);
  await page.keyboard.press('Enter');
  await page.keyboard.press('Space');
  await button.evaluate((node) => node.click());
  await expectCount(2);
  await mode('disabled-loading');
  await capture('disabled-loading-dark', 2);
  await setTheme('light');
  await capture('disabled-loading-light', 2);
  await button.evaluate((node) =>
    node.dispatchEvent(new MouseEvent('click', { detail: 0, bubbles: true })),
  );
  await expectCount(2);
  await mode('disabled');
  await capture('disabled-light', 2);
  await setTheme('dark');
  await capture('disabled-dark', 2);
  await screenshot('theme-dark.png');

  await mode('normal');
  await button.focus();
  await page.keyboard.down('Space');
  await capture('space-before-loading', 2);
  await mode('loading');
  await setTheme('light');
  await capture('space-loading-light', 2);
  await mode('normal');
  await page.keyboard.up('Space');
  await capture('space-loading-cancelled', 2);
  await pointerDown();
  await capture('pointer-before-disabled', 2);
  await mode('disabled');
  await setTheme('dark');
  await capture('pointer-disabled-dark', 2);
  await mode('normal');
  await page.mouse.up();
  await capture('pointer-disabled-cancelled', 2);
  await button.click();
  await capture('fresh-after-gates', 3);
  await setTheme('light');
  await capture('focus-hover-after-gates-light', 3);
  await pointerDown();
  await outside();
  await setTheme('dark');
  await capture('pointer-outside-dark', 3);
  await page.mouse.up();
  await capture('pointer-outside-cancelled', 3);
  await button.click();
  await capture('fresh-after-outside', 4);

  await page.keyboard.down('Space');
  await setTheme('light');
  await page.locator('#theme-before').focus();
  await page.keyboard.up('Space');
  await capture('blur-cancelled-after-switch', 4);
  await page.evaluate(() => {
    document.querySelector('#theme-a [data-yk-key="increment"]').click();
    api.setThemeFixtureTheme('theme-a', 'dark');
  });
  await capture('queued-activation-retained', 5);
  await page.locator('#theme-a [data-yk-key="theme-toggle"]').click();
  await capture('common-model-toggle', 5);
  assert.equal(await page.evaluate(() => api.themeFixtureTheme('theme-a')), 'light');
  assert.equal(
    await page.evaluate(
      () =>
        document.activeElement === document.querySelector('#theme-a [data-yk-key="theme-toggle"]'),
    ),
    true,
    'common model theme action retains focus on its keyed button',
  );
  await scoped();

  const beforeInvalid = await page.locator('#theme-a').getAttribute('data-yk-theme');
  assert.equal(
    await page.evaluate(() => api.setThemeFixtureTheme('theme-a', 'sepia')),
    'invalid-theme',
  );
  assert.equal(
    await page.evaluate(() => api.setThemeFixtureMode('theme-a', 'unknown')),
    'invalid-mode',
  );
  assert.equal(
    await page.evaluate(() => api.mountThemeFixture('theme-cleanup', 'sepia')),
    'invalid-theme',
  );
  assert.equal(await page.locator('#theme-cleanup').textContent(), '');
  assert.equal(await page.locator('#theme-a').getAttribute('data-yk-theme'), beforeInvalid);
  assert.equal(
    await page.evaluate(() => api.setThemeFixtureTheme('absent', 'dark')),
    'missing-fixture',
  );
  assert.equal(await page.evaluate(() => api.clearThemeFixtureTheme('theme-a')), 'updated');
  assert.equal(await page.locator('#theme-a').getAttribute('data-yk-theme'), null);
  assert.equal(await page.locator('#theme-a').getAttribute('class'), null);
  await page.locator('#theme-before').focus();
  await outside();
  assert.deepEqual(await colors(button), await page.evaluate(() => window.themeBaseline));
  await setTheme('dark');
  await capture('theme-restored-after-clear', 5);

  assert.equal(await mount('theme-cleanup', 'light'), 'mounted');
  assert.equal(await page.evaluate(() => api.disposeThemeFixture('theme-cleanup')), 'disposed');
  assert.equal(await page.locator('#theme-cleanup').getAttribute('data-yk-theme'), 'host-theme');
  assert.equal(await page.locator('#theme-cleanup').getAttribute('class'), 'host-root yk-ui-root');
  assert.equal(await mount('theme-cleanup', 'light'), 'mounted');
  assert.equal(await page.evaluate(() => api.clearThemeFixtureTheme('theme-cleanup')), 'updated');
  await page.evaluate(() => {
    const root = document.getElementById('theme-cleanup');
    root.setAttribute('data-yk-theme', 'host-after-clear');
    root.className = 'host-restyled';
  });
  assert.equal(
    await page.evaluate(() => api.setThemeFixtureTheme('theme-cleanup', 'dark')),
    'updated',
  );
  assert.equal(await page.evaluate(() => api.disposeThemeFixture('theme-cleanup')), 'disposed');
  assert.equal(
    await page.locator('#theme-cleanup').getAttribute('data-yk-theme'),
    'host-after-clear',
  );
  assert.equal(await page.locator('#theme-cleanup').getAttribute('class'), 'host-restyled');
  assert.equal(await mount('theme-host-change', 'light'), 'mounted');
  await page.evaluate(() =>
    document.getElementById('theme-host-change').setAttribute('data-yk-theme', 'host-edit'),
  );
  assert.equal(
    await page.evaluate(() => api.setThemeFixtureTheme('theme-host-change', 'dark')),
    'host-tree-changed',
  );
  assert.equal(await page.evaluate(() => api.disposeThemeFixture('theme-host-change')), 'disposed');
  assert.equal(await page.locator('#theme-host-change').getAttribute('data-yk-theme'), 'host-edit');
  assert.equal(await page.locator('#theme-host-change').getAttribute('class'), 'host-root');
  assert.equal(await mount('theme-host-change', 'light'), 'mounted');
  await page.evaluate(() => {
    window.themeMoved = document.querySelector('#theme-host-change [data-yk-key="increment"]');
    document.getElementById('theme-fixture').append(window.themeMoved);
  });
  assert.equal(
    await page.evaluate(() => api.setThemeFixtureTheme('theme-host-change', 'dark')),
    'host-tree-changed',
  );
  assert.equal(await page.evaluate(() => api.disposeThemeFixture('theme-host-change')), 'disposed');
  await page.evaluate(() => window.themeMoved.remove());
  assert.equal(await page.evaluate(() => api.disposeThemeFixture('theme-a')), 'disposed');
  assert.equal(await page.evaluate(() => api.disposeThemeFixture('theme-b')), 'disposed');
  assert.equal(
    await page.evaluate(() => api.setThemeFixtureTheme('theme-a', 'dark')),
    'missing-fixture',
  );
  assert.equal(await page.locator('#theme-a').getAttribute('data-yk-theme'), null);
  assert.equal(await page.locator('#theme-b').getAttribute('data-yk-theme'), null);
  assert.equal(await page.locator('#theme-a').getAttribute('class'), null);
  assert.equal(await page.locator('#theme-b').getAttribute('class'), null);
  await page.evaluate(() => {
    api.disposeCounter('theme-legacy');
    document.getElementById('theme-fixture').remove();
    delete window.themeNodes;
    delete window.themeMoved;
  });
  assert.equal(await page.evaluate(() => window.ownedButtonListeners), beforeListeners);
  observe('theme-lifecycle-and-scope', {
    phases: phases.length,
    finalCount: 5,
    retained: true,
    restoredRootAttributes: true,
    unrelatedColorsPreserved: true,
    listenersBefore: beforeListeners,
    listenersAfter: await page.evaluate(() => window.ownedButtonListeners),
    profileDifferences: [
      'Chromium keeps native :hover and :active observations across gate changes; GPUI may clear them.',
    ],
  });
  return phases;
}
