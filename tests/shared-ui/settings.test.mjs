import assert from 'node:assert/strict';
import { createServer } from 'node:http';
import { readFile } from 'node:fs/promises';
import { resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import test from 'node:test';
import { chromium } from 'playwright';

const root = fileURLToPath(new URL('../../', import.meta.url));
const bundlePath = resolve(
  root,
  '_build/js/release/build/examples/shared_settings_dom/shared_settings_dom.js',
);

test('Shared Settings drives validation, composition, dialog and completion in real DOM', async () => {
  const bundle = await readFile(bundlePath);
  const css = await readFile(resolve(root, 'styles/shared-ui.css'));
  const server = createServer((request, response) => {
    if (request.url === '/shared.js') {
      response.setHeader('Content-Type', 'text/javascript');
      response.end(bundle);
    } else if (request.url === '/shared.css') {
      response.setHeader('Content-Type', 'text/css');
      response.end(css);
    } else if (request.url === '/') {
      response.setHeader('Content-Type', 'text/html');
      response.end(
        '<!doctype html><html lang="en"><head><meta charset="utf-8"><link rel="stylesheet" href="/shared.css"><title>Settings</title></head><body><main id="settings-root"></main><main id="settings-other"></main></body></html>',
      );
    } else {
      response.writeHead(404);
      response.end();
    }
  });
  await new Promise((done) => server.listen(0, '127.0.0.1', done));
  let browser;
  try {
    browser = await chromium.launch({
      headless: true,
      ...(process.env.SHARED_UI_CHROMIUM_EXECUTABLE
        ? { executablePath: process.env.SHARED_UI_CHROMIUM_EXECUTABLE }
        : {}),
    });
    const page = await browser.newPage({ viewport: { width: 720, height: 560 } });
    const errors = [];
    page.on('pageerror', (error) => errors.push(error.message));
    await page.goto(`http://127.0.0.1:${server.address().port}/`);
    await page.evaluate(async () => {
      window.api = await import('/shared.js');
    });

    assert.equal(await page.evaluate(() => window.api.mountSettings('settings-root')), 'mounted');
    assert.equal(await page.locator('#settings-root input').count(), 1);
    assert.equal(await page.locator('[data-yk-key="settings-status"]').textContent(), 'Not saved');
    assert.equal(await page.locator('dialog').count(), 1);
    assert.equal(await page.evaluate(() => document.querySelector('dialog').open), false);

    // An empty draft cannot open the confirmation dialog.
    await page.click('[data-yk-key="settings-save"]');
    await page.waitForFunction(() => window.api.settingsError('settings-root') !== '');
    assert.equal(
      await page.evaluate(() => window.api.settingsError('settings-root')),
      'Enter a name before saving.',
    );
    assert.match(
      await page.locator('.yk-ui-field-error').textContent(),
      /Enter a name before saving\./,
    );
    assert.equal(await page.locator('#settings-root input').getAttribute('aria-invalid'), 'true');
    assert.equal(await page.evaluate(() => document.querySelector('dialog').open), false);

    // Editing clears the error; composition text stays out of the model until
    // the composition ends.
    await page.fill('#settings-root input', '闇雲');
    await page.waitForFunction(() => window.api.settingsName('settings-root') === '闇雲');
    assert.equal(await page.locator('#settings-root input').getAttribute('aria-invalid'), null);
    await page.evaluate(() => {
      const input = document.querySelector('#settings-root input');
      input.dispatchEvent(new CompositionEvent('compositionstart', { bubbles: true, data: '' }));
      input.value = 'にほん';
      input.dispatchEvent(
        new CompositionEvent('compositionupdate', { bubbles: true, data: 'にほん' }),
      );
      input.dispatchEvent(
        new InputEvent('input', { bubbles: true, data: 'にほん', isComposing: true }),
      );
    });
    await page.waitForTimeout(0);
    assert.equal(await page.evaluate(() => window.api.settingsName('settings-root')), '闇雲');
    await page.evaluate(() => {
      const input = document.querySelector('#settings-root input');
      input.dispatchEvent(
        new CompositionEvent('compositionend', { bubbles: true, data: '日本語' }),
      );
      input.value = '日本語';
      input.dispatchEvent(
        new InputEvent('input', { bubbles: true, data: '日本語', isComposing: false }),
      );
    });
    await page.waitForFunction(() => window.api.settingsName('settings-root') === '日本語');

    // The confirmation dialog owns focus, dismissal keeps the draft and
    // restores the opener.
    await page.click('[data-yk-key="settings-save"]');
    await page.waitForFunction(() => window.api.settingsDialogOpen('settings-root') === true);
    assert.equal(await page.evaluate(() => document.querySelector('dialog').open), true);
    assert.equal(
      await page.evaluate(() => document.querySelector('dialog').matches(':modal')),
      true,
    );
    assert.equal(
      await page.evaluate(() => document.activeElement?.getAttribute('data-yk-key')),
      'settings-confirm',
    );
    await page.click('[data-yk-key="settings-cancel"]');
    await page.waitForFunction(() => window.api.settingsDialogOpen('settings-root') === false);
    assert.equal(await page.evaluate(() => window.api.settingsName('settings-root')), '日本語');
    assert.equal(
      await page.evaluate(() => document.activeElement?.getAttribute('data-yk-key')),
      'settings-save',
    );

    // Confirming closes the dialog, runs the simulated save and completes.
    await page.click('[data-yk-key="settings-save"]');
    await page.waitForFunction(() => window.api.settingsDialogOpen('settings-root') === true);
    await page.click('[data-yk-key="settings-confirm"]');
    await page.waitForFunction(() => window.api.settingsSaved('settings-root') === true);
    assert.equal(await page.evaluate(() => window.api.settingsDialogOpen('settings-root')), false);
    assert.equal(await page.evaluate(() => window.api.settingsSaving('settings-root')), false);
    assert.equal(await page.evaluate(() => document.querySelector('dialog').open), false);
    assert.equal(await page.locator('[data-yk-key="settings-status"]').textContent(), 'Saved');
    assert.equal(
      await page.evaluate(() => document.activeElement?.getAttribute('data-yk-key')),
      'settings-save',
    );

    // Two roots keep independent drafts and completion state.
    assert.equal(await page.evaluate(() => window.api.mountSettings('settings-other')), 'mounted');
    await page.fill('#settings-other input', 'Second');
    await page.waitForFunction(() => window.api.settingsName('settings-other') === 'Second');
    assert.equal(await page.evaluate(() => window.api.settingsName('settings-root')), '日本語');
    assert.equal(await page.evaluate(() => window.api.settingsSaved('settings-other')), false);
    await page.evaluate(() => window.api.disposeSettings('settings-other'));
    assert.equal(await page.evaluate(() => window.api.settingsName('settings-other')), '');
    assert.equal(
      await page.evaluate(() => window.api.disposeSettings('settings-other')),
      undefined,
    );

    assert.deepEqual(errors, []);
  } finally {
    await browser?.close();
    await new Promise((done) => server.close(done));
  }
});
