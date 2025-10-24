import { defineConfig } from 'eslint/config'
import baseConfig from '../../eslint.config.mjs'

export default defineConfig([
  baseConfig,
  {
    rules: {
      'vue/no-deprecated-delete-set': 'warn',
    },
  },
])
