import assert from 'node:assert/strict';
import test from 'node:test';
import { mkdtempSync, writeFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { createHash } from 'node:crypto';
import { validateResult, validateGate, validateArtifacts } from './evidence.mjs';

const candidate = 'a'.repeat(40);
function record() {
  return {
    schemaVersion: 'shared-ui-result/v1',
    contractVersion: 'shared-ui-contract/v1',
    fixtureId: 'counter-two-activations',
    candidateSha: candidate,
    sourceDirty: false,
    startedAt: '2026-10-16T00:00:00Z',
    finishedAt: '2026-10-16T00:00:01Z',
    dependencies: [{ name: 'moonbit-core', revision: '0.10.14+7d59c7ec9' }],
    profile: {
      platform: 'web',
      backend: 'dom',
      target: 'js',
      layer: 'runtime',
      environment: { os: 'fixture', arch: 'fixture', toolchain: 'fixture', browser: 'fixture' },
    },
    capability: 'supported',
    status: 'pass',
    command: ['fixture-only'],
    exitCode: 0,
    artifacts: [{ path: 'trace.json', sha256: 'b'.repeat(64) }],
    profileDifferences: [],
    observed: { counts: [0, 1, 2] },
  };
}

test('valid fixture record and exact profile gate', () => {
  assert.equal(validateResult(record(), candidate).status, 'pass');
  assert.equal(
    validateGate([record()], ['counter-two-activations:web/dom/js/runtime'], candidate),
    true,
  );
});

for (const [name, mutate] of [
  [
    'unsupported cannot pass',
    (r) => {
      r.capability = 'unsupported';
    },
  ],
  [
    'unverified cannot pass',
    (r) => {
      r.capability = 'unverified';
    },
  ],
  [
    'artifacts cannot be omitted',
    (r) => {
      r.artifacts = [];
    },
  ],
  [
    'dirty tree cannot qualify an exact commit',
    (r) => {
      r.sourceDirty = true;
    },
  ],
  [
    'stale SHA cannot pass',
    (r) => {
      r.candidateSha = 'c'.repeat(40);
    },
  ],
  [
    'failed command cannot pass',
    (r) => {
      r.exitCode = 1;
    },
  ],
  [
    'unexecuted command cannot pass',
    (r) => {
      r.exitCode = null;
    },
  ],
  [
    'domain differences cannot be hidden by equal images',
    (r) => {
      r.observed.counts = [0, 2, 4];
    },
  ],
  [
    'new allowlist entries cannot excuse mismatches',
    (r) => {
      r.profileDifferences = ['double-activate'];
    },
  ],
  [
    'DOM cannot claim native platform',
    (r) => {
      r.profile.platform = 'macos';
    },
  ],
  [
    'unversioned dependencies cannot pass',
    (r) => {
      r.dependencies[0].revision = '';
    },
  ],
  [
    'unknown fixture cannot pass',
    (r) => {
      r.fixtureId = 'invented';
    },
  ],
]) {
  test(name, () => {
    const result = record();
    mutate(result);
    assert.throws(() => validateResult(result, candidate));
  });
}

test('missing profiles and different observation layers fail closed', () => {
  assert.throws(() =>
    validateGate(
      [record()],
      ['counter-two-activations:macos/gpui-native/native/runtime'],
      candidate,
    ),
  );
  assert.throws(() =>
    validateGate([record()], ['counter-two-activations:web/dom/js/semantic'], candidate),
  );
  assert.throws(() =>
    validateGate([record(), record()], ['counter-two-activations:web/dom/js/runtime'], candidate),
  );
});

test('not-run and unsupported are retained but do not qualify a gate', () => {
  const result = record();
  Object.assign(result, {
    capability: 'unsupported',
    status: 'not-run',
    reason: 'Host is not implemented',
    exitCode: null,
    artifacts: [],
    observed: null,
  });
  assert.equal(validateResult(result, candidate).status, 'not-run');
  assert.throws(() =>
    validateGate([result], ['counter-two-activations:web/dom/js/runtime'], candidate),
  );
});

test('an undeclared empty gate cannot pass', () => {
  assert.throws(() => validateGate([], [], candidate));
});

test('retained artifacts must exist and match their recorded bytes', () => {
  const directory = mkdtempSync(join(tmpdir(), 'shared-ui-artifact-test-'));
  try {
    const result = record();
    assert.throws(() => validateArtifacts(result, directory));
    writeFileSync(join(directory, 'trace.json'), 'actual trace');
    assert.throws(() => validateArtifacts(result, directory));
    result.artifacts[0].sha256 = createHash('sha256').update('actual trace').digest('hex');
    assert.equal(validateArtifacts(result, directory), true);
  } finally {
    rmSync(directory, { recursive: true, force: true });
  }
});

for (const fixtureId of ['button-interrupted-loading', 'button-interrupted-disabled']) {
  test(`${fixtureId} requires its exact interruption trace and cannot borrow another fixture`, () => {
    const result = record();
    result.fixtureId = fixtureId;
    result.observed = { counts: [0, 0, 0, 1, 1, 2] };
    assert.equal(validateResult(result, candidate).status, 'pass');
    const required = [`${fixtureId}:web/dom/js/runtime`];
    assert.equal(validateGate([result], required, candidate), true);
    assert.throws(() => validateGate([record()], required, candidate), /required evidence/);
    result.observed.counts[2] = 1;
    assert.throws(() => validateResult(result, candidate), /domain result mismatch/);
  });
}
