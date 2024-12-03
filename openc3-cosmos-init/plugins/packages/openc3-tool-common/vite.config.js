import { resolve } from 'path'
import { defineConfig } from 'vite'
import vue from '@vitejs/plugin-vue'

export default defineConfig({
  build: {
    sourcemap: true,
    cssCodeSplit: false,
    lib: {
      entry: {
        'admin': './src/admin/index.js',
        'base': './src/base/index.js',
        'calendar': './src/calendar/index.js'
      },
      name: '@openc3/tool-common',
    },
    rollupOptions: {
      preserveEntrySignatures: 'strict',
      external: ['single-spa', 'vue', 'vuex', 'vue-router', 'vuetify'],
    },
  },
  plugins: [vue()],
  resolve: {
    alias: {
      '@': resolve(__dirname, './src'),
    },
  },
})
