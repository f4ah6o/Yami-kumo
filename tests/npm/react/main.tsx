import * as React from 'react';
import { createRoot } from 'react-dom/client';
import { AppShell, type AppShellProps } from '@f4ah6o/yami-kumo/react';
import '@f4ah6o/yami-kumo/styles.css';

function App() {
  const [count, setCount] = React.useState(0);
  const [open, setOpen] = React.useState(true);
  const props: AppShellProps = {
    brand: 'Packed React',
    sidebar: 'Navigation',
    mobileSidebarOpen: open,
    onMobileSidebarDismiss: () => setOpen(false),
    contextPanel: 'Details',
    contextPanelOpen: open,
    onContextPanelDismiss: () => setOpen(false),
    children: (
      <button id="counter" onClick={() => setCount(count + 1)}>
        Count {count}
      </button>
    ),
  };
  return <AppShell {...props} />;
}
createRoot(document.getElementById('app')!).render(<App />);
