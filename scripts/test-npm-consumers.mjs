import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { mkdtemp, cp, readFile, writeFile, mkdir, access, realpath, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { createServer } from 'node:http';
import { chromium } from 'playwright';

const root = fileURLToPath(new URL('../', import.meta.url));
await rm(path.join(root, 'dist/npm-consumers.json'), { force: true });
const workspace = await mkdtemp(path.join(tmpdir(), 'yami-kumo-consumers-'));
assert.ok(!workspace.startsWith(root));
const env = { ...process.env, NODE_PATH: '', npm_config_audit: 'false', npm_config_fund: 'false' };
function run(command, args, cwd = root) {
  const result = spawnSync(command, args, {
    cwd,
    env,
    encoding: 'utf8',
    shell: process.platform === 'win32',
  });
  if (result.status !== 0)
    throw new Error(
      `${command} ${args.join(' ')} in ${cwd}\n${result.stdout}\n${result.stderr || result.error}`,
    );
  return result.stdout.trim();
}
run('node', ['scripts/build-npm.mjs']);
const dry = JSON.parse(run('npm', ['pack', '--dry-run', '--json'], path.join(root, 'dist/npm')))[0];
const packed = JSON.parse(
  run(
    'npm',
    ['pack', '--json', '--pack-destination', path.join(root, 'dist')],
    path.join(root, 'dist/npm'),
  ),
)[0];
const tarball = path.join(root, 'dist', packed.filename);
assert.deepEqual(
  packed.files.map((f) => f.path),
  dry.files.map((f) => f.path),
);
const expected = [
  'ACKNOWLEDGEMENTS.md',
  'BUILD.json',
  'LICENSE',
  'README.md',
  'dom.d.ts',
  'dom.js',
  'index.d.ts',
  'index.js',
  'moonbit.js',
  'package.json',
  'react.d.ts',
  'react.js',
  'styles.css',
  'licenses/cloudflare-kumo-LICENSE',
  'licenses/moonbit-core-LICENSE',
  'licenses/moonbit-core-NOTICE',
  'licenses/tailwindcss-LICENSE',
];
assert.deepEqual(packed.files.map((f) => f.path).sort(), expected.sort());
const manifest = JSON.parse(await readFile(path.join(root, 'dist/npm/package.json'), 'utf8'));
assert.equal(manifest.scripts, undefined);
assert.equal(manifest.dependencies, undefined);
assert.equal(JSON.parse(await readFile(path.join(root, 'package.json'), 'utf8')).private, true);
const bin = path.join(workspace, 'bin');
await mkdir(bin);
await writeFile(
  path.join(bin, 'moon'),
  '#!/bin/sh\necho unexpected-compiler-invocation > "' +
    path.join(workspace, 'compiler-called') +
    '"\nexit 1\n',
  { mode: 0o755 },
);
env.PATH = bin + path.delimiter + env.PATH;
const dirs = {};
for (const name of ['javascript', 'typescript', 'browser', 'react']) {
  const dir = path.join(workspace, name);
  dirs[name] = dir;
  await cp(path.join(root, 'tests/npm', name), dir, { recursive: true });
  run('npm', ['install', '--save-exact', tarball], dir);
  assert.equal(
    await realpath(path.join(dir, 'node_modules/@f4ah6o/yami-kumo')),
    path.join(dir, 'node_modules/@f4ah6o/yami-kumo'),
  );
  run('npm', ['ls', '--all'], dir);
  console.log(`PASS install/dependency graph: ${name}`);
}
console.log(run('node', ['test.mjs'], dirs.javascript));
for (const resolution of ['NodeNext', 'Bundler']) {
  run(
    'node',
    [
      'node_modules/typescript/bin/tsc',
      '--noEmit',
      '--strict',
      '--skipLibCheck',
      'false',
      '--target',
      'ES2022',
      '--module',
      resolution === 'Bundler' ? 'ESNext' : 'NodeNext',
      '--moduleResolution',
      resolution,
      'test.ts',
    ],
    dirs.typescript,
  );
}
console.log(
  'PASS TypeScript: installed declarations, invalid props, NodeNext and Bundler without React types',
);
run(
  'node',
  [
    'node_modules/typescript/bin/tsc',
    '--noEmit',
    '--strict',
    '--skipLibCheck',
    'false',
    '--target',
    'ES2022',
    '--module',
    'NodeNext',
    '--moduleResolution',
    'NodeNext',
    '--jsx',
    'react-jsx',
    'main.tsx',
  ],
  dirs.react,
);
console.log(run('node', ['ssr.mjs'], dirs.react));
for (const name of ['browser', 'react'])
  run('node', ['node_modules/vite/bin/vite.js', 'build'], dirs[name]);
const browser = await chromium.launch({
  headless: true,
  executablePath: process.env.PLAYWRIGHT_CHROMIUM_EXECUTABLE_PATH || undefined,
});
const observations = [];
try {
  for (const name of ['browser', 'react']) {
    const base = path.join(dirs[name], 'dist');
    const server = createServer(async (req, res) => {
      try {
        const url = new URL(req.url, 'http://localhost');
        const target = path.join(base, url.pathname === '/' ? 'index.html' : url.pathname);
        if (!target.startsWith(base + path.sep)) {
          res.writeHead(403).end();
          return;
        }
        const ext = path.extname(target);
        res.setHeader(
          'Content-Type',
          { '.html': 'text/html', '.js': 'text/javascript', '.css': 'text/css' }[ext] ||
            'application/octet-stream',
        );
        res.setHeader(
          'Content-Security-Policy',
          "default-src 'self'; script-src 'self'; style-src 'self'; img-src 'self'; font-src 'self'; object-src 'none'; base-uri 'none'",
        );
        res.end(await readFile(target));
      } catch {
        res.writeHead(404).end();
      }
    });
    await new Promise((resolve) => server.listen(0, '127.0.0.1', resolve));
    const page = await browser.newPage({ viewport: { width: 1440, height: 1000 } });
    const errors = [];
    page.on('pageerror', (error) => errors.push(String(error)));
    page.on('console', (message) => {
      if (message.type() === 'error' && !message.text().includes('404'))
        errors.push(message.text());
    });
    try {
      await page.goto(`http://127.0.0.1:${server.address().port}/`);
      await page.waitForSelector('.yk-shell');
      assert.equal(
        await page.locator('.yk-shell').evaluate((el) => getComputedStyle(el).display),
        'grid',
      );
      if (name === 'browser') {
        const host = await page.evaluate(() => ({
          bodyMargin: getComputedStyle(document.body).margin,
          background: getComputedStyle(document.body).backgroundColor,
          width: getComputedStyle(document.querySelector('#root')).width,
          padding: getComputedStyle(document.querySelector('#root')).padding,
          paragraphMargin: getComputedStyle(document.querySelector('#host-content')).marginTop,
        }));
        assert.deepEqual(host, {
          bodyMargin: '23px',
          background: 'rgb(12, 34, 56)',
          width: '211px',
          padding: '7px',
          paragraphMargin: '16px',
        });
        observations.push({ host });
        const email = page.locator('#email');
        await email.focus();
        assert.equal(await email.evaluate((el) => el.hasAttribute('data-focused')), true);
        await email.fill('invalid');
        assert.equal(
          await email.evaluate(
            (el) => el.hasAttribute('data-dirty') && el.hasAttribute('data-filled'),
          ),
          true,
        );
        await email.press('Enter');
        assert.equal(
          await email.evaluate(
            (el) =>
              el.hasAttribute('data-invalid') &&
              el.getAttribute('aria-invalid') === 'true' &&
              el.hasAttribute('data-touched'),
          ),
          true,
        );
        await email.fill('user@example.com');
        assert.equal(
          await email.evaluate(
            (el) => el.hasAttribute('data-valid') && !el.hasAttribute('aria-invalid'),
          ),
          true,
        );
        const other = page.locator('#other');
        assert.equal(await other.getAttribute('aria-invalid'), 'false');
        await other.focus();
        await page.waitForFunction(
          () => !document.querySelector('#email').hasAttribute('data-focused'),
        );
        assert.equal(await other.getAttribute('aria-describedby'), 'other-error');
        await other.fill('not-an-email');
        await other.press('Enter');
        assert.equal(await other.getAttribute('aria-invalid'), 'true');
        await other.fill('valid@example.com');
        assert.equal(await other.getAttribute('aria-invalid'), 'false');
        assert.equal(await other.getAttribute('data-valid'), '');
        await other.fill('not-an-email');
        await other.press('Enter');
        await other.evaluate((el) => el.setAttribute('aria-invalid', 'grammar'));
        await other.fill('valid-again@example.com');
        assert.equal(await other.getAttribute('aria-invalid'), 'grammar');
        const primary = page.locator('[data-variant="primary"]');
        await primary.focus();
        await page.keyboard.down('Enter');
        assert.equal(await page.locator('body').getAttribute('data-activations'), '1');
        await page.keyboard.up('Enter');
        await page.keyboard.down('Space');
        assert.equal(await page.locator('body').getAttribute('data-activations'), '1');
        await page.keyboard.up('Space');
        assert.equal(await page.locator('body').getAttribute('data-activations'), '2');
        assert.equal(await page.locator('#disabled').isDisabled(), true);
        assert.equal(await page.locator('[data-variant]').count(), 6);
        assert.equal(
          await page.locator('.yk-sidebar').evaluate((el) => el.getBoundingClientRect().width),
          240,
        );
        await page.setViewportSize({ width: 390, height: 844 });
        assert.equal(
          await page.locator('.yk-rail').evaluate((el) => getComputedStyle(el).display),
          'none',
        );
        await page.locator('#menu').click();
        assert.equal(
          await page.locator('.yk-sidebar').evaluate((el) => getComputedStyle(el).pointerEvents),
          'auto',
        );
        await page.locator('.yk-sidebar-scrim').click({ position: { x: 320, y: 200 } });
        assert.equal(
          await page.locator('.yk-shell').getAttribute('data-mobile-sidebar-open'),
          'false',
        );
      } else {
        await page.locator('#counter').click();
        assert.equal(await page.locator('#counter').textContent(), 'Count 1');
        await page.setViewportSize({ width: 390, height: 844 });
        await page.locator('.yk-context-panel-scrim').click({ position: { x: 2, y: 200 } });
        assert.equal(
          await page.locator('.yk-shell').getAttribute('data-context-panel-open'),
          'false',
        );
        await page.locator('#react-menu').click();
        assert.equal(
          await page.locator('.yk-shell').getAttribute('data-mobile-sidebar-open'),
          'true',
        );
        await page.locator('.yk-sidebar-scrim').click({ position: { x: 320, y: 200 } });
        assert.equal(
          await page.locator('.yk-shell').getAttribute('data-mobile-sidebar-open'),
          'false',
        );
      }
      assert.deepEqual(errors, []);
      console.log(
        `PASS ${name}: production browser build, external CSS, strict CSP, desktop/phone layout and interactions`,
      );
    } finally {
      await page.close();
      await new Promise((resolve) => server.close(resolve));
    }
  }
  await assert.rejects(access(path.join(workspace, 'compiler-called')));
  const result = {
    status: 'PASS',
    tarball: packed.filename,
    shasum: packed.shasum,
    integrity: packed.integrity,
    browser: browser.version(),
    consumers: Object.keys(dirs),
    observations,
  };
  await writeFile(
    path.join(root, 'dist/npm-consumers.json'),
    JSON.stringify(result, null, 2) + '\n',
  );
  console.log(
    `PASS packed artifact: ${packed.filename}; evidence dist/npm-consumers.json; consumers ${workspace}`,
  );
} finally {
  await browser.close();
}
