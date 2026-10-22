import * as React from 'react';
import { createRoot } from 'react-dom/client';
import { AppShell, type AppShellProps } from '@f12o/yami-kumo/react';
import '@f12o/yami-kumo/styles.css';

function App() {
  const [count, setCount] = React.useState(0);
  const [sidebarOpen, setSidebarOpen] = React.useState(false);
  const [contextOpen, setContextOpen] = React.useState(true);
  const props: AppShellProps = {
    brand: 'Packed React',
    navigationTrigger: (
      <button id="react-menu" onClick={() => setSidebarOpen(true)}>
        Menu
      </button>
    ),
    sidebar: 'Navigation',
    mobileSidebarOpen: sidebarOpen,
    onMobileSidebarDismiss: () => setSidebarOpen(false),
    contextPanel: 'Details',
    contextPanelOpen: contextOpen,
    onContextPanelDismiss: () => setContextOpen(false),
    children: (
      <button id="counter" onClick={() => setCount(count + 1)}>
        Count {count}
      </button>
    ),
  };
  return <AppShell {...props} />;
}
createRoot(document.getElementById('app')!).render(<App />);
