/*
# Copyright 2026 OpenC3, Inc.
# All Rights Reserved.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
# See LICENSE.md for more details.
*/

// Merge the raw V8 coverage cached by tests/fixture.ts across ALL
// `playwright test` invocations (pnpm test runs three) into one report:
// coverage/index.html, lcov.info, cobertura-coverage.xml.
// Run automatically at the end of `pnpm test`, or manually via
// `pnpm coverage` after any COVERAGE=1 playwright run.
//
// MCR deletes coverage/.cache when generate() finishes, so before generating
// we copy it to coverage-raw/ (outside the output dir, which MCR also cleans).
// Filters and path mappings in coverage.config.mjs are applied at report
// time, so after tweaking them just rerun this script - it regenerates from
// coverage-raw/ without rerunning the tests. The backup mirrors the most
// recent test session: the next session's generate replaces it.
import fs from 'fs'
import { CoverageReport } from 'monocart-coverage-reports'
import coverageOptions from './coverage.config.mjs'

const cacheDir = './coverage/.cache'
const rawDir = './coverage-raw'

if (fs.existsSync(cacheDir)) {
  fs.rmSync(rawDir, { recursive: true, force: true })
  fs.cpSync(cacheDir, rawDir, { recursive: true })
  await new CoverageReport(coverageOptions).generate()
} else if (fs.existsSync(rawDir)) {
  process.stdout.write(`Regenerating report from ${rawDir}\n`)
  await new CoverageReport({
    ...coverageOptions,
    inputDir: rawDir,
  }).generate()
} else {
  // No-op so the `pnpm test` chain works without COVERAGE=1
  process.stdout.write(
    'No V8 coverage cache found - skipping report generation\n',
  )
}
