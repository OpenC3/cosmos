import { defineConfig } from 'vite'
import { createHtmlPlugin } from 'vite-plugin-html'
import vue from '@vitejs/plugin-vue'

const DEFAULT_EXTENSIONS = ['.mjs', '.js', '.ts', '.jsx', '.tsx', '.json']

export default defineConfig({
  build: {
    outDir: 'tools/base',
    emptyOutDir: true,
    rollupOptions: {
      input: 'src/main.js',
      output: {
        format: 'systemjs',
        entryFileNames: `[name].js`,
      },
      external: ['single-spa', 'vue', 'vuex', 'vue-router', 'vuetify'],
      preserveEntrySignatures: 'strict',
    },
  },
  plugins: [vue()],
  resolve: {
    extensions: [...DEFAULT_EXTENSIONS, '.vue'], // not recommended but saves us from having to change every SFC import
  },
})
