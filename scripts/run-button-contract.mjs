#!/usr/bin/env node
import { execFileSync, spawnSync } from 'node:child_process';
import { mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import os from 'node:os';
import { createServer } from 'vite';
import { chromium } from 'playwright';
import { compareCase, compareStyles, loadFixtures, sha256 } from './button_contract.mjs';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const output = process.argv[2];
if (!output || process.argv.length !== 3)
  throw new Error('Usage: node scripts/run-button-contract.mjs NEW_OUTPUT');
const out = resolve(output);
mkdirSync(out, { recursive: false });
const suitePath = resolve(root, 'tests/button-contract/fixtures.json');
const suite = loadFixtures(suitePath);
const sourceFiles = execFileSync(
  'git',
  ['ls-files', '-z', '--cached', '--others', '--exclude-standard'],
  { cwd: root, encoding: 'utf8' },
)
  .split('\0')
  .filter(Boolean)
  .sort();
const sourceHashes = () =>
  Object.fromEntries(sourceFiles.map((name) => [name, sha256(readFileSync(resolve(root, name)))]));
const report = {
  version: 1,
  status: 'running',
  source_revision: execFileSync('git', ['rev-parse', 'HEAD'], {
    cwd: root,
    encoding: 'utf8',
  }).trim(),
  source_dirty: Boolean(
    execFileSync('git', ['status', '--porcelain'], { cwd: root, encoding: 'utf8' }).trim(),
  ),
  fixture_sha256: sha256(readFileSync(suitePath)),
  source_hashes: sourceHashes(),
  environment: {
    platform: process.platform,
    architecture: process.arch,
    release: os.release(),
    node: process.version,
  },
  started_at: new Date().toISOString(),
  layers: {
    web: 'running',
    native_consumer_scene: 'running',
    native_host_input: 'not-run',
    native_gpu: 'not-run',
    physical_hardware: 'not-run',
    native_accessibility: 'not-run',
  },
  cases: [],
};
const save = () =>
  writeFileSync(resolve(out, 'report.json'), JSON.stringify(report, null, 2) + '\n');
save();
let server, browser;
try {
  const target = resolve(out, 'native-build');
  const command = [
    'scripts/native_ui_workspace.sh',
    'moon',
    'build',
    resolve(root, 'native/examples/button_contract'),
    '--target',
    'native',
    '--deny-warn',
    '--target-dir',
    target,
  ];
  const build = spawnSync('sh', command, { cwd: root, encoding: 'utf8', timeout: 120000 });
  writeFileSync(resolve(out, 'native-build.log'), (build.stdout ?? '') + (build.stderr ?? ''));
  if (build.error || build.status !== 0)
    throw new Error(`Native consumer build failed: ${build.error ?? build.status}`);
  const executable = resolve(
    target,
    'native/debug/build/f4ah6o/yami_kumo_native/examples/button_contract/button_contract.exe',
  );
  report.native_executable_sha256 = sha256(readFileSync(executable));
  report.environment.moon = execFileSync('moon', ['version', '--all'], { encoding: 'utf8' }).trim();
  report.environment.gpui_revision = execFileSync('git', ['rev-parse', 'HEAD'], {
    cwd: process.env.GPUI_SOURCE ?? resolve(root, '../gpui.mbt'),
    encoding: 'utf8',
  }).trim();
  const expectedGPUI = readFileSync(
    resolve(root, 'tests/native-ui/gpui-revision.txt'),
    'utf8',
  ).trim();
  if (report.environment.gpui_revision !== expectedGPUI)
    throw new Error('GPUI source differs from the pinned revision');
  let hostReport;
  if (process.env.YAMI_BUTTON_NATIVE_HOST_REPORT) {
    hostReport = JSON.parse(readFileSync(process.env.YAMI_BUTTON_NATIVE_HOST_REPORT, 'utf8'));
    if (
      hostReport.fixture_sha256 !== report.fixture_sha256 ||
      hostReport.source_revision !== report.source_revision ||
      hostReport.status === 'failed'
    )
      throw new Error('Native host evidence is stale, failed or for another fixture');
    if (
      JSON.stringify(hostReport.source_hashes) !== JSON.stringify(report.source_hashes) ||
      hostReport.gpui_revision !== expectedGPUI ||
      hostReport.source_dirty !== report.source_dirty
    )
      throw new Error('Native host source files or pinned GPUI differ from the comparison source');
    report.native_host = hostReport;
  }
  server = await createServer({
    configFile: false,
    root,
    server: { host: '127.0.0.1', port: 0, strictPort: false },
  });
  await server.listen();
  browser = await chromium.launch({ headless: true });
  report.environment.browser = browser.version();
  for (const specification of suite.cases) {
    const record = {
      id: specification.id,
      specification,
      web: { status: 'running', phases: [] },
      native: { status: 'running' },
    };
    report.cases.push(record);
    save();
    const native = spawnSync(executable, [], {
      env: { ...process.env, YAMI_BUTTON_CASE: JSON.stringify(specification) },
      encoding: 'utf8',
      timeout: 15000,
      maxBuffer: 16 * 1024 * 1024,
    });
    writeFileSync(resolve(out, `${specification.id}.native.stdout`), native.stdout ?? '');
    writeFileSync(resolve(out, `${specification.id}.native.stderr`), native.stderr ?? '');
    if (native.error || native.status !== 0)
      throw new Error(
        `Native fixture failed: ${specification.id}: ${native.error ?? native.status}`,
      );
    record.native = JSON.parse(native.stdout);
    const context = await browser.newContext({
      viewport: { width: 800, height: 600 },
      reducedMotion: 'reduce',
    });
    const page = await context.newPage();
    const errors = [];
    page.on('pageerror', (error) => errors.push(String(error)));
    await page.goto(
      `http://127.0.0.1:${server.httpServer.address().port}/tests/button-phase/index.html?run_token=${report.fixture_sha256}&disabled=${specification.disabled ? 1 : 0}&loading=${specification.loading ? 1 : 0}`,
    );
    await page.waitForFunction(() => Boolean(window.phaseFixture?.snapshot()));
    let previousCount = 0,
      previousEvents = 0;
    const snapshot = async (phase, index) => {
      await page.evaluate(
        () => new Promise((accept) => requestAnimationFrame(() => requestAnimationFrame(accept))),
      );
      const state = await page.evaluate(() => window.phaseFixture.snapshot());
      if (state.run_token !== report.fixture_sha256 || state.component !== 'Button')
        throw new Error('Wrong browser fixture identity');
      const value = {
        index,
        phase,
        activation_count: state.action_count,
        activation_delta: state.action_count - previousCount,
        focused: state.focused,
        pressed: state.pressed,
        hovered: state.hovered,
        disabled: state.disabled,
        loading: state.loading,
        computed: state.computed,
        focus_visible: state.focus_visible,
        events: state.events.slice(previousEvents),
        raw: state,
      };
      previousCount = state.action_count;
      previousEvents = state.events.length;
      record.web.phases.push(value);
      if (state.events.some((event) => event.is_trusted !== true))
        throw new Error('Untrusted browser input in the observed trace');
      if (
        phase.endsWith('-repeat') &&
        !value.events.some((event) => event.type === 'keydown' && event.repeat === true)
      )
        throw new Error('Browser did not deliver the requested repeat phase');
      await page.screenshot({ path: resolve(out, `${specification.id}.${index}.png`) });
      const [x, y, width, height] = state.bounds;
      const roi = {
        x: x - 4,
        y: y - 4,
        width: Math.ceil(width) + 8,
        height: Math.ceil(height) + 8,
      };
      const roiPath = `${specification.id}.${index}.button.png`;
      const png = await page.screenshot({ path: resolve(out, roiPath), clip: roi });
      value.button_raster = { path: roiPath, roi, png_sha256: sha256(png) };
    };
    await snapshot('initial', 0);
    for (const [index, phase] of specification.steps.entries()) {
      const bounds = await page.locator('#target').boundingBox();
      if (phase === 'pointer-hover' || phase === 'pointer-away') {
        await page.mouse.move(
          phase === 'pointer-hover' ? bounds.x + bounds.width / 2 : 790,
          phase === 'pointer-hover' ? bounds.y + bounds.height / 2 : 590,
        );
      } else if (phase === 'keyboard-focus') await page.keyboard.press('ArrowLeft');
      else if (phase === 'pointer-down') {
        await page.mouse.move(bounds.x + bounds.width / 2, bounds.y + bounds.height / 2);
        await page.mouse.down();
      } else if (phase === 'pointer-up' || phase === 'pointer-up-outside') {
        await page.mouse.move(
          phase === 'pointer-up' ? bounds.x + bounds.width / 2 : 790,
          phase === 'pointer-up' ? bounds.y + bounds.height / 2 : 590,
        );
        await page.mouse.up();
      } else if (phase === 'repaint') await page.evaluate(() => window.phaseFixture.repaint());
      else if (phase === 'focus-loss') await page.locator('#outside').focus();
      else {
        const [name, action] = phase.split('-');
        const key = name === 'enter' ? 'Enter' : 'Space';
        if (action === 'up') await page.keyboard.up(key);
        else await page.keyboard.down(key);
      }
      await snapshot(phase, index + 1);
    }
    if (errors.length) throw new Error(errors.join('\n'));
    record.web.status = 'observed';
    record.comparison = compareCase(specification, record.web, record.native);
    record.pressed_style = compareStyles(record.web, record.native);
    if (hostReport) {
      const hostCase = hostReport.cases.find((item) => item.id === specification.id);
      if (!hostCase || (specification.host && hostCase.status !== 'observed'))
        throw new Error(`Required Native host case missing: ${specification.id}`);
      record.host_comparison = compareCase(specification, record.web, hostCase);
      record.host_pressed_style = compareStyles(record.web, hostCase);
    }
    await context.close();
    save();
  }
  report.layers.web = 'observed';
  if (JSON.stringify(sourceHashes()) !== JSON.stringify(report.source_hashes))
    throw new Error('Source files changed during fixture observation');
  report.layers.native_consumer_scene = 'observed';
  if (hostReport) {
    report.layers.native_host_input = 'partial';
    report.layers.native_gpu = 'partial';
  }
  const semanticFields = new Set([
    'activation_count',
    'activation_delta',
    'focused',
    'disabled',
    'loading',
    'activation_event_phase',
    'focus_visible',
    'hovered',
  ]);
  const regressions = report.cases
    .flatMap((item) => [item.comparison, item.host_comparison].filter(Boolean))
    .flatMap((item) => item.differences)
    .filter((item) => semanticFields.has(item.field));
  report.supported_semantics = regressions.length ? 'failed' : 'passed';
  if (regressions.length)
    throw new Error(`Supported Button semantics differ: ${JSON.stringify(regressions)}`);
  const visualRegressions = report.cases.filter(
    (item) =>
      item.pressed_style.status === 'gap-detected' ||
      item.host_pressed_style?.status === 'gap-detected',
  );
  report.supported_feedback = visualRegressions.length ? 'failed' : 'passed';
  if (visualRegressions.length)
    throw new Error(
      `Supported Button visual feedback differs: ${visualRegressions.map((item) => item.id).join(', ')}`,
    );
  report.status =
    report.cases.some(
      (item) =>
        item.comparison.status !== 'matched' ||
        item.pressed_style.status === 'gap-detected' ||
        (item.host_comparison && item.host_comparison.status !== 'matched') ||
        item.host_pressed_style?.status === 'gap-detected',
    ) ||
    report.layers.native_host_input !== 'observed' ||
    report.layers.native_gpu !== 'observed'
      ? 'partial'
      : 'matched';
  if (process.env.YAMI_BUTTON_REQUIRE_COMPLETE === '1' && report.status !== 'matched')
    process.exitCode = 2;
} catch (error) {
  report.status = 'failed';
  report.error = String(error);
  process.exitCode = 1;
} finally {
  await browser?.close();
  await server?.close();
  report.finished_at = new Date().toISOString();
  save();
}
console.log(
  JSON.stringify({
    status: report.status,
    cases: report.cases.map(({ id, comparison, pressed_style }) => ({
      id,
      comparison: comparison?.status,
      differences: comparison?.differences,
      pressed_style: pressed_style?.status,
    })),
  }),
);
