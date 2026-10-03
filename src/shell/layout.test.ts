import { describe, expect, it } from 'vitest';
import { resolveShellRegions } from './layout';

describe('resolveShellRegions', () => {
  it('starts with only the durable frame and main task', () => {
    expect(resolveShellRegions()).toEqual(['header', 'main']);
  });

  it('composes optional regions independently', () => {
    expect(
      resolveShellRegions({
        hasRail: true,
        hasSidebar: true,
        hasTabs: true,
        hasContextPanel: true,
        hasBottomBar: true,
      }),
    ).toEqual(['header', 'rail', 'sidebar', 'tabs', 'main', 'contextPanel', 'bottomBar']);
  });

  it('treats a collapsed sidebar as visually absent', () => {
    expect(resolveShellRegions({ hasSidebar: true, sidebarCollapsed: true })).not.toContain(
      'sidebar',
    );
  });
});
