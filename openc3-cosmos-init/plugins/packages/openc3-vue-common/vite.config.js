import { resolve } from 'path'
import { defineConfig } from 'vite'
import vue from '@vitejs/plugin-vue'

export default defineConfig({
  build: {
    sourcemap: true,
    cssCodeSplit: false,
    lib: {
      entry: {
        'components': './src/components/index.js',
        'icons': './src/icons/index.js',
        'plugins': './src/plugins/index.js',
        'tools/admin': './src/tools/admin/index.js',
        'tools/base': './src/tools/base/index.js',
        'tools/calendar': './src/tools/calendar/index.js',
        'util': './src/util/index.js',
        'widgets': './src/widgets/index.js',
      },
      name: '@openc3/vue-common',
    },
    rollupOptions: {
      external: ['single-spa', 'vue', 'vuex', 'vue-router', 'vuetify'],
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

        if (ignoredWarnings.some((ignoredWarning) => warning.message.includes(ignoredWarning))) {
          return
        }
        warn(warning)
      },
    },
  },
  plugins: [vue()],
  resolve: {
    alias: {
      '@': resolve(__dirname, './src'),
    },
  },
})
