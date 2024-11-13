import path from 'path'
import { defineConfig } from 'vite'
import vue from '@vitejs/plugin-vue'

const default_extensions = ['.mjs', '.js', '.ts', '.jsx', '.tsx', '.json']

export default defineConfig({
  plugins: [
    vue(),
  ],
  resolve: {
    alias: {
      '@': path.resolve(__dirname, './src'),
    },
    extensions: [...default_extensions, '.vue'], // not recommended, but saves us from having to change every SFC import
  },
})
