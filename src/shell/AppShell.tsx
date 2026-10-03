import type { ReactNode } from 'react';

export interface AppShellProps {
  brand: ReactNode;
  navigationTrigger?: ReactNode;
  globalSearch?: ReactNode;
  headerActions?: ReactNode;
  accountMenu?: ReactNode;
  rail?: ReactNode;
  sidebar?: ReactNode;
  tabs?: ReactNode;
  contextPanel?: ReactNode;
  contextPanelLabel?: string;
  bottomBar?: ReactNode;
  children: ReactNode;
  sidebarCollapsed?: boolean;
  mobileSidebarOpen?: boolean;
  onMobileSidebarDismiss?: () => void;
  contextPanelOpen?: boolean;
  onContextPanelDismiss?: () => void;
}

export function AppShell({
  brand,
  navigationTrigger,
  globalSearch,
  headerActions,
  accountMenu,
  rail,
  sidebar,
  tabs,
  contextPanel,
  contextPanelLabel = 'Context panel',
  bottomBar,
  children,
  sidebarCollapsed = false,
  mobileSidebarOpen = false,
  onMobileSidebarDismiss,
  contextPanelOpen = false,
  onContextPanelDismiss,
}: AppShellProps) {
  return (
    <div
      className="yk-shell"
      data-has-rail={Boolean(rail)}
      data-has-sidebar={Boolean(sidebar)}
      data-sidebar-collapsed={sidebarCollapsed}
      data-mobile-sidebar-open={mobileSidebarOpen}
      data-has-context-panel={Boolean(contextPanel)}
      data-context-panel-open={contextPanelOpen}
      data-has-bottom-bar={Boolean(bottomBar)}
    >
      <header className="yk-topbar">
        <div className="yk-brand-group">
          {navigationTrigger ? (
            <div className="yk-navigation-trigger">{navigationTrigger}</div>
          ) : null}
          <div className="yk-brand">{brand}</div>
        </div>

        <div className="yk-global-search">{globalSearch}</div>

        <div className="yk-header-end">
          {headerActions ? <div className="yk-header-actions">{headerActions}</div> : null}
          {accountMenu ? <div className="yk-account-menu">{accountMenu}</div> : null}
        </div>
      </header>

      {rail ? (
        <nav className="yk-rail" aria-label="Primary">
          {rail}
        </nav>
      ) : null}

      {sidebar ? (
        <>
          <button
            type="button"
            className="yk-drawer-scrim yk-sidebar-scrim"
            aria-label="Close workspace navigation"
            onClick={onMobileSidebarDismiss}
          />
          <aside id="yk-mobile-navigation" className="yk-sidebar" aria-label="Workspace navigation">
            {sidebar}
          </aside>
        </>
      ) : null}

      <section className="yk-workspace" data-has-tabs={Boolean(tabs)}>
        {tabs ? (
          <nav className="yk-tabs" aria-label="Workspace tabs">
            {tabs}
          </nav>
        ) : null}
        <main className="yk-main">{children}</main>
      </section>

      {contextPanel ? (
        <>
          <button
            type="button"
            className="yk-drawer-scrim yk-context-panel-scrim"
            aria-label={`Close ${contextPanelLabel}`}
            onClick={onContextPanelDismiss}
          />
          <aside id="yk-context-panel" className="yk-context-panel" aria-label={contextPanelLabel}>
            {contextPanel}
          </aside>
        </>
      ) : null}

      {bottomBar ? <footer className="yk-bottom-bar">{bottomBar}</footer> : null}
    </div>
  );
}
