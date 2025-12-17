import { defineConfig } from 'eslint/config'
import baseConfig from '../../eslint.config.mjs'

export default defineConfig([
  baseConfig,
  {
    rules: {
      'no-console': 'warn',
      'vue/no-mutating-props': 'warn',
      'vue/no-side-effects-in-computed-properties': 'warn',
      'vue/valid-v-slot': 'warn',
      'vuetify/no-deprecated-classes': 'warn',
      'vuetify/no-deprecated-components': 'warn',
      'vuetify/no-deprecated-props': 'warn',
    },
  },
])
