import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { spawnSync } from 'node:child_process';
import { pathToFileURL } from 'node:url';

const root = new URL('../', import.meta.url);
const build = spawnSync('moon', ['build', 'browser', '--target', 'js', '--release'], {
  cwd: root,
  encoding: 'utf8',
});
if (build.status !== 0) {
  process.stderr.write(build.stderr || build.stdout);
  process.exit(build.status ?? 1);
}

const outputUrl = new URL('../_build/js/release/build/browser/browser.js', import.meta.url);
const output = await readFile(outputUrl, 'utf8');
assert.ok(output.length > 10_000, 'compiled MoonBit output is unexpectedly empty');
assert.match(output, /as renderParityCase/, 'compiled MoonBit renderer export is missing');
assert.doesNotMatch(
  output,
  /from\s+["']react(?:\/|["'])|require\(["']react(?:\/|["'])/,
  'compiled MoonBit output must not depend on React',
);
assert.doesNotMatch(
  output,
  /@cloudflare\/kumo/,
  'compiled MoonBit output must not import the React Kumo package',
);

const { enhanceYamiKumo, renderParityCase } = await import(pathToFileURL(outputUrl.pathname).href);
assert.equal(typeof enhanceYamiKumo, 'function', 'compiled component behavior export is missing');
const button = renderParityCase(
  JSON.stringify({
    component: 'button',
    content: '<Save & continue>',
    props: { variant: 'primary', size: 'lg', target: 'save' },
  }),
);
assert.match(button, /data-parity-target="save"/);
assert.match(button, /data-kumo-component="Button"/);
assert.match(button, /&lt;Save &amp; continue&gt;/);
assert.match(button, /yk-kumo-button-emphasis-primary/);
assert.doesNotMatch(button, /\sstyle=/, 'strict CSP requires the button to use external CSS');

const input = renderParityCase(
  JSON.stringify({
    component: 'input',
    props: {
      id: 'email',
      label: 'Email',
      description: 'Used for account notices',
      error: 'Enter a valid address',
      variant: 'error',
      target: 'email',
    },
  }),
);
assert.match(input, /data-parity-target="email"/);
assert.match(input, /for="email"/);
assert.match(input, /aria-labelledby="email-label"/);
assert.match(input, /aria-describedby="email-error"/);
assert.doesNotMatch(input, /id="email-description"/);
assert.doesNotMatch(input, /aria-invalid=/);
assert.match(input, /id="email-error"/);

const describedInput = renderParityCase(
  JSON.stringify({
    component: 'input',
    props: {
      id: 'account-name',
      label: 'Account name',
      description: 'Shown to your team',
      target: 'account-name',
    },
  }),
);
assert.match(describedInput, /for="account-name"/);
assert.match(describedInput, /aria-labelledby="account-name-label"/);
assert.match(describedInput, /aria-describedby="account-name-description"/);
assert.match(describedInput, /id="account-name-description"/);

const unlabeledInput = renderParityCase(
  JSON.stringify({
    component: 'input',
    props: {
      id: 'workspace-search',
      placeholder: 'Search workspace',
      ariaLabel: 'Search workspace',
    },
  }),
);
assert.match(unlabeledInput, /<input id="workspace-search"/);
assert.match(unlabeledInput, /aria-label="Search workspace"/);
assert.doesNotMatch(unlabeledInput, /<label/);
assert.doesNotMatch(unlabeledInput, /yk-kumo-input-field/);

const inputGroup = renderParityCase(
  JSON.stringify({
    component: 'input',
    props: {
      grouped: true,
      firstId: 'first-name',
      firstLabel: 'Display name',
      firstDescription: 'Shown to teammates',
      firstTarget: 'first-field',
      secondId: 'email',
      secondLabel: 'Email',
      secondDescription: 'Superseded helper text',
      secondError: 'Enter a valid address',
      secondTarget: 'second-field',
    },
  }),
);
const ids = [...inputGroup.matchAll(/\bid="([^"]+)"/g)].map((match) => match[1]);
assert.equal(new Set(ids).size, ids.length, 'multiple inputs must keep every id unique');
for (const [, referencedIds] of inputGroup.matchAll(/\b(?:for|aria-describedby)="([^"]+)"/g)) {
  for (const referencedId of referencedIds.split(/\s+/)) {
    assert.ok(ids.includes(referencedId), `input reference ${referencedId} must resolve`);
  }
}
assert.match(inputGroup, /aria-describedby="first-name-description"/);
assert.match(inputGroup, /aria-describedby="email-error"/);
assert.doesNotMatch(inputGroup, /Superseded helper text/);

console.log('Compiled MoonBit renderer exports safe component HTML without React dependencies.');
