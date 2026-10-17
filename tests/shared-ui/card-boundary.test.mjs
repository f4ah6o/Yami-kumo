import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { runInNewContext } from 'node:vm';
import test from 'node:test';
// Execute production FFI; this is not browser layout/runtime evidence.
const source = readFileSync(process.env.SHARED_UI_CARD_BOUNDARY_SOURCE || new URL('../../ui/dom/dom.mbt', import.meta.url), 'utf8');
const block = source.match(/extern "js" fn update_node\([\s\S]*? =\n((?:  #\|.*\n)+)/)?.[1];
assert.ok(block);
const update = runInNewContext(`(${block.replace(/^  #\| ?/gm, '')})`);
test('production DOM update toggles only compatible Column Card decoration', () => {
  const classes = new Set(['yk-ui-column']);
  const node = {classList: {toggle(name, enabled) { if (enabled) classes.add(name); else classes.delete(name); }}};
  update(node, 2, '', false, false, true);
  assert.deepEqual([...classes], ['yk-ui-column', 'yk-ui-card']);
  update(node, 2, '', false, false, false);
  assert.deepEqual([...classes], ['yk-ui-column']);
  update(node, 3, '', false, false, true);
  assert.deepEqual([...classes], ['yk-ui-column']);
});
