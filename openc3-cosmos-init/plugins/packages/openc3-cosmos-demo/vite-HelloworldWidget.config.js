import { defineConfig } from 'vite'
import VitePluginStyleInject from 'vite-plugin-style-inject'
import vue from '@vitejs/plugin-vue'

const DEFAULT_EXTENSIONS = ['.mjs', '.js', '.ts', '.jsx', '.tsx', '.json']

export default defineConfig({
  build: {
    outDir: 'tools/widgets/HelloworldWidget',
    emptyOutDir: true,
    sourcemap: true,
    rollupOptions: {
      input: './src/HelloworldWidget.vue',
      output: {
        format: 'systemjs',
        entryFileNames: 'HelloworldWidget.umd.min.js',
        inlineDynamicImports: true,
      },
      external: ['vue', 'vuetify'],
      preserveEntrySignatures: 'strict',
    },
  },
  plugins: [vue(), VitePluginStyleInject()],
  resolve: {
    extensions: [...DEFAULT_EXTENSIONS, '.vue'], // not recommended but saves us from having to change every SFC import
  },
})
