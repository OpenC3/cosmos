import { resolve } from 'path'
import { defineConfig } from 'vite'
import vue from '@vitejs/plugin-vue'
import { devServerPlugin } from '@openc3/tool-common/viteDevServerPlugin'

const DEFAULT_EXTENSIONS = ['.mjs', '.js', '.ts', '.jsx', '.tsx', '.json']

export default defineConfig((options) => {
  return {
    build: {
      outDir: 'tools/dataviewer',
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
    server: {
      port: 2919,
    },
    plugins: [vue(), devServerPlugin(options)],
    resolve: {
      alias: {
        '@': resolve(__dirname, './src'),
      },
      extensions: [...DEFAULT_EXTENSIONS, '.vue'], // not recommended but saves us from having to change every SFC import
    },
    define: {
      __BASE_URL__: JSON.stringify('/tools/dataviewer'),
    },
    optimizeDeps: {
      entries: [], // https://github.com/vituum/vituum/issues/25#issuecomment-1690080284
    },
  }
})
