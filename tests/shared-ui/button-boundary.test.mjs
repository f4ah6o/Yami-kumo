import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import test from 'node:test';
import { runInNewContext } from 'node:vm';

// Exercise the exact JS FFI source, not a second implementation. EventTarget
// tests prove admission/default cancellation only; they are not browser input.
const source = readFileSync(
  process.env.SHARED_UI_BUTTON_BOUNDARY_SOURCE || new URL('../../ui/dom/dom.mbt', import.meta.url),
  'utf8',
);
const block = source.match(/extern "js" fn add_button_events\([\s\S]*? =\n((?:  #\|.*\n)+)/)?.[1];
assert.ok(block, 'Button event boundary missing');
const attach = runInNewContext(`(${block.replace(/^  #\| ?/gm, '')})`);
const event = (type, props = {}) => Object.assign(new Event(type, { cancelable: true }), props);
const key = (type, key, repeat = false) => event(type, { key, repeat });
const pointer = (type, props = {}) =>
  event(type, {
    button: 0,
    isPrimary: true,
    pointerType: 'mouse',
    pointerId: 1,
    detail: 1,
    ...props,
  });
function fixture() {
  const registrations = new Set();
  const node = new EventTarget();
  const add = node.addEventListener.bind(node);
  const remove = node.removeEventListener.bind(node);
  node.addEventListener = (type, callback) => {
    registrations.add(callback);
    add(type, callback);
  };
  node.removeEventListener = (type, callback) => {
    registrations.delete(callback);
    remove(type, callback);
  };
  let count = 0;
  const boundary = attach(node, () => count++);
  return { node, boundary, count: () => count, listeners: () => registrations.size };
}

test('only click activates; canceled held keys prevent browser default, never demand a key for AT-like click', () => {
  const { node, boundary, count } = fixture();
  for (const name of [' ', 'Enter']) {
    for (const state of [
      [false, true],
      [true, false],
      [true, true],
    ]) {
      node.dispatchEvent(key('keydown', name));
      boundary.update(...state);
      boundary.update(false, false);
      const repeat = key('keydown', name, true);
      const release = key('keyup', name);
      node.dispatchEvent(repeat);
      node.dispatchEvent(release);
      assert.equal(repeat.defaultPrevented, true);
      assert.equal(release.defaultPrevented, true);
      assert.equal(count(), 0);
    }
  }
  node.dispatchEvent(key('keydown', ' '));
  boundary.update(false, true);
  boundary.update(false, false);
  node.dispatchEvent(event('click', { detail: 0 }));
  assert.equal(count(), 1, 'unrelated detail=0 activation must remain admitted');
  node.dispatchEvent(key('keyup', ' '));
  const freshDown = key('keydown', ' ');
  const freshUp = key('keyup', ' ');
  node.dispatchEvent(freshDown);
  node.dispatchEvent(freshUp);
  assert.equal(freshDown.defaultPrevented, false);
  assert.equal(freshUp.defaultPrevented, false);
  assert.equal(count(), 1, 'keys must not emit activation');
  node.dispatchEvent(event('click', { detail: 0 }));
  assert.equal(count(), 2);
});

test('pointer cancellation is tied to its pointer identity and independent input stays usable', () => {
  const { node, boundary, count } = fixture();
  node.dispatchEvent(pointer('pointerdown'));
  boundary.update(false, true);
  boundary.update(false, false);
  // A foreign non-primary pointer must not reset the canceled mouse gesture.
  node.dispatchEvent(pointer('pointerdown', { pointerId: 2, isPrimary: false }));
  node.dispatchEvent(pointer('pointercancel', { pointerId: 2 }));
  node.dispatchEvent(pointer('pointerdown', { pointerId: 3, pointerType: 'pen' }));
  node.dispatchEvent(pointer('click', { pointerId: 3, pointerType: 'pen' }));
  assert.equal(count(), 1);
  node.dispatchEvent(event('click', { detail: 0 }));
  assert.equal(count(), 2);
  const stale = pointer('click');
  node.dispatchEvent(stale);
  assert.equal(stale.defaultPrevented, true);
  assert.equal(count(), 2);
  node.dispatchEvent(pointer('pointerdown'));
  node.dispatchEvent(pointer('click'));
  assert.equal(count(), 3);
  node.dispatchEvent(pointer('pointerdown'));
  node.dispatchEvent(pointer('pointercancel', { pointerId: 99 }));
  node.dispatchEvent(pointer('click'));
  assert.equal(count(), 4, 'foreign pointercancel must not cancel current primary');
  node.dispatchEvent(pointer('pointerdown'));
  node.dispatchEvent(event('blur'));
  node.dispatchEvent(pointer('click'));
  assert.equal(count(), 4);
  node.dispatchEvent(pointer('pointerdown'));
  node.dispatchEvent(pointer('pointercancel'));
  node.dispatchEvent(pointer('click'));
  assert.equal(count(), 4);
});

test('unavailable input is blocked synchronously, unchanged props retain input, disposal removes every listener', () => {
  const { node, boundary, count, listeners } = fixture();
  assert.equal(listeners(), 6);
  node.dispatchEvent(pointer('pointerdown'));
  boundary.update(false, false);
  node.dispatchEvent(pointer('click'));
  assert.equal(count(), 1);
  boundary.update(false, true);
  const down = key('keydown', ' ');
  const click = event('click', { detail: 0 });
  node.dispatchEvent(down);
  node.dispatchEvent(click);
  assert.equal(down.defaultPrevented, true);
  assert.equal(click.defaultPrevented, true);
  assert.equal(count(), 1);
  boundary.dispose();
  boundary.dispose();
  assert.equal(listeners(), 0);
  const after = key('keyup', ' ');
  node.dispatchEvent(after);
  node.dispatchEvent(event('click', { detail: 0 }));
  assert.equal(after.defaultPrevented, false);
  assert.equal(count(), 1);
});
