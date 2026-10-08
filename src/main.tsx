import { StrictMode } from 'react';
import { createRoot } from 'react-dom/client';
import '../styles/kumo-standalone.css';
import '../styles/yami-kumo-components.css';
import App from './App';
import './styles.css';

const root = document.getElementById('root');

if (!root) {
  throw new Error('Root element was not found');
}

if (window.location.pathname === '/parity') {
  void import('./parity-gallery').then(({ mountParityGallery }) => {
    mountParityGallery(root);
  });
} else {
  createRoot(root).render(
    <StrictMode>
      <App />
    </StrictMode>,
  );
}
