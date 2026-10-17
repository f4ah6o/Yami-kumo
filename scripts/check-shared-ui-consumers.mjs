#!/usr/bin/env node
// Independent package/model qualification, not a browser or native-window test.
// Only bootstrap/test code is generated. All application and runtime source is
// imported directly from the checkout through explicit temporary workspaces.
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import {
  existsSync,
  mkdirSync,
  mkdtempSync,
  readFileSync,
  readdirSync,
  realpathSync,
  rmSync,
  writeFileSync,
} from 'node:fs';
import os from 'node:os';
import { basename, dirname, join, relative, resolve, sep } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = realpathSync(resolve(dirname(fileURLToPath(import.meta.url)), '..'));
if (process.argv.length > 3) {
  throw new Error('Usage: node scripts/check-shared-ui-consumers.mjs [NEW_OUTPUT_DIRECTORY]');
}
let out;
if (process.argv[2]) {
  out = resolve(process.argv[2]);
  mkdirSync(out, { recursive: false });
} else {
  mkdirSync(join(root, '_build'), { recursive: true });
  out = mkdtempSync(join(root, '_build', 'shared-ui-consumers-'));
}
const temporary = mkdtempSync(join(os.tmpdir(), 'yami-shared-ui-consumers-'));
const slash = (path) => path.split(sep).join('/');
const hash = (data) => createHash('sha256').update(data).digest('hex');
const packages = ['ui/core', 'ui/runtime', 'examples/shared_counter'];
const commonPackages = packages.map((name) => `f4ah6o/yami_kumo/${name}`);
const forbiddenPublic =
  /\b(?:HTMLElement|ReactNode|JSValue|WindowHandle|SceneSnapshot)\b|@(?:gpui|dom)\.|#external\b/;
const read = (path) => readFileSync(path, 'utf8');
const git = (...args) => {
  const result = spawnSync('git', args, { cwd: root, encoding: 'utf8' });
  assert.equal(result.status, 0, `git ${args.join(' ')} failed: ${result.stderr ?? result.error}`);
  return result.stdout.trim();
};
const sourceNames = [
  'moon.mod',
  'scripts/check-shared-ui-consumers.mjs',
  'fixtures/shared-ui/contract-v1.json',
  ...packages.flatMap((dir) =>
    readdirSync(join(root, dir))
      .filter((name) => name.endsWith('.mbt') || name.endsWith('.mbti') || name === 'moon.pkg')
      .map((name) => `${dir}/${name}`),
  ),
].sort();
const snapshot = () =>
  Object.fromEntries(sourceNames.map((name) => [name, hash(readFileSync(join(root, name)))]));
const report = {
  version: 'shared-ui-consumers/v1',
  status: 'running',
  scope: 'Independent JS/native package consumers and pure model/runtime fixtures only',
  sourceRevision: git('rev-parse', 'HEAD'),
  sourceDirty: git('status', '--porcelain').length > 0,
  sourcePath: root,
  sourceHashes: snapshot(),
  commonSourceCopied: false,
  environment: {
    platform: process.platform,
    architecture: process.arch,
    release: os.release(),
    node: process.version,
  },
  startedAt: new Date().toISOString(),
  commands: [],
  consumers: [],
  notRun: ['DOM rendering', 'native windows', 'host input', 'IME', 'accessibility providers'],
};
const save = () => writeFileSync(join(out, 'report.json'), JSON.stringify(report, null, 2) + '\n');
const artifact = (path) => ({ path: slash(relative(out, path)), sha256: hash(readFileSync(path)) });
function run(name, command, args, cwd) {
  const stdoutPath = join(out, `${name}.stdout.log`);
  const stderrPath = join(out, `${name}.stderr.log`);
  const startedAt = new Date().toISOString();
  const result = spawnSync(command, args, {
    cwd,
    encoding: 'utf8',
    timeout: 120000,
    maxBuffer: 16 * 1024 * 1024,
  });
  writeFileSync(stdoutPath, result.stdout ?? '');
  writeFileSync(
    stderrPath,
    (result.stderr ?? '') + (result.error ? `\n${String(result.error)}\n` : ''),
  );
  const record = {
    name,
    command: [command, ...args],
    cwd,
    startedAt,
    finishedAt: new Date().toISOString(),
    exitCode: result.status,
    signal: result.signal,
    error: result.error ? String(result.error) : null,
    stdout: artifact(stdoutPath),
    stderr: artifact(stderrPath),
  };
  report.commands.push(record);
  save();
  assert.equal(result.status, 0, `${name} failed; see ${stderrPath}`);
  return result.stdout;
}
function filesUnder(directory) {
  return readdirSync(directory, { withFileTypes: true }).flatMap((entry) => {
    const path = join(directory, entry.name);
    return entry.isDirectory() ? filesUnder(path) : [path];
  });
}
function verifyPublic(text, packageName) {
  assert.ok(!forbiddenPublic.test(text), `Host-specific public type in ${packageName}`);
  for (const block of text.matchAll(/import\s*\{([\s\S]*?)\}/g)) {
    for (const [, dependency] of block[1].matchAll(/"([^"]+)"/g)) {
      assert.ok(
        commonPackages.includes(dependency) || dependency.startsWith('moonbitlang/core/'),
        `Unexpected public dependency ${dependency} in ${packageName}`,
      );
    }
  }
  if (packageName.endsWith('/ui/runtime')) {
    for (const name of ['Runtime', 'InstanceToken', 'FocusRequest', 'FocusResult']) {
      assert.match(
        text,
        new RegExp(`pub struct ${name} \\{\\s*// private fields\\s*\\}`),
        `${name} must not expose forgeable state`,
      );
    }
  }
}

