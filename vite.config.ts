import react from '@vitejs/plugin-react';
import { defineConfig } from 'vite-plus';

export default defineConfig({
  base: '/Yami-kumo/',
  plugins: [react()],
  test: {
    include: ['src/**/*.test.ts'],
  },
  lint: {
    ignorePatterns: ['dist/**'],
  },
  fmt: {
    semi: true,
    singleQuote: true,
  },
});
