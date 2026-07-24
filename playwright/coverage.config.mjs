/*
# Copyright 2026 OpenC3, Inc.
# All Rights Reserved.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
# See LICENSE.md for more details.
*/

// Shared between tests/fixture.ts (add) and generate-coverage.mjs (generate).
// Raw V8 dumps from every worker of every `playwright test` invocation
// accumulate under coverage/.cache; `pnpm coverage` merges them into one
// report (and consumes the cache, so the next session starts fresh).
// NOTE: Do NOT generate() per invocation - MCR deletes the cache dir when
// generate() finishes, which would drop everything collected so far.

/** @type {import('monocart-coverage-reports').CoverageReportOptions} */
const coverageOptions = {
  name: 'OpenC3 COSMOS Playwright Coverage',
  outputDir: './coverage',
  reports: [
    'v8', // raw per-bundle view; shows exactly which script URLs were captured
    'html', // human-readable line-level report
    'lcovonly', // coverage/lcov.info for codecov upload
    'cobertura', // coverage/cobertura-coverage.xml (codecov also accepts this)
    'console-summary',
  ],
  // Only our tool bundles served from bucket storage; skips vue/vuetify/
  // single-spa importmap externals, any anonymous eval'd scripts, and the
  // static sites (/tools/staticdocs docusaurus bundles etc.)
  entryFilter: (entry) =>
    !entry.url.includes('/tools/static') &&
    /\/tools\/[^/]+\/.+\.js/.test(entry.url),
  // After sourcemap remap, keep only original package sources
  sourceFilter: (sourcePath) =>
    !sourcePath.includes('node_modules') && /\bsrc\b/.test(sourcePath),
  // Normalize map-relative paths (../../openc3-vue-common/src/...) to
  // repo-relative so reports and codecov paths match the checkout
  sourcePath: (filePath) => {
    const marker = filePath.lastIndexOf('openc3-')
    if (marker !== -1) {
      return `openc3-cosmos-init/plugins/packages/${filePath.slice(marker)}`
    }
    return filePath
  },
}

export default coverageOptions
