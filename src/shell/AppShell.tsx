import type { ReactNode } from 'react';

export interface AppShellProps {
  brand: ReactNode;
  globalSearch?: ReactNode;
  headerActions?: ReactNode;
  rail: ReactNode;
  sidebar?: ReactNode;
  tabs?: ReactNode;
  rightSidebar?: ReactNode;
  bottomBar?: ReactNode;
  children: ReactNode;
  sidebarCollapsed?: boolean;
  rightSidebarOpen?: boolean;
}

export function AppShell({
  brand,
  globalSearch,
  headerActions,
  rail,
  sidebar,
  tabs,
  rightSidebar,
  bottomBar,
  children,
  sidebarCollapsed = false,
  rightSidebarOpen = true,
}: AppShellProps) {
  return (
    <div
      className="yk-shell"
      data-sidebar-collapsed={sidebarCollapsed}
      data-has-sidebar={Boolean(sidebar)}
      data-has-right-sidebar={Boolean(rightSidebar)}
      data-right-sidebar-open={rightSidebarOpen}
    >
      <header className="yk-topbar">
        <div className="yk-brand">{brand}</div>
        <div className="yk-global-search">{globalSearch}</div>
        <div className="yk-header-actions">{headerActions}</div>
      </header>

      <nav className="yk-rail" aria-label="Primary">
        {rail}
      </nav>

      {sidebar ? (
        <aside className="yk-sidebar" aria-label="Workspace navigation">
          {sidebar}
        </aside>
      ) : null}

      <section className="yk-workspace">
        {tabs ? (
          <nav className="yk-tabs" aria-label="Workspace tabs">
            {tabs}
          </nav>
        ) : null}
        <main className="yk-main">{children}</main>
      </section>

      {rightSidebar ? (
        <aside className="yk-right-sidebar" aria-label="Inspector">
          {rightSidebar}
        </aside>
      ) : null}

      {bottomBar ? <footer className="yk-bottom-bar">{bottomBar}</footer> : null}
    </div>
  );
}
