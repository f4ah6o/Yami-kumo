import { spawnSync } from 'node:child_process';
import { readFile, writeFile, mkdir, rm, copyFile } from 'node:fs/promises';
import { createHash } from 'node:crypto';
import { fileURLToPath } from 'node:url';
import postcss from 'postcss';

const root = fileURLToPath(new URL('../', import.meta.url));
process.chdir(root);
function run(command, args) {
  const result = spawnSync(command, args, {
    cwd: root,
    encoding: 'utf8',
    shell: process.platform === 'win32',
  });
  if (result.status !== 0)
    throw new Error(`${command} failed: ${result.stderr || result.stdout || result.error}`);
  return result.stdout.trim();
}
const out = 'dist/npm';
await rm(out, { recursive: true, force: true });
await mkdir(`${out}/licenses`, { recursive: true });
for (const target of ['bridge', 'dom'])
  run('moon', ['build', `npm/${target}`, '--target', 'js', '--release']);
run('node', ['node_modules/typescript/bin/tsc', '-p', 'npm/tsconfig.json']);
run('node', [
  'node_modules/typescript/bin/tsc',
  'src/shell/AppShell.tsx',
  '--target',
  'ES2022',
  '--module',
  'ESNext',
  '--moduleResolution',
  'Bundler',
  '--jsx',
  'react-jsx',
  '--declaration',
  '--outDir',
  'dist/npm-react',
]);
for (const [from, to] of [
  ['_build/js/release/build/npm/bridge/bridge.js', 'moonbit.js'],
  ['_build/js/release/build/npm/dom/dom.js', 'dom.js'],
  ['dist/npm-react/AppShell.js', 'react.js'],
  ['dist/npm-react/AppShell.d.ts', 'react.d.ts'],
  ['npm/package.json', 'package.json'],
  ['npm/README.md', 'README.md'],
  ['LICENSE', 'LICENSE'],
  ['ACKNOWLEDGEMENTS.md', 'ACKNOWLEDGEMENTS.md'],
  ['licenses/cloudflare-kumo-LICENSE', 'licenses/cloudflare-kumo-LICENSE'],
  ['licenses/moonbit-core-LICENSE', 'licenses/moonbit-core-LICENSE'],
  ['licenses/moonbit-core-NOTICE', 'licenses/moonbit-core-NOTICE'],
  ['licenses/tailwindcss-LICENSE', 'licenses/tailwindcss-LICENSE'],
])
  await copyFile(from, `${out}/${to}`);
await writeFile(`${out}/dom.d.ts`, 'export declare function enhanceYamiKumo(): void;\n');

const css = postcss.parse(await readFile('styles/kumo-standalone.css', 'utf8'));
css.walkAtRules('layer', (layer) => {
  if (layer.params !== 'base') return;
  const scope = postcss.atRule({ name: 'scope', params: '(:where(.yk-scope, .yk-shell))' });
  // Do not iterate the live list: removing reset rules would skip their siblings.
  for (const item of layer.nodes.slice()) {
    if (
      item.type === 'rule' &&
      item.nodes.every((decl) => decl.type === 'decl' && decl.prop.startsWith('--'))
    )
      continue;
    item.remove();
    if (item.type === 'rule')
      item.selector = item.selector.replace(/\bhtml\b|:host|:root/g, ':scope');
    scope.append(item);
  }
  layer.append(scope);
});
await writeFile(
  `${out}/styles.css`,
  [
    css.toString(),
    await readFile('styles/yami-kumo-components.css', 'utf8'),
    await readFile('styles/yami-kumo-shell.css', 'utf8'),
  ].join('\n'),
);
const manifest = JSON.parse(await readFile('npm/package.json', 'utf8'));
const moonModule = await readFile('moon.mod', 'utf8');
const workflow = await readFile('.github/workflows/ci.yml', 'utf8');
const inputs = [
  'moon.mod',
  'pnpm-lock.yaml',
  'kumo_contract.generated.mbt',
  'styles/kumo-standalone.css',
];
const hashes = {};
for (const file of inputs)
  hashes[file] = createHash('sha256')
    .update(await readFile(file))
    .digest('hex');
await writeFile(
  `${out}/BUILD.json`,
  JSON.stringify(
    {
      version: manifest.version,
      mooncakesVersion: moonModule.match(/^version\s*=\s*"([^"]+)"/m)[1],
      kumoVersion: '2.14.0',
      sourceSha: run('git', ['rev-parse', 'HEAD']),
      sourceDirty: Boolean(run('git', ['status', '--porcelain'])),
      compiler: run('moon', ['version', '--all']),
      ciCompilerPin: workflow.match(/^\s+version: (0\.[^\s]+)$/m)[1],
      ciCorePin: workflow.match(/^\s+core-version: ([^\s]+)$/m)[1],
      hashes,
    },
    null,
    2,
  ) + '\n',
);
console.log(`Built ${manifest.name}@${manifest.version} in ${out}`);
