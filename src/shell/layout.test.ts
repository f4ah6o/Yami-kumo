import { describe, expect, it } from 'vitest';
import { resolveShellRegions } from './layout';

describe('resolveShellRegions', () => {
  it('keeps the default shell focused on navigation and main content', () => {
    expect(resolveShellRegions()).toEqual([
      'header',
      'rail',
      'sidebar',
      'tabs',
      'main',
      'bottomBar',
    ]);
  });

  it('adds a context panel only when the product has contextual content for it', () => {
    expect(resolveShellRegions({ hasContextPanel: true })).toContain('contextPanel');
  });

  it('removes optional regions without changing the main workspace', () => {
    expect(
      resolveShellRegions({
        hasSidebar: false,
        hasTabs: false,
        hasContextPanel: false,
        hasBottomBar: false,
      }),
    ).toEqual(['header', 'rail', 'main']);
  });

  it('treats a collapsed sidebar as visually absent', () => {
    expect(resolveShellRegions({ sidebarCollapsed: true })).not.toContain('sidebar');
  });
});
