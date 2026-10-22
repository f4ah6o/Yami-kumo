#!/usr/bin/env node
// Aggregate the Shared Settings lane reports into one matrix. Required rows
// must pass; declared NOT_RUN rows need a reason and can never fill a required
// row. This is a report builder, not a test runner.
import assert from 'node:assert/strict';
import { readFileSync, readdirSync, writeFileSync, mkdirSync } from 'node:fs';
import { resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const SCHEMA = 'settings-lane/v1';
const REQUIRED = [
  'settings-flow:web/dom/js/runtime',
  'settings-flow:linux/gpui-native/native/runtime',
  'settings-flow:windows/gpui-native/native/runtime',
];
const DECLARED_NOT_RUN = [
  {
    key: 'settings-ime:linux/gpui-native/native/host',
    reason: 'The Wayland lane installs no input-method engine.',
  },
  {
    key: 'settings-ime:windows/gpui-native/native/host',
    reason:
      'The Windows lane drives ASCII through SendInput; real IME composition is not exercised.',
  },
  {
    key: 'settings-ax:linux/gpui-native/native/semantic',
    reason: 'No AT-SPI provider is linked.',
  },
  {
    key: 'settings-ax:windows/gpui-native/native/semantic',
    reason: 'No UI Automation provider is linked.',
  },
];

export function laneKey(lane) {
  return `${lane.fixtureId}:${lane.platform}/${lane.backend}/${lane.target}/${lane.layer}`;
}

export function validateLane(lane, candidateSha) {
  assert.equal(lane.schemaVersion, SCHEMA, 'lane schema');
  assert.ok(typeof lane.fixtureId === 'string' && lane.fixtureId.length > 0, 'fixtureId');
  if (candidateSha)
    assert.equal(lane.candidateSha, candidateSha, `stale candidate for ${lane.fixtureId}`);
  assert.ok(['web', 'linux', 'windows', 'macos'].includes(lane.platform), 'platform');
  assert.ok(['model', 'dom', 'gpui-native', 'gpui-canvas'].includes(lane.backend), 'backend');
  assert.ok(['js', 'native', 'wasm', 'wasm-gc'].includes(lane.target), 'target');
  assert.ok(
    ['model', 'host', 'runtime', 'semantic', 'visual', 'lifecycle', 'package'].includes(lane.layer),
    'layer',
  );
  assert.ok(['pass', 'fail', 'not-run'].includes(lane.status), 'status');
  if (lane.status !== 'pass') assert.ok(lane.reason, `${lane.fixtureId} needs a reason`);
  return lane;
}

export function buildMatrix(lanes, candidateSha) {
  const indexed = new Map();
  for (const lane of lanes) {
    validateLane(lane, candidateSha);
    const key = laneKey(lane);
    assert.ok(!indexed.has(key), `duplicate lane ${key}`);
    indexed.set(key, lane);
  }
  const rows = REQUIRED.map((key) => {
    const lane = indexed.get(key);
    assert.ok(lane, `required lane missing: ${key}`);
    assert.equal(lane.status, 'pass', `required lane is not passing: ${key}`);
    return { key, status: lane.status, source: lane.platform };
  });
  const notRun = DECLARED_NOT_RUN.map(({ key, reason }) => {
    assert.ok(reason && reason.trim().length > 0, `declared NOT_RUN needs a reason: ${key}`);
    assert.ok(!REQUIRED.includes(key), `declared NOT_RUN overlaps required: ${key}`);
    const lane = indexed.get(key);
    if (!lane) return { key, status: 'not-run', reason };
    assert.equal(lane.status, 'not-run', `declared NOT_RUN lane must be not-run: ${key}`);
    return { key, status: lane.status, reason: lane.reason ?? reason };
  });
  for (const key of indexed.keys()) {
    assert.ok(
      REQUIRED.includes(key) || DECLARED_NOT_RUN.some((entry) => entry.key === key),
      `undeclared lane: ${key}`,
    );
  }
  return {
    schemaVersion: 'settings-matrix/v1',
    candidateSha,
    status: 'pass',
    required: rows,
    declaredNotRun: notRun,
    lanes: [...indexed.values()],
  };
}

export function renderMatrix(matrix) {
  const lines = [
    '# Shared Settings evidence matrix',
    '',
    `Candidate: \`${matrix.candidateSha}\``,
    '',
    '## Required',
    '',
    '| Row | Status |',
    '| --- | --- |',
  ];
  for (const row of matrix.required) lines.push(`| ${row.key} | ${row.status} |`);
  lines.push('', '## Declared NOT_RUN', '', '| Row | Reason |', '| --- | --- |');
  for (const row of matrix.declaredNotRun) lines.push(`| ${row.key} | ${row.reason} |`);
  lines.push('');
  return lines.join('\n');
}

function main() {
  const args = process.argv.slice(2);
  const dirIndex = args.indexOf('--dir');
  assert.ok(dirIndex >= 0, 'usage: matrix.mjs --dir <evidence-dir> [--candidate-sha <sha>]');
  const directory = resolve(args[dirIndex + 1]);
  const shaIndex = args.indexOf('--candidate-sha');
  const candidateSha = shaIndex >= 0 ? args[shaIndex + 1] : undefined;
  const lanes = readdirSync(directory)
    .filter((name) => name.endsWith('.json') && name !== 'matrix.json')
    .map((name) => JSON.parse(readFileSync(resolve(directory, name), 'utf8')))
    .filter((value) => value.schemaVersion === SCHEMA);
  assert.ok(lanes.length > 0, 'no settings-lane reports found');
  const matrix = buildMatrix(lanes, candidateSha);
  mkdirSync(directory, { recursive: true });
  writeFileSync(resolve(directory, 'matrix.json'), `${JSON.stringify(matrix, null, 2)}\n`);
  writeFileSync(resolve(directory, 'matrix.md'), renderMatrix(matrix));
  console.log(renderMatrix(matrix));
}

// Compare native paths: the Windows CLI argument is `C:\...`, not a file URL.
if (process.argv[1] && fileURLToPath(import.meta.url) === resolve(process.argv[1])) main();
