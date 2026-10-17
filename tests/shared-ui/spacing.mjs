import assert from 'node:assert/strict';

// Fixed before implementation. Only intrinsic-size fixture hosts assert exact
// content envelopes; ordinary unconstrained DOM Rows may have trailing space.
export const spacingTolerance = 1;
export function checkStackGeometry(stack, gap, padding, direction) {
  const near = (actual, expected) =>
    assert.ok(
      Math.abs(actual - expected) <= spacingTolerance,
      `stack ${stack.key}: expected ${expected}, got ${actual}`,
    );
  assert.equal(stack.kind, 'DIV');
  assert.equal(stack.tabIndex, -1);
  assert.equal(stack.role, null);
  assert.equal(stack.direction, direction);
  assert.equal(stack.gap, `${gap}px`);
  assert.deepEqual(stack.padding, Array(4).fill(`${padding}px`));
  assert.equal(stack.children.length > 0, true);
  const children = stack.children;
  near(Math.min(...children.map((c) => c.x)) - stack.x, padding);
  near(Math.min(...children.map((c) => c.y)) - stack.y, padding);
  near(stack.x + stack.width - Math.max(...children.map((c) => c.x + c.width)), padding);
  near(stack.y + stack.height - Math.max(...children.map((c) => c.y + c.height)), padding);
  for (let i = 1; i < children.length; i++) {
    const a = children[i - 1],
      b = children[i];
    near(direction === 'row' ? b.x - a.x - a.width : b.y - a.y - a.height, gap);
  }
}

export function checkSpacingGeometry(nodes, expanded) {
  checkStackGeometry(nodes.counter, expanded ? 12 : 0, expanded ? 16 : 4, 'column');
  checkStackGeometry(nodes.actions, expanded ? 16 : 4, expanded ? 8 : 0, 'row');
  const card = nodes.preview,
    child = nodes['card-label'];
  assert.deepEqual(card.border, Array(4).fill('1px'));
  assert.deepEqual(card.padding, Array(4).fill('16px'));
  assert.equal(card.gap, '12px');
  for (const distance of [
    child.x - card.x,
    child.y - card.y,
    card.x + card.width - child.x - child.width,
    card.y + card.height - child.y - child.height,
  ]) {
    assert.ok(Math.abs(distance - 17) <= spacingTolerance);
  }
}

export function checkFixedSpacingGeometry(nodes) {
  checkStackGeometry(nodes.fixed, 8, 24, 'column');
  checkStackGeometry(nodes['fixed-row'], 12, 4, 'row');
  // In a Row, browser stretching may increase a child's cross-axis height.
  assert.equal(nodes['box-a'].width, 16);
  assert.equal(nodes['box-b'].width, 32);
  assert.ok(nodes['box-a'].height >= 16);
  assert.ok(nodes['box-b'].height >= 32);
  assert.equal(nodes['fixed-row'].width, 68);
  assert.equal(nodes.fixed.width, 116);
  assert.equal(nodes.fixed.height, 130);
  const card = nodes['fixed-card'],
    child = nodes['box-c'];
  for (const distance of [
    child.x - card.x,
    child.y - card.y,
    card.x + card.width - child.x - child.width,
    card.y + card.height - child.y - child.height,
  ]) {
    assert.ok(Math.abs(distance - 17) <= spacingTolerance);
  }
}

export async function measureSpacing(page, id) {
  return page.evaluate((id) => {
    const rect = (n) => {
      const r = n.getBoundingClientRect();
      return { x: r.x, y: r.y, width: r.width, height: r.height };
    };
    return Object.fromEntries(
      [...document.getElementById(id).querySelectorAll('[data-yk-key]')].map((node) => {
        const style = getComputedStyle(node);
        const key = node.getAttribute('data-yk-key');
        return [
          key,
          {
            ...rect(node),
            key,
            kind: node.tagName,
            tabIndex: node.tabIndex,
            role: node.getAttribute('role'),
            direction: style.flexDirection,
            gap: style.gap,
            padding: ['Top', 'Right', 'Bottom', 'Left'].map((s) => style[`padding${s}`]),
            border: ['Top', 'Right', 'Bottom', 'Left'].map((s) => style[`border${s}Width`]),
            children: [...node.children].map(rect),
          },
        ];
      }),
    );
  }, id);
}