// This is a host-free test driver, not an alternate copy of the application.
const bootstrap = String.raw`///|
fn ensure(condition : Bool, message : String) -> Unit {
  if !condition { abort(message) }
}

///|
fn commit(runtime : @runtime.Runtime, view : @core.View) -> Unit {
  ensure(runtime.commit(view) is Ok(_), "view commit rejected")
}

///|
fn emit(fixture : String, counts : Array[Int]) -> Unit {
  let values = counts.map(value => value.to_string()).join(",")
  println("{\"fixtureId\":\"" + fixture + "\",\"counts\":[" + values + "]}")
}

///|
// Test-only immutable gate transform; screen structure/text still comes from
// the imported application view, and update always uses the imported model.
fn gate(view : @core.View, disabled~ : Bool, loading~ : Bool) -> @core.View {
  match view.kind() {
    @core.Text => view
    @core.Button => @core.button(view.key(), view.label(), disabled~, loading~)
    @core.Column => @core.column(view.key(), view.children().map(child => gate(child, disabled~, loading~)))
    @core.Row => @core.row(view.key(), view.children().map(child => gate(child, disabled~, loading~)))
  }
}

///|
fn main {
  let runtime = @runtime.Runtime::new()
  let mut model = @shared_counter.Model::new()
  commit(runtime, model.view())
  let increment = runtime.token(@core.NodeKey::new("increment")).unwrap()
  let counts = [model.value()]
  for _ in 0..<2 {
    ensure(runtime.enqueue_activate(increment), "increment rejected")
    model = model.update(runtime.next_action().unwrap())
    commit(runtime, model.view())
    counts.push(model.value())
  }
  emit("counter-two-activations", counts)
  runtime.dispose()
  ensure(!runtime.enqueue_activate(increment), "disposed callback accepted")

  let gates = @runtime.Runtime::new()
  let mut gated_model = @shared_counter.Model::new()
  commit(gates, gated_model.view())
  let target = gates.token(@core.NodeKey::new("increment")).unwrap()
  let gated_counts = [gated_model.value()]
  commit(gates, gate(gated_model.view(), disabled=true, loading=false))
  ensure(!gates.enqueue_activate(target), "disabled activation accepted")
  ensure(gates.next_action() is None, "disabled action delivered")
  gated_counts.push(gated_model.value())
  commit(gates, gate(gated_model.view(), disabled=false, loading=true))
  ensure(!gates.enqueue_activate(target), "loading activation accepted")
  ensure(gates.next_action() is None, "loading action delivered")
  gated_counts.push(gated_model.value())
  commit(gates, gated_model.view())
  ensure(gates.enqueue_activate(target), "enabled activation rejected")
  gated_model = gated_model.update(gates.next_action().unwrap())
  commit(gates, gated_model.view())
  gated_counts.push(gated_model.value())
  emit("counter-disabled-loading", gated_counts)
  gates.dispose()
  let cards = @runtime.Runtime::new()
  let mut card_model = @shared_counter.Model::new()
  commit(cards, card_model.card_view())
  ensure(card_model.card_view().is_card(), "Card decoration missing")
  ensure(card_model.card_view().children() == card_model.view().children(), "counter view duplicated")
  let card_target = cards.token(@core.NodeKey::new("increment")).unwrap()
  let card_counts = [card_model.value()]
  for _ in 0..<2 {
    ensure(cards.enqueue_activate(card_target), "Card nested Button rejected")
    card_model = card_model.update(cards.next_action().unwrap())
    commit(cards, card_model.card_view())
    card_counts.push(card_model.value())
  }
  emit("card-counter-two-activations", card_counts)
  cards.dispose()
  let spacing_runtime = @runtime.Runtime::new()
  let mut spacing_model = @shared_counter.SpacingModel::new()
  commit(spacing_runtime, spacing_model.view())
  let spacing_counts = [spacing_model.value()]
  let spacing_increment = spacing_runtime.token(@core.NodeKey::new("increment")).unwrap()
  let spacing_toggle = spacing_runtime.token(@core.NodeKey::new("spacing-toggle")).unwrap()
  for target in [spacing_increment, spacing_toggle, spacing_increment, spacing_toggle] {
    ensure(spacing_runtime.enqueue_activate(target), "spacing Button rejected")
    spacing_model = spacing_model.update(spacing_runtime.next_action().unwrap())
    commit(spacing_runtime, spacing_model.view())
    ensure(spacing_runtime.is_current(spacing_increment), "increment identity changed")
    ensure(spacing_runtime.is_current(spacing_toggle), "toggle identity changed")
    spacing_counts.push(spacing_model.value())
  }
  emit("spacing-count-and-toggle", spacing_counts)
  spacing_runtime.dispose()
  let palette_runtime = @runtime.Runtime::new()
  let mut palette_model = @shared_counter.PaletteModel::new()
  commit(palette_runtime, palette_model.palette_view())
  let palette_counts = [palette_model.value()]
  let increment = palette_runtime.token(@core.NodeKey::new("increment")).unwrap()
  let toggle = palette_runtime.token(@core.NodeKey::new("palette-toggle")).unwrap()
  for target in [increment, toggle, increment, toggle, toggle] {
    ensure(palette_runtime.enqueue_activate(target), "palette action rejected")
    palette_model = palette_model.update_palette(palette_runtime.next_action().unwrap())
    commit(palette_runtime, palette_model.palette_view())
    ensure(palette_runtime.is_current(increment) && palette_runtime.is_current(toggle), "palette replaced identity")
    palette_counts.push(palette_model.value())
  }
  emit("palette-count-and-toggle", palette_counts)
  palette_runtime.dispose()

}
`;

