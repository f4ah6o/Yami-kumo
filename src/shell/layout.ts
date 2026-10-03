export type ShellRegion =
  | 'header'
  | 'rail'
  | 'sidebar'
  | 'tabs'
  | 'main'
  | 'contextPanel'
  | 'bottomBar';

export interface ShellLayoutOptions {
  hasRail?: boolean;
  hasSidebar?: boolean;
  hasTabs?: boolean;
  hasContextPanel?: boolean;
  hasBottomBar?: boolean;
  sidebarCollapsed?: boolean;
}

export function resolveShellRegions({
  hasRail = false,
  hasSidebar = false,
  hasTabs = false,
  hasContextPanel = false,
  hasBottomBar = false,
  sidebarCollapsed = false,
}: ShellLayoutOptions = {}): ShellRegion[] {
  const regions: ShellRegion[] = ['header'];

  if (hasRail) {
    regions.push('rail');
  }

  if (hasSidebar && !sidebarCollapsed) {
    regions.push('sidebar');
  }

  if (hasTabs) {
    regions.push('tabs');
  }

  regions.push('main');

  if (hasContextPanel) {
    regions.push('contextPanel');
  }

  if (hasBottomBar) {
    regions.push('bottomBar');
  }

  return regions;
}
