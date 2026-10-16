import {
  appShell,
  button,
  input,
  textComponent,
  layerCard,
  fragment,
  renderHtml,
} from '@f4ah6o/yami-kumo';
import { enhanceYamiKumo } from '@f4ah6o/yami-kumo/dom';
import '@f4ah6o/yami-kumo/styles.css';

document.querySelector('#app').innerHTML = renderHtml(
  appShell({
    brand: 'Packed browser',
    navigationTrigger: button('Menu', { attrs: { id: 'menu' } }),
    rail: 'Rail',
    sidebar: 'Navigation',
    tabs: 'Tabs',
    contextPanel: 'Details',
    bottomBar: 'Ready',
    children: fragment([
      textComponent('Account', { variant: 'heading' }),
      layerCard(
        input({
          id: 'email',
          label: 'Email',
          description: 'Enter email',
          attrs: { type: 'email' },
        }),
      ),
      input({
        id: 'other',
        label: 'Other',
        error: 'Error detail',
        attrs: { type: 'email', 'aria-invalid': 'false' },
      }),
      ...['primary', 'secondary', 'ghost', 'destructive', 'secondary-destructive', 'outline'].map(
        (variant) => button(variant, { variant, attrs: { 'data-variant': variant } }),
      ),
      button('Disabled', { disabled: true, attrs: { id: 'disabled' } }),
    ]),
  }),
);
let activations = 0;
document.querySelector('[data-variant="primary"]').addEventListener('click', () => {
  document.body.dataset.activations = String(++activations);
});
document.querySelector('#menu').addEventListener('click', () => {
  document.querySelector('.yk-shell').dataset.mobileSidebarOpen = 'true';
});
document.querySelector('.yk-sidebar-scrim').addEventListener('click', () => {
  document.querySelector('.yk-shell').dataset.mobileSidebarOpen = 'false';
});
enhanceYamiKumo();
enhanceYamiKumo();
document.body.dataset.ready = 'true';
