import assert from 'node:assert/strict';
import { mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import test from 'node:test';

const source = readFileSync(new URL('../../ui/dom/dom.mbt', import.meta.url), 'utf8');
const fixture = fileURLToPath(new URL('./button-boundary.test.mjs', import.meta.url));
// Isolated source mutations prove that the executable boundary assertions reject
// meaningful regressions. The checked-out production source is never changed.
for (const [name, before, after] of [
  [
    'omit gate cancellation',
    'if (disabled !== nextDisabled || loading !== nextLoading) cancel();',
    '// negative control: no transition cancellation',
  ],
  [
    'emit a second activation from keyup',
    'keys.delete(event.key);',
    'callback(); keys.delete(event.key);',
  ],
  [
    'reject independent detail=0 click',
    'const pointer = event.detail > 0 ?',
    'if (event.detail === 0) return; const pointer = event.detail > 0 ?',
  ],
  [
    'ignore pointer identity on cancel',
    'if (pointer?.id === event.pointerId) pointer.cancelled = true;',
    'if (pointer) pointer.cancelled = true;',
  ],
  [
    'leak owned listeners',
    'for (const [type, listener] of Object.entries(listeners)) node.removeEventListener(type, listener);',
    '// negative control: listeners leaked',
  ],
]) {
  test(`negative control rejected: ${name}`, () => {
    assert.equal(source.split(before).length, 2, 'mutation must have exactly one target');
    const directory = mkdtempSync(join(tmpdir(), 'yami-button-boundary-control-'));
    try {
      const mutated = join(directory, 'dom.mbt');
      writeFileSync(mutated, source.replace(before, after));
      const env = { ...process.env, SHARED_UI_BUTTON_BOUNDARY_SOURCE: mutated };
      // This is a fresh test runner, not a child speaking the parent's binary
      // node:test worker protocol (which would not return the runner exit code).
      delete env.NODE_TEST_CONTEXT;
      const result = spawnSync(process.execPath, ['--test', fixture], {
        env,
        encoding: 'utf8',
        timeout: 30000,
      });
      assert.equal(result.error, undefined);
      assert.equal(result.status, 1, 'a mutation must fail the real boundary assertions');
      assert.match(result.stdout + result.stderr, /AssertionError|ERR_ASSERTION/);
      assert.doesNotMatch(result.stdout + result.stderr, /SyntaxError/);
    } finally {
      rmSync(directory, { recursive: true, force: true });
    }
  });
}
