import { defineConfig } from 'vite'
import { createHtmlPlugin } from 'vite-plugin-html'
import { vitePluginSingleSpa } from 'vite-plugin-single-spa'
import vue from '@vitejs/plugin-vue'

const DEFAULT_EXTENSIONS = ['.mjs', '.js', '.ts', '.jsx', '.tsx', '.json']

export default defineConfig({
  build: {
    outDir: 'tools/base',
    emptyOutDir: true,
    copyPublicDir: true,
  },
  rollupOptions: {
    input: 'src/openc3-tool-base.js',
    format: 'systemjs',
    preserveEntrySignatures: true,
  },
  plugins: [
    vue(),
    vitePluginSingleSpa({
      type: 'root',
      imo: () => 'public/js/import-map-overrides-3.1.1.min.js',
    }),
    createHtmlPlugin({
      template: 'index.html',
    }),
    createHtmlPlugin({
      template: 'index-allow-http.html',
    }),
  ],
  resolve: {
    extensions: [...DEFAULT_EXTENSIONS, '.vue'], // not recommended but saves us from having to change every SFC import
  },
})
