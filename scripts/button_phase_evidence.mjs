import { createHash } from 'node:crypto';
import * as fs from 'node:fs';
import { isAbsolute, join, resolve } from 'node:path';

export const DEFAULT_REPORT_CAPACITY = 1024 * 1024;
export const DEFAULT_LOG_CAPACITY = 1024 * 1024;
export const REQUIRED_HEADROOM_BYTES = 512 * 1024 * 1024;
const RESERVATION_CHUNK = 64 * 1024;

export function assessHeadroom(availableBytes, requiredBytes = REQUIRED_HEADROOM_BYTES) {
  return {
    available_bytes: availableBytes,
    required_headroom_bytes: requiredBytes,
    sufficient: Number.isFinite(availableBytes) && availableBytes >= requiredBytes,
  };
}

export function assessMeasurementHost(platform) {
  return { platform, supported: platform === 'darwin', supported_platforms: ['darwin'] };
}

export function resolveChromeExecutable(platform, override) {
  if (platform !== 'darwin') return null;
  if (override !== undefined && override !== null) {
    if (!isAbsolute(override)) {
      throw Object.assign(new Error('KUMO_HEADLESS_CHROME must be an absolute path'), {
        code: 'KUMO_CHROME_PATH_NOT_ABSOLUTE',
      });
    }
    return resolve(override);
  }
  return '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome';
}

export function canMarkObserved(
  report,
  { stdoutTruncated = false, stderrTruncated = false, aborting = false } = {},
) {
  return (
    report.measurement_complete === true &&
    report.cases.length === 7 &&
    report.cases.every((item) => item.status === 'observed') &&
    report.browser?.returncode === 0 &&
    !report.browser?.signal &&
    report.browser?.closed_returncode === 0 &&
    !report.browser?.closed_signal &&
    report.server_cleanup?.succeeded === true &&
    !report.retention_error &&
    !stdoutTruncated &&
    !stderrTruncated &&
    !report.cleanup_error &&
    !aborting
  );
}

function writeFully(fd, buffer, position, io = fs) {
  let written = 0;
  while (written < buffer.length) {
    const count = io.writeSync(fd, buffer, written, buffer.length - written, position + written);
    if (count <= 0)
      throw Object.assign(new Error('Evidence write made no progress'), { code: 'EIO' });
    written += count;
  }
}

function readFully(fd, length, position = 0, io = fs) {
  const buffer = Buffer.alloc(length);
  let read = 0;
  while (read < length) {
    const count = io.readSync(fd, buffer, read, length - read, position + read);
    if (count <= 0) throw Object.assign(new Error('Evidence readback was short'), { code: 'EIO' });
    read += count;
  }
  return buffer;
}

function reserve(fd, capacity, fillByte, io = fs) {
  const block = Buffer.alloc(Math.min(RESERVATION_CHUNK, capacity), fillByte);
  let offset = 0;
  while (offset < capacity) {
    const length = Math.min(block.length, capacity - offset);
    writeFully(fd, length === block.length ? block : block.subarray(0, length), offset, io);
    offset += length;
  }
  io.fsyncSync(fd);
  if (io.fstatSync(fd).size !== capacity) throw new Error('Evidence reservation size differs');
}

function jsonBlock(value, capacity) {
  const payload = Buffer.from(`${JSON.stringify(value, null, 2)}\n`);
  if (payload.length > capacity) {
    throw Object.assign(
      new Error(`Checkpoint needs ${payload.length} bytes; reserved ${capacity}`),
      {
        code: 'EVIDENCE_CAPACITY',
      },
    );
  }
  const block = Buffer.alloc(capacity, 0x20);
  payload.copy(block);
  return { block, payloadLength: payload.length };
}

function writeJsonSlot(fd, capacity, value, io = fs) {
  const { block } = jsonBlock(value, capacity);
  writeFully(fd, block, 0, io);
  io.fsyncSync(fd);
  const readback = readFully(fd, capacity, 0, io);
  if (!readback.equals(block)) throw new Error('Durable JSON readback differs');
  let parsed;
  try {
    parsed = JSON.parse(readback.toString('utf8'));
  } catch {
    throw new Error('Durable JSON readback is invalid');
  }
  if (JSON.stringify(parsed) !== JSON.stringify(value))
    throw new Error('Durable JSON value differs');
}

