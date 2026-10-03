import { Button, Input, LayerCard } from '@cloudflare/kumo';
import { Folder, Gear, House, List, SquaresFour, UserCircle, X } from '@phosphor-icons/react';
import { useState } from 'react';
import { AppShell } from './shell/AppShell';

const tabs = ['Overview', 'Activity'];

function App() {
  const [activeTab, setActiveTab] = useState('Overview');
  const [activeNav, setActiveNav] = useState('Home');
  const [sidebarCollapsed, setSidebarCollapsed] = useState(false);
  const [mobileSidebarOpen, setMobileSidebarOpen] = useState(false);

  return (
    <AppShell
      navigationTrigger={
        <button
          type="button"
          className="starter-icon-button starter-mobile-nav-trigger"
          aria-label={mobileSidebarOpen ? 'Close navigation' : 'Open navigation'}
          aria-controls="yk-mobile-navigation"
          aria-expanded={mobileSidebarOpen}
          onClick={() => setMobileSidebarOpen((value) => !value)}
        >
          <List size={20} weight="bold" />
        </button>
      }
      brand={
        <a className="starter-brand" href="./" aria-label="Application home">
          <span className="starter-brand-mark">A</span>
          <strong>Application</strong>
        </a>
      }
      globalSearch={<Input aria-label="Global search" placeholder="Search…" />}
      headerActions={
        <Button
          className="starter-sidebar-toggle"
          onClick={() => setSidebarCollapsed((value) => !value)}
        >
          {sidebarCollapsed ? 'Show navigation' : 'Hide navigation'}
        </Button>
      }
      accountMenu={
        <button type="button" className="starter-account" aria-label="Account menu">
          <UserCircle size={26} weight="regular" aria-hidden="true" />
        </button>
      }
      rail={
        <div className="starter-rail">
          <button type="button" className="starter-rail-button" aria-label="Home">
            <House size={20} weight="regular" />
          </button>
          <button type="button" className="starter-rail-button" aria-label="Apps">
            <SquaresFour size={20} weight="regular" />
          </button>
          <button type="button" className="starter-rail-button" aria-label="Settings">
            <Gear size={20} weight="regular" />
          </button>
        </div>
      }
      sidebar={
        <div className="starter-sidebar">
          <div className="starter-sidebar-heading">
            <div>
              <span className="starter-eyebrow">Workspace</span>
              <strong>My workspace</strong>
            </div>
            <button
              type="button"
              className="starter-icon-button starter-mobile-nav-close"
              aria-label="Close navigation"
              onClick={() => setMobileSidebarOpen(false)}
            >
              <X size={18} />
            </button>
          </div>

          {[
            { label: 'Home', icon: House },
            { label: 'Projects', icon: Folder },
            { label: 'Settings', icon: Gear },
          ].map(({ label, icon: Icon }) => (
            <button
              type="button"
              key={label}
              className="starter-nav-item"
              data-active={activeNav === label}
              onClick={() => {
                setActiveNav(label);
                setMobileSidebarOpen(false);
              }}
            >
              <Icon size={18} />
              <span>{label}</span>
            </button>
          ))}
        </div>
      }
      tabs={
        <div className="starter-tabs">
          {tabs.map((tab) => (
            <button
              type="button"
              key={tab}
              className="starter-tab"
              data-active={activeTab === tab}
              aria-selected={activeTab === tab}
              onClick={() => setActiveTab(tab)}
            >
              {tab}
            </button>
          ))}
        </div>
      }
      bottomBar={
        <div className="starter-status">
          <span className="starter-status-dot" />
          Ready
        </div>
      }
      sidebarCollapsed={sidebarCollapsed}
      mobileSidebarOpen={mobileSidebarOpen}
      onMobileSidebarDismiss={() => setMobileSidebarOpen(false)}
    >
      <section className="starter-page">
        <span className="starter-eyebrow">
          {activeNav} / {activeTab}
        </span>
        <h1>Start building here</h1>
        <p className="starter-lead">
          Keep the shell stable and replace this area with the primary task for your product.
        </p>

        <div className="starter-grid">
          <LayerCard className="starter-card">
            <h2>Main content owns the task</h2>
            <p>
              Required actions, forms, errors, and results belong in the center workspace rather
              than optional chrome.
            </p>
          </LayerCard>

          <LayerCard className="starter-card">
            <h2>Add optional regions only when useful</h2>
            <p>
              Tabs, a context panel, account controls, and the bottom bar are slots. Omit any of
              them when they do not improve the workflow.
            </p>
          </LayerCard>
        </div>
      </section>
    </AppShell>
  );
}

export default App;
