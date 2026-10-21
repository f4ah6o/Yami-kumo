import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { readFileSync, readdirSync } from 'node:fs';
import { execFileSync } from 'node:child_process';

const readJson = (file) => JSON.parse(readFileSync(file, 'utf8'));
const manifest = readJson('npm/package.json');
assert.equal(process.env.GITHUB_REPOSITORY, 'f4ah6o/Yami-kumo', 'release repository mismatch');
assert.equal(process.env.GITHUB_REF, 'refs/heads/main', 'dispatch this workflow from main');
assert.equal(process.env.RELEASE_VERSION, manifest.version, 'version must match npm/package.json');
assert.match(
  manifest.version,
  /^\d+\.\d+\.\d+-preview\.\d+$/,
  'only explicit preview versions are enabled',
);
assert.equal(manifest.name, '@f4ah6o/yami-kumo');
assert.equal(manifest.publishConfig.access, 'public');
assert.equal(manifest.publishConfig.tag, 'preview');
assert.equal(readJson('package.json').private, true);

if (process.argv.includes('--artifact')) {
  const evidence = readJson('dist/npm-consumers.json');
  assert.equal(evidence.status, 'PASS', 'packed consumer tests must pass');
  assert.deepEqual(evidence.consumers.slice().sort(), [
    'browser',
    'javascript',
    'react',
    'typescript',
  ]);
  const filename = `f4ah6o-yami-kumo-${manifest.version}.tgz`;
  assert.equal(evidence.tarball, filename);
  assert.deepEqual(
    readdirSync('dist').filter((name) => name.endsWith('.tgz')),
    [filename],
    'exactly one tested tarball is allowed',
  );
  const tarball = `dist/${filename}`;
  const bytes = readFileSync(tarball);
  assert.equal(evidence.integrity, `sha512-${createHash('sha512').update(bytes).digest('base64')}`);
  assert.equal(evidence.shasum, createHash('sha1').update(bytes).digest('hex'));
  const extract = (file) =>
    JSON.parse(execFileSync('tar', ['-xOf', tarball, `package/${file}`], { encoding: 'utf8' }));
  assert.deepEqual(
    extract('package.json'),
    manifest,
    'packed manifest differs from the release source',
  );
  const build = extract('BUILD.json');
  assert.equal(build.version, manifest.version);
  assert.equal(
    build.sourceSha,
    process.env.GITHUB_SHA,
    'artifact must come from this workflow commit',
  );
  assert.equal(build.sourceDirty, false, 'artifact must be built from a clean checkout');
}
console.log(
  `PASS release identity${process.argv.includes('--artifact') ? ' and tested tarball' : ''}: ${manifest.name}@${manifest.version}`,
);