save();
try {
  report.environment.moon = run('toolchain', 'moon', ['version', '--all'], root).trim();
  const contract = JSON.parse(read(join(root, 'fixtures/shared-ui/contract-v1.json')));
  const expected = new Map(contract.fixtures.map((fixture) => [fixture.id, fixture.expected]));
  report.contractVersion = contract.version;
  const moduleVersion = read(join(root, 'moon.mod')).match(/^version\s*=\s*"([^"]+)"/m)?.[1];
  assert.ok(moduleVersion, 'Source module version missing');
  writeFileSync(join(out, 'consumer-main.mbt'), bootstrap);
  report.bootstrap = artifact(join(out, 'consumer-main.mbt'));

  for (const target of ['js', 'native']) {
    const workspace = join(temporary, target);
    const consumer = join(workspace, 'consumer');
    const targetOut = join(out, target);
    mkdirSync(consumer, { recursive: true });
    mkdirSync(targetOut);
    const moduleName = `yami_shared_consumer/${target}`;
    const moduleManifest = `name = "${moduleName}"\nversion = "0.0.0"\nimport {\n  "f4ah6o/yami_kumo@${moduleVersion}",\n}\n`;
    const packageManifest = `import {\n${commonPackages.map((name) => `  "${name}",`).join('\n')}\n}\npkgtype(kind: "executable")\n`;
    const workspaceManifest = `members = [${JSON.stringify(slash(root))}, ${JSON.stringify(slash(consumer))}]\n`;
    writeFileSync(join(workspace, 'moon.work'), workspaceManifest);
    writeFileSync(join(consumer, 'moon.mod'), moduleManifest);
    writeFileSync(join(consumer, 'moon.pkg'), packageManifest);
    writeFileSync(join(consumer, 'main.mbt'), bootstrap);
    for (const [name, contents] of [
      ['moon.work', workspaceManifest],
      ['moon.mod', moduleManifest],
      ['moon.pkg', packageManifest],
    ]) {
      writeFileSync(join(targetOut, name), contents);
    }
    const build = join(targetOut, 'build');
    const args = [
      'build',
      consumer,
      '--target',
      target,
      '--release',
      '--deny-warn',
      '--target-dir',
      build,
    ];
    const plan = run(`${target}-plan`, 'moon', [...args, '--dry-run'], workspace);
    const plannedPackages = [...plan.matchAll(/\s-pkg\s+([^\s'"\r\n]+)/g)]
      .map((match) => match[1])
      .sort();
    assert.deepEqual(
      plannedPackages,
      [...commonPackages, moduleName].sort(),
      `${target} compilation must include only the neutral packages and consumer`,
    );
    const normalizedPlan = plan.replaceAll('\\', '/').toLowerCase();
    for (const source of packages) {
      assert.ok(
        normalizedPlan.includes(slash(join(root, source)).toLowerCase()),
        `${target} must compile the unchanged original source at ${source}`,
      );
    }
    run(`${target}-build`, 'moon', args, workspace);
    const buildRoot = join(build, target, 'release', 'build');
    const compiled = filesUnder(buildRoot)
      .filter((path) => path.endsWith('.core'))
      .map((path) => slash(relative(buildRoot, path)));
    const expectedCompiled = [...commonPackages, moduleName]
      .map((name) => `${name}/${basename(name)}.core`)
      .sort();
    assert.deepEqual(
      compiled.sort(),
      expectedCompiled,
      `${target} artifacts contain an unexpected package dependency`,
    );
    const compiledInterfaces = [];
    for (const packageName of commonPackages) {
      const interfacePath = join(buildRoot, packageName, `${basename(packageName)}.mi`);
      const actual = run(
        `${target}-${basename(packageName)}-interface`,
        'mooninfo',
        ['-format', 'text', interfacePath],
        workspace,
      );
      verifyPublic(actual, packageName);
      const packagePath = packages[commonPackages.indexOf(packageName)];
      const checkedIn = read(join(root, packagePath, 'pkg.generated.mbti'));
      assert.equal(
        actual.replaceAll('\r\n', '\n'),
        checkedIn.replaceAll('\r\n', '\n'),
        `Stale or target-dependent public interface: ${packageName}`,
      );
      compiledInterfaces.push({
        package: packageName,
        sourcePath: join(root, packagePath),
        checkedInSha256: hash(checkedIn),
        actualSha256: hash(actual),
      });
    }
    const artifactPath = join(buildRoot, moduleName, `${target}.${target === 'js' ? 'js' : 'exe'}`);
    assert.ok(existsSync(artifactPath), `Missing ${target} executable`);
    if (target === 'js') {
      const javascript = read(artifactPath);
      assert.ok(
        !/^\s*import\b|\brequire\s*\(|\bimport\s*\(/m.test(javascript),
        'Pure compiled JS must have no external runtime imports',
      );
      assert.ok(
        !/@cloudflare\/kumo|react-dom|\bReact\b|@zag-js|\bHTMLElement\b|\bgpui\b/i.test(javascript),
        'Host/framework content leaked into compiled JS',
      );
    }
    const output =
      target === 'js'
        ? run(`${target}-run`, process.execPath, [artifactPath], workspace)
        : run(`${target}-run`, artifactPath, [], workspace);
    const observations = output
      .trim()
      .split(/\r?\n/)
      .map((line) => JSON.parse(line));
    assert.deepEqual(
      observations.map((item) => item.fixtureId),
      [
        'counter-two-activations',
        'counter-disabled-loading',
        'card-counter-two-activations',
        'spacing-count-and-toggle',
        'palette-count-and-toggle',
      ],
    );
    for (const { fixtureId, ...observed } of observations) {
      assert.deepEqual(
        observed,
        expected.get(fixtureId),
        `${target} fixture mismatch: ${fixtureId}`,
      );
    }
    const catalogPath = join(buildRoot, 'all_pkgs.json');
    const catalog = JSON.parse(read(catalogPath));
    const coreArtifact = catalog.packages.find(
      (entry) => entry.root === 'moonbitlang/core',
    )?.artifact;
    assert.ok(coreArtifact, 'Compiler catalog must identify MoonBit core');
    const coreSource = coreArtifact.replaceAll('\\', '/').split('/_build/')[0];
    report.consumers.push({
      target,
      status: 'pass',
      workspacePath: workspace,
      consumerPath: consumer,
      explicitWorkspaceMembers: [root, consumer],
      compiledPackages: plannedPackages,
      compiledInterfaces,
      executable: artifact(artifactPath),
      catalog: artifact(catalogPath),
      observations,
      dependencies: [
        {
          name: 'f4ah6o/yami_kumo',
          version: moduleVersion,
          sourcePath: root,
          revision: report.sourceRevision,
          dirty: report.sourceDirty,
        },
        {
          name: 'moonbitlang/core',
          sourcePath: coreSource,
          toolchain: report.environment.moon,
          manifestSha256: existsSync(join(coreSource, 'moon.mod'))
            ? hash(readFileSync(join(coreSource, 'moon.mod')))
            : null,
        },
      ],
    });
    save();
  }
  report.sourceHashesAfter = snapshot();
  assert.deepEqual(
    report.sourceHashesAfter,
    report.sourceHashes,
    'Source changed during the consumer checks',
  );
  report.sourceRevisionEnd = git('rev-parse', 'HEAD');
  report.sourceDirtyEnd = git('status', '--porcelain').length > 0;
  report.status = 'pass';
} catch (error) {
  report.status = 'fail';
  report.error = String(error.stack ?? error);
  process.exitCode = 1;
} finally {
  report.finishedAt = new Date().toISOString();
  rmSync(temporary, { recursive: true, force: true });
  report.temporaryWorkspacesRemoved = true;
  save();
  console.log(`${report.status.toUpperCase()}: ${join(out, 'report.json')}`);
  if (report.error) console.error(report.error);
}
