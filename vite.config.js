import { defineConfig } from 'vite';

// GitHub project Pages use /repository/. Other hosts use the root by default.
export default defineConfig({
  base: process.env.VITE_BASE_PATH || '/',
  optimizeDeps: {exclude: ['@electric-sql/pglite']},
});
