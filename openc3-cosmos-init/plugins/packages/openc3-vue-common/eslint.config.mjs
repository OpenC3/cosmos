import { dirname, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'
import { defineConfig } from 'eslint/config'
import tseslint from 'typescript-eslint'
import baseConfig from '../../eslint.config.mjs'

const packageDir = dirname(fileURLToPath(import.meta.url))

export default defineConfig([
  baseConfig,
  {
    // TODO: expand this list to other parts of the src folder and to other packages
    files: ['src/tools/**/*.{js,vue}'],

    plugins: {
      '@typescript-eslint': tseslint.plugin,
    },

    languageOptions: {
      parserOptions: {
        parser: tseslint.parser,
        projectService: true,
        tsconfigRootDir: resolve(packageDir, '../..'),
        extraFileExtensions: ['.vue'],
      },
    },

    rules: {
      '@typescript-eslint/no-floating-promises': 'error',
    },
  },
])
