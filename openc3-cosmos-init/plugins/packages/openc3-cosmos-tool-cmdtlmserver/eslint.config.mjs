import { defineConfig } from 'eslint/config'
import baseConfig from '../../eslint.config.mjs'

export default defineConfig([
  baseConfig,
  {
    rules: {
      'no-console': 'warn',
      'vue/no-side-effects-in-computed-properties': 'warn',
      'vuetify/no-deprecated-props': 'warn',
    },
  },
])
