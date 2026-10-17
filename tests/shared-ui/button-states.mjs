import assert from 'node:assert/strict';

// Called by the real Chromium runner so source identity, browser version,
// raw observations and screenshot use that runner's existing evidence envelope.
export async function exerciseButtonStates(page, observe) {
  await page.evaluate(() => {
    const form = document.createElement('form');
    form.id = 'button-state-form';
    form.innerHTML =
      '<button type="button" id="before-state">Before</button><div id="state-root"></div><button type="button" id="click-only-baseline">Click-only baseline</button>';
    document.body.prepend(form);
    window.stateSubmits = 0;
    form.addEventListener('submit', (event) => {
      event.preventDefault();
      window.stateSubmits++;
    });
    api.mountCounter('state-root');
    // Exact old admission policy: latest gates are checked only when native
    // click arrives. This is a browser negative control, not old-SHA evidence.
    window.baselineLoading = false;
    window.baselineCount = 0;
    document.getElementById('click-only-baseline').addEventListener('click', () => {
      if (!window.baselineLoading) window.baselineCount++;
    });
  });
  const button = page.locator('#state-root button');
  const count = () => page.evaluate(() => api.counterValue('state-root'));
  const update = (mode = 'normal', label = 'Increment') =>
    page.evaluate(([mode, label]) => api.updateCounter('state-root', mode, label), [mode, label]);
  const state = () =>
    button.evaluate((node) => ({
      focused: document.activeElement === node,
      focusVisible: node.matches(':focus-visible'),
      hovered: node.matches(':hover'),
      disabled: node.disabled,
      busy: node.getAttribute('aria-busy'),
      ariaDisabled: node.getAttribute('aria-disabled'),
      type: node.type,
    }));
  const expectCount = async (expected) => {
    // Let the real event loop and queued application drain settle; no timer is
    // used by the adapter's cancellation boundary.
    await page.evaluate(() => new Promise((resolve) => requestAnimationFrame(resolve)));
    assert.equal(await count(), expected);
  };
  const pointerDown = async () => {
    const box = await button.boundingBox();
    assert.ok(box);
    await page.mouse.move(box.x + box.width / 2, box.y + box.height / 2);
    await page.mouse.down();
  };

  await page.locator('#before-state').focus();
  await page.keyboard.press('Tab');
  assert.equal((await state()).focused, true);
  assert.equal((await state()).focusVisible, true);
  await page.evaluate(() => {
    window.stateNode = document.querySelector('#state-root button');
  });
  await update('normal', 'Changed label');
  await update('loading', 'Changed label');
  const loading = await state();
  assert.deepEqual(
    {
      focused: loading.focused,
      focusVisible: loading.focusVisible,
      disabled: loading.disabled,
      busy: loading.busy,
      ariaDisabled: loading.ariaDisabled,
    },
    { focused: true, focusVisible: true, disabled: false, busy: 'true', ariaDisabled: 'true' },
  );
  assert.equal(await page.evaluate(() => api.focusCounter('state-root')), false);
  assert.equal((await state()).focused, true);
  await page.keyboard.press('Enter');
  await page.keyboard.press('Space');
  await button.evaluate((node) => node.click());
  await expectCount(0);
  await update('disabled-loading', 'Both gates');
  const both = await state();
  assert.equal(both.disabled, true);
  assert.equal(both.focused, false);
  assert.equal(both.busy, 'true');
  assert.equal(both.ariaDisabled, 'true');
  await button.evaluate((node) => node.dispatchEvent(new MouseEvent('click', { detail: 0 })));
  await expectCount(0);
  await update();
  assert.equal((await state()).focused, false, 'reenabling must not restore disabled focus');
  await button.hover();
  assert.equal((await state()).hovered, true);
  await update('normal', 'Repainted');
  assert.equal((await state()).hovered, true);
  assert.equal(await button.evaluate((node) => window.stateNode === node), true);
  await button.click();
  await expectCount(1);
  assert.equal((await state()).focused, true);
  assert.equal(
    (await state()).focusVisible,
    false,
    'Chromium pointer focus uses its native heuristic',
  );
  observe('button-state-focus-hover-label', { loading, afterPointer: await state(), count: 1 });

  // Retained label updates do not replace the browser's Button. Native has a
  // different documented policy: label/bounds changes cancel its GPUI press.
  await page.keyboard.down('Space');
  await update('normal', 'Label while held');
  await expectCount(1);
  await page.keyboard.up('Space');
  await expectCount(2);
  await page.keyboard.down('Enter');
  await expectCount(3);
  await page.keyboard.down('Enter');
  await expectCount(4);
  await page.keyboard.up('Enter');
  await page.keyboard.down('Space');
  await page.keyboard.down('Space');
  await expectCount(4);
  await page.keyboard.up('Space');
  await expectCount(5);
  assert.equal((await state()).type, 'button');
  assert.equal(await page.evaluate(() => window.stateSubmits), 0);
  observe('button-state-browser-repeat-default', { counts: [1, 2, 3, 4, 4, 5], submits: 0 });

  const gateTraces = [];
  for (const mode of ['loading', 'disabled']) {
    const initial = await count();
    const counts = [0];
    await button.focus();
    await page.keyboard.down('Space');
    await update(mode);
    const gated = await state();
    assert.equal(gated.disabled, mode === 'disabled');
    assert.equal(await page.evaluate(() => api.focusCounter('state-root')), false);
    assert.equal(await count(), initial, 'gated held input cannot activate');
    // Focus-loss timing is browser-owned: activeElement may remain this node
    // during a disabled held-Space transition. Preserve that raw observation.
    await update();
    await page.keyboard.up('Space');
    await expectCount(initial);
    counts.push((await count()) - initial);
    await pointerDown();
    await update(mode);
    await update();
    await page.mouse.up();
    await expectCount(initial);
    counts.push((await count()) - initial);
    // Stale Enter repeats after a loading transition must not revive input.
    await button.focus();
    await page.keyboard.down('Enter');
    await expectCount(initial + 1);
    counts.push((await count()) - initial);
    await update(mode);
    await update();
    await page.keyboard.down('Enter');
    await page.keyboard.up('Enter');
    await expectCount(initial + 1);
    counts.push((await count()) - initial);
    await button.click();
    await expectCount(initial + 2);
    counts.push((await count()) - initial);
    observe(`button-interrupted-${mode}`, { counts });
    gateTraces.push({ mode, before: initial, after: initial + 2, gated });
  }
  observe('button-state-interrupted-gates', { cases: gateTraces });

  const initial = await count();
  await button.focus();
  await page.keyboard.down('Space');
  await update('loading');
  await update();
  await button.evaluate((node) =>
    node.dispatchEvent(new MouseEvent('click', { detail: 0, bubbles: true })),
  );
  await expectCount(initial + 1);
  await page.keyboard.up('Space');
  await expectCount(initial + 1);
  await pointerDown();
  await update('loading');
  await update();
  await button.evaluate((node) => node.click());
  await expectCount(initial + 2);
  await page.mouse.up();
  await expectCount(initial + 2);
  observe('button-state-independent-zero-detail', { counts: [initial, initial + 1, initial + 2] });

  // Blur, release outside, remove/retype and root disposal exercise browser
  // defaults plus owned listener cleanup. No programmatic key event activates.
  await pointerDown();
  await page.mouse.move(899, 599);
  await page.mouse.up();
  await expectCount(initial + 2);
  await button.focus();
  await page.keyboard.down('Space');
  await page.locator('#before-state').focus();
  await page.keyboard.up('Space');
  await expectCount(initial + 2);
  for (const mode of ['removed', 'text']) {
    await button.focus();
    await page.keyboard.down('Space');
    await page.evaluate(() => {
      window.removedStateButton = document.querySelector('#state-root button');
    });
    await update(mode);
    await update();
    await button.focus();
    await page.keyboard.up('Space');
    await page.evaluate(() => window.removedStateButton.click());
    await expectCount(initial + 2);
  }
  await pointerDown();
  await update('removed');
  await update();
  await page.mouse.up();
  await expectCount(initial + 2);
  await button.focus();
  await page.keyboard.down('Space');
  await page.evaluate(() => {
    api.disposeCounter('state-root');
    api.mountCounter('state-root');
  });
  await button.focus();
  await page.keyboard.up('Space');
  await expectCount(0);
  await button.click();
  await expectCount(1);
  observe('button-state-held-lifetime-cancellation', { remountedCount: 1 });

  const baseline = page.locator('#click-only-baseline');
  await baseline.focus();
  await page.keyboard.down('Space');
  await page.evaluate(() => {
    window.baselineLoading = true;
    document.getElementById('click-only-baseline').setAttribute('aria-busy', 'true');
    window.baselineLoading = false;
    document.getElementById('click-only-baseline').removeAttribute('aria-busy');
  });
  await page.keyboard.up('Space');
  assert.equal(
    await page.evaluate(() => window.baselineCount),
    1,
    'negative control must demonstrate click-only gate loses held-Space cancellation',
  );
  const baselineBox = await baseline.boundingBox();
  await page.mouse.move(baselineBox.x + 5, baselineBox.y + 5);
  await page.mouse.down();
  await page.evaluate(() => {
    window.baselineLoading = true;
    window.baselineLoading = false;
  });
  await page.mouse.up();
  assert.equal(await page.evaluate(() => window.baselineCount), 2);
  observe('button-state-click-only-negative-control', { baselineActivations: 2 });
  await page.evaluate(() => {
    api.disposeCounter('state-root');
    document.getElementById('button-state-form').remove();
  });
}
