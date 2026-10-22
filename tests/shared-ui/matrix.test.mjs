import assert from 'node:assert/strict';
import test from 'node:test';
import { buildMatrix } from './matrix.mjs';

const sha = 'a'.repeat(40);

function lane(fixtureId, platform, backend, target, layer, status = 'pass') {
  return {
    schemaVersion: 'settings-lane/v1',
    fixtureId,
    candidateSha: sha,
    platform,
    backend,
    target,
    layer,
    status,
    claims: {},
    ...(status === 'pass' ? {} : { reason: 'declared' }),
  };
}

const required = [
  lane('settings-flow', 'web', 'dom', 'js', 'runtime'),
  lane('settings-flow', 'linux', 'gpui-native', 'native', 'runtime'),
  lane('settings-flow', 'windows', 'gpui-native', 'native', 'runtime'),
];

test('three passing flow lanes produce a matrix', () => {
  const matrix = buildMatrix(required, sha);
  assert.equal(matrix.status, 'pass');
  assert.equal(matrix.required.length, 3);
  assert.ok(matrix.declaredNotRun.every((row) => row.status === 'not-run'));
});

test('a missing required lane fails', () => {
  assert.throws(() => buildMatrix(required.slice(0, 2), sha), /required lane missing/);
});

test('a declared NOT_RUN lane cannot satisfy a required row', () => {
  const lanes = [
    lane('settings-flow', 'web', 'dom', 'js', 'runtime', 'not-run'),
    ...required.slice(1),
  ];
  assert.throws(() => buildMatrix(lanes, sha), /not passing/);
});

test('a stale candidate fails', () => {
  assert.throws(() => buildMatrix(required, 'b'.repeat(40)), /stale candidate/);
});

test('an undeclared lane fails', () => {
  const lanes = [...required, lane('settings-extra', 'web', 'dom', 'js', 'semantic')];
  assert.throws(() => buildMatrix(lanes, sha), /undeclared lane/);
});

test('a passing lane cannot fill a declared NOT_RUN row', () => {
  const lanes = [
    ...required,
    lane('settings-ime', 'linux', 'gpui-native', 'native', 'host', 'pass'),
  ];
  assert.throws(() => buildMatrix(lanes, sha), /must be not-run/);
});
