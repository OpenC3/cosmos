import { resolve } from 'node:path'
import { defineConfig } from 'vite'
import vue from '@vitejs/plugin-vue'
import sourcemaps from 'rollup-plugin-sourcemaps2'

// monaco-editor 0.56's entry point registers the css / html / json /
// typescript language services, and each one spawns its own web worker with
// `new Worker(new URL('css.worker.js', import.meta.url), ...)`. In this lib
// build vite emits those workers as dist/assets/*.worker-<hash>.js and
// rewrites the URLs to root-absolute /assets/... paths, which are wrong under
// COSMOS's microfrontend routing (tools are served under /tools/<name>/) and
// which downstream tool builds then try to resolve out of their own public/
// dir - "Could not resolve entry module public/assets/css.worker-*.js".
// COSMOS only edits Ruby / Python / JS scripts, so drop the four services.
// Monarch syntax highlighting (which runs on the main thread) and every
// editor contribution are unaffected.
const monacoLanguageServiceStub = () => {
  const stub = resolve(__dirname, './build/monaco-language-service-stub.js')
  return {
    name: 'openc3:monaco-language-service-stub',
    enforce: 'pre',
    resolveId(source, importer) {
      if (
        importer?.includes('monaco-editor') &&
        /languages\/features\/(css|html|json|typescript)\/register\.js$/.test(
          source,
        )
      ) {
        return stub
      }
      return null
    },
  }
}

export default defineConfig(({ mode }) => {
  // Sourcemaps roughly tripled the dist/ footprint after the Monaco swap
  // (the dialog chunk's map alone is ~14 MB). Keep them in dev / the
  // dev-server build for debugging and in the COVERAGE_BUILD=1 CI build
  // (they map V8 coverage from the Playwright tests back to src); drop them
  // from the production build that gets baked into the openc3-cosmos-init
  // image.
  const coverageBuild =
    process.env.COVERAGE_BUILD === '1' || mode !== 'production'
  return {
    build: {
      sourcemap: coverageBuild,
      cssCodeSplit: false,
      lib: {
        entry: {
          components: './src/components/index.js',
          composables: './src/composables/index.js',
          icons: './src/icons/index.js',
          plugins: './src/plugins/index.js',
          'tools/admin': './src/tools/admin/index.js',
          'tools/base': './src/tools/base/index.js',
          'tools/calendar': './src/tools/calendar/index.js',
          'tools/scriptrunner': './src/tools/scriptrunner/index.js',
          util: './src/util/index.js',
          widgets: './src/widgets/index.js',
        },
        name: '@openc3/vue-common',
      },
      rollupOptions: {
        external: ['single-spa', 'vue', 'pinia', 'vue-router', 'vuetify'],
        preserveEntrySignatures: 'strict',
        onwarn: (warning, warn) => {
          const ignoredWarnings = [
            // We do eval on purpose 😈
            'Use of eval in "src/components/widgets/ButtonWidget.vue" is strongly discouraged',

            // TODO: Is this actually an issue?
            // This warning comes up for all the widgets because we statically import them in other widgets, as well as
            // dynamically import them in WidgetComponents.js, which is needed to make screens work.
            'widgets/index.js, dynamic import will not move module into another chunk',
          ]

          if (
            ignoredWarnings.some((ignoredWarning) =>
              warning.message.includes(ignoredWarning),
            )
          ) {
            return
          }
          warn(warning)
        },
      },
    },
    plugins: [
      monacoLanguageServiceStub(),
      vue(),
      // Chain the prebuilt @openc3/js-common dist sourcemaps into this
      // build's maps so coverage resolves to their original src (rollup
      // does not read dependency .map files on its own)
      coverageBuild && sourcemaps(),
    ],
    resolve: {
      alias: {
        '@': resolve(__dirname, './src'),
      },
      dedupe: ['single-spa', 'vue', 'vuetify', 'vue-router', 'pinia'],
    },
  }
})
