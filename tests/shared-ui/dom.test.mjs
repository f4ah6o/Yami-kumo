import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { createServer } from 'node:http';
import { mkdir, readFile, writeFile } from 'node:fs/promises';
import { resolve } from 'node:path';
import os from 'node:os';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { execFileSync } from 'node:child_process';
import test from 'node:test';
import { chromium } from 'playwright';
import { validateResult, validateArtifacts, validateGate } from './evidence.mjs';
import { exerciseButtonStates } from './button-states.mjs';
import { exerciseCard } from './card.mjs';
import { exerciseSpacing } from './spacing.mjs';
import { exerciseTheme } from './theme.mjs';

const root = fileURLToPath(new URL('../../', import.meta.url));
const bundle = resolve(
  root,
  '_build/js/release/build/examples/shared_counter_dom/shared_counter_dom.js',
);
const output =
  process.env.SHARED_UI_EVIDENCE_DIR || resolve(root, `_build/shared-ui-dom-${Date.now()}`);
const hash = (bytes) => createHash('sha256').update(bytes).digest('hex');
const git = (...args) => execFileSync('git', args, { cwd: root, encoding: 'utf8' }).trim();
const sourcePaths = [
  'ui/core',
  'ui/runtime',
  'ui/dom',
  'ui/theme',
  'examples/shared_counter',
  'examples/shared_counter_dom',
  'examples/shared_button_theme',
  'styles/shared-ui.css',
  'fixtures/shared-ui',
  'tests/shared-ui',
  'docs/shared-card.md',
  'docs/shared-stack-spacing.md',
];
async function sourceHashes() {
  const paths = git('ls-files', '-z', '--', ...sourcePaths)
    .split('\0')
    .filter(Boolean);
  return Object.fromEntries(
    await Promise.all(paths.map(async (path) => [path, hash(await readFile(resolve(root, path)))])),
  );
}