export async function exerciseSpacing(page, observe, capture) {
  const unaffected = await page.locator('#root-b').evaluate((n) => n.innerHTML);
  const hostStyles = () =>
    page.locator('body').evaluate((n) => {
      const s = getComputedStyle(n);
      return [s.display, s.margin, s.color, s.backgroundColor, s.fontFamily];
    });
  const bodyBefore = await hostStyles();
  await page.evaluate(() => {
    api.mountCounter('spacing-root');
    api.updateCounter('spacing-root', 'spacing', 'Increment');
    window.spacingNodes = new Map(
      [...document.querySelectorAll('#spacing-root [data-yk-key]')].map((n) => [
        n.getAttribute('data-yk-key'),
        n,
      ]),
    );
  });
  const counts = [0],
    geometries = [await measureSpacing(page, 'spacing-root')];
  checkSpacingGeometry(geometries[0], false);
  await capture('spacing-0.png');
  assert.equal(await page.locator('#spacing-root b').count(), 0);
  const expanded = [false, false, true, true, false];
  const targets = ['increment', 'spacing-toggle', 'increment', 'spacing-toggle'];
  for (let i = 0; i < targets.length; i++) {
    await page.locator(`#spacing-root [data-yk-key="${targets[i]}"]`).click();
    counts.push(await page.evaluate(() => api.counterValue('spacing-root')));
    const geometry = await measureSpacing(page, 'spacing-root');
    geometries.push(geometry);
    checkSpacingGeometry(geometry, expanded[i + 1]);
    await capture(`spacing-${i + 1}.png`);
    assert.equal(
      await page.evaluate((key) => document.activeElement === spacingNodes.get(key), targets[i]),
      true,
    );
    assert.equal(
      await page.evaluate(() =>
        [...spacingNodes].every(
          ([key, node]) => node === document.querySelector(`#spacing-root [data-yk-key="${key}"]`),
        ),
      ),
      true,
    );
  }
  assert.deepEqual(counts, [0, 1, 1, 2, 2]);
  observe('spacing-count-and-toggle', {
    counts,
    expanded,
    geometries,
    retainedIdentity: true,
    retainedFocus: true,
  });
  await page.evaluate(() => api.focusCounter('spacing-root'));
  await page.keyboard.down('Space');
  await page.evaluate(() => api.updateCounter('spacing-root', 'spacing', 'Increment'));
  await page.keyboard.up('Space');
  assert.equal(await page.evaluate(() => api.counterValue('spacing-root')), 3);
  assert.equal(
    await page.evaluate(() => document.activeElement === spacingNodes.get('increment')),
    true,
  );
  observe('spacing-unchanged-held-space', { count: 3 });
  // Changing spacing remains browser-owned held-input behavior. A programmatic
  // toggle while Space is held keeps the actual increment node/focus alive.
  await page.keyboard.down('Space');
  await page.evaluate(() => spacingNodes.get('spacing-toggle').click());
  await page.keyboard.up('Space');
  assert.equal(await page.evaluate(() => api.counterValue('spacing-root')), 4);
  assert.equal(
    await page.evaluate(() => document.activeElement === spacingNodes.get('increment')),
    true,
  );
  observe('spacing-changed-held-space-browser-profile', { count: 4 });
  await page.evaluate(() => {
    api.mountCounter('fixed-spacing-root');
    api.updateCounter('fixed-spacing-root', 'fixed-spacing', '');
  });
  const fixed = await measureSpacing(page, 'fixed-spacing-root');
  checkFixedSpacingGeometry(fixed);
  observe('spacing-fixed-font-independent', { geometry: fixed });
  await capture('spacing-fixed.png');
  // Executed production class-removal negative controls in the actual browser.
  for (const className of ['yk-ui-gap-8', 'yk-ui-padding-24']) {
    await page
      .locator('#fixed-spacing-root [data-yk-key="fixed"]')
      .evaluate((n, c) => n.classList.remove(c), className);
    const invalid = await measureSpacing(page, 'fixed-spacing-root');
    assert.throws(() => checkFixedSpacingGeometry(invalid), assert.AssertionError);
    await page.evaluate(() => api.updateCounter('fixed-spacing-root', 'fixed-spacing', ''));
    checkFixedSpacingGeometry(await measureSpacing(page, 'fixed-spacing-root'));
  }
  await page.evaluate(() => api.updateCounter('spacing-root', 'normal', 'Increment'));
  assert.equal(await page.locator('#spacing-root [class*="yk-ui-gap-"]').count(), 0);
  assert.equal(await page.locator('#spacing-root [class*="yk-ui-padding-"]').count(), 0);
  assert.equal(await page.locator('#root-b').evaluate((n) => n.innerHTML), unaffected);
  assert.deepEqual(await hostStyles(), bodyBefore);
  await page.evaluate(() => {
    api.disposeCounter('spacing-root');
    api.disposeCounter('fixed-spacing-root');
  });
}
