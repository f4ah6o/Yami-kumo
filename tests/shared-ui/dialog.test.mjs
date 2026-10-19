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

test('real DOM Dialog owns the top layer, dismisses once and restores focus', async () => {
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
        '<!doctype html><html lang="en"><head><meta charset="utf-8"><link rel="stylesheet" href="/shared.css"><title>Dialog</title></head><body><main id="dialog-root"></main></body></html>',
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
    assert.equal(await page.evaluate(() => window.api.mountDialog('dialog-root')), 'mounted');
    assert.equal(await page.locator('dialog').count(), 1);
    assert.equal(await page.evaluate(() => document.querySelector('dialog').open), false);

    await page.click('button[data-yk-key="open"]');
    await page.waitForFunction(() => window.api.dialogOpen('dialog-root') === true);
    assert.equal(await page.evaluate(() => document.querySelector('dialog').open), true);
    assert.equal(
      await page.evaluate(() => document.querySelector('dialog').matches(':modal')),
      true,
    );
    assert.equal(
      await page.evaluate(() => document.activeElement?.getAttribute('data-yk-key')),
      'confirm',
    );

    await page.keyboard.press('Escape');
    await page.waitForFunction(() => window.api.dialogOpen('dialog-root') === false);
    assert.equal(await page.evaluate(() => document.querySelector('dialog').open), false);
    assert.equal(
      await page.evaluate(() => document.activeElement?.getAttribute('data-yk-key')),
      'open',
    );

    await page.click('button[data-yk-key="open"]');
    await page.waitForFunction(() => window.api.dialogOpen('dialog-root') === true);
    await page.click('button[data-yk-key="confirm"]');
    await page.waitForFunction(() => window.api.dialogConfirmed('dialog-root') === true);
    assert.equal(await page.evaluate(() => window.api.dialogOpen('dialog-root')), false);
    assert.equal(await page.evaluate(() => document.querySelector('dialog').open), false);
    assert.equal(
      await page.evaluate(() => document.activeElement?.getAttribute('data-yk-key')),
      'open',
    );

    // A non-dismissible dialog ignores Escape.
    assert.equal(
      await page.evaluate(() => window.api.setDialogDismissible('dialog-root', false)),
      'updated',
    );
    await page.click('button[data-yk-key="open"]');
    await page.waitForFunction(() => window.api.dialogOpen('dialog-root') === true);
    await page.keyboard.press('Escape');
    await page.waitForTimeout(50);
    assert.equal(await page.evaluate(() => window.api.dialogOpen('dialog-root')), true);
    assert.equal(
      await page.evaluate(() => window.api.setDialogDismissible('dialog-root', true)),
      'updated',
    );
    await page.keyboard.press('Escape');
    await page.waitForFunction(() => window.api.dialogOpen('dialog-root') === false);

    await page.click('button[data-yk-key="open"]');
    await page.waitForFunction(() => window.api.dialogOpen('dialog-root') === true);
    await page.click('button[data-yk-key="cancel"]');
    await page.waitForFunction(() => window.api.dialogOpen('dialog-root') === false);
    assert.equal(await page.evaluate(() => window.api.dialogConfirmed('dialog-root')), true);

    await page.evaluate(() => window.api.disposeDialog('dialog-root'));
    assert.equal(await page.locator('dialog').count(), 0);
    assert.deepEqual(errors, []);
  } finally {
    if (browser) await browser.close();
    await new Promise((done) => server.close(done));
  }
});
