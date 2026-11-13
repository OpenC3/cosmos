import shared from '../../eslint.config.mjs'

export default [
  ...shared,
  {
    // Template names that aren't defined in <script setup> are undefined at
    // runtime (and fail silently in production), so catch them in lint
    files: ['**/*.vue'],
    rules: {
      'vue/no-undef-properties': 'error',
    },
  },
]
