import { resolve } from 'path'
import { defineConfig } from 'vite'
import vue from '@vitejs/plugin-vue'
import sourcemaps from 'rollup-plugin-sourcemaps2'
import { devServerPlugin } from '@openc3/js-common/viteDevServerPlugin'

const DEFAULT_EXTENSIONS = ['.mjs', '.js', '.ts', '.jsx', '.tsx', '.json']

export default defineConfig((options) => {
  // Sourcemaps map V8 coverage from the Playwright tests back to original
  // sources but bloat the production build that gets baked into the
  // openc3-cosmos-init image, so they are opt-in: COVERAGE_BUILD=1 (CI
  // coverage build) or any non-production mode enables them.
  const coverageBuild =
    process.env.COVERAGE_BUILD === '1' || options.mode !== 'production'
  return {
    build: {
      sourcemap: coverageBuild,
      outDir: 'tools/tlmgrapher',
      emptyOutDir: true,
      rollupOptions: {
        input: 'src/main.js',
        output: {
          format: 'systemjs',
          hashCharacters: 'hex',
          entryFileNames: '[name].js',
          chunkFileNames: '[name]-[hash:20].js',
          assetFileNames: 'assets/[name]-[hash][extname]',
        },
        external: ['single-spa', 'vue', 'pinia', 'vue-router', 'vuetify'],
        preserveEntrySignatures: 'strict',
      },
    },
    server: {
      port: 2917,
    },
    plugins: [
      vue({
        template: {
          compilerOptions: {
            isCustomElement: (tag) => tag.startsWith('rux-'),
          },
        },
      }),
      // Chain the prebuilt @openc3/*-common dist sourcemaps into this
      // build's maps so coverage resolves to their original src (rollup
      // does not read dependency .map files on its own)
      coverageBuild && sourcemaps(),
      devServerPlugin(options),
    ],
    resolve: {
      alias: {
        '@': resolve(__dirname, './src'),
      },
      extensions: [...DEFAULT_EXTENSIONS, '.vue'], // not recommended but saves us from having to change every SFC import
      dedupe: ['single-spa', 'vue', 'vuetify', 'vue-router', 'pinia'],
    },
    define: {
      __BASE_URL__: JSON.stringify('/tools/tlmgrapher'),
    },
    optimizeDeps: {
      entries: [], // https://github.com/vituum/vituum/issues/25#issuecomment-1690080284
    },
  }
})
