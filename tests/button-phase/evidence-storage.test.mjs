import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import {
  assessHeadroom,
  assessMeasurementHost,
  canMarkObserved,
  EvidenceStore,
  RawLogCapture,
  resolveChromeExecutable,
  REQUIRED_HEADROOM_BYTES,
} from '../../scripts/button_phase_evidence.mjs';

class MemoryFileSystem {
  constructor() {
    this.files = new Map();
    this.handles = new Map();
    this.nextFd = 10;
    this.failAfter = new Map();
  }

  openSync(path, flags) {
    if (flags === 'wx+' && this.files.has(path))
      throw Object.assign(new Error('exists'), { code: 'EEXIST' });
    if (flags === 'wx+') this.files.set(path, Buffer.alloc(0));
    if (!this.files.has(path)) throw new Error('missing fake file: ' + path);
    const fd = this.nextFd++;
    this.handles.set(fd, path);
    return fd;
  }

  writeSync(fd, buffer, bufferOffset, length, position) {
    const path = this.handles.get(fd);
    const budget = this.failAfter.get(path);
    if (budget === 0) throw Object.assign(new Error('injected ENOSPC'), { code: 'ENOSPC' });
    const count = Math.min(length, 37, budget === undefined ? length : budget);
    if (count <= 0) throw Object.assign(new Error('injected ENOSPC'), { code: 'ENOSPC' });
    const file = this.files.get(path);
    const end = position + count;
    if (end > file.length) {
      const grown = Buffer.alloc(end);
      file.copy(grown);
      this.files.set(path, grown);
    }
    buffer.copy(this.files.get(path), position, bufferOffset, bufferOffset + count);
    if (budget !== undefined) this.failAfter.set(path, budget - count);
    return count;
  }

  readSync(fd, target, targetOffset, length, position) {
    const file = this.files.get(this.handles.get(fd));
    const count = Math.min(length, 53, Math.max(0, file.length - position));
    file.copy(target, targetOffset, position, position + count);
    return count;
  }

  fsyncSync() {}
  fstatSync(fd) {
    return { size: this.files.get(this.handles.get(fd)).length };
  }
  ftruncateSync(fd, length) {
    const path = this.handles.get(fd);
    const old = this.files.get(path);
    const next = Buffer.alloc(length);
    old.copy(next, 0, 0, Math.min(length, old.length));
    this.files.set(path, next);
  }
  closeSync(fd) {
    this.handles.delete(fd);
  }
  renameSync(from, to) {
    this.files.set(to, this.files.get(from));
    this.files.delete(from);
  }

  json(path) {
    return JSON.parse(this.files.get(path).toString('utf8'));
  }
}

function hash(raw) {
  return createHash('sha256').update(raw).digest('hex');
}

const io = new MemoryFileSystem();
const store = new EvidenceStore(
  '/memory/run',
  {
    status: 'unverified',
    run_token: 'test-token',
    cases: [],
    browser: { pid: 77 },
  },
  { reportCapacity: 8192, logCapacity: 32, io },
);
const stdout = new RawLogCapture(32);
const stderr = new RawLogCapture(32);
const rawStdout = Buffer.from([0x00, 0xff, 0x80, 0x0a, 0x42]);
const rawStderr = Buffer.from([0x81, 0x00]);
stdout.push(rawStdout);
stderr.push(rawStderr);

store.checkpoint(
  { status: 'unverified', run_token: 'test-token', cases: [], browser: { pid: 77 } },
  stdout,
  stderr,
  { stage: 'first-valid-checkpoint' },
);
const slotA = store.paths.checkpoints[0];
const first = io.json(slotA);
assert.equal(first.status, 'unverified');
assert.equal(first.progress.stage, 'first-valid-checkpoint');
assert.equal(first.browser.logs.stdout.observed_length, rawStdout.length);
assert.equal(first.browser.logs.stdout.retained_sha256, hash(rawStdout));
assert.deepEqual(io.files.get(store.paths.logs[0]).subarray(0, rawStdout.length), rawStdout);
assert.equal(first.browser.logs.stderr.sha256, hash(rawStderr));

assert.throws(
  () => store.checkpoint({ status: 'unverified', padding: 'x'.repeat(9000) }, stdout, stderr),
  { code: 'EVIDENCE_CAPACITY' },
);
assert.equal(
  io.json(slotA).progress.stage,
  'first-valid-checkpoint',
  'oversized JSON leaves the prior valid slot intact',
);

const tornSlot = store.paths.checkpoints[1];
io.failAfter.set(tornSlot, 97);
assert.throws(
  () =>
    store.checkpoint(
      { status: 'unverified', run_token: 'test-token', note: 'partial overwrite' },
      stdout,
      stderr,
    ),
  { code: 'ENOSPC' },
);
assert.equal(
  io.json(slotA).progress.stage,
  'first-valid-checkpoint',
  'partial slot write cannot destroy its alternate',
);

const overflowing = new RawLogCapture(4);
overflowing.push(Buffer.from([0x00, 0xff, 0x80, 0x0a, 0x42]));
assert.deepEqual(overflowing.metadata(), {
  observed_length: 5,
  retained_length: 4,
  sha256: hash(Buffer.from([0x00, 0xff, 0x80, 0x0a, 0x42])),
  retained_sha256: hash(Buffer.from([0x00, 0xff, 0x80, 0x0a])),
  truncated: true,
});
assert.throws(
  () => store.finalizeObserved({ status: 'observed', browser: {} }, overflowing, stderr),
  /retention limit/,
);
assert.equal(assessHeadroom(REQUIRED_HEADROOM_BYTES - 1).sufficient, false);
assert.equal(assessHeadroom(REQUIRED_HEADROOM_BYTES).sufficient, true);
assert.equal(assessHeadroom(Number.NaN).sufficient, false);
assert.equal(assessMeasurementHost('darwin').supported, true);
assert.equal(assessMeasurementHost('linux').supported, false);
assert.equal(resolveChromeExecutable('darwin', '/opt/test/chrome'), '/opt/test/chrome');
assert.equal(resolveChromeExecutable('linux', '/usr/bin/chromium'), null);
assert.throws(() => resolveChromeExecutable('darwin', 'chrome'), {
  code: 'KUMO_CHROME_PATH_NOT_ABSOLUTE',
});
const completeReport = {
  measurement_complete: true,
  cases: Array.from({ length: 7 }, () => ({ status: 'observed' })),
  browser: { returncode: 0, signal: null, closed_returncode: 0, closed_signal: null },
  server_cleanup: { attempted: true, succeeded: true },
};
assert.equal(canMarkObserved(completeReport), true);
assert.equal(
  canMarkObserved({ ...completeReport, server_cleanup: { attempted: true, succeeded: false } }),
  false,
  'failed fixture-server cleanup cannot be promoted to observed',
);
store.close();

console.log(
  'evidence storage checks passed (in-memory fake filesystem; no browser or disk reservations)',
);
