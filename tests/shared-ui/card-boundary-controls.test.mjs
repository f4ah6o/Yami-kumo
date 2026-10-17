import assert from 'node:assert/strict';
import { mkdtempSync, readFileSync, writeFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { spawnSync } from 'node:child_process';
import test from 'node:test';
const source = readFileSync(new URL('../../ui/dom/dom.mbt', import.meta.url), 'utf8');
const before = 'if (kind === 2) node.classList.toggle("yk-ui-card", card);';
for (const [name, after] of [
  ['missing decoration', '// omit decoration'],
  ['sticky decoration', 'if (kind === 2) node.classList.toggle("yk-ui-card", true);'],
  ['decorating Row', 'if (kind === 2 || kind === 3) node.classList.toggle("yk-ui-card", card);'],
])
  test(`production Card negative control rejected: ${name}`, () => {
    assert.equal(source.split(before).length, 2);
    const dir = mkdtempSync(join(tmpdir(), 'yami-card-control-'));
    try {
      const path = join(dir, 'dom.mbt');
      writeFileSync(path, source.replace(before, after));
      const env = { ...process.env, SHARED_UI_CARD_BOUNDARY_SOURCE: path };
      delete env.NODE_TEST_CONTEXT;
      const result = spawnSync(
        process.execPath,
        ['--test', fileURLToPath(new URL('./card-boundary.test.mjs', import.meta.url))],
        { env, encoding: 'utf8', timeout: 30000 },
      );
      assert.equal(result.error, undefined);
      assert.equal(result.status, 1, result.stdout + result.stderr);
      assert.match(result.stdout + result.stderr, /AssertionError/);
    } finally {
      rmSync(dir, { recursive: true, force: true });
    }
  });
