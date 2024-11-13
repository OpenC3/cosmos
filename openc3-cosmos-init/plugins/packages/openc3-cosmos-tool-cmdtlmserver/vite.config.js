import { resolve } from 'path'
import { defineConfig } from 'vite'
import { vitePluginSingleSpa } from 'vite-plugin-single-spa'
import vue from '@vitejs/plugin-vue'

const default_extensions = ['.mjs', '.js', '.ts', '.jsx', '.tsx', '.json']

export default defineConfig({
  base: '/tools/cmdtlmserver',
  build: {
    outDir: 'tools/cmdtlmserver',
    emptyOutDir: true,
    /*
    lib: {
      entry: resolve(__dirname, 'src/main.js'),
      name: '@openc3/tool-cmdtlmserver',
      fileName: 'my-lib',
    },
    */
    rollupOptions: {
      /*
      input: "src/main.js",
      external: ['vue', 'vuetify', 'vuex', 'vue-router'],
      */
      output: {
        format: 'system',
        globals: {
          vue: 'Vue',
          /*
          vuetify: 'Vuetify',
          vuex: 'Vuex',
          'vue-router': 'VueRouter',
          */
        },
      },
    },
  },
  /*
  rollupOptions: {
    input: "src/main.js",
    format: "system",
    preserveEntrySignatures: true,
  },
  */
  plugins: [
    vue(),
    vitePluginSingleSpa({
      type: 'mife', // micro front-end
      serverPort: 2911,
      spaEntryPoints: 'src/main.js',
    }),
  ],
  resolve: {
    alias: {
      '@': resolve(__dirname, './src'),
    },
    extensions: [...default_extensions, '.vue'], // not recommended, but saves us from having to change every SFC import
  },
})