test('new common DOM entry is inert in Node and contains no third-party GUI runtime', async () => {
  const bytes = await readFile(bundle, 'utf8');
  assert.doesNotMatch(
    bytes,
    /from\s+["']|import\s*\(|require\s*\(/,
    'compiled bridge must be self-contained',
  );
  assert.doesNotMatch(bytes, /@cloudflare\/kumo|@zag-js|react-dom|ReactNode/);
  const old = Object.getOwnPropertyDescriptor(globalThis, 'document');
  Object.defineProperty(globalThis, 'document', {
    configurable: true,
    get() {
      throw new Error('import touched DOM');
    },
  });
  let api;
  try {
    api = await import(pathToFileURL(bundle).href);
  } finally {
    if (old) Object.defineProperty(globalThis, 'document', old);
    else delete globalThis.document;
  }
  assert.equal(api.mountCounter('unavailable'), 'missing-document');
});

test('real DOM counter preserves keyed identity and isolates root lifetime', async () => {
  await mkdir(output, { recursive: true });
  const compiled = await readFile(bundle);
  const css = await readFile(resolve(root, 'styles/shared-ui.css'));
  const fixtureCss = await readFile(resolve(root, 'tests/shared-ui/spacing-fixture.css'));
  const themeFixture = await readFile(resolve(root, 'fixtures/shared-ui/button-theme-v1.json'));
  const boundSources = await sourceHashes();
  const server = createServer((request, response) => {
    const route = request.url;
    response.setHeader(
      'Content-Security-Policy',
      "default-src 'none'; script-src 'self'; style-src 'self'; img-src 'self'",
    );
    if (route === '/shared.js') {
      response.setHeader('Content-Type', 'text/javascript');
      response.end(compiled);
    } else if (route === '/shared.css') {
      response.setHeader('Content-Type', 'text/css');
      response.end(css);
    } else if (route === '/spacing-fixture.css') {
      response.setHeader('Content-Type', 'text/css');
      response.end(fixtureCss);
    } else if (route === '/') {
      response.setHeader('Content-Type', 'text/html');
      response.end(
        '<!doctype html><html lang="en"><head><meta charset="utf-8"><link rel="stylesheet" href="/shared.css"><link rel="stylesheet" href="/spacing-fixture.css"><title>Shared UI counter proof</title></head><body><main id="root-a"></main><section id="root-b"></section><section id="occupied"><p>Existing content</p></section><section id="spacing-root"></section><section id="fixed-spacing-root"></section><aside id="unrelated">Unrelated host</aside></body></html>',
      );
    } else {
      response.writeHead(404);
      response.end();
    }
  });
  await new Promise((done) => server.listen(0, '127.0.0.1', done));
  let browser;
  const startedAt = new Date().toISOString();
  const trace = [];
  const observe = (name, details = {}) => trace.push({ name, ...details });
  try {
    browser = await chromium.launch({
      headless: true,
      ...(process.env.SHARED_UI_CHROMIUM_EXECUTABLE
        ? { executablePath: process.env.SHARED_UI_CHROMIUM_EXECUTABLE }
        : {}),
    });
    const page = await browser.newPage({ viewport: { width: 900, height: 600 } });
    const errors = [];
    page.on('pageerror', (error) => errors.push(error.message));
    await page.addInitScript(() => {
      const listeners = new WeakMap();
      const originalAdd = EventTarget.prototype.addEventListener;
      const originalRemove = EventTarget.prototype.removeEventListener;
      window.ownedClickListeners = 0;
      window.ownedButtonListeners = 0;
      EventTarget.prototype.addEventListener = function (type, callback, options) {
        if (
          this instanceof Element &&
          this.tagName === 'BUTTON' &&
          this.hasAttribute('data-yk-key')
        ) {
          const types = listeners.get(this) || new Map();
          const set = types.get(type) || new Set();
          if (!set.has(callback)) {
            set.add(callback);
            window.ownedButtonListeners++;
            if (type === 'click') window.ownedClickListeners++;
          }
          types.set(type, set);
          listeners.set(this, types);
        }
        return originalAdd.call(this, type, callback, options);
      };
      EventTarget.prototype.removeEventListener = function (type, callback, options) {
        if (listeners.get(this)?.get(type)?.delete(callback)) {
          window.ownedButtonListeners--;
          if (type === 'click') window.ownedClickListeners--;
        }
        return originalRemove.call(this, type, callback, options);
      };
    });
    await page.goto(`http://127.0.0.1:${server.address().port}/`);
    await page.evaluate(async () => {
      window.api = await import('/shared.js');
    });
    assert.equal(await page.evaluate(() => window.ownedClickListeners), 0);
    assert.equal(await page.evaluate(() => api.mountCounter('occupied')), 'root-not-empty');
    assert.equal(await page.evaluate(() => api.mountCounter('absent')), 'missing-root');
    assert.equal(await page.evaluate(() => api.mountCounter('root-a')), 'mounted');
    assert.equal(await page.evaluate(() => api.mountCounter('root-b')), 'mounted');
    assert.equal(await page.evaluate(() => api.mountCounter('root-a')), 'already-mounted');
    assert.equal(await page.evaluate(() => window.ownedClickListeners), 2);
    assert.equal(await page.locator('#unrelated').textContent(), 'Unrelated host');
    observe('mount-isolated-roots', { countA: 0, countB: 0 });
    // Adjacent Text views must be separate flex items, not one anonymous text run.
    const textLayout = () =>
      page.evaluate(() => {
        const heading = document.querySelector('#root-a [data-yk-key="heading"]');
        const value = document.querySelector('#root-a [data-yk-key="value"]');
        const a = heading.getBoundingClientRect();
        const b = value.getBoundingClientRect();
        return {
          heading: { x: a.x, y: a.y, width: a.width, height: a.height },
          value: { x: b.x, y: b.y, width: b.width, height: b.height },
          literalText: [heading.textContent, value.textContent],
          distinctElements:
            heading !== value && heading.tagName === 'SPAN' && value.tagName === 'SPAN',
        };
      });
    const columnText = await textLayout();
    assert.equal(columnText.distinctElements, true);
    assert.deepEqual(columnText.literalText, ['Shared counter', 'Count: 0']);
    assert.ok(columnText.heading.height > 0);
    assert.ok(columnText.value.y >= columnText.heading.y + columnText.heading.height);
    await page.evaluate(() => {
      window.retainedHeading = document.querySelector('#root-a [data-yk-key="heading"]');
      window.retainedValue = document.querySelector('#root-a [data-yk-key="value"]');
    });
    assert.equal(
      await page.evaluate(() => api.updateCounter('root-a', 'row', 'Increment')),
      'updated',
    );
    const rowText = await textLayout();
    assert.equal(rowText.distinctElements, true);
    assert.ok(rowText.heading.width > 0);
    assert.ok(rowText.value.x >= rowText.heading.x + rowText.heading.width);
    assert.equal(rowText.value.y, rowText.heading.y);
    assert.equal(
      await page.evaluate(() => api.updateCounter('root-a', 'normal', 'Increment')),
      'updated',
    );
    assert.equal(
      await page.evaluate(
        () =>
          window.retainedHeading === document.querySelector('#root-a [data-yk-key="heading"]') &&
          window.retainedValue === document.querySelector('#root-a [data-yk-key="value"]'),
      ),
      true,
    );
    observe('adjacent-text-layout', { column: columnText, row: rowText, retained: true });
    const count = (id) => page.evaluate((rootId) => api.counterValue(rootId), id);
    const expectCount = (id, value) =>
      page.waitForFunction(
        ([rootId, expected]) => api.counterValue(rootId) === expected,
        [id, value],
      );
    const button = page.locator('#root-a button');
    await button.click();
    await expectCount('root-a', 1);
    await button.focus();
    await page.keyboard.press('Enter');
    await expectCount('root-a', 2);
    observe('counter-two-activations', { counts: [0, 1, await count('root-a')] });
    await page.keyboard.down('Space');
    assert.equal(await count('root-a'), 2);
    await page.keyboard.up('Space');
    await expectCount('root-a', 3);
    assert.equal(await count('root-b'), 0);
    await page.locator('#root-b button').click();
    await expectCount('root-b', 1);
    assert.equal(await count('root-a'), 3);
    observe('native-pointer-enter-space', { countA: 3, countB: 1 });

    await button.focus();
    const hostile = '<img src=x onerror="window.injected=true"> & "literal"';
    assert.equal(
      await page.evaluate((label) => {
        window.retained = document.querySelector('#root-a button');
        return api.updateCounter('root-a', 'normal', label);
      }, hostile),
      'updated',
    );
    assert.equal(await button.textContent(), hostile);
    assert.equal(await page.locator('#root-a img').count(), 0);
    assert.equal(await page.evaluate(() => window.injected), undefined);
    assert.equal(
      await page.evaluate(
        () =>
          retained === document.querySelector('#root-a button') &&
          document.activeElement === retained,
      ),
      true,
    );
    assert.equal(await page.evaluate(() => window.ownedClickListeners), 2);
    observe('keyed-label-and-literal-text');
    assert.equal(
      await page.evaluate(() => api.updateCounter('root-a', 'nested-a', 'Nested')),
      'updated',
    );
    assert.equal(
      await page.evaluate(() => api.updateCounter('root-a', 'nested-b', 'Nested')),
      'updated',
    );
    assert.equal(
      await page
        .locator(
          '#root-a > [data-yk-key="ancestor-b"] > [data-yk-key="ancestor-a"] > [data-yk-key="counter"]',
        )
        .count(),
      1,
    );
    assert.equal(
      await page.evaluate(
        () =>
          retained === document.querySelector('#root-a button') &&
          document.activeElement === retained,
      ),
      true,
    );
    assert.equal(await page.evaluate(() => window.ownedClickListeners), 2);
    assert.equal(
      await page.evaluate(() => api.updateCounter('root-a', 'normal', 'Increment')),
      'updated',
    );
    assert.equal(
      await page.evaluate(
        () =>
          retained === document.querySelector('#root-a button') &&
          document.activeElement === retained,
      ),
      true,
    );
    observe('retained-ancestor-inversion-and-focus');

    assert.equal(
      await page.evaluate(() => api.updateCounter('root-a', 'disabled', 'Disabled')),
      'updated',
    );
    await page.evaluate(() => retained.dispatchEvent(new MouseEvent('click', { bubbles: true })));
    assert.equal(await count('root-a'), 3);
    assert.equal(await button.isDisabled(), true);
    await page.evaluate(() => api.updateCounter('root-a', 'normal', 'Increment'));
    await button.focus();
    await page.evaluate(() => api.updateCounter('root-a', 'loading', 'Saving'));
    assert.equal(await page.evaluate(() => document.activeElement === retained), true);
    assert.equal(await button.getAttribute('aria-busy'), 'true');
    assert.equal(await button.getAttribute('aria-disabled'), 'true');
    await page.evaluate(() => retained.click());
    assert.equal(await count('root-a'), 3);
    await page.evaluate(() => api.updateCounter('root-a', 'normal', 'Increment'));
    assert.equal(await button.getAttribute('aria-busy'), null);
    await button.click();
    await expectCount('root-a', 4);
    observe('disabled-loading-gates', { counts: [3, 3, 3, 4] });
    await page.evaluate(() => {
      api.disposeCounter('root-b');
      api.mountCounter('root-b');
    });
    const gateCounts = [await count('root-b')];
    await page.evaluate(() => {
      api.updateCounter('root-b', 'disabled', 'Disabled');
      document
        .querySelector('#root-b button')
        .dispatchEvent(new MouseEvent('click', { bubbles: true }));
    });
    gateCounts.push(await count('root-b'));
    await page.evaluate(() => {
      api.updateCounter('root-b', 'loading', 'Loading');
      document.querySelector('#root-b button').click();
    });
    gateCounts.push(await count('root-b'));
    await page.evaluate(() => api.updateCounter('root-b', 'normal', 'Increment'));
    await page.locator('#root-b button').click();
    await expectCount('root-b', 1);
    gateCounts.push(await count('root-b'));
    observe('counter-disabled-loading', { counts: gateCounts });

    await page.evaluate(() => {
      retained.click();
      api.updateCounter('root-a', 'loading', 'Saving');
      api.updateCounter('root-a', 'normal', 'Increment');
    });
    assert.equal(
      await count('root-a'),
      4,
      'old accepted action must be revoked by a gate transition',
    );
    assert.equal(
      await page.evaluate(() => api.updateCounter('root-a', 'duplicate', 'Invalid')),
      'invalid-view',
    );
    assert.equal(
      await page.evaluate(() => retained === document.querySelector('#root-a button')),
      true,
    );
    assert.equal(await button.textContent(), 'Increment');
    observe('queued-gate-revocation-and-atomic-invalid-view');

    await page.evaluate(() => api.updateCounter('root-a', 'removed', 'Removed'));
    assert.equal(await page.locator('#root-a button').count(), 0);
    await page.evaluate(() => {
      retained.click();
      api.updateCounter('root-a', 'normal', 'Replacement');
      retained.click();
    });
    assert.equal(await count('root-a'), 4);
    assert.equal(
      await page.evaluate(() => retained !== document.querySelector('#root-a button')),
      true,
    );
    await page.evaluate((label) => {
      window.replaced = document.querySelector('#root-a button');
      api.updateCounter('root-a', 'text', label);
      window.retainedText = document.querySelector('#root-a [data-yk-key="increment"]');
    }, hostile);
    assert.equal(await page.locator('#root-a button').count(), 0);
    const textReplacement = page.locator('#root-a [data-yk-key="increment"]');
    assert.equal(await textReplacement.textContent(), hostile);
    assert.equal(await textReplacement.locator('*').count(), 0);
    await page.evaluate(
      (label) => api.updateCounter('root-a', 'text', label),
      hostile + ' updated',
    );
    assert.equal(await textReplacement.textContent(), hostile + ' updated');
    assert.equal(await textReplacement.locator('*').count(), 0);
    assert.equal(await page.evaluate(() => window.injected), undefined);
    assert.equal(
      await page.evaluate(
        () => retainedText === document.querySelector('#root-a [data-yk-key="increment"]'),
      ),
      true,
    );
    observe('literal-text-create-update', { retained: true, parsedElements: 0 });
    await page.evaluate(() => {
      api.updateCounter('root-a', 'normal', 'Replacement');
      replaced.click();
    });
    assert.equal(await count('root-a'), 4);
    observe('removed-and-retyped-events-rejected');

    assert.equal(
      await page.evaluate(() => {
        const nested = document.createElement('div');
        nested.id = 'nested-root';
        document.getElementById('root-a').append(nested);
        const result = api.mountCounter('nested-root');
        nested.remove();
        return result;
      }),
      'overlapping-root',
    );
    assert.equal(await page.evaluate(() => api.focusCounter('root-a')), true);
    assert.equal(await page.evaluate(() => api.focusOutcome('root-a')), 'focused');
    assert.equal(await page.evaluate(() => api.focusOutcome('root-a')), 'none');
    observe('root-overlap-and-observed-focus');

    await page.evaluate(() => {
      document.querySelector('#root-a button').click();
      api.disposeCounter('root-a');
      api.disposeCounter('root-a');
      api.mountCounter('root-a');
    });
    assert.equal(await count('root-a'), 0, 'disposed queued callbacks must not reach remount');
    assert.equal(await count('root-b'), 1);
    assert.equal(await page.evaluate(() => window.ownedClickListeners), 2);
    for (let i = 0; i < 100; i++) {
      assert.equal(
        await page.evaluate(() => {
          api.disposeCounter('root-a');
          return api.mountCounter('root-a');
        }),
        'mounted',
      );
    }
    assert.equal(await page.evaluate(() => window.ownedClickListeners), 2);
    observe('100-mount-dispose-cycles', { activeOwnedClickListeners: 2 });

    await page.evaluate(() => {
      window.moved = document.querySelector('#root-a button');
      document.getElementById('unrelated').append(moved);
    });
    assert.equal(
      await page.evaluate(() => api.updateCounter('root-a', 'normal', 'Cannot update')),
      'host-tree-changed',
    );
    await page.evaluate(() => {
      api.disposeCounter('root-a');
      moved.click();
    });
    assert.equal(
      await page.evaluate(() => document.getElementById('unrelated').contains(moved)),
      true,
    );
    assert.equal(await page.evaluate(() => window.ownedClickListeners), 1);
    await page.evaluate(() => {
      moved.remove();
      api.mountCounter('root-a');
    });
    observe('external-dom-move-is-not-mutated-and-listener-revoked');
    const beforeStateListeners = await page.evaluate(() => window.ownedButtonListeners);
    await exerciseButtonStates(page, observe);
    assert.equal(await page.evaluate(() => window.ownedButtonListeners), beforeStateListeners);
    await exerciseCard(page, observe);
    await exerciseSpacing(page, observe, (name) =>
      page.screenshot({ path: resolve(output, name) }),
    );
    await exerciseTheme(page, observe, JSON.parse(themeFixture), (name) =>
      page.screenshot({ path: resolve(output, name) }),
    );
    assert.deepEqual(errors, []);
    await page.screenshot({ path: resolve(output, 'counter.png') });
    await page.evaluate(() => {
      api.disposeCounter('root-a');
      api.disposeCounter('root-b');
    });
    assert.equal(await page.evaluate(() => window.ownedClickListeners), 0);
    assert.equal(await page.evaluate(() => window.ownedButtonListeners), 0);
    assert.equal(await page.locator('#root-a').textContent(), '');
    assert.equal(await page.locator('#root-b').textContent(), '');
    assert.equal(await page.locator('#occupied').textContent(), 'Existing content');
    assert.equal(await page.locator('#unrelated').textContent(), 'Unrelated host');
    observe('final-dispose', { activeOwnedClickListeners: 0 });
    await writeFile(resolve(output, 'trace.json'), JSON.stringify(trace, null, 2) + '\n');
    const candidateSha = git('rev-parse', 'HEAD');
    const sourceDirty = git('status', '--porcelain').length > 0;
    assert.deepEqual(await sourceHashes(), boundSources, 'source changed during browser fixture');
    await writeFile(resolve(output, 'shared-ui.css'), css);
    await writeFile(resolve(output, 'spacing-fixture.css'), fixtureCss);
    await writeFile(resolve(output, 'button-theme-v1.json'), themeFixture);
    await writeFile(
      resolve(output, 'source-provenance.json'),
      JSON.stringify(
        {
          candidateSha,
          sourceDirty,
          sourceSha256: boundSources,
          servedCssSha256: hash(css),
          servedFixtureCssSha256: hash(fixtureCss),
          themeFixtureSha256: hash(themeFixture),
          compiledBridgeSha256: hash(compiled),
        },
        null,
        2,
      ) + '\n',
    );
    const artifacts = [];
    for (const path of [
      'spacing-0.png',
      'spacing-1.png',
      'spacing-2.png',
      'spacing-3.png',
      'spacing-4.png',
      'spacing-fixed.png',
      'theme-light.png',
      'theme-dark.png',
      'trace.json',
      'counter.png',
      'shared-ui.css',
      'spacing-fixture.css',
      'button-theme-v1.json',
      'source-provenance.json',
    ])
      artifacts.push({ path, sha256: hash(await readFile(resolve(output, path))) });
    const finishedAt = new Date().toISOString();
    const coreManifest = await readFile(
      resolve(root, '_build/js/release/build/all_pkgs.json'),
      'utf8',
    );
    const coreCatalog = JSON.parse(coreManifest).packages.find(
      (entry) => entry.root === 'moonbitlang/core',
    );
    const coreRoot = coreCatalog.artifact.replaceAll('\\', '/').split('/_build/')[0];
    const coreHash = hash(await readFile(resolve(coreRoot, 'moon.mod')));
    const results = [
      'counter-two-activations',
      'counter-disabled-loading',
      'button-interrupted-loading',
      'button-interrupted-disabled',
      'card-counter-two-activations',
      'spacing-count-and-toggle',
    ].map((fixtureId) => ({
      schemaVersion: 'shared-ui-result/v1',
      contractVersion: 'shared-ui-contract/v1',
      fixtureId,
      candidateSha,
      sourceDirty,
      startedAt,
      finishedAt,
      dependencies: [
        { name: 'compiled-bridge-sha256', revision: hash(compiled) },
        { name: 'served-stylesheet-sha256', revision: hash(css) },
        { name: 'served-fixture-stylesheet-sha256', revision: hash(fixtureCss) },
        { name: 'moonbit-core-manifest-sha256', revision: coreHash },
      ],
      profile: {
        platform: 'web',
        backend: 'dom',
        target: 'js',
        layer: 'runtime',
        environment: {
          os: `${process.platform} ${os.release()}`,
          arch: process.arch,
          toolchain: execFileSync('moon', ['version'], { encoding: 'utf8' }).trim(),
          browser: browser.version(),
        },
      },
      capability: 'supported',
      status: sourceDirty ? 'fail' : 'pass',
      ...(sourceDirty
        ? { reason: 'Local source is dirty; behavior passed but cannot qualify an exact commit.' }
        : {}),
      command: ['node', '--test', 'tests/shared-ui/dom.test.mjs'],
      exitCode: 0,
      artifacts,
      profileDifferences: [],
      observed: { counts: trace.find((item) => item.name === fixtureId).counts },
    }));
    for (const result of results) {
      validateResult(result, candidateSha);
      validateArtifacts(result, output);
    }
    if (!sourceDirty)
      validateGate(
        results,
        results.map((r) => `${r.fixtureId}:web/dom/js/runtime`),
        candidateSha,
      );
    await writeFile(resolve(output, 'evidence.json'), JSON.stringify(results, null, 2) + '\n');
    await writeFile(
      resolve(output, 'result.json'),
      JSON.stringify(
        {
          status: 'pass',
          scope:
            'Chromium DOM Text/Button/Card fixed geometry, scoped Button theme and root lifecycle only',
          startedAt,
          finishedAt,
          candidateSha: git('rev-parse', 'HEAD'),
          dirty: git('status', '--porcelain').length > 0,
          browser: browser.version(),
          node: process.version,
          platform: process.platform,
          arch: process.arch,
          bundleSha256: hash(compiled),
          fixtures: trace,
          artifacts,
          excluded: [
            'native windows',
            'physical hardware input',
            'IME',
            'external accessibility',
            'full visual parity',
            'Firefox',
            'Safari',
          ],
        },
        null,
        2,
      ) + '\n',
    );
    console.log(`Shared UI DOM evidence: ${output}`);
  } catch (error) {
    await writeFile(
      resolve(output, 'failure.json'),
      JSON.stringify({ status: 'fail', error: String(error), trace }, null, 2) + '\n',
    );
    throw error;
  } finally {
    if (browser) await browser.close();
    await new Promise((done) => server.close(done));
  }
});
