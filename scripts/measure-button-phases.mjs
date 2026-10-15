#!/usr/bin/env node
// Owned headless-browser measurement only: no desktop input/capture or profile.
import { spawn, execFileSync } from 'node:child_process';
import { createHash, randomUUID } from 'node:crypto';
import { existsSync, mkdirSync, readFileSync, readdirSync, readlinkSync, realpathSync, writeFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import os from 'node:os';
import { createServer } from 'vite';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const output = process.argv[2];
if (!output || process.argv.length !== 3) throw new Error('Usage: node scripts/measure-button-phases.mjs NEW_OUTPUT');
const out = resolve(output);
if (existsSync(out)) throw new Error('Output exists; preserve prior evidence');
mkdirSync(out, { recursive: true });
const chromePath = process.env.KUMO_HEADLESS_CHROME ?? '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome';
const hash = (path) => createHash('sha256').update(readFileSync(path)).digest('hex');
const git = (...args) => execFileSync('git', args, { cwd: root, encoding: 'utf8' }).trim();
const token = randomUUID();
const report = { schema_version: 1, kind: 'owned-headless-kumo-button-phases', status: 'unverified',
  qualification: 'Real pinned Kumo in the owned headless browser; no native OS input, native rendering or cross-platform conformance claim',
  run_token: token, platform: { os: process.platform, architecture: process.arch, release: os.release() },
  source_revision: git('rev-parse', 'HEAD'), source_dirty: Boolean(git('status', '--porcelain', '--untracked-files=no')),
  started_at: new Date().toISOString(), node: process.version, cases: [], cdp: [] };
let server, chrome, ws, ownedGroup;
let browserOut = '', browserErr = '', aborting = false;
function retain() {
  if (report.browser) {
    report.browser.returncode = chrome?.exitCode ?? null;
    report.browser.signal = chrome?.signalCode ?? null;
    report.browser.cleanup_complete = !ownedGroup || chrome?.exitCode !== null || Boolean(chrome?.signalCode);
    writeFileSync(resolve(out, 'browser.stdout'), browserOut);
    writeFileSync(resolve(out, 'browser.stderr'), browserErr);
    report.browser.stdout_sha256 = hash(resolve(out, 'browser.stdout'));
    report.browser.stderr_sha256 = hash(resolve(out, 'browser.stderr'));
  }
  report.finished_at = new Date().toISOString();
  writeFileSync(resolve(out, 'report.json'), JSON.stringify(report, null, 2) + '\n');
}
function signalOwned(signal) {
  if (!Number.isInteger(ownedGroup) || ownedGroup <= 0 || ownedGroup !== chrome?.pid) return;
  if (chrome.exitCode !== null || chrome.signalCode) return;
  try { process.kill(-ownedGroup, signal); }
  catch (error) { if (error.code !== 'ESRCH') report.cleanup_error = String(error); }
}
function abort(reason) {
  if (aborting) return;
  aborting = true;
  report.status = 'unverified'; report.reason = reason;
  signalOwned('SIGTERM');
  // This watchdog also covers stalled startup, WebSocket opens, and finally.
  setTimeout(() => {
    if (chrome?.exitCode === null && !chrome?.signalCode) signalOwned('SIGKILL');
    try { retain(); } finally { process.exit(2); }
  }, 2000);
  try { retain(); } catch (error) { report.retention_error = String(error); }
}
const watchdog = setTimeout(() => abort('Overall owned-browser deadline expired'), 90000);
for (const signal of ['SIGINT', 'SIGTERM']) process.on(signal, () => abort(`Runner received ${signal}`));
process.on('uncaughtException', (error) => abort(`Uncaught runner error: ${error}`));
process.on('unhandledRejection', (error) => abort(`Unhandled runner rejection: ${error}`));
function dependencyInventory() {
  const base = realpathSync(resolve(root, 'node_modules'));
  const entries = [];
  function walk(path, prefix = '') {
    for (const item of readdirSync(path, { withFileTypes: true }).sort((a, b) => a.name.localeCompare(b.name))) {
      const name = prefix ? `${prefix}/${item.name}` : item.name;
      const full = resolve(path, item.name);
      if (item.isSymbolicLink()) {
        const target = realpathSync(full);
        if (target !== base && !target.startsWith(base + '/')) throw new Error(`Dependency route escapes installed runtime: ${name}`);
        entries.push({ path: name, type: 'symlink', target: readlinkSync(full) });
      } else if (item.isDirectory()) walk(full, name);
      else if (item.isFile()) entries.push({ path: name, type: 'file', sha256: hash(full) });
      else throw new Error(`Unsupported dependency entry: ${name}`);
    }
  }
  walk(base);
  return { root: base, entries };
}
const pending = new Map();
let nextId = 0;
const delay = (ms) => new Promise((accept) => setTimeout(accept, ms));
const deadline = Date.now() + 90000;
function checkDeadline() { if (aborting || Date.now() >= deadline) throw new Error('Owned browser deadline expired'); }
async function until(callback) {
  while (!aborting && Date.now() < deadline) { const value = await callback(); if (value) return value; await delay(25); }
  throw new Error('Owned browser did not become ready');
}
async function cdp(method, params = {}, sessionId) {
  checkDeadline();
  const id = ++nextId;
  return new Promise((accept, reject) => {
    const timer = setTimeout(() => { pending.delete(id); reject(new Error(`CDP timeout: ${method}`)); }, 5000);
    pending.set(id, { accept, reject, timer, method, params });
    ws.send(JSON.stringify({ id, method, params, ...(sessionId ? { sessionId } : {}) }));
  });
}
try {
  if (report.source_dirty) throw new Error('Measurement source must be committed and clean');
  const kumo = JSON.parse(readFileSync(resolve(root, 'node_modules/@cloudflare/kumo/package.json')));
  if (kumo.version !== '2.14.0') throw new Error('Expected pinned Kumo 2.14.0');
  report.dependencies = { kumo: kumo.version,
    react: JSON.parse(readFileSync(resolve(root, 'node_modules/react/package.json'))).version,
    react_dom: JSON.parse(readFileSync(resolve(root, 'node_modules/react-dom/package.json'))).version };
  if (report.dependencies.react !== '19.3.0' || report.dependencies.react_dom !== '19.3.0') throw new Error('Locked React versions differ');
  const inventory = dependencyInventory();
  const inventoryPath = resolve(out, 'dependency-inventory.json');
  writeFileSync(inventoryPath, JSON.stringify(inventory, null, 2) + '\n');
  report.dependency_inventory = { path: 'dependency-inventory.json', sha256: hash(inventoryPath), entries: inventory.entries.length };
  report.source_hashes = Object.fromEntries(['pnpm-lock.yaml', 'package.json', 'tests/button-phase/fixture.js',
    'tests/button-phase/index.html', 'scripts/measure-button-phases.mjs', 'node_modules/@cloudflare/kumo/package.json',
    'node_modules/@cloudflare/kumo/dist/components/button.js', 'node_modules/@cloudflare/kumo/dist/styles/kumo-standalone.css']
    .map((name) => [name, hash(resolve(root, name))]));
  server = await createServer({ configFile: false, root, cacheDir: resolve(root, '_build/button-phase-vite-cache'),
    server: { host: '127.0.0.1', port: 0 }, logLevel: 'error' });
  await server.listen();
  checkDeadline();
  const address = server.httpServer.address();
  if (typeof address !== 'object' || address.address !== '127.0.0.1') throw new Error('Fixture server must bind loopback');
  const profile = resolve(out, 'browser-profile');
  const argv = ['--headless=new', '--remote-debugging-port=0', '--remote-debugging-address=127.0.0.1',
    `--user-data-dir=${profile}`, '--no-first-run', '--no-default-browser-check', '--disable-extensions',
    '--disable-background-networking', 'about:blank'];
  const executableHash = hash(chromePath);
  chrome = spawn(chromePath, argv, { detached: true, stdio: ['ignore', 'pipe', 'pipe'] });
  ownedGroup = Number.isInteger(chrome.pid) && chrome.pid > 0 ? chrome.pid : null;
  report.browser = { executable: chromePath, executable_sha256: executableHash, command: [chromePath, ...argv],
    pid: chrome.pid, started_at: new Date().toISOString() };
  chrome.stdout.on('data', (data) => { browserOut += data; });
  chrome.stderr.on('data', (data) => { browserErr += data; });
  chrome.on('error', (error) => { ownedGroup = null; report.browser.spawn_error = String(error); abort('Owned browser spawn failed'); });
  chrome.on('exit', () => { report.browser.finished_at = new Date().toISOString(); });
  const portFile = resolve(profile, 'DevToolsActivePort');
  const portLines = await until(() => {
    if (chrome.exitCode !== null || chrome.signalCode) throw new Error('Owned browser exited before debugging ready');
    return existsSync(portFile) && readFileSync(portFile, 'utf8').trim().split('\n');
  });
  if (!/^\d+$/.test(portLines[0]) || !portLines[1]?.startsWith('/devtools/browser/')) throw new Error('Invalid owned debugger endpoint');
  ws = new WebSocket(`ws://127.0.0.1:${portLines[0]}${portLines[1]}`);
  await new Promise((accept, reject) => { ws.onopen = accept; ws.onerror = reject; });
  checkDeadline();
  ws.onmessage = ({ data }) => {
    try {
      const message = JSON.parse(data);
      if (!message || typeof message !== 'object' || Array.isArray(message)) throw new Error('Debugger message must be an object');
      const request = pending.get(message.id);
      if (!request) return;
      pending.delete(message.id); clearTimeout(request.timer);
      report.cdp.push({ id: message.id, method: request.method, params: request.params,
        result: message.result ?? null, error: message.error ?? null, received_at: new Date().toISOString() });
      if (message.error) request.reject(new Error(JSON.stringify(message.error))); else request.accept(message.result);
    } catch (error) { abort(`Malformed owned debugger message: ${error}`); }
  };
  report.browser.version = await cdp('Browser.getVersion');
  const key = (name, up = false, repeat = false) => ({ type: up ? 'keyUp' : 'keyDown',
    key: name === 'Space' ? ' ' : name, code: name,
    windowsVirtualKeyCode: { Enter: 13, Space: 32, Tab: 9 }[name],
    nativeVirtualKeyCode: { Enter: 36, Space: 49, Tab: 48 }[name],
    ...(!up && name !== 'Tab' ? { text: name === 'Enter' ? '\r' : ' ', unmodifiedText: name === 'Enter' ? '\r' : ' ' } : {}),
    autoRepeat: repeat, modifiers: 0 });
  const specifications = [
    ['pointer-repaint', false, ['pointer-down', 'repaint', 'pointer-up']],
    ['enter-first', false, ['focus-tab', 'enter-down', 'repaint', 'enter-up']],
    ['enter-repeat', false, ['focus-tab', 'enter-down', 'enter-repeat', 'repaint', 'enter-up']],
    ['space-repeat', false, ['focus-tab', 'space-down', 'space-repeat', 'repaint', 'space-up']],
    ['space-blur', false, ['focus-tab', 'space-down', 'focus-tab', 'space-up']],
    ['pointer-outside', false, ['pointer-down', 'pointer-up-outside']],
    ['disabled-pointer-key', true, ['pointer-down', 'pointer-up', 'focus-tab', 'enter-down', 'enter-up']],
  ];
  for (const [id, disabled, phases] of specifications) {
    const url = `http://127.0.0.1:${address.port}/tests/button-phase/index.html?run_token=${token}&disabled=${disabled ? 1 : 0}`;
    const { targetId } = await cdp('Target.createTarget', { url });
    const { sessionId } = await cdp('Target.attachToTarget', { targetId, flatten: true });
    const evaluate = async (expression) => {
      const value = await cdp('Runtime.evaluate', { expression, returnByValue: true, awaitPromise: true }, sessionId);
      if (value.exceptionDetails) throw new Error(JSON.stringify(value.exceptionDetails));
      return value.result.value;
    };
    await until(async () => evaluate('Boolean(window.phaseFixture?.snapshot())'));
    const snapshots = [];
    const snapshot = async (phase) => {
      await evaluate('new Promise(resolve => requestAnimationFrame(() => requestAnimationFrame(resolve)))');
      const state = await evaluate('window.phaseFixture.snapshot()');
      if (state.run_token !== token || state.component !== 'Button') throw new Error('Fixture challenge/component differs');
      snapshots.push({ phase, state });
      return state;
    };
    const initial = await snapshot('initial');
    const [x, y, width, height] = initial.bounds;
    for (const phase of phases) {
      if (phase === 'repaint') await evaluate('window.phaseFixture.repaint()');
      else if (phase === 'focus-tab') {
        await cdp('Input.dispatchKeyEvent', key('Tab'), sessionId);
        await cdp('Input.dispatchKeyEvent', key('Tab', true), sessionId);
      } else if (phase.startsWith('pointer-')) {
        const outside = phase === 'pointer-up-outside';
        await cdp('Input.dispatchMouseEvent', { type: phase === 'pointer-down' ? 'mousePressed' : 'mouseReleased',
          x: outside ? x + width + 100 : x + width / 2, y: outside ? y + height + 100 : y + height / 2,
          button: 'left', buttons: phase === 'pointer-down' ? 1 : 0, clickCount: 1 }, sessionId);
      } else {
        const [name, action] = phase.split('-');
        await cdp('Input.dispatchKeyEvent', key(name === 'enter' ? 'Enter' : 'Space', action === 'up', action === 'repeat'), sessionId);
      }
      await snapshot(phase);
    }
    report.cases.push({ id, target_id: targetId, session_id: sessionId, url, disabled, snapshots, status: 'observed' });
    await cdp('Target.closeTarget', { targetId });
  }
  if (git('rev-parse', 'HEAD') !== report.source_revision || git('status', '--porcelain', '--untracked-files=no')) throw new Error('Measurement source changed');
  if (JSON.stringify(dependencyInventory()) !== JSON.stringify(inventory)) throw new Error('Installed runtime changed during measurement');
  report.status = 'observed';
  await cdp('Browser.close');
  ws.close();
  await until(() => chrome.exitCode !== null || chrome.signalCode);
  report.browser.returncode = chrome.exitCode;
  report.browser.signal = chrome.signalCode;
  report.browser.finished_at = new Date().toISOString();
  if (chrome.exitCode !== 0 || chrome.signalCode) throw new Error('Owned browser did not exit normally');
} catch (error) {
  report.status = 'unverified'; report.reason = String(error);
} finally {
  if (ws && ws.readyState < 2) ws.close();
  if (ownedGroup && chrome.exitCode === null && !chrome.signalCode) {
    signalOwned('SIGTERM');
    await Promise.race([new Promise((accept) => chrome.once('exit', accept)), delay(2000)]);
    if (chrome.exitCode === null && !chrome.signalCode) {
      signalOwned('SIGKILL');
      await Promise.race([new Promise((accept) => chrome.once('exit', accept)), delay(2000)]);
    }
  }
  try {
    if (server) await Promise.race([server.close(), delay(2000).then(() => { report.status = 'unverified'; report.reason = 'Owned server cleanup timed out'; })]);
  } catch (error) { report.status = 'unverified'; report.reason = `Owned server cleanup failed: ${error}`; }
  try { retain(); } catch (error) { report.status = 'unverified'; report.retention_error = String(error); }
  clearTimeout(watchdog);
}
console.log(JSON.stringify({ status: report.status, cases: report.cases.length, reason: report.reason ?? null }));
process.exit(report.status === 'observed' ? 0 : 2);
