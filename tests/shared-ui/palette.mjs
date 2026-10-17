import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
export const palettes = JSON.parse(
  readFileSync(new URL('../../fixtures/shared-ui/button-palettes.json', import.meta.url)),
);
const rgb = (v) => `rgb(${v.join(', ')})`;
export async function measurePalette(page) {
  return page.evaluate(() =>
    Object.fromEntries(
      [...document.querySelectorAll('#palette-root button')].map((n) => {
        const s = getComputedStyle(n),
          r = n.getBoundingClientRect();
        return [
          n.dataset.ykKey,
          {
            classes: n.className,
            bounds: [r.x, r.y, r.width, r.height],
            border: s.borderTopColor,
            fill: s.backgroundColor,
            foreground: s.color,
            hovered: n.matches(':hover'),
            focused: document.activeElement === n,
            focusVisible: n.matches(':focus-visible'),
            pressed: n.matches(':active'),
            disabled: n.disabled,
            loading: n.getAttribute('aria-busy') === 'true',
          },
        ];
      }),
    ),
  );
}
export function checkPalette(nodes, token) {
  for (const n of Object.values(nodes)) {
    assert.equal(n.classes.includes('yk-ui-button-light'), token === 'Light');
    assert.equal(n.classes.includes('yk-ui-button-dark'), token === 'Dark');
    if (!token) continue;
    const colors = Object.fromEntries(palettes.roles.map((r, i) => [r, rgb(palettes[token][i])]));
    assert.equal(
      n.border,
      colors[n.disabled ? 'disabled_border' : n.focusVisible ? 'focused_border' : 'normal_border'],
    );
    assert.equal(
      n.fill,
      colors[
        n.disabled
          ? 'disabled_fill'
          : n.loading
            ? 'loading_fill'
            : n.pressed
              ? 'pressed_fill'
              : n.hovered
                ? 'hovered_fill'
                : 'normal_fill'
      ],
    );
    assert.equal(n.foreground, colors[n.disabled ? 'disabled_foreground' : 'enabled_foreground']);
  }
}
export async function exercisePalette(page, observe, capture) {
  const unchanged = await page.locator('#root-b').evaluate((n) => n.outerHTML);
  const body = await page.locator('body').evaluate((n) => {
    const s = getComputedStyle(n);
    return [s.color, s.backgroundColor, s.margin, s.fontFamily];
  });
  await page.evaluate(() => {
    api.mountCounter('palette-root');
    api.updateCounter('palette-root', 'palette', 'Increment');
    document
      .querySelector('#palette-root [data-yk-key="increment"]')
      .classList.add('consumer-owned');
    document
      .querySelector('#palette-root [data-yk-key="increment"]')
      .setAttribute('data-consumer', 'preserved');
    window.paletteNodes = new Map(
      [...document.querySelectorAll('#palette-root [data-yk-key]')].map((n) => [
        n.dataset.ykKey,
        n,
      ]),
    );
  });
  const counts = [0],
    observations = [];
  const targets = ['increment', 'palette-toggle', 'increment', 'palette-toggle', 'palette-toggle'];
  const tokens = [null, null, 'Light', 'Light', 'Dark', null];
  for (let phase = 0; phase < 6; phase++) {
    if (phase) {
      await page.locator(`#palette-root [data-yk-key="${targets[phase - 1]}"]`).click();
      counts.push(await page.evaluate(() => api.counterValue('palette-root')));
      assert.equal(
        await page.evaluate(
          (key) => document.activeElement === paletteNodes.get(key),
          targets[phase - 1],
        ),
        true,
      );
    }
    const nodes = await measurePalette(page);
    checkPalette(nodes, tokens[phase]);
    assert.equal(
      await page.locator('#palette-root [data-yk-key="increment"]').getAttribute('data-consumer'),
      'preserved',
    );
    assert.ok(nodes.increment.classes.includes('consumer-owned'));
    if (phase)
      for (const key of Object.keys(nodes))
        assert.deepEqual(nodes[key].bounds, observations[0][key].bounds);
    observations.push(nodes);
    assert.equal(
      await page.evaluate(() =>
        [...paletteNodes].every(
          ([key, n]) => n === document.querySelector(`#palette-root [data-yk-key="${key}"]`),
        ),
      ),
      true,
    );
    await capture(`palette-${phase}.png`);
  }
  assert.deepEqual(counts, [0, 1, 1, 2, 2, 2]);
  observe('palette-count-and-toggle', { counts, tokens, observations, retainedIdentity: true });
  // A real held Space survives an application palette change on the same node.
  await page.evaluate(() => api.focusCounter('palette-root'));
  await page.keyboard.down('Space');
  await page.evaluate(() => paletteNodes.get('palette-toggle').click());
  checkPalette(await measurePalette(page), 'Light');
  await page.keyboard.up('Space');
  assert.equal(await page.evaluate(() => api.counterValue('palette-root')), 3);
  assert.equal(
    await page.evaluate(() => document.activeElement === paletteNodes.get('increment')),
    true,
  );
  observe('palette-held-space-browser-profile', { count: 3, state: await measurePalette(page) });
  // Executed class removal control must fail paint/class assertions.
  await page
    .locator('#palette-root [data-yk-key="increment"]')
    .evaluate((n) => n.classList.remove('yk-ui-button-light'));
  assert.throws(() => checkPalette(observations[2], 'Dark'), assert.AssertionError);
  const missing = await measurePalette(page);
  assert.throws(() => checkPalette(missing, 'Light'), assert.AssertionError);
  await page.evaluate(() => api.updateCounter('palette-root', 'palette', 'Increment'));
  checkPalette(await measurePalette(page), 'Light');
  await page.evaluate(() => api.updateCounter('palette-root', 'normal', 'Increment'));
  const legacy = await measurePalette(page);
  checkPalette(legacy, null);
  await page.evaluate(() => api.disposeCounter('palette-root'));
  assert.equal(await page.locator('#palette-root').textContent(), '');
  assert.equal(await page.locator('#root-b').evaluate((n) => n.outerHTML), unchanged);
  assert.deepEqual(
    await page.locator('body').evaluate((n) => {
      const s = getComputedStyle(n);
      return [s.color, s.backgroundColor, s.margin, s.fontFamily];
    }),
    body,
  );
  observe('palette-isolation-cleanup', { unrelatedRootUnchanged: true, bodyUnchanged: true });
}
