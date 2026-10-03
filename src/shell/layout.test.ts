import { describe, expect, it } from 'vitest';
import { resolveShellRegions } from './layout';

describe('resolveShellRegions', () => {
  it('returns the canonical desktop shell regions', () => {
    expect(resolveShellRegions()).toEqual([
      'header',
      'rail',
      'sidebar',
      'tabs',
      'main',
      'rightSidebar',
      'bottomBar',
    ]);
  });

  it('removes optional regions without changing the main workspace', () => {
    expect(
      resolveShellRegions({
        hasSidebar: false,
        hasTabs: false,
        hasRightSidebar: false,
        hasBottomBar: false,
      }),
    ).toEqual(['header', 'rail', 'main']);
  });

  it('treats a collapsed sidebar as visually absent', () => {
    expect(resolveShellRegions({ sidebarCollapsed: true })).not.toContain(
      'sidebar',
    );
  });
});
