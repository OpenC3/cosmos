import prettierConfig from '@vue/eslint-config-prettier'
import { defineConfig } from 'eslint/config'
import pluginVue from 'eslint-plugin-vue'
import vuetify from 'eslint-plugin-vuetify'
import globals from 'globals'
import parser from 'vue-eslint-parser'

export default defineConfig([
  pluginVue.configs['flat/recommended'],
  vuetify.configs['flat/base'],
  {
    languageOptions: {
      globals: {
        ...globals.node,
      },

      parser: parser,
      ecmaVersion: 2022,
      sourceType: 'module',
    },

    rules: {
      'no-console': 'error',
      'no-debugger': 'error',

      'prettier/prettier': [
        'warn',
        {
          endOfLine: 'auto',
        },
      ],

      'vue/multi-word-component-names': 'off',

      'vue/valid-v-slot': [
        'error',
        {
          allowModifiers: true,
        },
      ],
    },
  },
  {
    files: ['**/__tests__/*.{j,t}s?(x)', '**/tests/unit/**/*.spec.{j,t}s?(x)'],

    languageOptions: {
      globals: {
        ...globals.jest,
      },
    },
  },
  prettierConfig,
])
