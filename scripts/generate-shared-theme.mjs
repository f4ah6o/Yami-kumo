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
const payload = JSON.parse(result.stdout);
assert.deepEqual(Object.keys(payload), ['buttons', 'shell']);
const buttons = payload.buttons;
const shell = payload.shell;
assert.deepEqual(Object.keys(buttons), ['light', 'dark']);
assert.deepEqual(Object.keys(shell), ['light', 'dark']);
const buttonSlots = [
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
const shellSlots = ['background', 'panel', 'subtle', 'border', 'strong_border', 'text', 'muted'];
for (const tokens of Object.values(buttons)) {
  assert.deepEqual(Object.keys(tokens), buttonSlots);
  for (const rgb of Object.values(tokens)) {
    assert.equal(rgb.length, 3);
    assert.ok(rgb.every((byte) => Number.isInteger(byte) && byte >= 0 && byte <= 255));
  }
}
for (const tokens of Object.values(shell)) {
  assert.deepEqual(Object.keys(tokens), shellSlots);
  for (const rgb of Object.values(tokens)) {
    assert.equal(rgb.length, 3);
    assert.ok(rgb.every((byte) => Number.isInteger(byte) && byte >= 0 && byte <= 255));
  }
}
// Root themes share the established per-Button colors without changing that API.
const explicitPalettes = JSON.parse(
  readFileSync(new URL('../fixtures/shared-ui/button-palettes.json', import.meta.url), 'utf8'),
);
assert.deepEqual(explicitPalettes.roles, buttonSlots);
for (const name of ['Light', 'Dark']) {
  assert.deepEqual(
    explicitPalettes[name],
    buttonSlots.map((slot) => buttons[name.toLowerCase()][slot]),
    `standard theme would change the existing ${name} per-Button palette`,
  );
}
function declarations(themes, prefix) {
  return Object.entries(themes)
    .map(
      ([theme, tokens]) =>
        `.yk-ui-root[data-yk-theme='${theme}'] {\n${Object.entries(tokens)
          .map(
            ([slot, rgb]) => `  --${prefix}-${slot.replaceAll('_', '-')}: rgb(${rgb.join(', ')});`,
          )
          .join('\n')}\n}`,
    )
    .join('\n\n');
}
function replaceRegion(css, begin, end, body) {
  const first = css.indexOf(begin);
  const last = css.indexOf(end);
  assert.ok(first >= 0 && last > first, `missing generated region: ${begin}`);
  assert.equal(css.lastIndexOf(begin), first);
  assert.equal(css.lastIndexOf(end), last);
  return `${css.slice(0, first)}${begin}\n${body}\n${end}${css.slice(last + end.length)}`;
}
const cssPath = new URL('../styles/shared-ui.css', import.meta.url);
const css = readFileSync(cssPath, 'utf8');
let nextCss = replaceRegion(
  css,
  '/* BEGIN GENERATED BUTTON THEME TOKENS */',
  '/* END GENERATED BUTTON THEME TOKENS */',
  declarations(buttons, 'yk-button'),
);
nextCss = replaceRegion(
  nextCss,
  '/* BEGIN GENERATED SHELL THEME TOKENS */',
  '/* END GENERATED SHELL THEME TOKENS */',
  declarations(shell, 'yk-shell'),
);
function rewriteJson(path, update) {
  const source = readFileSync(path, 'utf8');
  const fixture = JSON.parse(source);
  update(fixture);
  const next = `${JSON.stringify(fixture, null, 2).replace(
    /\[\n\s+(\d+),\n\s+(\d+),\n\s+(\d+)\n\s+\]/g,
    '[$1, $2, $3]',
  )}\n`;
  return [source, next];
}
const buttonFixturePath = new URL('../fixtures/shared-ui/button-theme-v1.json', import.meta.url);
const [buttonSource, buttonNext] = rewriteJson(buttonFixturePath, (fixture) => {
  assert.equal(fixture.version, 'shared-button-theme/v1');
  fixture.themes = buttons;
});
const shellFixturePath = new URL('../fixtures/shared-ui/app-shell-v1.json', import.meta.url);
const [shellSource, shellNext] = rewriteJson(shellFixturePath, (fixture) => {
  assert.equal(fixture.version, 'shared-app-shell/v1');
  fixture.themes = shell;
});
for (const [path, before, after] of [
  [cssPath, css, nextCss],
  [buttonFixturePath, buttonSource, buttonNext],
  [shellFixturePath, shellSource, shellNext],
]) {
  if (check) assert.equal(before, after, `stale theme tokens: ${fileURLToPath(path)}`);
  else if (before !== after) writeFileSync(path, after);
}
console.log(`PASS: shared theme tokens ${check ? 'checked' : 'generated'} from ui/theme`);
