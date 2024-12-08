import { resolve } from 'path'
import { defineConfig } from 'vite'

export default defineConfig({
  build: {
    sourcemap: true,
    lib: {
      entry: {
        'services': './src/services/index.js',
        'utils': './src/utils/index.js',
      },
      name: '@openc3/js-common',
    },
  },
  resolve: {
    alias: {
      '@': resolve(__dirname, './src'),
    },
  },
})
