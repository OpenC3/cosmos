import prettierConfig from '@vue/eslint-config-prettier'
import globals from 'globals'
import parser from 'vue-eslint-parser'

export default [
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
]
