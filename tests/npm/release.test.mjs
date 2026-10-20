import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { spawnSync, execFileSync } from 'node:child_process';
import { mkdtempSync, mkdirSync, readFileSync, writeFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import test from 'node:test';

const root = fileURLToPath(new URL('../../', import.meta.url));
const script = path.join(root, 'scripts/check-npm-release.mjs');
const manifest = JSON.parse(readFileSync(path.join(root, 'npm/package.json')));

test('release gates reject wrong identity and unverified or altered artifacts', () => {
  const dir = mkdtempSync(path.join(tmpdir(), 'yk-release-'));
  try {
    for (const name of ['npm', 'package', 'dist']) mkdirSync(path.join(dir, name));
    const json = (file, value) => writeFileSync(path.join(dir, file), JSON.stringify(value));
    json('npm/package.json', manifest);
    json('package.json', { private: true });
    json('package/package.json', manifest);
    const build = { version: manifest.version, sourceSha: 'source-sha', sourceDirty: false };
    const filename = `f4ah6o-yami-kumo-${manifest.version}.tgz`;
    const evidence = { status: 'PASS', consumers: ['javascript', 'typescript', 'browser', 'react'], tarball: filename };
    const pack = () => {
      json('package/BUILD.json', build);
      execFileSync('tar', ['-czf', `dist/${filename}`, 'package'], { cwd: dir });
      const bytes = readFileSync(path.join(dir, 'dist', filename));
      evidence.integrity = `sha512-${createHash('sha512').update(bytes).digest('base64')}`;
      evidence.shasum = createHash('sha1').update(bytes).digest('hex');
      json('dist/npm-consumers.json', evidence);
    };
    const run = (overrides = {}, artifact = false) => spawnSync(process.execPath, [script, ...(artifact ? ['--artifact'] : [])], {
      cwd: dir, encoding: 'utf8', env: { ...process.env, GITHUB_REPOSITORY: 'f4ah6o/Yami-kumo', GITHUB_REF: 'refs/heads/main', RELEASE_VERSION: manifest.version, GITHUB_SHA: 'source-sha', ...overrides },
    });
    const pass = (result) => assert.equal(result.status, 0, result.stderr);
    const reject = (result, message) => {
      assert.notEqual(result.status, 0);
      assert.match(result.stderr, message);
    };
    pass(run());
    reject(run({ GITHUB_REF: 'refs/heads/topic' }), /dispatch this workflow from main/);
    reject(run({ GITHUB_REPOSITORY: 'someone/fork' }), /release repository mismatch/);
    reject(run({ RELEASE_VERSION: '0.0.0' }), /version must match/);
    pack();
    pass(run({}, true));
    reject(run({ GITHUB_SHA: 'different-source' }, true), /artifact must come from/);
    evidence.status = 'FAIL';
    json('dist/npm-consumers.json', evidence);
    reject(run({}, true), /packed consumer tests must pass/);
    evidence.status = 'PASS';
    evidence.consumers = ['javascript'];
    json('dist/npm-consumers.json', evidence);
    reject(run({}, true), /AssertionError/);
    evidence.consumers = ['javascript', 'typescript', 'browser', 'react'];
    pack();
    writeFileSync(path.join(dir, 'dist', filename), 'tampered tarball');
    reject(run({}, true), /AssertionError/);
    build.sourceDirty = true;
    pack();
    reject(run({}, true), /clean checkout/);
    build.sourceDirty = false;
    json('package/package.json', { ...manifest, name: '@someone/other' });
    pack();
    reject(run({}, true), /packed manifest differs/);
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});
