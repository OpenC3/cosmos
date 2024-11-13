import path from 'path'
import { defineConfig } from 'vite'
import { createHtmlPlugin } from 'vite-plugin-html'
import { vitePluginSingleSpa } from 'vite-plugin-single-spa'
import { viteStaticCopy } from 'vite-plugin-static-copy'
import vue from '@vitejs/plugin-vue'

const default_extensions = ['.mjs', '.js', '.ts', '.jsx', '.tsx', '.json']

export default defineConfig({
  build: {
    outDir: 'tools/base',
    emptyOutDir: true,
    copyPublicDir: true,
  },
  rollupOptions: {
    input: "src/openc3-tool-base.js",
    format: "system",
    preserveEntrySignatures: true,
  },
  plugins: [
    vue(),
    vitePluginSingleSpa({
      type: 'root',
      imo: '3.1.1', // TODO: change this to like `() => '/path/to/our/import-map-overrides.js'`
      /*
      importMaps: {
        build: ['/openc3-api/map.json'],
        dev: ['/openc3-api/map.json'],
      },
      */
    }),
    /*
    createHtmlPlugin({
      template: 'index.html',
    }),
    */
    createHtmlPlugin({
      template: 'index-allow-http.html',
    }),
    // should be handled by this?
    //    https://vite.dev/config/build-options#build-copypublicdir
    //    https://vite.dev/guide/assets#the-public-directory
    /*
    viteStaticCopy({
      targets: [
        {
          src: 'public',
          dest: '.',
        },
      ],
    }),
    */
  ],
  resolve: {
    alias: {
      '@': path.resolve(__dirname, './src'),
    },
    extensions: [...default_extensions, '.vue'], // not recommended, but saves us from having to change every SFC import
  },
})
