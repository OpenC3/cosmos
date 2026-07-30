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

const CORE_PACKAGES = 'openc3-cosmos-init/plugins/packages'
// The enterprise tools live in the cosmos-enterprise repo. Its Playwright job
// checks cosmos out as a subdirectory and reuses this config, so both sets of
// packages can show up in one report; ENTERPRISE=1 is set for that run.
const ENTERPRISE_PACKAGES = 'openc3-cosmos-enterprise-init/plugins/packages'
const enterprise = process.env.ENTERPRISE === '1'

// A tool's own sources are map-relative to its bundle (../../src/App.vue), so
// the package name is nowhere in the path - every tool would collapse into a
// single src/ tree. Recover it from the /tools/<dir>/ segment of the bundle
// URL. Enterprise ships its own admin and base at the same URLs as core and
// replaces them, hence the ENTERPRISE split rather than one merged table.
const TOOL_PACKAGES = {
  bucketexplorer: `${CORE_PACKAGES}/openc3-cosmos-tool-bucketexplorer`,
  cmdsender: `${CORE_PACKAGES}/openc3-cosmos-tool-cmdsender`,
  cmdtlmserver: `${CORE_PACKAGES}/openc3-cosmos-tool-cmdtlmserver`,
  dataextractor: `${CORE_PACKAGES}/openc3-cosmos-tool-dataextractor`,
  dataviewer: `${CORE_PACKAGES}/openc3-cosmos-tool-dataviewer`,
  handbooks: `${CORE_PACKAGES}/openc3-cosmos-tool-handbooks`,
  iframe: `${CORE_PACKAGES}/openc3-cosmos-tool-iframe`,
  limitsmonitor: `${CORE_PACKAGES}/openc3-cosmos-tool-limitsmonitor`,
  packetviewer: `${CORE_PACKAGES}/openc3-cosmos-tool-packetviewer`,
  scriptrunner: `${CORE_PACKAGES}/openc3-cosmos-tool-scriptrunner`,
  tablemanager: `${CORE_PACKAGES}/openc3-cosmos-tool-tablemanager`,
  tlmgrapher: `${CORE_PACKAGES}/openc3-cosmos-tool-tlmgrapher`,
  tlmviewer: `${CORE_PACKAGES}/openc3-cosmos-tool-tlmviewer`,
  ...(enterprise
    ? {
        admin: `${ENTERPRISE_PACKAGES}/openc3-cosmos-enterprise-tool-admin`,
        base: `${ENTERPRISE_PACKAGES}/openc3-enterprise-tool-base`,
        autonomic: `${ENTERPRISE_PACKAGES}/openc3-cosmos-tool-autonomic`,
        calendar: `${ENTERPRISE_PACKAGES}/openc3-cosmos-tool-calendar`,
        cmdhistory: `${ENTERPRISE_PACKAGES}/openc3-cosmos-tool-cmdhistory`,
        cmdqueue: `${ENTERPRISE_PACKAGES}/openc3-cosmos-tool-cmdqueue`,
        logexplorer: `${ENTERPRISE_PACKAGES}/openc3-cosmos-tool-logexplorer`,
        notebooks: `${ENTERPRISE_PACKAGES}/openc3-cosmos-tool-notebooks`,
        systemhealth: `${ENTERPRISE_PACKAGES}/openc3-cosmos-tool-systemhealth`,
      }
    : {
        admin: `${CORE_PACKAGES}/openc3-cosmos-tool-admin`,
        base: `${CORE_PACKAGES}/openc3-tool-base`,
      }),
}

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
  // Normalize map-relative paths to repo-relative so reports and codecov
  // paths match the checkout
  sourcePath: (filePath, info) => {
    // Shared packages pulled in from another package's dist (the path still
    // names them, e.g. ../../openc3-vue-common/src/...) always come from core
    const marker = filePath.lastIndexOf('openc3-')
    if (marker !== -1) {
      return `${CORE_PACKAGES}/${filePath.slice(marker)}`
    }
    // A tool's own sources: attribute them to the tool that served the bundle
    if (/^\.{0,2}\/?src\//.test(filePath)) {
      const tool = /\/tools\/([^/]+)\//.exec(info?.distFile || '')?.[1]
      const pkg = tool && TOOL_PACKAGES[tool]
      if (pkg) {
        return `${pkg}/${filePath.replace(/^\.{0,2}\//, '')}`
      }
    }
    return filePath
  },
}

export default coverageOptions
