import { defineConfig } from 'eslint/config'
import baseConfig from '../../eslint.config.mjs'

export default defineConfig([
  baseConfig,
  {
    rules: {
      'vue/no-side-effects-in-computed-properties': 'warn',
      'vuetify/no-deprecated-props': 'warn',
    },
  },
])
