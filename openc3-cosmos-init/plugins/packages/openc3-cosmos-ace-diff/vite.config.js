import { defineConfig } from 'vite'

export default defineConfig({
  build: {
    sourcemap: true,
    rollupOptions: {
      input: ['./src/index.js', './src/styles/ace-diff.scss', './src/styles/ace-diff-dark.scss'],
      output: {
        format: 'commonjs',
        entryFileNames: 'ace-diff.min.js',
        assetFileNames: '[name].min[extname]',
      },
      preserveEntrySignatures: 'strict',
    },
  },
})
