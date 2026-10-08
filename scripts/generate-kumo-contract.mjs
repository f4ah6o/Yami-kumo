import React from 'react';
import { renderToStaticMarkup } from 'react-dom/server';
import { Button, Input, LayerCard, Text } from '@cloudflare/kumo';
import { mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { join } from 'node:path';

const sizes = ['xs', 'sm', 'base', 'lg'];
const buttonVariants = [
  'primary',
  'secondary',
  'ghost',
  'destructive',
  'secondary-destructive',
  'outline',
];
const inputVariants = ['default', 'error'];
const textVariants = ['heading', 'body', 'secondary', 'success', 'error', 'mono', 'mono-secondary'];

function className(markup, selector = /<[^>]*class="([^"]+)"/) {
  const match = markup.match(selector);
  if (!match) throw new Error(`Could not find class in Kumo markup: ${markup}`);
  return match[1];
}

function buttonInlineStyle(markup) {
  const match = markup.match(/<button\b[^>]*\bstyle="([^"]+)"/);
  if (!match) throw new Error(`Could not find Kumo emphasis styles: ${markup}`);
  return match[1];
}

function keyMatchFunction(name, entries) {
  const clauses = entries
    .map(([key, value]) => `    ${JSON.stringify(key)} => ${JSON.stringify(value)}`)
    .join('\n');
  return `fn ${name}(key : String) -> String {\n  match key {\n${clauses}\n    _ => ""\n  }\n}\n`;
}

const buttonClasses = [];
const buttonEmphasisStyles = [];
for (const size of sizes) {
  for (const variant of buttonVariants) {
    for (const disabled of [false, true]) {
      const markup = renderToStaticMarkup(
        React.createElement(Button, { size, variant, disabled }, 'Action'),
      );
      buttonClasses.push([`${variant}|${size}|${disabled}`, className(markup)]);
      if (size === 'base' && !disabled && ['primary', 'destructive'].includes(variant)) {
        buttonEmphasisStyles.push([variant, buttonInlineStyle(markup)]);
      }
    }
  }
}

