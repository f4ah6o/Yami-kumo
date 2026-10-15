import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { readFileSync } from 'node:fs';

export function loadFixtures(path) {
  const suite = JSON.parse(readFileSync(path, 'utf8'));
  assert.equal(suite.version, 1);
  assert.equal(suite.component, 'Button');
  const operations = new Set([
    'pointer-down',
    'pointer-hover',
    'pointer-away',
    'keyboard-focus',
    'control-key',
    'alt-key',
    'meta-key',
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
      for (const field of ['focused', 'pressed', 'disabled', 'loading', 'hovered', 'focus_visible'])
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
      'hovered',
      'focus_visible',
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
  assert.equal(web.phases.length, native.phases.length, 'Incomplete visual phase trace');
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
      web_hovered: phase.hovered,
      native_hovered: nativePhase.hovered,
      web_focus_visible: phase.focus_visible,
      native_focus_visible: nativePhase.focus_visible,
      web_computed: phase.computed,
      web_style_sha256: sha256(JSON.stringify(phase.computed)),
      native_surface_sha256: sha256(JSON.stringify(surface)),
      native_surface: surface,
      native_gpu_button_sha256: nativePhase.gpu_button_sha256,
    };
  });
  const transitions = observations.slice(1).map((item, offset) => {
    const previous = observations[offset];
    const webChanged = item.web_style_sha256 !== previous.web_style_sha256;
    const sceneChanged = item.native_surface_sha256 !== previous.native_surface_sha256;
    const gpuChanged =
      item.native_gpu_button_sha256 === undefined
        ? undefined
        : item.native_gpu_button_sha256 !== previous.native_gpu_button_sha256;
    return {
      index: item.index,
      phase: item.phase,
      web_style_changed: webChanged,
      native_scene_changed: sceneChanged,
      native_gpu_button_changed: gpuChanged,
      status:
        webChanged === sceneChanged && (gpuChanged === undefined || gpuChanged === webChanged)
          ? 'matched-feedback'
          : 'diverged',
    };
  });
  const disabled = web.phases.some((phase) => phase.disabled);
  return {
    status: disabled
      ? 'unsupported-disabled-style'
      : transitions.some((item) => item.status === 'diverged')
        ? 'gap-detected'
        : 'matched-feedback',
    reason:
      'Temporal feedback compares actual Web CSS changes (including the decorative gradient) with Native scene/GPU changes; unchanged Web press feedback must stay unchanged in Native',
    raster_equivalence: 'unverified',
    native_representation: 'flat-gradient-midpoint-and-square-ring',
    transitions,
    observations,
  };
}
