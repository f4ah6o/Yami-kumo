import assert from 'node:assert/strict';
import { readFileSync, mkdtempSync, writeFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { spawnSync } from 'node:child_process';
import test from 'node:test';
const source = readFileSync(new URL('../../ui/dom/dom.mbt', import.meta.url), 'utf8');
for (const [name, before, after] of [
  ['missing gap', 'gap === value', 'false'],
  ['wrong padding', 'padding === value', 'padding === value + 4'],
  [
    'stale classes',
    'node.classList.toggle(`yk-ui-gap-${value}`, gap === value);',
    'if (gap === value) node.classList.toggle(`yk-ui-gap-${value}`, true);',
  ],
])
  test(`production spacing negative control: ${name}`, () => {
    assert.ok(source.includes(before));
    const dir = mkdtempSync(join(tmpdir(), 'yami-spacing-negative-'));
    try {
      const path = join(dir, 'dom.mbt');
      writeFileSync(path, source.replace(before, after));
      const env = { ...process.env, SHARED_UI_SPACING_SOURCE: path };
      delete env.NODE_TEST_CONTEXT;
      const run = spawnSync(
        process.execPath,
        ['--test', new URL('./spacing-boundary.test.mjs', import.meta.url).pathname],
        {
          encoding: 'utf8',
          env,
          timeout: 30000,
        },
      );
      assert.equal(run.status, 1, run.stdout + run.stderr);
      assert.match(run.stdout, /AssertionError/);
    } finally {
      rmSync(dir, { recursive: true, force: true });
    }
  });
