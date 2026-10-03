export type ShellRegion =
  | 'header'
  | 'rail'
  | 'sidebar'
  | 'tabs'
  | 'main'
  | 'contextPanel'
  | 'bottomBar';

export interface ShellLayoutOptions {
  hasSidebar?: boolean;
  hasTabs?: boolean;
  hasContextPanel?: boolean;
  hasBottomBar?: boolean;
  sidebarCollapsed?: boolean;
}

export function resolveShellRegions({
  hasSidebar = true,
  hasTabs = true,
  hasContextPanel = false,
  hasBottomBar = true,
  sidebarCollapsed = false,
}: ShellLayoutOptions = {}): ShellRegion[] {
  const regions: ShellRegion[] = ['header', 'rail'];

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
