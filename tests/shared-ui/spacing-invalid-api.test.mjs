import assert from 'node:assert/strict';
import { mkdtempSync, writeFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { spawnSync } from 'node:child_process';
import test from 'node:test';

test('closed spacing API rejects numeric, forged and wrong-target inputs at compile time', () => {
  const root = fileURLToPath(new URL('../../', import.meta.url));
  const dir = mkdtempSync(join(tmpdir(), 'yami-spacing-api-'));
  try {
    writeFileSync(join(dir, 'moon.work'), `members = [${JSON.stringify(root)}, "."]\n`);
    writeFileSync(
      join(dir, 'moon.mod'),
      'name = "spacing_api_probe"\nversion = "0.0.0"\nimport { "f4ah6o/yami_kumo@0.1.0", }\n',
    );
    writeFileSync(
      join(dir, 'moon.pkg'),
      'import { "f4ah6o/yami_kumo/ui/core", }\npkgtype(kind: "executable")\n',
    );
    const run = (expression) => {
      writeFileSync(join(dir, 'main.mbt'), `fn main { let _ = ${expression} }\n`);
      return spawnSync('moon', ['check', '--target', 'js', '--deny-warn'], {
        cwd: dir,
        encoding: 'utf8',
        timeout: 30000,
      });
    };
    const good = run('@core.StackSpacing::new(@core.Zero, @core.TwentyFour)');
    assert.equal(good.status, 0, good.stdout + good.stderr);
    for (const expression of [
      '@core.StackSpacing::new(-1.0, @core.Zero)',
      '@core.StackSpacing::new(0.0 / 0.0, @core.Zero)',
      '@core.StackSpacing::new(1.0 / 0.0, @core.Zero)',
      '@core.StackSpacing::new(3.0, @core.Zero)',
      '@core.StackSpacing::new(@core.Two, @core.Zero)',
      '({ gap: @core.Zero, padding: @core.Zero } : @core.StackSpacing)',
      '@core.card(@core.NodeKey::new("card"), [], @core.StackSpacing::new(@core.Zero, @core.Zero))',
      '@core.button(@core.NodeKey::new("button"), "label", spacing=@core.StackSpacing::new(@core.Zero, @core.Zero))',
    ]) {
      const bad = run(expression);
      assert.equal(bad.error, undefined);
      assert.notEqual(bad.status, 0, expression);
      assert.match(bad.stdout + bad.stderr, /Error:/);
    }
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});
