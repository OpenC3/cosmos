import { defineConfig } from 'eslint/config'
import baseConfig from '../../eslint.config.mjs'

export default defineConfig([
  baseConfig,
  {
    rules: {
      'vuetify/no-deprecated-props': 'warn',
    },
  },
])
