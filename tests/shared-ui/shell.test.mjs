import assert from 'node:assert/strict';
import { createServer } from 'node:http';
import { readFile } from 'node:fs/promises';
import { resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import test from 'node:test';
import { chromium } from 'playwright';

const root = fileURLToPath(new URL('../../', import.meta.url));
const bundle = resolve(
  root,
  '_build/js/release/build/examples/shared_counter_dom/shared_counter_dom.js',
);
const contract = JSON.parse(
  await readFile(resolve(root, 'fixtures/shared-ui/app-shell-v1.json'), 'utf8'),
);
const cssRgb = (rgb) => `rgb(${rgb.join(', ')})`;

async function withPage(run) {
  const compiled = await readFile(bundle);
  const css = await readFile(resolve(root, 'styles/shared-ui.css'));
  const fixtureCss = [
    '#shell-root { width: 1000px; height: 700px; }',
    '#shell-root[data-fixture-width="700"] { width: 700px; }',
    '#shell-root[data-fixture-width="820"] { width: 820px; }',
    '#shell-root[data-fixture-width="821"] { width: 821px; }',
    '#shell-second { width: 700px; height: 700px; }',
    '#shell-minimal { width: 1000px; height: 700px; }',
  ].join('\n');
  const server = createServer((request, response) => {
    response.setHeader(
      'Content-Security-Policy',
      "default-src 'none'; script-src 'self'; style-src 'self'; img-src 'self'",
    );
    if (request.url === '/shared.js') {
      response.setHeader('Content-Type', 'text/javascript');
      response.end(compiled);
    } else if (request.url === '/shared.css') {
      response.setHeader('Content-Type', 'text/css');
      response.end(css);
    } else if (request.url === '/fixture.css') {
      response.setHeader('Content-Type', 'text/css');
      response.end(fixtureCss);
    } else {
      response.setHeader('Content-Type', 'text/html');
      response.end(
        '<!doctype html><html lang="en"><head><meta charset="utf-8"><link rel="stylesheet" href="/shared.css"><link rel="stylesheet" href="/fixture.css"><title>Shared AppShell proof</title></head><body><main id="shell-root"></main><section id="shell-second"></section><section id="shell-minimal"></section><section id="occupied"><p>Existing content</p></section><aside id="unrelated">Unrelated host</aside></body></html>',
      );
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
    const page = await browser.newPage({ viewport: { width: 1100, height: 800 } });
    const pageErrors = [];
    page.on('pageerror', (error) => pageErrors.push(error.message));
    await page.goto(`http://127.0.0.1:${server.address().port}/`);
    await page.evaluate(async () => {
      window.api = await import('/shared.js');
    });
    await run(page, pageErrors);
  } finally {
    await browser?.close();
    await new Promise((done) => server.close(done));
  }
}

const bounds = (page, selector) =>
  page.evaluate((value) => {
    const node = document.querySelector(value);
    const rect = node.getBoundingClientRect();
    return {
      x: rect.x,
      y: rect.y,
      width: rect.width,
      height: rect.height,
      bottom: rect.bottom,
      right: rect.right,
    };
  }, selector);

const display = (page, selector) =>
  page.evaluate((value) => getComputedStyle(document.querySelector(value)).display, selector);

const setShellWidth = (page, width) =>
  page.evaluate(async (value) => {
    document.querySelector('#shell-root').dataset.fixtureWidth = String(value);
    await new Promise((done) => requestAnimationFrame(() => requestAnimationFrame(done)));
  }, width);

test('shared AppShell renders semantic regions and fills the wide layout', async () => {
  await withPage(async (page, errors) => {
    assert.equal(await page.evaluate(() => api.mountShell('occupied', 'light')), 'root-not-empty');
    assert.equal(await page.evaluate(() => api.mountShell('shell-root', 'light')), 'mounted');
    assert.equal(
      await page.evaluate(() => api.mountShell('shell-root', 'light')),
      'already-mounted',
    );
    assert.equal(await page.locator('#unrelated').textContent(), 'Unrelated host');
    assert.equal(await page.evaluate(() => document.querySelector('.yk-ui-shell').tagName), 'DIV');
    assert.equal(
      await page.evaluate(() => document.querySelector('.yk-ui-topbar').tagName),
      'HEADER',
    );
    assert.equal(await page.evaluate(() => document.querySelector('.yk-ui-rail').tagName), 'NAV');
    assert.equal(
      await page.evaluate(() => document.querySelector('.yk-ui-sidebar').tagName),
      'ASIDE',
    );
    assert.equal(await page.evaluate(() => document.querySelector('.yk-ui-main').tagName), 'MAIN');
    assert.equal(
      await page.evaluate(() => document.querySelector('.yk-ui-bottom-bar').tagName),
      'FOOTER',
    );
    assert.equal(await page.evaluate(() => document.querySelector('.yk-ui-tabs').tagName), 'NAV');
    assert.equal(
      await page.evaluate(() => document.querySelector('.yk-ui-context-panel').tagName),
      'ASIDE',
    );
    assert.equal(
      await page.evaluate(() => document.querySelector('.yk-ui-rail').getAttribute('aria-label')),
      'Primary',
    );
    assert.equal(
      await page.evaluate(() =>
        document.querySelector('.yk-ui-sidebar').getAttribute('aria-label'),
      ),
      'Workspace navigation',
    );
    assert.equal(
      await page.evaluate(() =>
        document.querySelector('.yk-ui-context-panel').getAttribute('aria-label'),
      ),
      'Context panel',
    );
    const shell = await bounds(page, '.yk-ui-shell');
    const header = await bounds(page, '.yk-ui-topbar');
    const rail = await bounds(page, '.yk-ui-rail');
    const sidebar = await bounds(page, '.yk-ui-sidebar');
    const main = await bounds(page, '.yk-ui-main');
    const tabs = await bounds(page, '.yk-ui-tabs');
    const content = await bounds(page, '#shell-root [data-yk-key="counter"]');
    const bottom = await bounds(page, '.yk-ui-bottom-bar');
    assert.ok(shell.width > 0 && shell.height > 0);
    assert.equal(header.height, contract.geometry.header);
    assert.equal(rail.width, contract.geometry.rail);
    assert.equal(sidebar.width, contract.geometry.sidebar);
    assert.equal(bottom.height, contract.geometry.bottomBar);
    assert.equal(tabs.height, contract.geometry.tabs);
    assert.equal(content.x, main.x + contract.geometry.mainPadding);
    assert.ok(rail.right <= sidebar.x + 1);
    assert.ok(sidebar.right <= main.x + 1);
    assert.ok(header.bottom <= main.y);
    assert.ok(main.bottom <= bottom.y + 1);
    assert.equal(await display(page, '.yk-ui-navigation-trigger'), 'none');
    assert.equal(await display(page, '.yk-ui-context-panel'), 'none');
    assert.equal(await display(page, '.yk-ui-sidebar'), 'flex');
    assert.equal(await page.evaluate(() => document.querySelectorAll('.yk-ui-shell').length), 1);
    assert.equal(
      await page.evaluate(() => getComputedStyle(document.body).backgroundColor),
      'rgba(0, 0, 0, 0)',
    );
    assert.deepEqual(errors, []);
  });
});

test('shared AppShell stacks optional regions at the compact breakpoint', async () => {
  await withPage(async (page) => {
    assert.equal(await page.evaluate(() => api.mountShell('shell-root', 'light')), 'mounted');
    await setShellWidth(page, contract.breakpoint);
    assert.equal(await display(page, '.yk-ui-rail'), 'none');
    assert.equal(await display(page, '.yk-ui-navigation-trigger'), 'block');
    assert.equal(await display(page, '.yk-ui-sidebar'), 'none');
    assert.equal(await display(page, '.yk-ui-context-panel'), 'none');
    assert.equal(
      await page.evaluate(() => api.shellAction('shell-root', 'toggle-sidebar')),
      'updated',
    );
    assert.equal(
      await page.evaluate(() => api.shellAction('shell-root', 'toggle-context')),
      'updated',
    );
    assert.equal(await display(page, '.yk-ui-sidebar'), 'flex');
    assert.equal(await display(page, '.yk-ui-context-panel'), 'flex');
    const main = await bounds(page, '.yk-ui-main');
    const sidebar = await bounds(page, '.yk-ui-sidebar');
    const context = await bounds(page, '.yk-ui-context-panel');
    assert.ok(sidebar.bottom <= main.y + 1);
    assert.ok(main.bottom <= context.y + 1);
    assert.equal(sidebar.height, contract.geometry.compactSidebar);
    assert.equal(context.height, contract.geometry.compactContext);
    assert.equal(await page.evaluate(() => api.shellSidebarOpen('shell-root')), true);
    assert.equal(await page.evaluate(() => api.shellContextOpen('shell-root')), true);
  });
});

test('shared AppShell uses the shell width rather than the viewport', async () => {
  await withPage(async (page) => {
    assert.equal(await page.evaluate(() => api.mountShell('shell-second', 'light')), 'mounted');
    assert.equal(await page.evaluate(() => window.innerWidth), 1100);
    assert.equal((await bounds(page, '#shell-second .yk-ui-shell')).width, 700);
    assert.equal(await display(page, '#shell-second .yk-ui-rail'), 'none');
    assert.equal(await display(page, '#shell-second .yk-ui-navigation-trigger'), 'block');
    assert.equal(await display(page, '#shell-second .yk-ui-sidebar'), 'none');
    assert.equal((await bounds(page, '#shell-second .yk-ui-main')).width, 700);
  });
});

test('shared AppShell switches exactly at the 820px shell boundary', async () => {
  await withPage(async (page) => {
    assert.equal(await page.evaluate(() => api.mountShell('shell-root', 'light')), 'mounted');
    await setShellWidth(page, contract.breakpoint);
    assert.equal(await page.evaluate(() => window.innerWidth), 1100);
    assert.equal(await display(page, '.yk-ui-rail'), 'none');
    assert.equal(await display(page, '.yk-ui-navigation-trigger'), 'block');
    await setShellWidth(page, contract.breakpoint + 1);
    assert.equal(await page.evaluate(() => window.innerWidth), 1100);
    assert.equal(await display(page, '.yk-ui-rail'), 'flex');
    assert.equal(await display(page, '.yk-ui-navigation-trigger'), 'none');
  });
});

test('shared AppShell omits empty header-end flex space', async () => {
  await withPage(async (page) => {
    assert.equal(await page.evaluate(() => api.mountShellMinimal('shell-minimal')), 'mounted');
    assert.equal(await display(page, '#shell-minimal .yk-ui-header-end'), 'none');
    assert.equal(await display(page, '#shell-minimal .yk-ui-header-actions'), 'none');
    assert.equal(await display(page, '#shell-minimal .yk-ui-account-menu'), 'none');
    assert.equal(
      await page.evaluate(() =>
        document.querySelector('#shell-minimal .yk-ui-header-end').getAttribute('data-present'),
      ),
      'false',
    );
    const shell = await bounds(page, '#shell-minimal .yk-ui-shell');
    const search = await bounds(page, '#shell-minimal .yk-ui-global-search');
    assert.ok(search.width > shell.width / 2);
    assert.ok(search.right >= shell.right - 16);
    assert.equal(await page.evaluate(() => api.disposeMinimalShell('shell-minimal')), undefined);
  });
});

test('shared AppShell keeps visible identity and rejects hidden focus and queued actions', async () => {
  await withPage(async (page) => {
    assert.equal(await page.evaluate(() => api.mountShell('shell-root', 'light')), 'mounted');
    const before = await page.evaluate(() => {
      window.retainedIncrement = document.querySelector('#shell-root [data-yk-key="increment"]');
      return api.focusShell('shell-root', 'increment');
    });
    assert.equal(before, true);
    assert.equal(
      await page.evaluate(() => document.activeElement.getAttribute('data-yk-key')),
      'increment',
    );
    assert.equal(await page.evaluate(() => api.setShellTheme('shell-root', 'dark')), 'updated');
    assert.equal(
      await page.evaluate(
        () =>
          window.retainedIncrement ===
          document.querySelector('#shell-root [data-yk-key="increment"]'),
      ),
      true,
    );
    assert.equal(
      await page.evaluate(() => document.activeElement.getAttribute('data-yk-key')),
      'increment',
    );
    await setShellWidth(page, 700);
    assert.equal(
      await page.evaluate(() => api.shellAction('shell-root', 'toggle-sidebar')),
      'updated',
    );
    assert.equal(
      await page.evaluate(() => api.focusShell('shell-root', 'sidebar-increment')),
      true,
    );
    const sidebarIncrement = await page.evaluate(() =>
      document
        .querySelector('#shell-root [data-yk-key="sidebar-increment"]')
        .getBoundingClientRect()
        .toJSON(),
    );
    assert.ok(sidebarIncrement.width > 0);
    assert.equal(
      await page.evaluate(() => {
        const node = document.querySelector('#shell-root [data-yk-key="sidebar-increment"]');
        node.click();
        return api.shellAction('shell-root', 'toggle-sidebar');
      }),
      'updated',
    );
    await page.waitForTimeout(30);
    assert.equal(await page.evaluate(() => api.shellValue('shell-root')), 0);
    assert.equal(
      await page.evaluate(() => api.focusShell('shell-root', 'sidebar-increment')),
      false,
    );
    assert.equal(await page.evaluate(() => api.shellSidebarOpen('shell-root')), false);
  });
});

test('shared AppShell applies one root theme without changing other roots', async () => {
  await withPage(async (page) => {
    assert.equal(await page.evaluate(() => api.mountShell('shell-root', 'light')), 'mounted');
    assert.equal(await page.evaluate(() => api.mountShell('shell-second', 'dark')), 'mounted');
    const colors = await page.evaluate(() => {
      const shell = (id) => document.querySelector(`#${id} .yk-ui-shell`);
      return {
        first: getComputedStyle(shell('shell-root')).backgroundColor,
        second: getComputedStyle(shell('shell-second')).backgroundColor,
        firstText: getComputedStyle(document.querySelector('#shell-root .yk-ui-text')).color,
        secondText: getComputedStyle(document.querySelector('#shell-second .yk-ui-text')).color,
      };
    });
    assert.equal(colors.first, cssRgb(contract.themes.light.background));
    assert.equal(colors.second, cssRgb(contract.themes.dark.background));
    assert.equal(colors.firstText, cssRgb(contract.themes.light.text));
    assert.equal(colors.secondText, cssRgb(contract.themes.dark.text));
    assert.equal(await page.evaluate(() => api.setShellTheme('shell-root', 'dark')), 'updated');
    assert.equal(
      await page.evaluate(
        () => getComputedStyle(document.querySelector('#shell-root .yk-ui-shell')).backgroundColor,
      ),
      cssRgb(contract.themes.dark.background),
    );
    assert.equal(await page.evaluate(() => api.disposeShell('shell-root')), undefined);
    assert.equal(
      await page.evaluate(() => document.querySelector('#shell-root .yk-ui-shell')),
      null,
    );
    assert.equal(await page.evaluate(() => api.shellValue('shell-root')), -1);
  });
});
