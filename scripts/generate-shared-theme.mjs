import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { readFileSync, writeFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';

const root = fileURLToPath(new URL('../', import.meta.url));
assert.ok(
  process.argv.length === 2 || (process.argv.length === 3 && process.argv[2] === '--check'),
);
const check = process.argv[2] === '--check';
const build = spawnSync(
  'moon',
  ['build', 'tools/theme_tokens', '--target', 'js', '--release', '--deny-warn'],
  {
    cwd: root,
    encoding: 'utf8',
  },
);
assert.ifError(build.error);
assert.equal(build.status, 0, build.stderr || String(build.error));
const result = spawnSync(
  process.execPath,
  ['_build/js/release/build/tools/theme_tokens/theme_tokens.js'],
  {
    cwd: root,
    encoding: 'utf8',
  },
);
assert.ifError(result.error);
assert.equal(result.status, 0, result.stderr || String(result.error));
const themes = JSON.parse(result.stdout);
assert.deepEqual(Object.keys(themes), ['light', 'dark']);
const slots = [
  'normal_border',
  'focused_border',
  'disabled_border',
  'normal_fill',
  'hovered_fill',
  'pressed_fill',
  'loading_fill',
  'disabled_fill',
  'enabled_foreground',
  'disabled_foreground',
];
for (const tokens of Object.values(themes)) {
  assert.deepEqual(Object.keys(tokens), slots);
  for (const rgb of Object.values(tokens)) {
    assert.equal(rgb.length, 3);
    assert.ok(rgb.every((byte) => Number.isInteger(byte) && byte >= 0 && byte <= 255));
  }
}
const begin = '/* BEGIN GENERATED BUTTON THEME TOKENS */';
const end = '/* END GENERATED BUTTON THEME TOKENS */';
const declarations = Object.entries(themes)
  .map(
    ([theme, tokens]) =>
      `.yk-ui-root[data-yk-theme='${theme}'] {\n${Object.entries(tokens)
        .map(([slot, rgb]) => `  --yk-button-${slot.replaceAll('_', '-')}: rgb(${rgb.join(', ')});`)
        .join('\n')}\n}`,
  )
  .join('\n\n');
const cssPath = new URL('../styles/shared-ui.css', import.meta.url);
const css = readFileSync(cssPath, 'utf8');
const first = css.indexOf(begin);
const last = css.indexOf(end);
assert.ok(first >= 0 && last > first, 'missing generated theme token region');
assert.equal(css.lastIndexOf(begin), first);
assert.equal(css.lastIndexOf(end), last);
const nextCss = `${css.slice(0, first)}${begin}\n${declarations}\n${end}${css.slice(last + end.length)}`;
const fixturePath = new URL('../fixtures/shared-ui/button-theme-v1.json', import.meta.url);
const fixtureSource = readFileSync(fixturePath, 'utf8');
const fixture = JSON.parse(fixtureSource);
assert.equal(fixture.version, 'shared-button-theme/v1');
fixture.themes = themes;
// Byte triples need no formatter or legacy CSS toolchain to stay reproducible.
const nextFixture = `${JSON.stringify(fixture, null, 2).replace(
  /\[\n\s+(\d+),\n\s+(\d+),\n\s+(\d+)\n\s+\]/g,
  '[$1, $2, $3]',
)}\n`;
for (const [path, before, after] of [
  [cssPath, css, nextCss],
  [fixturePath, fixtureSource, nextFixture],
]) {
  if (check) assert.equal(before, after, `stale theme tokens: ${fileURLToPath(path)}`);
  else if (before !== after) writeFileSync(path, after);
}
console.log(`PASS: shared Button theme tokens ${check ? 'checked' : 'generated'} from ui/theme`);
