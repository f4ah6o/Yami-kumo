import { appShell, button, fragment, input, renderHtml, type Html } from '@f4ah6o/yami-kumo';
import { enhanceYamiKumo } from '@f4ah6o/yami-kumo/dom';
const node: Html = appShell({
  brand: 'Brand',
  children: fragment([
    button('Save', { variant: 'primary' }),
    input({ id: 'email', required: true }),
  ]),
});
const html: string = renderHtml(node);
void html;
void enhanceYamiKumo;
// @ts-expect-error Unsupported Button variant.
button('Bad', { variant: 'unknown' });
// @ts-expect-error Input IDs are required.
input({ label: 'No ID' });
// @ts-expect-error Html nodes cannot be forged.
renderHtml({});
// @ts-expect-error React-only callbacks are not in the plain HTML API.
appShell({ brand: 'Brand', children: 'Main', onContextPanelDismiss: () => {} });