/** Keeps the original raw bytes, while making any capped retention explicit. */
export class RawLogCapture {
  constructor(capacity = DEFAULT_LOG_CAPACITY) {
    this.capacity = capacity;
    this.chunks = [];
    this.length = 0;
    this.retainedLength = 0;
    this.fullHash = createHash('sha256');
    this.retainedHash = createHash('sha256');
    this.truncated = false;
  }

  push(value) {
    const bytes = Buffer.isBuffer(value) ? value : Buffer.from(value);
    this.length += bytes.length;
    this.fullHash.update(bytes);
    const remaining = Math.max(0, this.capacity - this.retainedLength);
    const kept = bytes.subarray(0, remaining);
    if (kept.length) {
      const copy = Buffer.from(kept);
      this.chunks.push(copy);
      this.retainedLength += copy.length;
      this.retainedHash.update(copy);
    }
    if (kept.length !== bytes.length) this.truncated = true;
    return this.truncated;
  }

  bytes() {
    return Buffer.concat(this.chunks, this.retainedLength);
  }

  metadata() {
    return {
      observed_length: this.length,
      retained_length: this.retainedLength,
      sha256: this.fullHash.copy().digest('hex'),
      retained_sha256: this.retainedHash.copy().digest('hex'),
      truncated: this.truncated,
    };
  }
}

/**
 * Reserves all evidence extents before a browser can be spawned. Checkpoints
 * alternate between two independently valid slots; each write is positional,
 * bounded, fsynced and read back before its slot is considered current.
 */
export class EvidenceStore {
  constructor(directory, initial, options = {}) {
    this.directory = directory;
    this.reportCapacity = options.reportCapacity ?? DEFAULT_REPORT_CAPACITY;
    this.logCapacity = options.logCapacity ?? DEFAULT_LOG_CAPACITY;
    this.io = options.io ?? fs;
    this.generation = 0;
    this.nextSlot = 0;
    this.closed = false;
    this.handles = new Map();
    this.paths = {
      canonical: join(directory, 'report.json'),
      checkpoints: [join(directory, 'checkpoint-a.json'), join(directory, 'checkpoint-b.json')],
      final: join(directory, 'report-final-slot.json'),
      logs: [join(directory, 'browser.stdout'), join(directory, 'browser.stderr')],
    };
    try {
      for (const [key, path] of [
        ['canonical', this.paths.canonical],
        ['checkpoint0', this.paths.checkpoints[0]],
        ['checkpoint1', this.paths.checkpoints[1]],
        ['final', this.paths.final],
      ]) {
        const fd = this.io.openSync(path, 'wx+', 0o600);
        this.handles.set(key, fd);
        reserve(fd, this.reportCapacity, 0x20, this.io);
        writeJsonSlot(
          fd,
          this.reportCapacity,
          { ...initial, status: 'unverified', checkpoint_generation: 0 },
          this.io,
        );
      }
      for (const [index, path] of this.paths.logs.entries()) {
        const fd = this.io.openSync(path, 'wx+', 0o600);
        this.handles.set(`log${index}`, fd);
        reserve(fd, this.logCapacity, 0xa5, this.io);
      }
    } catch (error) {
      try {
        this.close();
      } catch {
        /* preserve the reservation failure */
      }
      throw error;
    }
  }

