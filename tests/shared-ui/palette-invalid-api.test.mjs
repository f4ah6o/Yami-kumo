import assert from 'node:assert/strict';
import { mkdtempSync, writeFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { spawnSync } from 'node:child_process';
import test from 'node:test';

test('closed Button palette rejects numeric, forged and wrong-target input', () => {
  const root = fileURLToPath(new URL('../../', import.meta.url));
  const dir = mkdtempSync(join(tmpdir(), 'yami-palette-api-'));
  try {
    writeFileSync(join(dir, 'moon.work'), `members = [${JSON.stringify(root)}, "."]\n`);
    writeFileSync(
      join(dir, 'moon.mod'),
      'name = "palette_api_probe"\nversion = "0.0.0"\nimport { "f4ah6o/yami_kumo@0.1.0", }\n',
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
    const good = run('@core.button_with_palette(@core.NodeKey::new("b"), "B", @core.Light)');
    assert.equal(good.status, 0, good.stdout + good.stderr);
    for (const expression of [
      '@core.button_with_palette(@core.NodeKey::new("b"), "B", 1)',
      '@core.button_with_palette(@core.NodeKey::new("b"), "B", @core.System)',
      '({ red: 1, green: 2, blue: 3 } : @core.ButtonPaletteColor)',
      '@core.ButtonPaletteColor::new(1, 2, 3)',
      '@core.card(@core.NodeKey::new("c"), [], palette=@core.Light)',
      '@core.text(@core.NodeKey::new("t"), "T", palette=@core.Light)',
      '@core.row(@core.NodeKey::new("r"), [], palette=@core.Light)',
      '@core.button(@core.NodeKey::new("b"), "B", palette=@core.Light)',
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
