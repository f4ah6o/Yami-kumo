import assert from 'node:assert/strict';
import test from 'node:test';
import { checkStackGeometry } from './spacing.mjs';
const valid = () => ({
  key: 'synthetic',
  kind: 'DIV',
  tabIndex: -1,
  role: null,
  direction: 'row',
  gap: '12px',
  padding: Array(4).fill('4px'),
  x: 0,
  y: 0,
  width: 68,
  height: 40,
  children: [
    { x: 4, y: 4, width: 16, height: 16 },
    { x: 32, y: 4, width: 32, height: 32 },
  ],
});
test('synthetic stack oracle rejects every inset and gap error', () => {
  checkStackGeometry(valid(), 12, 4, 'row');
  for (const mutate of [
    (s) => (s.gap = '0px'),
    (s) => (s.padding[2] = '8px'),
    (s) => (s.children[0].x += 3),
    (s) => (s.children[0].y -= 3),
    (s) => (s.width += 3),
    (s) => (s.height += 3),
    (s) => (s.children[1].x += 3),
    (s) => (s.role = 'button'),
    (s) => (s.direction = 'column'),
  ]) {
    const value = valid();
    mutate(value);
    assert.throws(() => checkStackGeometry(value, 12, 4, 'row'), assert.AssertionError);
  }
});
