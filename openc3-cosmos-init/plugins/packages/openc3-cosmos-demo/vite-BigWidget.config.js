import { defineConfig } from 'vite'
import federation from '@originjs/vite-plugin-federation'
import VitePluginStyleInject from 'vite-plugin-style-inject'
import vue from '@vitejs/plugin-vue'

const DEFAULT_EXTENSIONS = ['.mjs', '.js', '.ts', '.jsx', '.tsx', '.json']

export default defineConfig({
  build: {
    outDir: 'tools/widgets/BigWidget',
    emptyOutDir: true,
    sourcemap: true,
    /*
    lib: {
      entry: './src/BigWidget.vue',
      name: 'BigWidget',
      fileName: (format, entryName) => `${entryName}.${format}.min.js`,
      formats: ['umd'],
    },
    */
    rollupOptions: {
      input: ['./src/BigWidget.vue'],
      output: {
        entryFileNames: 'BigWidget.umd.min.js',
        format: 'umd',
        /*
        globals: {
          vue: 'Vue',
          vuetify: 'Vuetify',
        },
        */
      },
      // external: ['vue', 'vuetify'],
    },
  },
  plugins: [
    vue(),
    /*
    federation({
      name: 'BigWidget',
      filename: 'BigWidget.umd.min.js',
      exposes: {
        './BigWidget': './src/BigWidget.vue',
      },
    }),
    */
    VitePluginStyleInject(),
  ],
  resolve: {
    extensions: [...DEFAULT_EXTENSIONS, '.vue'], // not recommended but saves us from having to change every SFC import
    // dedupe: ['vue'],
    /*
    alias: {
      vue: 'window.Vue',
      vuetify: 'window.Vuetify',
    },
    */
  },
  /*
  optimizeDeps: {
    entries: [],
    // exclude: ['vue', 'vuetify'],
  },
  */
})
