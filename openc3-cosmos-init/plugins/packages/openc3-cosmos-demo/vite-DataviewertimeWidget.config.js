import { defineConfig } from 'vite'
import VitePluginStyleInject from 'vite-plugin-style-inject'
import vue from '@vitejs/plugin-vue'

const DEFAULT_EXTENSIONS = ['.mjs', '.js', '.ts', '.jsx', '.tsx', '.json']

export default defineConfig({
  build: {
    outDir: 'tools/widgets/DataviewertimeWidget',
    emptyOutDir: true,
    sourcemap: true,
    lib: {
      entry: './src/DataviewertimeWidget.vue',
      name: 'DataviewertimeWidget',
      fileName: (format, entryName) => `${entryName}.${format}.min.js`,
      formats: ['umd'],
    },
    rollupOptions: {
      output: {
        globals: {
          vue: 'Vue',
          vuetify: 'Vuetify',
        },
      },
      external: ['vue', 'vuetify'],
    },
  },
  plugins: [vue(), VitePluginStyleInject()],
  resolve: {
    extensions: [...DEFAULT_EXTENSIONS, '.vue'], // not recommended but saves us from having to change every SFC import
  },
})
