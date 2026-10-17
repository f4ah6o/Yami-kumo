import assert from 'node:assert/strict';
import { mkdtempSync, readFileSync, writeFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { spawnSync } from 'node:child_process';
import test from 'node:test';
const cases = [
  ['stale light class', 'dom', 'palette === 1', 'palette !== 0'],
  ['missing dark class', 'dom', 'palette === 2', 'false'],
  ['wrong foreground', 'css', 'color: rgb(25, 43, 62)', 'color: rgb(26, 43, 62)'],
  [
    'wrong disabled precedence',
    'css',
    '.yk-ui-button-light:disabled',
    '.yk-ui-button-light:enabled',
  ],
];
for (const [name, kind, before, after] of cases)
  test(`executed palette control: ${name}`, () => {
    const source = readFileSync(
      new URL(
        kind === 'dom' ? '../../ui/dom/dom.mbt' : '../../styles/shared-ui.css',
        import.meta.url,
      ),
      'utf8',
    );
    assert.equal(source.split(before).length, 2);
    const directory = mkdtempSync(join(tmpdir(), 'yami-palette-mutant-'));
    try {
      const path = join(directory, 'source');
      writeFileSync(path, source.replace(before, after));
      const env = {
        ...process.env,
        [kind === 'dom' ? 'YAMI_PALETTE_DOM_SOURCE' : 'YAMI_PALETTE_CSS_SOURCE']: path,
      };
      delete env.NODE_TEST_CONTEXT;
      const result = spawnSync(
        process.execPath,
        ['--test', fileURLToPath(new URL('./palette-boundary.test.mjs', import.meta.url))],
        { env, encoding: 'utf8', timeout: 30000 },
      );
      assert.equal(result.status, 1);
      assert.match(result.stdout + result.stderr, /AssertionError|ERR_ASSERTION/);
      assert.doesNotMatch(result.stdout + result.stderr, /SyntaxError/);
    } finally {
      rmSync(directory, { recursive: true, force: true });
    }
  });
