import { Button, Input, LayerCard } from '@cloudflare/kumo';
import { useMemo, useState } from 'react';
import { AppShell } from './shell/AppShell';

const tabs = ['Overview', 'Activity', 'Reports', 'Team', 'Settings'];
const navItems = [
  ['⌂', 'Home'],
  ['✉', 'Inbox'],
  ['▣', 'Projects'],
  ['◎', 'Customers'],
  ['↗', 'Analytics'],
  ['⌘', 'Automations'],
  ['◇', 'Integrations'],
  ['⚙', 'Settings'],
] as const;

const railItems = ['⌂', '⌕', '▦', '♙', '⚙'];

const stats = [
  ['Total users', '12,482', '+12%'],
  ['Active projects', '342', '+8%'],
  ['Revenue', '$128.4K', '+23%'],
  ['Uptime', '99.9%', '+0.1%'],
] as const;

function App() {
  const [activeTab, setActiveTab] = useState('Overview');
  const [activeNav, setActiveNav] = useState('Home');
  const [sidebarCollapsed, setSidebarCollapsed] = useState(false);
  const [mobileSidebarOpen, setMobileSidebarOpen] = useState(false);
  const [rightSidebarOpen, setRightSidebarOpen] = useState(() =>
    typeof window === 'undefined' ? true : window.matchMedia('(min-width: 1181px)').matches,
  );

  const activity = useMemo(
    () => [
      ['Jane Smith created a new project', '2 minutes ago'],
      ['You updated workspace settings', '12 minutes ago'],
      ['Acme Corp. invited 3 teammates', '1 hour ago'],
    ],
    [],
  );

  return (
    <AppShell
      brand={
        <div className="yk-brand-group">
          <button
            type="button"
            className="yk-mobile-nav-toggle"
            aria-label={mobileSidebarOpen ? 'Close navigation' : 'Open navigation'}
            aria-controls="yk-mobile-navigation"
            aria-expanded={mobileSidebarOpen}
            onClick={() => {
              setRightSidebarOpen(false);
              setMobileSidebarOpen((value) => !value);
            }}
          >
            ☰
          </button>
          <a className="yk-logo" href="./" aria-label="Yami-kumo home">
            <span className="yk-logo-mark">YK</span>
            <span className="yk-logo-name">Yami-kumo</span>
          </a>
        </div>
      }
      globalSearch={
        <Input
          aria-label="Global search"
          placeholder="Search everything…"
          className="yk-search-input"
        />
      }
      headerActions={
        <>
          <Button
            className="yk-toolbar-button yk-sidebar-toggle"
            onClick={() => setSidebarCollapsed((value) => !value)}
          >
            {sidebarCollapsed ? 'Show sidebar' : 'Hide sidebar'}
          </Button>
          <Button
            className="yk-toolbar-button yk-inspector-toggle"
            aria-controls="yk-inspector"
            aria-expanded={rightSidebarOpen}
            onClick={() => {
              setMobileSidebarOpen(false);
              setRightSidebarOpen((value) => !value);
            }}
          >
            <span className="yk-inspector-toggle-wide">
              {rightSidebarOpen ? 'Hide inspector' : 'Show inspector'}
            </span>
            <span className="yk-inspector-toggle-compact" aria-hidden="true">
              ◧
            </span>
          </Button>
          <span className="yk-avatar" aria-label="Demo user">
            JD
          </span>
        </>
      }
      rail={
        <div className="yk-rail-inner">
          <div className="yk-rail-stack">
            {railItems.map((item, index) => (
              <button
                type="button"
                key={item}
                className="yk-rail-button"
                aria-label={['Home', 'Search', 'Apps', 'People', 'Settings'][index]}
              >
                {item}
              </button>
            ))}
          </div>
          <button type="button" className="yk-rail-user" aria-label="Profile">
            JD
          </button>
        </div>
      }
      sidebar={
        <div className="yk-sidebar-inner">
          <div className="yk-sidebar-heading">
            <div>
              <span className="yk-eyebrow">Workspace</span>
              <strong>Product studio</strong>
            </div>
            <div className="yk-sidebar-heading-actions">
              <span aria-hidden="true">⌄</span>
              <button
                type="button"
                className="yk-mobile-sidebar-close"
                aria-label="Close navigation"
                onClick={() => setMobileSidebarOpen(false)}
              >
                ×
              </button>
            </div>
          </div>

          <div className="yk-sidebar-nav">
            {navItems.map(([icon, label]) => (
              <button
                type="button"
                key={label}
                className="yk-sidebar-link"
                data-active={activeNav === label}
                onClick={() => {
                  setActiveNav(label);
                  setMobileSidebarOpen(false);
                }}
              >
                <span aria-hidden="true">{icon}</span>
                <span>{label}</span>
                {label === 'Inbox' ? <span className="yk-count">7</span> : null}
              </button>
            ))}
          </div>

          <div className="yk-sidebar-divider" />
          <span className="yk-section-label">Favorites</span>
          <div className="yk-favorites">
            {['Q1 Plan', 'Reporting', 'Launch room', 'Untitled 3'].map((item) => (
              <button type="button" key={item} className="yk-favorite">
                ☆ {item}
              </button>
            ))}
          </div>
        </div>
      }
      tabs={
        <div className="yk-tab-list">
          {tabs.map((tab) => (
            <button
              type="button"
              key={tab}
              className="yk-tab"
              aria-selected={activeTab === tab}
              data-active={activeTab === tab}
              onClick={() => setActiveTab(tab)}
            >
              {tab}
            </button>
          ))}
          <button type="button" className="yk-tab yk-new-tab">
            + New tab
          </button>
        </div>
      }
      rightSidebar={
        <div className="yk-inspector">
          <div className="yk-inspector-heading">
            <div>
              <span className="yk-eyebrow">Inspector</span>
              <h2>Get started</h2>
            </div>
            <div className="yk-inspector-heading-actions">
              <span>3 / 5</span>
              <button
                type="button"
                className="yk-inspector-close"
                aria-label="Close inspector"
                onClick={() => setRightSidebarOpen(false)}
              >
                ×
              </button>
            </div>
          </div>

          <div className="yk-progress" aria-label="3 of 5 complete">
            <span />
          </div>

          <label className="yk-check">
            <input type="checkbox" defaultChecked /> Create your profile
          </label>
          <label className="yk-check">
            <input type="checkbox" defaultChecked /> Invite a teammate
          </label>
          <label className="yk-check">
            <input type="checkbox" /> Connect an integration
          </label>
          <label className="yk-check">
            <input type="checkbox" /> Customize your workspace
          </label>
          <label className="yk-check">
            <input type="checkbox" /> Build something great
          </label>

          <LayerCard className="yk-assistant-card">
            <span className="yk-eyebrow">Kumo block</span>
            <h3>Slot-first shell</h3>
            <p>
              Swap navigation, tabs, main content, inspector, and status regions without changing
              the shell contract.
            </p>
          </LayerCard>

          <LayerCard className="yk-ack-card">
            <span className="yk-eyebrow">Acknowledgements</span>
            <p>Layout inspiration:</p>
            <a
              href="https://x.com/thenanyu/status/2105704619704029435?s=46"
              target="_blank"
              rel="noreferrer"
            >
              @thenanyu reference ↗
            </a>
            <a
              href="https://x.com/lawrluk/status/2105711205172273621?s=46"
              target="_blank"
              rel="noreferrer"
            >
              @lawrluk reference ↗
            </a>
          </LayerCard>
        </div>
      }
      bottomBar={
        <>
          <span className="yk-status">
            <i /> All systems operational
          </span>
          <span>3 background jobs running</span>
          <span className="yk-bottom-links">
            <a href="https://github.com/f4ah6o/Yami-kumo">GitHub</a>
            <a href="https://github.com/cloudflare/kumo">Kumo</a>
            <span>v0.1.0</span>
          </span>
        </>
      }
      sidebarCollapsed={sidebarCollapsed}
      mobileSidebarOpen={mobileSidebarOpen}
      onMobileSidebarDismiss={() => setMobileSidebarOpen(false)}
      rightSidebarOpen={rightSidebarOpen}
      onRightSidebarDismiss={() => setRightSidebarOpen(false)}
    >
      <div className="yk-page">
        <div className="yk-page-header">
          <div>
            <span className="yk-eyebrow">Template / {activeTab}</span>
            <h1>Welcome back, John!</h1>
            <p>One shell, many products. Keep the frame stable and replace the slots.</p>
          </div>
          <Button className="yk-date-button">Last 30 days ⌄</Button>
        </div>

        <section className="yk-stat-grid" aria-label="Workspace summary">
          {stats.map(([label, value, delta]) => (
            <LayerCard className="yk-stat-card" key={label}>
              <div className="yk-stat-label">{label}</div>
              <strong>{value}</strong>
              <span className="yk-positive">{delta}</span>
              <div className="yk-sparkline" aria-hidden="true">
                <i />
                <i />
                <i />
                <i />
                <i />
                <i />
              </div>
            </LayerCard>
          ))}
        </section>

        <section className="yk-two-column">
          <LayerCard className="yk-chart-card">
            <div className="yk-card-heading">
              <div>
                <span className="yk-eyebrow">Growth over time</span>
                <h2>Users</h2>
              </div>
              <span className="yk-pill">12 months</span>
            </div>
            <div className="yk-chart" aria-label="Decorative growth chart">
              <div className="yk-chart-grid" />
              <svg viewBox="0 0 600 190" role="img" aria-label="User growth trend">
                <polyline
                  points="20,165 70,148 120,128 170,139 220,112 270,105 320,96 370,70 420,68 470,58 520,49 575,28"
                  fill="none"
                  stroke="currentColor"
                  strokeWidth="3"
                  vectorEffect="non-scaling-stroke"
                />
                {[
                  [20, 165],
                  [70, 148],
                  [120, 128],
                  [170, 139],
                  [220, 112],
                  [270, 105],
                  [320, 96],
                  [370, 70],
                  [420, 68],
                  [470, 58],
                  [520, 49],
                  [575, 28],
                ].map(([cx, cy]) => (
                  <circle
                    key={cx}
                    cx={cx}
                    cy={cy}
                    r="4"
                    fill="white"
                    stroke="currentColor"
                    strokeWidth="2"
                  />
                ))}
              </svg>
            </div>
          </LayerCard>

          <LayerCard className="yk-feature-card">
            <div className="yk-card-heading">
              <div>
                <span className="yk-eyebrow">Top features</span>
                <h2>Adoption</h2>
              </div>
            </div>
            {[
              ['Analytics', 86],
              ['Automations', 72],
              ['Integrations', 61],
              ['Reporting', 52],
              ['AI Magic', 39],
            ].map(([label, width]) => (
              <div className="yk-feature-row" key={label}>
                <span>{label}</span>
                <i>
                  <b style={{ width: `${width}%` }} />
                </i>
              </div>
            ))}
          </LayerCard>
        </section>

        <LayerCard className="yk-activity-card">
          <div className="yk-card-heading">
            <div>
              <span className="yk-eyebrow">Recent activity</span>
              <h2>Workspace events</h2>
            </div>
          </div>
          <div className="yk-activity-list">
            {activity.map(([label, time]) => (
              <div className="yk-activity-row" key={label}>
                <span className="yk-activity-avatar" aria-hidden="true">
                  •
                </span>
                <span>{label}</span>
                <time>{time}</time>
              </div>
            ))}
          </div>
        </LayerCard>
      </div>
    </AppShell>
  );
}

export default App;
