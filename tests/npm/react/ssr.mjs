import assert from 'node:assert/strict';
import { createElement } from 'react';
import { renderToString } from 'react-dom/server';
import { AppShell } from '@f12o/yami-kumo/react';
const html = renderToString(
  createElement(AppShell, { brand: 'React SSR', children: createElement('button', null, 'Child') }),
);
assert.match(html, /<button>Child<\/button>/);
assert.match(html, /yk-main/);
console.log('PASS React SSR with consumer React instance');
