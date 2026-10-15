#!/usr/bin/env node
// Owned headless-browser measurement only: no desktop input/capture or profile.
import { spawn, execFileSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import { closeSync, existsSync, fsyncSync, mkdirSync, openSync, readFileSync, readdirSync, readlinkSync, realpathSync, statfsSync, writeFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import os from 'node:os';
import { createServer } from 'vite';
import { assessHeadroom, EvidenceStore, RawLogCapture } from './button_phase_evidence.mjs';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const output = process.argv[2];
if (!output || process.argv.length !== 3) throw new Error('Usage: node scripts/measure-button-phases.mjs NEW_OUTPUT');
const out = resolve(output);
const hash = (path) => createHash('sha256').update(readFileSync(path)).digest('hex');
const git = (...args) => execFileSync('git', args, { cwd: root, encoding: 'utf8' }).trim();
const supervisorPid = Number(process.env.KUMO_PHASE_SUPERVISOR_PID);
const token = process.env.KUMO_PHASE_RUN_TOKEN;
const expectedOutput = process.env.KUMO_PHASE_MEASUREMENT_DIR ? resolve(process.env.KUMO_PHASE_MEASUREMENT_DIR) : null;
if (!Number.isSafeInteger(supervisorPid) || supervisorPid <= 1 || process.ppid !== supervisorPid) {
  throw new Error('This runner requires its approved Python supervisor as its direct parent');
}
if (!/^[0-9a-f-]{36}$/i.test(token ?? '') || !expectedOutput || expectedOutput !== out) {
  throw new Error('Supervisor run identity or measurement path is missing or mismatched');
}
const processGroup = Number(execFileSync('ps', ['-o', 'pgid=', '-p', String(process.pid)], { encoding: 'utf8' }).trim());
if (processGroup !== process.pid) throw new Error('Node must be the leader of its fresh supervisor process group');
if (existsSync(out)) throw new Error('Output exists; preserve prior evidence');
mkdirSync(out, { recursive: true, mode: 0o700 });
const chromePath = process.env.KUMO_HEADLESS_CHROME ?? (process.platform === 'darwin'
  ? '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome'
  : ['/usr/bin/google-chrome-stable', '/usr/bin/google-chrome', '/usr/bin/chromium', '/usr/bin/chromium-browser'].find(existsSync));
const sourceHashes = Object.fromEntries([
  'pnpm-lock.yaml', 'package.json', 'tests/button-phase/fixture.js', 'tests/button-phase/index.html',
  'scripts/measure-button-phases.mjs', 'scripts/button_phase_evidence.mjs', 'scripts/measure_button_phases.py',
].map((name) => [name, hash(resolve(root, name))]));
const report = { schema_version: 1, kind: 'owned-headless-kumo-button-phases', status: 'unverified',
  qualification: 'Real pinned Kumo in the owned headless browser; no native OS input, native rendering or cross-platform conformance claim',
  run_token: token, supervisor_pid: supervisorPid, node_pid: process.pid, process_group: processGroup,
  platform: { os: process.platform, architecture: process.arch, release: os.release() },
  source_revision: git('rev-parse', 'HEAD'), source_dirty: Boolean(git('status', '--porcelain')),
  source_hashes: sourceHashes, started_at: new Date().toISOString(), node: process.version, cases: [], cdp: [],
  launch_intent: { status: 'unverified', output: out, supervisor_pid: supervisorPid, node_pid: process.pid,
    process_group: processGroup, run_token: token, created_at: new Date().toISOString() } };
let store;
try {
  store = new EvidenceStore(out, report);
} catch (error) {
  console.log(JSON.stringify({ status: 'unverified', cases: 0, reason: 'Evidence reservation failed',
    retention_error: { code: error?.code ?? 'ERR_RETENTION', stage: 'reserve_evidence_files', run_token: token } }));
  process.exit(2);
}
const browserOut = new RawLogCapture();
const browserErr = new RawLogCapture();
let server, chrome, ws, chromeClosePromise, aborting = false, retentionError = null, abortTimer;
let rejectAbort;
const abortPromise = new Promise((_, reject) => { rejectAbort = reject; });
abortPromise.catch(() => {});
const withAbort = (promise) => Promise.race([promise, abortPromise]);
function retentionFailure(error, stage) {
  retentionError = { code: error?.code ?? 'ERR_RETENTION', stage, run_token: token };
  report.retention_error = retentionError;
}
function checkpoint(progress) {
  try { store.checkpoint(report, browserOut, browserErr, progress); }
  catch (error) { retentionFailure(error, 'checkpoint'); throw error; }
}
function signalChrome(signal) {
  const pid = chrome?.pid;
  if (!Number.isSafeInteger(pid) || pid <= 1 || chrome.exitCode !== null || chrome.signalCode) return;
  try { process.kill(pid, signal); }
  catch (error) { if (error.code !== 'ESRCH') report.cleanup_error = String(error); }
}
function abort(reason) {
  if (aborting) return;
  aborting = true;
  report.status = 'unverified'; report.reason = reason;
  try { checkpoint({ stage: 'abort', reason }); }
  catch (error) { retentionFailure(error, 'abort_checkpoint'); }
  signalChrome('SIGTERM');
  rejectAbort(new Error(reason));
  abortTimer = setTimeout(() => {
    signalChrome('SIGKILL');
    try { store.finalizeUnverified(report, browserOut, browserErr, { stage: 'forced-exit' }); }
    catch (error) { retentionFailure(error, 'forced_exit_retention'); }
    process.exit(2);
  }, 2000);
}
const watchdog = setTimeout(() => abort('Overall owned-browser deadline expired'), 90000);
for (const signal of ['SIGINT', 'SIGTERM']) process.on(signal, () => abort('Runner received ' + signal));
process.on('uncaughtException', (error) => abort('Uncaught runner error: ' + error));
process.on('unhandledRejection', (error) => abort('Unhandled runner rejection: ' + error));
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
  while (!aborting && Date.now() < deadline) {
    const value = await withAbort(Promise.resolve().then(callback));
    if (value) return value;
    await withAbort(delay(25));
  }
  throw new Error('Owned browser did not become ready');
}
async function cdp(method, params = {}, sessionId) {
  checkDeadline();
  const id = ++nextId;
  return withAbort(new Promise((accept, reject) => {
    const timer = setTimeout(() => { pending.delete(id); reject(new Error(`CDP timeout: ${method}`)); }, 5000);
    pending.set(id, { accept, reject, timer, method, params });
    ws.send(JSON.stringify({ id, method, params, ...(sessionId ? { sessionId } : {}) }));
  }));
}
try {
  const free = statfsSync(out);
  const availableBytes = free.bavail * free.bsize;
  report.preflight = { ...assessHeadroom(availableBytes), evidence_reserved: true, browser_started: false };
  checkpoint({ stage: 'launch-intent-reserved' });
  if (!report.preflight.sufficient) {
    throw Object.assign(new Error('Insufficient disk headroom for a fresh browser profile, Vite and full dependency inventory'), {
      code: 'INSUFFICIENT_HEADROOM',
    });
  }
  if (report.source_dirty) throw new Error('Measurement source must be committed and clean');
  if (!chromePath || !existsSync(chromePath)) throw new Error('No installed headless Chrome executable was found');
  const kumo = JSON.parse(readFileSync(resolve(root, 'node_modules/@cloudflare/kumo/package.json')));
  if (kumo.version !== '2.14.0') throw new Error('Expected pinned Kumo 2.14.0');
  report.dependencies = { kumo: kumo.version,
    react: JSON.parse(readFileSync(resolve(root, 'node_modules/react/package.json'))).version,
    react_dom: JSON.parse(readFileSync(resolve(root, 'node_modules/react-dom/package.json'))).version };
  if (report.dependencies.react !== '19.3.0' || report.dependencies.react_dom !== '19.3.0') throw new Error('Locked React versions differ');
  const inventory = dependencyInventory();
  const inventoryPath = resolve(out, 'dependency-inventory.json');
  const inventoryBytes = Buffer.from(JSON.stringify(inventory, null, 2) + '\n');
  writeFileSync(inventoryPath, inventoryBytes, { flag: 'wx', mode: 0o600 });
  const inventoryFd = openSync(inventoryPath, 'r+');
  try { fsyncSync(inventoryFd); } finally { closeSync(inventoryFd); }
  if (!readFileSync(inventoryPath).equals(inventoryBytes)) throw new Error('Dependency inventory readback differs');
  report.dependency_inventory = { path: 'dependency-inventory.json', sha256: hash(inventoryPath), entries: inventory.entries.length };
  report.source_hashes = { ...sourceHashes, ...Object.fromEntries(['node_modules/@cloudflare/kumo/package.json',
    'node_modules/@cloudflare/kumo/dist/components/button.js', 'node_modules/@cloudflare/kumo/dist/styles/kumo-standalone.css']
    .map((name) => [name, hash(resolve(root, name))])) };
  checkpoint({ stage: 'dependency-inventory-retained' });
  server = await withAbort(createServer({ configFile: false, root, cacheDir: resolve(root, '_build/button-phase-vite-cache'),
    server: { host: '127.0.0.1', port: 0 }, logLevel: 'error' }));
  await withAbort(server.listen());
  checkDeadline();
  const address = server.httpServer.address();
  if (typeof address !== 'object' || address.address !== '127.0.0.1') throw new Error('Fixture server must bind loopback');
  checkpoint({ stage: 'loopback-fixture-server-ready', port: address.port });
  const profile = resolve(out, 'browser-profile');
  if (existsSync(profile)) throw new Error('Fresh owned browser profile path already exists');
  const argv = ['--headless=new', '--remote-debugging-port=0', '--remote-debugging-address=127.0.0.1',
    `--user-data-dir=${profile}`, '--no-first-run', '--no-default-browser-check', '--disable-extensions',
    '--disable-background-networking', 'about:blank'];
  const executableHash = hash(chromePath);
  chrome = spawn(chromePath, argv, { detached: false, stdio: ['ignore', 'pipe', 'pipe'] });
  report.browser = { executable: chromePath, executable_sha256: executableHash, command: [chromePath, ...argv],
    pid: chrome.pid ?? null, command_token: token, process_group: processGroup,
    started_at: new Date().toISOString(), profile,
    debugger_endpoint: { host: '127.0.0.1', port: null, requested_port: 0,
      devtools_active_port_file: resolve(profile, 'DevToolsActivePort') } };
  report.preflight.browser_started = true;
  chrome.stdout.on('data', (data) => { if (browserOut.push(data)) abort('Owned browser stdout exceeded the 1 MiB raw-log limit'); });
  chrome.stderr.on('data', (data) => { if (browserErr.push(data)) abort('Owned browser stderr exceeded the 1 MiB raw-log limit'); });
  chrome.on('error', (error) => { report.browser.spawn_error = String(error); abort('Owned browser spawn failed'); });
  chrome.on('exit', () => { report.browser.finished_at = new Date().toISOString(); });
  chromeClosePromise = new Promise((accept) => chrome.once('close', (code, signal) => accept({ code, signal })));
  checkpoint({ stage: 'owned-browser-spawned', chrome_pid: chrome.pid ?? null,
    chrome_command: [chromePath, ...argv], profile, run_token: token,
    debugger_endpoint: report.browser.debugger_endpoint });
  const portFile = resolve(profile, 'DevToolsActivePort');
  const portLines = await until(() => {
    if (chrome.exitCode !== null || chrome.signalCode) throw new Error('Owned browser exited before debugging ready');
    return existsSync(portFile) && readFileSync(portFile, 'utf8').trim().split('\n');
  });
  if (!/^\d+$/.test(portLines[0]) || !portLines[1]?.startsWith('/devtools/browser/')) throw new Error('Invalid owned debugger endpoint');
  report.browser.debugger_endpoint = { host: '127.0.0.1', port: Number(portLines[0]), path: portLines[1],
    devtools_active_port_file: portFile };
  checkpoint({ stage: 'owned-debugger-ready', chrome_pid: chrome.pid,
    debugger_endpoint: report.browser.debugger_endpoint });
  ws = new WebSocket(`ws://127.0.0.1:${portLines[0]}${portLines[1]}`);
  await withAbort(new Promise((accept, reject) => { ws.onopen = accept; ws.onerror = reject; }));
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
    } catch (error) { abort('Malformed owned debugger message: ' + error); }
  };
  report.browser.version = await cdp('Browser.getVersion');
  checkpoint({ stage: 'browser-version-recorded' });
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
    const caseRecord = { id, target_id: targetId, session_id: sessionId, url, disabled, snapshots: [], status: 'in-progress' };
    report.cases.push(caseRecord);
    const snapshot = async (phase) => {
      await evaluate('new Promise(resolve => requestAnimationFrame(() => requestAnimationFrame(resolve)))');
      const state = await evaluate('window.phaseFixture.snapshot()');
      if (state.run_token !== token || state.component !== 'Button') throw new Error('Fixture challenge/component differs');
      caseRecord.snapshots.push({ phase, state });
      return state;
    };
    const initial = await snapshot('initial');
    checkpoint({ stage: 'phase-observed', case_id: id, phase: 'initial' });
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
      checkpoint({ stage: 'phase-observed', case_id: id, phase });
    }
    caseRecord.status = 'observed';
    checkpoint({ stage: 'case-complete', case_id: id });
    await cdp('Target.closeTarget', { targetId });
  }
  if (git('rev-parse', 'HEAD') !== report.source_revision || git('status', '--porcelain')) throw new Error('Measurement source changed');
  if (JSON.stringify(dependencyInventory()) !== JSON.stringify(inventory)) throw new Error('Installed runtime changed during measurement');
  await cdp('Browser.close');
  ws.close();
  await until(() => chrome.exitCode !== null || chrome.signalCode);
  const closed = await withAbort(chromeClosePromise);
  report.browser.returncode = chrome.exitCode;
  report.browser.signal = chrome.signalCode;
  report.browser.closed_returncode = closed.code;
  report.browser.closed_signal = closed.signal;
  report.browser.finished_at = new Date().toISOString();
  if (chrome.exitCode !== 0 || chrome.signalCode) throw new Error('Owned browser did not exit normally');
  checkpoint({ stage: 'browser-exited-normally', returncode: chrome.exitCode, signal: chrome.signalCode });
  report.measurement_complete = true;
} catch (error) {
  report.status = 'unverified'; report.reason = String(error);
} finally {
  if (ws && ws.readyState < 2) ws.close();
  if (Number.isSafeInteger(chrome?.pid) && chrome.pid > 1 && chrome.exitCode === null && !chrome.signalCode) {
    signalChrome('SIGTERM');
    await Promise.race([new Promise((accept) => chrome.once('exit', accept)), delay(2000)]);
    if (chrome.exitCode === null && !chrome.signalCode) {
      signalChrome('SIGKILL');
      await Promise.race([new Promise((accept) => chrome.once('exit', accept)), delay(2000)]);
    }
  }
  if (chromeClosePromise) await Promise.race([chromeClosePromise, delay(1000)]);
  try {
    if (server) await Promise.race([withAbort(server.close()), delay(2000).then(() => { throw new Error('Owned server cleanup timed out'); })]);
  } catch (error) { report.status = 'unverified'; report.reason = `Owned server cleanup failed: ${error}`; }
  if (report.browser) {
    report.browser.returncode = chrome?.exitCode ?? null;
    report.browser.signal = chrome?.signalCode ?? null;
    report.browser.finished_at ??= new Date().toISOString();
  }
  report.finished_at = new Date().toISOString();
  const complete = report.measurement_complete === true && report.cases.length === 7 &&
    report.cases.every((item) => item.status === 'observed') && report.browser?.returncode === 0 && !report.browser?.signal &&
    report.browser?.closed_returncode === 0 && !report.browser?.closed_signal &&
    !report.retention_error && !browserOut.truncated && !browserErr.truncated && !report.cleanup_error && !aborting;
  if (complete) {
    report.status = 'observed';
    try { store.finalizeObserved(report, browserOut, browserErr); }
    catch (error) { report.status = 'unverified'; report.reason = 'Final evidence retention failed'; retentionFailure(error, 'final_commit'); }
  } else {
    report.status = 'unverified';
    try { store.finalizeUnverified(report, browserOut, browserErr, { stage: 'run-finished' }); }
    catch (error) { retentionFailure(error, 'final_unverified_retention'); }
  }
  clearTimeout(watchdog);
  if (abortTimer) clearTimeout(abortTimer);
}
console.log(JSON.stringify({ status: report.status, cases: report.cases.length, reason: report.reason ?? null,
  retention_error: retentionError }));
process.exit(report.status === 'observed' ? 0 : 2);