  checkpoint(report, stdout, stderr, progress = undefined) {
    this.assertOpen();
    const logs = [stdout, stderr];
    const logMetadata = [];
    for (const [index, capture] of logs.entries()) {
      if (capture.retainedLength > this.logCapacity) {
        throw Object.assign(new Error('Captured browser log exceeds reserved capacity'), {
          code: 'EVIDENCE_CAPACITY',
        });
      }
      const fd = this.handles.get(`log${index}`);
      const bytes = capture.bytes();
      writeFully(fd, bytes, 0, this.io);
      this.io.fsyncSync(fd);
      const observed = readFully(fd, bytes.length, 0, this.io);
      if (!observed.equals(bytes)) throw new Error(`Browser log ${index} readback differs`);
      const metadata = capture.metadata();
      if (createHash('sha256').update(observed).digest('hex') !== metadata.retained_sha256) {
        throw new Error(`Browser log ${index} hash readback differs`);
      }
      logMetadata.push(metadata);
    }

    this.generation += 1;
    const value = {
      ...report,
      status: 'unverified',
      checkpoint_generation: this.generation,
      ...(progress ? { progress } : {}),
      ...(report.browser
        ? {
            browser: {
              ...report.browser,
              logs: { stdout: logMetadata[0], stderr: logMetadata[1] },
            },
          }
        : {}),
    };
    const index = this.nextSlot;
    writeJsonSlot(this.handles.get(`checkpoint${index}`), this.reportCapacity, value, this.io);
    this.nextSlot = 1 - index;
    // The alternate valid slot is retained if this convenience copy tears.
    writeJsonSlot(this.handles.get('canonical'), this.reportCapacity, value, this.io);
    return value;
  }

  finalizeUnverified(report, stdout, stderr, progress = undefined) {
    this.assertOpen();
    let finalReport = this.checkpoint(report, stdout, stderr, progress);
    finalReport = this.finishLogs(finalReport, stdout, stderr);
    this.close();
    return finalReport;
  }

  finalizeObserved(report, stdout, stderr) {
    this.assertOpen();
    if (report.status !== 'observed')
      throw new Error('Only a fully checked report can be finalized as observed');
    if (stdout.truncated || stderr.truncated) {
      throw Object.assign(new Error('Browser output exceeded the raw-log retention limit'), {
        code: 'LOG_OVERFLOW',
      });
    }

    // Store a final unverified checkpoint before committing the observed file.
    let finalReport = this.checkpoint(report, stdout, stderr, { stage: 'final-retention' });
    finalReport = this.finishLogs(finalReport, stdout, stderr);
    // No evidence handles are left open when the atomic final report replaces
    // the still-valid launch-intent report.
    this.close();

    const observedReport = {
      ...report,
      status: 'observed',
      checkpoint_generation: this.generation + 1,
      browser: report.browser ? { ...report.browser, logs: finalReport.browser?.logs } : undefined,
      retention: { final_report: 'report.json', raw_logs_verified: true },
    };
    const finalFd = this.io.openSync(this.paths.final, 'r+');
    try {
      writeJsonSlot(finalFd, this.reportCapacity, observedReport, this.io);
    } finally {
      this.io.closeSync(finalFd);
    }
    // Atomic publication makes the verified, fsynced candidate authoritative.
    this.io.renameSync(this.paths.final, this.paths.canonical);
    return observedReport;
  }

  finishLogs(report, stdout, stderr) {
    const logs = [stdout, stderr];
    const verified = [];
    for (const [index, capture] of logs.entries()) {
      if (capture.truncated) {
        throw Object.assign(new Error('Browser output exceeded the raw-log retention limit'), {
          code: 'LOG_OVERFLOW',
        });
      }
      const fd = this.handles.get(`log${index}`);
      const bytes = capture.bytes();
      this.io.ftruncateSync(fd, bytes.length);
      this.io.fsyncSync(fd);
      const observed = readFully(fd, bytes.length, 0, this.io);
      if (!observed.equals(bytes)) throw new Error(`Final browser log ${index} readback differs`);
      const digest = createHash('sha256').update(observed).digest('hex');
      const metadata = capture.metadata();
      if (digest !== metadata.retained_sha256 || digest !== metadata.sha256) {
        throw new Error(`Final browser log ${index} digest differs`);
      }
      verified.push({ ...metadata, sha256: digest, retained_sha256: digest, verified: true });
    }
    return report.browser
      ? {
          ...report,
          browser: { ...report.browser, logs: { stdout: verified[0], stderr: verified[1] } },
        }
      : report;
  }

  close() {
    if (this.closed) return;
    this.closed = true;
    let firstError;
    for (const fd of this.handles.values()) {
      try {
        this.io.closeSync(fd);
      } catch (error) {
        firstError ??= error;
      }
    }
    this.handles.clear();
    if (firstError) throw firstError;
  }

  assertOpen() {
    if (this.closed) throw new Error('Evidence store is closed');
  }
}