const inputClasses = [];
for (const size of sizes) {
  for (const variant of inputVariants) {
    const props = { size, 'aria-label': 'Example' };
    if (variant === 'error') props.error = 'Invalid value';
    const markup = renderToStaticMarkup(React.createElement(Input, props));
    inputClasses.push([`${variant}|${size}`, className(markup, /<input\b[^>]*class="([^"]+)"/)]);
  }
}

const textClasses = [];
for (const size of sizes) {
  for (const variant of textVariants) {
    const markup = renderToStaticMarkup(React.createElement(Text, { size, variant }, 'Text'));
    textClasses.push([`${variant}|${size}`, className(markup)]);
  }
}

const simpleCard = renderToStaticMarkup(React.createElement(LayerCard, null, 'Card'));
const layeredCard = renderToStaticMarkup(
  React.createElement(LayerCard, null, [
    React.createElement(LayerCard.Secondary, { key: 'secondary' }, 'Section'),
    React.createElement(LayerCard.Primary, { key: 'primary' }, 'Content'),
  ]),
);
const layerCardClasses = [
  ['simple', className(simpleCard)],
  ['layered', className(layeredCard)],
  ['primary', ''],
  ['secondary', ''],
];

const sectionClasses = [...layeredCard.matchAll(/<div class="([^"]+)"/g)].map((match) => match[1]);
layerCardClasses[2][1] = sectionClasses[2];
layerCardClasses[3][1] = sectionClasses[1];

const kumoVersion = JSON.parse(
  readFileSync(new URL('../node_modules/@cloudflare/kumo/package.json', import.meta.url)),
).version;
const parityManifest = JSON.parse(
  readFileSync(new URL('../fixtures/kumo-cases.json', import.meta.url)),
);
if (parityManifest.kumoVersion !== kumoVersion) {
  throw new Error(
    `Parity fixture pins Kumo ${parityManifest.kumoVersion}, installed package is ${kumoVersion}`,
  );
}

const cases = parityManifest.cases ?? [];
const viewportIds = new Set((parityManifest.viewports ?? []).map((viewport) => viewport.id));
const ids = new Set();
for (const testCase of cases) {
  if (ids.has(testCase.id)) throw new Error(`Duplicate parity case id: ${testCase.id}`);
  ids.add(testCase.id);
  for (const interaction of testCase.interactions ?? []) {
    if (interaction.viewports === undefined) continue;
    if (
      !Array.isArray(interaction.viewports) ||
      interaction.viewports.length === 0 ||
      interaction.viewports.some((viewport) => !viewportIds.has(viewport))
    ) {
      throw new Error(
        `Parity interaction has invalid viewport applicability: ${testCase.id}/${interaction.type}`,
      );
    }
  }
}
const hasCase = (component, predicate) =>
  cases.some((testCase) => testCase.component === component && predicate(testCase));
for (const size of sizes) {
  for (const variant of buttonVariants) {
    for (const disabled of [false, true]) {
      if (
        !hasCase(
          'button',
          (testCase) =>
            testCase.props?.variant === variant &&
            testCase.props?.size === size &&
            Boolean(testCase.props?.disabled) === disabled,
        )
      ) {
        throw new Error(`Parity fixture is missing Button ${variant}/${size}/disabled=${disabled}`);
      }
    }
  }
  for (const variant of textVariants) {
    if (
      !hasCase(
        'text',
        (testCase) => testCase.props?.variant === variant && testCase.props?.size === size,
      )
    ) {
      throw new Error(`Parity fixture is missing Text ${variant}/${size}`);
    }
  }
  for (const state of ['default', 'error', 'disabled']) {
    if (
      !hasCase('input', (testCase) => {
        const props = testCase.props ?? {};
        return (
          props.size === size &&
          (state === 'default'
            ? props.variant === 'default' && !props.disabled && !props.error
            : state === 'error'
              ? props.variant === 'error' && Boolean(props.error) && !props.disabled
              : Boolean(props.disabled))
        );
      })
    ) {
      throw new Error(`Parity fixture is missing Input ${state}/${size}`);
    }
  }
}
const requiresInteraction = (component, type) =>
  hasCase(component, (testCase) => testCase.interactions?.some((item) => item.type === type));
for (const [component, type] of [
  ['button', 'click'],
  ['button', 'press'],
  ['input', 'fill'],
  ['appShell', 'press'],
]) {
  if (!requiresInteraction(component, type)) {
    throw new Error(`Parity fixture is missing a ${type} interaction for ${component}`);
  }
}
const multipleInputCase = cases.find(
  (testCase) => testCase.component === 'input' && testCase.props?.grouped === true,
);
if (
  !multipleInputCase ||
  !multipleInputCase.props?.firstId ||
  !multipleInputCase.props?.secondId ||
  multipleInputCase.props.firstId === multipleInputCase.props.secondId ||
  !multipleInputCase.props?.firstDescription ||
  !multipleInputCase.props?.secondError
) {
  throw new Error('Parity fixture must include two uniquely identified linked Input fields.');
}
if (
  !hasCase(
    'input',
    (testCase) =>
      testCase.props?.id === 'parity-search-field' &&
      testCase.props?.ariaLabel &&
      !testCase.props?.label &&
      !testCase.props?.description &&
      !testCase.props?.error,
  )
) {
  throw new Error('Parity fixture must cover an unlabeled Input retaining its explicit id.');
}

const generated = [
  '// Generated from the pinned @cloudflare/kumo package. Do not edit by hand.',
  `// Kumo version: ${kumoVersion}`,
  '///|',
  keyMatchFunction('generated_button_classes', buttonClasses),
  '///|',
  keyMatchFunction('generated_input_classes', inputClasses),
  '///|',
  keyMatchFunction('generated_text_classes', textClasses),
  '///|',
  keyMatchFunction('generated_layer_card_class', layerCardClasses),
].join('\n');

function formatMoonBit(source) {
  const projectRoot = fileURLToPath(new URL('../', import.meta.url));
  const directory = mkdtempSync(join(projectRoot, 'scripts/.kumo-contract-format-'));
  const path = join(directory, 'contract.mbt');
  try {
    writeFileSync(join(directory, 'moon.pkg'), '');
    writeFileSync(path, source);
    const result = spawnSync('moon', ['fmt', path], { cwd: projectRoot, encoding: 'utf8' });
    if (result.status !== 0) {
      throw new Error(result.stderr || result.stdout || 'moon fmt failed');
    }
    return readFileSync(path, 'utf8');
  } finally {
    rmSync(directory, { recursive: true, force: true });
  }
}

const formattedGenerated = formatMoonBit(generated);

const generatedComponentStyles = [
  '/* Generated from real React Kumo SSR output; values are moved from its inline style into strict-CSP-safe classes. */',
  `/* Kumo version: ${kumoVersion} */`,
  ...buttonEmphasisStyles.map(([variant, style]) => {
    const className =
      variant === 'primary'
        ? 'yk-kumo-button-emphasis-primary'
        : 'yk-kumo-button-emphasis-destructive';
    return `.${className}{${style}}`;
  }),
  '',
].join('\n');

const output = new URL('../kumo_contract.generated.mbt', import.meta.url);
const componentStylesOutput = new URL('../styles/yami-kumo-components.css', import.meta.url);
const standaloneStylesOutput = new URL('../styles/kumo-standalone.css', import.meta.url);
const generatedVersionModule = `// Generated by scripts/generate-kumo-contract.mjs.\nexport const kumoVersion = '${kumoVersion}';\n`;
const standaloneStyles = readFileSync(
  new URL('../node_modules/@cloudflare/kumo/dist/styles/kumo-standalone.css', import.meta.url),
  'utf8',
);
if (process.argv.includes('--check')) {
  const current = readFileSync(output, 'utf8');
  const currentComponentStyles = readFileSync(componentStylesOutput, 'utf8');
  const currentStandaloneStyles = readFileSync(standaloneStylesOutput, 'utf8');
  const currentVersionModule = readFileSync(
    new URL('../src/kumo-version.generated.ts', import.meta.url),
    'utf8',
  );
  if (current !== formattedGenerated) {
    console.error('kumo_contract.generated.mbt is stale; run `pnpm run generate:kumo-contract`.');
    process.exitCode = 1;
  }
  if (currentComponentStyles !== generatedComponentStyles) {
    console.error(
      'styles/yami-kumo-components.css is stale; run `pnpm run generate:kumo-contract`.',
    );
    process.exitCode = 1;
  }
  if (currentStandaloneStyles !== standaloneStyles) {
    console.error('styles/kumo-standalone.css is stale; run `pnpm run generate:kumo-contract`.');
    process.exitCode = 1;
  }
  if (currentVersionModule !== generatedVersionModule) {
    console.error('src/kumo-version.generated.ts is stale; run `pnpm run generate:kumo-contract`.');
    process.exitCode = 1;
  }
} else {
  writeFileSync(output, formattedGenerated);
  writeFileSync(componentStylesOutput, generatedComponentStyles);
  writeFileSync(standaloneStylesOutput, standaloneStyles);
  writeFileSync(
    new URL('../src/kumo-version.generated.ts', import.meta.url),
    generatedVersionModule,
  );
}
