import assert from 'node:assert/strict';
// Fixed before implementation. Font-dependent outer sizes are never compared.
const tolerance = 1;
export function checkCardGeometry(card) {
  const near = (actual, expected) => assert.ok(Math.abs(actual - expected) <= tolerance,
    `Card geometry: expected ${expected}, got ${actual}`);
  assert.equal(card.kind, 'DIV');
  assert.equal(card.tabIndex, -1);
  assert.equal(card.role, null);
  assert.deepEqual(card.border, ['1px', '1px', '1px', '1px']);
  assert.deepEqual(card.padding, ['16px', '16px', '16px', '16px']);
  assert.equal(card.gap, '12px');
  assert.equal(card.radius, '0px');
  assert.equal(card.children.length > 0, true);
  const first = card.children[0], last = card.children.at(-1);
  near(first.y - card.y, 17);
  near(card.y + card.height - last.y - last.height, 17);
  for (const child of card.children) {
    near(child.x - card.x, 17);
    near(card.x + card.width - child.x - child.width, 17);
  }
  for (let i = 1; i < card.children.length; i++)
    near(card.children[i].y - card.children[i - 1].y - card.children[i - 1].height, 12);
}
export async function exerciseCard(page, observe) {
  await page.evaluate(() => {
    api.disposeCounter('root-a'); api.mountCounter('root-a');
    window.cardButton = document.querySelector('#root-a button');
    window.cardContainer = document.querySelector('#root-a [data-yk-key="counter"]');
    api.focusCounter('root-a'); api.updateCounter('root-a', 'card', 'Increment');
  });
  const measure = () => page.evaluate(() => [...document.querySelectorAll('#root-a .yk-ui-card')].map(node => {
    const rect = n => { const r = n.getBoundingClientRect(); return { x:r.x, y:r.y, width:r.width, height:r.height }; };
    const style = getComputedStyle(node);
    return { ...rect(node), kind:node.tagName, tabIndex:node.tabIndex, role:node.getAttribute('role'),
      border:['Top','Right','Bottom','Left'].map(side => style[`border${side}Width`]),
      padding:['Top','Right','Bottom','Left'].map(side => style[`padding${side}`]),
      gap:style.gap, radius:style.borderRadius, children:[...node.children].map(rect) };
  }));
  const initialGeometry = await measure();
  assert.equal(initialGeometry.length, 1); initialGeometry.forEach(checkCardGeometry);
  assert.equal(await page.evaluate(() => cardButton === document.activeElement &&
    cardContainer === document.querySelector('#root-a .yk-ui-card')), true);
  assert.equal(await page.locator('#root-a').textContent(), 'Shared counterCount: 0Increment');
  await page.evaluate(() => cardContainer.click());
  assert.equal(await page.evaluate(() => api.counterValue('root-a')), 0);
  const counts = [0];
  await page.locator('#root-a button').click();
  counts.push(await page.evaluate(() => api.counterValue('root-a')));
  // Actual browser held Space, with a same-key/decorated repaint in between.
  await page.keyboard.down('Space');
  await page.evaluate(() => api.updateCounter('root-a', 'card', 'Increment'));
  await page.keyboard.up('Space');
  counts.push(await page.evaluate(() => api.counterValue('root-a')));
  assert.deepEqual(counts, [0, 1, 2]);
  assert.equal(await page.evaluate(() => document.activeElement === cardButton), true);
  await page.evaluate(() => api.updateCounter('root-a', 'nested-card', '<b>& literal'));
  const nestedGeometry = await measure();
  assert.equal(nestedGeometry.length, 2); nestedGeometry.forEach(checkCardGeometry);
  assert.equal(await page.locator('#root-a button').textContent(), '<b>& literal');
  assert.equal(await page.locator('#root-a b').count(), 0);
  assert.equal(await page.evaluate(() => document.activeElement === cardButton), true);
  await page.evaluate(() => api.updateCounter('root-a', 'normal', 'Increment'));
  assert.equal(await page.locator('#root-a .yk-ui-card').count(), 0);
  assert.equal(await page.evaluate(() => document.activeElement === cardButton &&
    cardContainer === document.querySelector('#root-a [data-yk-key="counter"]')), true);
  assert.equal(await page.locator('#root-a .yk-ui-column').evaluate(node => getComputedStyle(node).rowGap), 'normal');
  await page.evaluate(() => api.updateCounter('root-a', 'card', 'Increment'));
  const finalGeometry = await measure(); finalGeometry.forEach(checkCardGeometry);
  observe('card-counter-two-activations', {counts, initialGeometry, nestedGeometry, finalGeometry});
}
