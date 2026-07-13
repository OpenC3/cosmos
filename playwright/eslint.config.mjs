/*
# Copyright 2026 OpenC3, Inc.
# All Rights Reserved.
#
# This file may only be used under the terms of a commercial license
# purchased from OpenC3, Inc.
*/

import { defineConfig } from 'eslint/config'
import globals from 'globals'
import tseslint from 'typescript-eslint'

export default defineConfig([
  {
    // Ignore everything except the playwright/ root and the tests/ folder
    // (e.g. generated coverage/, test-results/, node_modules/).
    ignores: ['*/**', '!tests/**'],
  },
  {
    // Only lint files directly in the playwright/ root and anything under tests/.
    files: ['**/*.{js,mjs,cjs,ts}'],

    languageOptions: {
      parser: tseslint.parser,

      globals: {
        ...globals.jest,
      },
    },

    rules: {
      'no-console': 'error',
      'no-debugger': 'error',

      'require-await': 'error',
    },
  },
  {
    // Type-aware rules for the TypeScript specs. Requires the TS program, so a
    // tsconfig (and the files it references, e.g. fixture.ts) must be present.
    files: ['*.ts'],

    plugins: {
      '@typescript-eslint': tseslint.plugin,
    },

    languageOptions: {
      parserOptions: {
        projectService: true,
        tsconfigRootDir: import.meta.dirname,
      },
    },

    rules: {
      '@typescript-eslint/no-floating-promises': 'error',
    },
  },
])
