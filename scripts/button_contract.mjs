import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { readFileSync } from 'node:fs';

export function loadFixtures(path) {
  const suite = JSON.parse(readFileSync(path, 'utf8'));
  assert.equal(suite.version, 1);
  assert.equal(suite.component, 'Button');
  const operations = new Set([
    'pointer-down',
    'pointer-up',
    'pointer-up-outside',
    'enter-down',
    'enter-repeat',
    'enter-up',
    'space-down',
    'space-repeat',
    'space-up',
    'repaint',
    'focus-loss',
  ]);
  const ids = new Set();
  assert(suite.cases.length > 0);
  for (const item of suite.cases) {
    assert(typeof item.id === 'string' && !ids.has(item.id));
    ids.add(item.id);
    assert.equal(typeof item.disabled, 'boolean');
    assert.equal(typeof item.loading, 'boolean');
    assert(item.steps.length > 0 && item.steps.every((step) => operations.has(step)));
  }
  return suite;
}

export const sha256 = (data) => createHash('sha256').update(data).digest('hex');

export function compareCase(specification, web, native) {
  const phases = ['initial', ...specification.steps];
  const result = { id: specification.id, status: 'unverified', differences: [], phases: [] };
  if (web.status !== 'observed' || native.status !== 'observed') {
    result.reason = native.reason ?? web.reason ?? 'Missing observations';
    return result;
  }
  assert.equal(web.phases.length, phases.length, 'Incomplete Web phase trace');
  assert.equal(native.phases.length, phases.length, 'Incomplete Native phase trace');
  for (const [index, phase] of phases.entries()) {
    const left = web.phases[index];
    const right = native.phases[index];
    for (const trace of [left, right]) {
      assert.equal(trace.index, index);
      assert.equal(trace.phase, phase);
      for (const field of ['activation_count', 'activation_delta'])
        assert(Number.isSafeInteger(trace[field]) && trace[field] >= 0, field);
      for (const field of ['focused', 'pressed', 'disabled', 'loading'])
        assert.equal(typeof trace[field], 'boolean', field);
    }
    const differences = [];
    for (const field of [
      'activation_count',
      'activation_delta',
      'focused',
      'pressed',
      'disabled',
      'loading',
    ]) {
      if (left[field] !== right[field])
        differences.push({ field, web: left[field], native: right[field] });
    }
    assert.equal(typeof right.activation_event, 'boolean');
    const webActions = left.events.filter(
      (event) => event.type === 'click' && event.target_button === 'target',
    );
    if (
      webActions.length !== right.activation_delta ||
      right.activation_event !== right.activation_delta > 0
    ) {
      differences.push({
        field: 'activation_event_phase',
        web: webActions,
        native: right.activation_event,
      });
    }
    result.phases.push({
      index,
      phase,
      status: differences.length ? 'diverged' : 'matched',
      differences,
    });
    result.differences.push(...differences.map((value) => ({ index, phase, ...value })));
  }
  result.status = result.differences.length ? 'diverged' : 'matched';
  return result;
}

export function compareStyles(web, native) {
  if (web.status !== 'observed' || native.status !== 'observed') return { status: 'unverified' };
  const observations = web.phases.map((phase, index) => {
    const nativePhase = native.phases[index];
    const surface = nativePhase.scene.items.filter((item) => item.id >= 40 && item.id <= 45);
    assert(
      surface.some((item) => item.id === 40),
      'Native Button scene surface is missing',
    );
    return {
      index,
      phase: phase.phase,
      web_pressed: phase.pressed,
      native_pressed: nativePhase.pressed,
      web_computed: phase.computed,
      native_surface_sha256: sha256(JSON.stringify(surface)),
      native_surface: surface,
    };
  });
  const resting = observations.find((item) => !item.web_pressed && !item.native_pressed);
  const held = observations.filter((item) => item.web_pressed || item.native_pressed);
  const noNativeChange =
    resting &&
    held.some(
      (item) => item.native_pressed && item.native_surface_sha256 === resting.native_surface_sha256,
    );
  return {
    status: noNativeChange ? 'gap-detected' : held.length ? 'observed' : 'not-exercised',
    reason: noNativeChange
      ? 'Native scene does not change its Button surface while pressed; no GPU/style parity claim'
      : 'Computed Web style and Native scene retained separately; raster/color equivalence is not inferred',
    observations,
  };
}
