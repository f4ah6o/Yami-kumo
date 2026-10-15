import assert from 'node:assert/strict';
import { test } from 'node:test';
import { compareCase, compareStyles, loadFixtures } from '../../scripts/button_contract.mjs';

const fixture = loadFixtures(new URL('./fixtures.json', import.meta.url));
const specification = { id: 'enter-repeat', steps: ['enter-down', 'enter-repeat', 'enter-up'] };
const phase = (index, name, count, delta) => ({
  index,
  phase: name,
  activation_count: count,
  activation_delta: delta,
  activation_event: delta > 0,
  focused: true,
  pressed: false,
  hovered: false,
  focus_visible: false,
  disabled: false,
  loading: false,
  events: delta ? [{ type: 'click', target_button: 'target' }] : [],
  computed: {},
  scene: { items: [{ id: 40, color: 'blue' }] },
});
const trace = () => ({
  status: 'observed',
  phases: [
    phase(0, 'initial', 0, 0),
    phase(1, 'enter-down', 1, 1),
    phase(2, 'enter-repeat', 2, 1),
    phase(3, 'enter-up', 2, 0),
  ],
});

test('the shared suite covers Enter/repeat, Space/release, disabled, loading, cancel and focus loss', () => {
  for (const id of ['enter-repeat', 'space-repeat', 'disabled', 'loading', 'cancel', 'focus-loss'])
    assert(fixture.cases.some((item) => item.id === id));
  assert(fixture.cases.filter((item) => item.host).length >= 4);
});
test('phase comparison detects delayed Enter activation and lost repeat', () => {
  const native = trace();
  native.phases[1].activation_delta = 0;
  native.phases[1].activation_event = false;
  native.phases[1].activation_count = 0;
  assert.equal(compareCase(specification, trace(), native).status, 'diverged');
  const repeat = trace();
  repeat.phases[2].activation_count = 1;
  repeat.phases[2].activation_delta = 0;
  assert.equal(compareCase(specification, trace(), repeat).status, 'diverged');
});
test('missing, reordered and malformed observations cannot match', () => {
  for (const mutate of [
    (value) => value.phases.pop(),
    (value) => value.phases.reverse(),
    (value) => delete value.phases[1].pressed,
  ]) {
    const native = trace();
    mutate(native);
    assert.throws(() => compareCase(specification, trace(), native));
  }
  assert.equal(
    compareCase(specification, trace(), { status: 'unsupported', reason: 'loading unavailable' })
      .status,
    'unverified',
  );
});
test('activation on the wrong event phase and lost focus cannot match', () => {
  const web = trace();
  web.phases[1].events = [];
  assert.equal(compareCase(specification, web, trace()).status, 'diverged');
  const native = trace();
  native.phases[1].focused = false;
  assert.equal(compareCase(specification, trace(), native).status, 'diverged');
});
test('unchanged Web press feedback does not require an invented Native palette', () => {
  const native = trace();
  native.phases[1].pressed = true;
  const web = trace();
  web.phases[1].pressed = true;
  assert.equal(compareStyles(web, native).status, 'matched-feedback');
  assert.equal(compareCase(specification, web, native).status, 'matched');
});

test('missing hover/focus feedback and a Native-only pressed color cannot match', () => {
  const web = trace();
  web.phases[1].computed = { layers: [{ background_image: 'hover gradient' }] };
  assert.equal(compareStyles(web, trace()).status, 'gap-detected');
  const native = trace();
  native.phases[1].scene.items[0].color = 'invented pressed color';
  assert.equal(compareStyles(trace(), native).status, 'gap-detected');
});

test('changed scenes with frozen GPU feedback and spurious GPU changes cannot match', () => {
  const web = trace(),
    native = trace();
  for (const phase of native.phases) phase.gpu_button_sha256 = 'same-frame';
  web.phases[1].computed = { box_shadow: 'focus ring 2px' };
  native.phases[1].scene.items[0].color = 'focus ring';
  assert.equal(compareStyles(web, native).status, 'gap-detected');
  const stable = trace();
  for (const phase of stable.phases) phase.gpu_button_sha256 = 'same-frame';
  stable.phases[1].gpu_button_sha256 = 'spurious-change';
  assert.equal(compareStyles(trace(), stable).status, 'gap-detected');
});

test('disabled visual differences stay unsupported and missing loading observations unverified', () => {
  const web = trace(),
    native = trace();
  for (const phase of web.phases) phase.disabled = true;
  assert.equal(compareStyles(web, native).status, 'unsupported-disabled-style');
  assert.equal(compareStyles(web, { status: 'unsupported' }).status, 'unverified');
});
