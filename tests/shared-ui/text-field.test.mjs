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
  '_build/js/release/build/examples/shared_counter_dom/shared_counter_dom.js',
);

test('real DOM TextField commits once, preserves composition and restores focus', async () => {
  const bundle = await readFile(bundlePath);
  const css = await readFile(resolve(root, 'styles/shared-ui.css'));
  const server = createServer((request, response) => {
    response.setHeader(
      'Content-Security-Policy',
      "default-src 'none'; script-src 'self'; style-src 'self'; img-src 'self'",
    );
    if (request.url === '/shared.js') {
      response.setHeader('Content-Type', 'text/javascript');
      response.end(bundle);
    } else if (request.url === '/shared.css') {
      response.setHeader('Content-Type', 'text/css');
      response.end(css);
    } else if (request.url === '/') {
      response.setHeader('Content-Type', 'text/html');
      response.end(
        '<!doctype html><html lang="en"><head><meta charset="utf-8"><link rel="stylesheet" href="/shared.css"><title>TextField</title></head><body><main id="field-root"></main></body></html>',
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
    const page = await browser.newPage({ viewport: { width: 640, height: 480 } });
    const errors = [];
    page.on('pageerror', (error) => errors.push(error.message));
    await page.goto(`http://127.0.0.1:${server.address().port}/`);
    await page.evaluate(async () => {
      window.api = await import('/shared.js');
    });
    assert.equal(await page.evaluate(() => window.api.mountTextField('field-root')), 'mounted');
    assert.equal(await page.locator('input').count(), 1);
    assert.equal(await page.locator('.yk-ui-field-label-text').textContent(), 'Name');
    assert.equal(await page.locator('.yk-ui-field-description').textContent(), 'Required');
    assert.equal(await page.locator('input').getAttribute('required'), '');
    assert.equal(await page.locator('input').getAttribute('aria-invalid'), 'true');

    await page.fill('input', '日本');
    await page.waitForFunction(() => window.api.textFieldValue('field-root') === '日本');
    assert.equal(await page.inputValue('input'), '日本');
    assert.equal(await page.locator('.yk-ui-field-description').textContent(), 'Japanese name');
    assert.equal(await page.locator('input').getAttribute('aria-invalid'), null);

    await page.press('input', 'Enter');
    await page.waitForFunction(() => window.api.textFieldSubmitted('field-root') === '日本');

    await page.evaluate(() => {
      const input = document.querySelector('input');
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
    assert.equal(await page.evaluate(() => window.api.textFieldValue('field-root')), '日本');

    // An external value is deferred while composing and applied on composition
    // end instead of overwriting the preedit.
    assert.equal(
      await page.evaluate(() => window.api.setTextFieldValue('field-root', '外部')),
      'updated',
    );
    await page.waitForTimeout(0);
    assert.equal(await page.inputValue('input'), 'にほん');
    await page.evaluate(() => {
      document
        .querySelector('input')
        .dispatchEvent(new CompositionEvent('compositionend', { bubbles: true, data: 'にほん' }));
    });
    await page.waitForFunction(() => document.querySelector('input').value === '外部');
    assert.equal(await page.evaluate(() => window.api.textFieldValue('field-root')), '外部');

    await page.evaluate(() => {
      const input = document.querySelector('input');
      input.dispatchEvent(new CompositionEvent('compositionstart', { bubbles: true, data: '' }));
      input.value = '日本語';
      input.dispatchEvent(
        new CompositionEvent('compositionend', { bubbles: true, data: '日本語' }),
      );
    });
    await page.waitForFunction(() => window.api.textFieldValue('field-root') === '日本語');
    assert.equal(await page.inputValue('input'), '日本語');
    assert.equal(await page.evaluate(() => window.api.textFieldValue('field-root')), '日本語');
    const compositionChanges = await page.evaluate(() => window.api.textFieldChanges('field-root'));

    // A post-composition input with the same value must not duplicate the commit.
    await page.evaluate(() => {
      const input = document.querySelector('input');
      input.dispatchEvent(
        new InputEvent('input', { bubbles: true, data: '日本語', isComposing: false }),
      );
    });
    await page.waitForTimeout(0);
    assert.equal(
      await page.evaluate(() => window.api.textFieldChanges('field-root')),
      compositionChanges,
    );

    // A same-revision rerender while focused must not roll the input backwards.
    await page.focus('input');
    const afterStaleRender = await page.evaluate(() => {
      const input = document.querySelector('input');
      input.value = '編集中';
      input.dispatchEvent(
        new InputEvent('input', { bubbles: true, data: '編集中', isComposing: false }),
      );
      window.api.rerenderTextField('field-root');
      return input.value;
    });
    assert.equal(afterStaleRender, '編集中');
    await page.waitForFunction(() => window.api.textFieldValue('field-root') === '編集中');
    assert.equal(await page.inputValue('input'), '編集中');

    // A new external revision applies even while the input is focused.
    assert.equal(
      await page.evaluate(() => window.api.setTextFieldValue('field-root', '外部2')),
      'updated',
    );
    await page.waitForFunction(() => document.querySelector('input').value === '外部2');
    assert.equal(await page.evaluate(() => window.api.textFieldValue('field-root')), '外部2');

    assert.equal(
      await page.evaluate(() => window.api.setTextFieldValue('field-root', '外部')),
      'updated',
    );
    await page.waitForFunction(() => document.querySelector('input').value === '外部');
    assert.equal(await page.evaluate(() => window.api.textFieldValue('field-root')), '外部');

    assert.equal(await page.evaluate(() => window.api.focusTextField('field-root')), true);
    assert.equal(await page.evaluate(() => document.activeElement?.tagName), 'INPUT');

    await page.evaluate(() => window.api.disposeTextField('field-root'));
    assert.equal(await page.locator('input').count(), 0);
    assert.deepEqual(errors, []);
  } finally {
    if (browser) await browser.close();
    await new Promise((done) => server.close(done));
  }
});
