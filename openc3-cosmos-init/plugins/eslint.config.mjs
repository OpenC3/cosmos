import prettierConfig from '@vue/eslint-config-prettier'
import { defineConfig } from 'eslint/config'
import pluginPromise from 'eslint-plugin-promise'
import pluginVue from 'eslint-plugin-vue'
import unicorn from 'eslint-plugin-unicorn'
import vuetify from 'eslint-plugin-vuetify'
import globals from 'globals'
import parser from 'vue-eslint-parser'

export default defineConfig([
  pluginVue.configs['flat/recommended'],
  vuetify.configs['flat/base'],
  {
    plugins: {
      promise: pluginPromise,
      unicorn: unicorn,
    },
    languageOptions: {
      globals: {
        ...globals.node,
      },

      parser: parser,
      ecmaVersion: 2022,
      sourceType: 'module',
    },

    rules: {
      'no-await-in-loop': 'error',
      'no-console': ['error', { allow: ['error'] }],
      'no-debugger': 'error',
      'no-case-declarations': 'error',
      'no-lonely-if': 'error',
      'no-sequences': 'error',

      'prettier/prettier': [
        'warn',
        {
          endOfLine: 'auto',
        },
      ],

      'promise/no-nesting': 'error',

      'require-await': 'error',

      'unicorn/no-typeof-undefined': 'error',
      'unicorn/prefer-array-some': 'error',
      'unicorn/prefer-date-now': 'error',
      'unicorn/prefer-includes': 'error',
      'unicorn/prefer-math-min-max': 'error',
      'unicorn/prefer-negative-index': 'error',
      'unicorn/prefer-number-properties': 'error',
      'unicorn/prefer-single-call': 'error',

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
