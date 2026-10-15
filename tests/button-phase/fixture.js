import React, { useState } from 'react';
import { createRoot } from 'react-dom/client';
import { Button } from '@cloudflare/kumo/components/button';
import '@cloudflare/kumo/styles/standalone';

// An observer of the real pinned component. No synthetic DOM input/default
// action implementation or expected event trace is installed in the fixture.
const token = new URL(location.href).searchParams.get('run_token');
const disabled = new URL(location.href).searchParams.get('disabled') === '1';
const loading = new URL(location.href).searchParams.get('loading') === '1';
const events = [];
const actions = [];
let repaint;
for (const type of [
  'pointerdown',
  'pointerup',
  'keydown',
  'keyup',
  'click',
  'focusin',
  'focusout',
]) {
  document.addEventListener(
    type,
    (event) => {
      events.push({
        type,
        target: event.target.id,
        target_button: event.target.closest?.('button')?.id ?? null,
        key: event.key ?? null,
        repeat: event.repeat ?? null,
        button: event.button ?? null,
        is_trusted: event.isTrusted,
        time_ms: performance.now(),
      });
    },
    true,
  );
}
function Fixture() {
  const [count, setCount] = useState(0);
  const [generation, setGeneration] = useState(0);
  repaint = () => setGeneration((value) => value + 1);
  return React.createElement(
    'main',
    { style: { padding: '40px' }, 'data-generation': generation },
    React.createElement(
      Button,
      {
        id: 'target',
        size: 'base',
        variant: 'primary',
        disabled,
        loading,
        onClick: (event) => {
          actions.push({
            type: event.type,
            detail: event.detail,
            is_trusted: event.isTrusted,
            time_ms: performance.now(),
          });
          setCount((value) => value + 1);
        },
      },
      'Action',
    ),
    React.createElement('button', { id: 'outside', style: { marginTop: '40px' } }, 'Outside'),
    React.createElement('output', { id: 'action-count' }, count),
  );
}
createRoot(document.getElementById('fixture-root')).render(React.createElement(Fixture));
window.phaseFixture = {
  repaint: () => repaint(),
  snapshot: () => {
    const button = document.getElementById('target');
    if (!button) return null;
    const rect = button.getBoundingClientRect();
    const style = getComputedStyle(button);
    return {
      run_token: token,
      disabled: button.disabled,
      loading,
      tag: button.tagName,
      component: button.dataset.kumoComponent,
      action_count: Number(document.getElementById('action-count').textContent),
      focused: document.activeElement === button,
      focus_visible: button.matches(':focus-visible'),
      pressed: button.matches(':active'),
      hovered: button.matches(':hover'),
      bounds: [rect.x, rect.y, rect.width, rect.height],
      repaint_generation: Number(document.querySelector('main').dataset.generation),
      computed: {
        background: style.backgroundColor,
        background_image: style.backgroundImage,
        color: style.color,
        box_shadow: style.boxShadow,
        outline_style: style.outlineStyle,
        outline_width: style.outlineWidth,
        transform: style.transform,
        layers: Array.from(button.children, (child) => {
          const layer = getComputedStyle(child);
          return {
            background: layer.backgroundColor,
            background_image: layer.backgroundImage,
            box_shadow: layer.boxShadow,
          };
        }),
      },
      events: events.slice(),
      actions: actions.slice(),
    };
  },
};
