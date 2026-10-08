import react from '@vitejs/plugin-react';
import { defineConfig } from 'vite-plus';
import { kumoVersion } from './src/kumo-version.generated';

export default defineConfig({
  base: './',
  plugins: [react()],
  define: {
    __KUMO_VERSION__: JSON.stringify(kumoVersion),
  },
  test: {
    include: ['src/**/*.test.ts'],
  },
  lint: {
    ignorePatterns: ['dist/**'],
  },
  fmt: {
    semi: true,
    singleQuote: true,
    ignorePatterns: ['dist/**', 'styles/kumo-standalone.css', 'styles/yami-kumo-components.css'],
  },
});
