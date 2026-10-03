export type ShellRegion =
  | 'header'
  | 'rail'
  | 'sidebar'
  | 'tabs'
  | 'main'
  | 'rightSidebar'
  | 'bottomBar';

export interface ShellLayoutOptions {
  hasSidebar?: boolean;
  hasTabs?: boolean;
  hasRightSidebar?: boolean;
  hasBottomBar?: boolean;
  sidebarCollapsed?: boolean;
}

export function resolveShellRegions({
  hasSidebar = true,
  hasTabs = true,
  hasRightSidebar = true,
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

  if (hasRightSidebar) {
    regions.push('rightSidebar');
  }

  if (hasBottomBar) {
    regions.push('bottomBar');
  }

  return regions;
}
