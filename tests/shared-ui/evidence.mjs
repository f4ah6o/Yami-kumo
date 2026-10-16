import assert from 'node:assert/strict';
import { readFileSync, realpathSync } from 'node:fs';
import { createHash } from 'node:crypto';
import { resolve, relative, isAbsolute } from 'node:path';

export const contract = JSON.parse(
  readFileSync(new URL('../../fixtures/shared-ui/contract-v1.json', import.meta.url), 'utf8'),
);
const sha = /^[a-f0-9]{40}$/;
const digest = /^[a-f0-9]{64}$/;
const nonempty = (value) => typeof value === 'string' && value.trim().length > 0;

// This is the executable v1 result schema. It is intentionally closed over the
// small fixture set; adding a control/profile difference requires a contract edit.
export function validateResult(result, expectedCandidateSha) {
  assert.equal(result.schemaVersion, 'shared-ui-result/v1');
  assert.equal(result.contractVersion, contract.version);
  const fixture = contract.fixtures.find((item) => item.id === result.fixtureId);
  assert.ok(fixture, 'unknown fixture');
  assert.match(result.candidateSha, sha, 'candidate must be an immutable Git revision');
  assert.equal(result.candidateSha, expectedCandidateSha, 'stale candidate revision');
  assert.equal(typeof result.sourceDirty, 'boolean', 'source dirtiness must be recorded');
  assert.ok(Number.isFinite(Date.parse(result.startedAt)), 'execution start timestamp is required');
  assert.ok(Number.isFinite(Date.parse(result.finishedAt)), 'execution end timestamp is required');
  assert.ok(
    Date.parse(result.finishedAt) >= Date.parse(result.startedAt),
    'execution timestamps are reversed',
  );
  assert.ok(Array.isArray(result.dependencies), 'dependencies must be explicit, including none');
  for (const dependency of result.dependencies) {
    assert.ok(nonempty(dependency.name));
    assert.ok(nonempty(dependency.revision), 'dependency version or SHA is required');
  }
  const { platform, backend, target, layer, environment } = result.profile;
  assert.ok(['web', 'linux', 'windows', 'macos'].includes(platform));
  assert.ok(['model', 'dom', 'gpui-native', 'gpui-canvas'].includes(backend));
  assert.ok(['js', 'native', 'wasm', 'wasm-gc'].includes(target));
  assert.ok(
    ['model', 'host', 'runtime', 'semantic', 'visual', 'lifecycle', 'package'].includes(layer),
  );
  if (backend === 'dom') {
    assert.equal(platform, 'web');
    assert.equal(target, 'js');
  }
  if (backend === 'gpui-native') {
    assert.notEqual(platform, 'web');
    assert.equal(target, 'native');
  }
  assert.ok(nonempty(environment.os));
  assert.ok(nonempty(environment.arch));
  assert.ok(nonempty(environment.toolchain));
  if (backend === 'dom') assert.ok(nonempty(environment.browser));
  assert.ok(['supported', 'unsupported', 'unverified'].includes(result.capability));
  assert.ok(['pass', 'fail', 'not-run'].includes(result.status));
  assert.ok(Array.isArray(result.command) && result.command.length > 0);
  assert.ok(result.command.every(nonempty));
  assert.ok(result.exitCode === null || Number.isInteger(result.exitCode));
  assert.ok(Array.isArray(result.artifacts));
  for (const artifact of result.artifacts) {
    assert.ok(nonempty(artifact.path));
    assert.ok(!artifact.path.startsWith('/') && !artifact.path.split(/[\\/]/).includes('..'));
    assert.match(artifact.sha256, digest);
  }
  assert.deepEqual(result.profileDifferences, [], 'v1 permits no unmeasured profile differences');
  if (result.status === 'pass') {
    assert.equal(result.capability, 'supported', 'unsupported/unverified cannot pass');
    assert.equal(result.sourceDirty, false, 'dirty source cannot qualify an exact commit');
    assert.equal(result.exitCode, 0, 'pass requires a successful executed command');
    assert.ok(result.artifacts.length > 0, 'pass requires retained artifacts');
    assert.deepEqual(result.observed, fixture.expected, 'domain result mismatch');
  } else {
    assert.ok(nonempty(result.reason), 'non-passing results need an explanation');
    if (result.status === 'not-run') assert.equal(result.exitCode, null);
  }
  return result;
}

export function profileKey(result) {
  const { platform, backend, target, layer } = result.profile;
  return `${platform}/${backend}/${target}/${layer}`;
}

// Validate a declared gate without silently dropping missing/unsupported rows.
// Model and visual records are separate keys and cannot fill runtime/AX rows.
export function validateGate(results, required, expectedCandidateSha) {
  assert.ok(
    Array.isArray(required) && required.length > 0,
    'a gate must declare required evidence',
  );
  const indexed = new Map();
  for (const result of results) {
    validateResult(result, expectedCandidateSha);
    const key = `${result.fixtureId}:${profileKey(result)}`;
    assert.ok(!indexed.has(key), `duplicate result: ${key}`);
    indexed.set(key, result);
  }
  for (const key of required) {
    assert.equal(
      indexed.get(key)?.status,
      'pass',
      `required evidence absent or non-passing: ${key}`,
    );
  }
  return true;
}

// Artifact references are checked separately against the retained evidence root.
// A schema-valid path or digest is not proof that the bytes actually exist.
export function validateArtifacts(result, evidenceRoot) {
  const root = realpathSync(evidenceRoot);
  for (const artifact of result.artifacts) {
    const file = realpathSync(resolve(root, artifact.path));
    const path = relative(root, file);
    assert.ok(
      path && !path.startsWith('..') && !isAbsolute(path),
      'artifact escapes evidence root',
    );
    const actual = createHash('sha256').update(readFileSync(file)).digest('hex');
    assert.equal(actual, artifact.sha256, 'artifact bytes do not match recorded digest');
  }
  return true;
}
