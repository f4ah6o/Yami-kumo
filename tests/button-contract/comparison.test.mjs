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
test('held state without a changed native Button scene is a visual gap', () => {
  const native = trace();
  native.phases[1].pressed = true;
  const web = trace();
  web.phases[1].pressed = true;
  assert.equal(compareStyles(web, native).status, 'gap-detected');
  assert.equal(compareCase(specification, web, native).status, 'matched');
});
