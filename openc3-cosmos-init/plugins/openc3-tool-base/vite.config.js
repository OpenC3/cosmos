import { defineConfig } from 'vite'
import vue from '@vitejs/plugin-vue'

const DEFAULT_EXTENSIONS = ['.mjs', '.js', '.ts', '.jsx', '.tsx', '.json']

export default defineConfig({
  build: {
    outDir: 'tools/base',
    emptyOutDir: true,
    copyPublicDir: true,
    rollupOptions: {
      input: ['index.html', 'index-allow-http.html'],
      format: 'systemjs',
      preserveEntrySignatures: true,
    },
  },
  plugins: [vue()],
  resolve: {
    extensions: [...DEFAULT_EXTENSIONS, '.vue'], // not recommended but saves us from having to change every SFC import
  },
})
