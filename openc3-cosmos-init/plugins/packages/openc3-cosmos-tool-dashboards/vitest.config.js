import { fileURLToPath } from 'node:url'
import { defineConfig } from 'vitest/config'

// Unit tests for the tool's pure modules (parser, layout, options,
// formatting), run in Node. Panel components and the shared COSMOS packages
// need a browser and a running COSMOS, so they're stubbed: the Playwright
// tests cover them.
const stub = (name) =>
  fileURLToPath(new URL(`./tests/stubs/${name}`, import.meta.url))

const STUBS = {
  '@openc3/js-common/services': stub('js-common-services.js'),
  '@openc3/vue-common/widgets': stub('vue-common.js'),
  '@openc3/vue-common/util': stub('vue-common.js'),
  '@openc3/vue-common/components': stub('vue-common.js'),
}

export default defineConfig({
  plugins: [
    {
      name: 'stub-components',
      enforce: 'pre',
      resolveId(id) {
        if (STUBS[id]) return STUBS[id]
        // Every .vue file is an empty component
        if (id.endsWith('.vue')) return stub('component.js')
        return null
      },
    },
  ],
  test: {
    environment: 'node',
    include: ['src/**/__tests__/**/*.spec.js'],
  },
})
