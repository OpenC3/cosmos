#!/usr/bin/env node
/*
# Copyright 2026 OpenC3, Inc.
# All Rights Reserved.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
# See LICENSE.md for more details.
#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.
*/
/* eslint-disable no-console */
// Run ESLint across every package that has its own eslint config file, so each
// package's source is checked against its *closest* config.
//
// ESLint's flat config (v9+) does not cascade like the old .eslintrc: a single
// run uses only the nearest config to the working directory. We therefore run
// ESLint once per config directory (with that directory as cwd) so each picks
// up its own config. Following the per-package `lint` scripts, we lint `src`
// only -- this skips build output (tools/) and vendored bundles (public/).
//
// Usage:
//   node lint-all.mjs            # lint every package's src
//   node lint-all.mjs --fix      # extra args are forwarded to eslint
import { spawnSync } from 'node:child_process'
import { existsSync, readdirSync } from 'node:fs'
import { createRequire } from 'node:module'
import { dirname, join, relative } from 'node:path'
import { fileURLToPath } from 'node:url'

const ROOT = dirname(fileURLToPath(import.meta.url))
const CONFIG_RE = /^eslint\.config\.[mc]?[jt]s$/

// Run eslint via the current Node binary and eslint's own JS entry point rather
// than resolving a `pnpm`/`eslint` command name through $PATH (which is
// hijackable). eslint's bin isn't exposed through its package `exports`, so we
// resolve the package root and append the known bin path.
const require = createRequire(import.meta.url)
const ESLINT_BIN = join(
  dirname(require.resolve('eslint/package.json')),
  'bin',
  'eslint.js',
)

// Recursively collect every directory that contains an eslint config file.
function findConfigDirs(dir, acc = []) {
  for (const entry of readdirSync(dir, { withFileTypes: true })) {
    if (entry.name === 'node_modules' || entry.name === '.git') continue
    if (entry.isDirectory()) {
      findConfigDirs(join(dir, entry.name), acc)
    } else if (CONFIG_RE.test(entry.name)) {
      acc.push(dir)
    }
  }
  return acc
}

const configDirs = findConfigDirs(ROOT).sort((a, b) => a.localeCompare(b))
const extraArgs = process.argv.slice(2)

if (configDirs.length === 0) {
  console.error('No eslint config files found under', ROOT)
  process.exit(1)
}

// A folder under packages/ that has source but no eslint.config.mjs would be
// linted by no one -- flag it as an error so it can't slip through unchecked.
const PACKAGES = join(ROOT, 'packages')
const configDirSet = new Set(configDirs)
const missingConfig = []
if (existsSync(PACKAGES)) {
  for (const entry of readdirSync(PACKAGES, { withFileTypes: true })) {
    if (!entry.isDirectory()) continue
    const pkgDir = join(PACKAGES, entry.name)
    if (existsSync(join(pkgDir, 'src')) && !configDirSet.has(pkgDir)) {
      missingConfig.push(relative(ROOT, pkgDir))
    }
  }
}

let overall = 0
const failed = []
const skipped = []

for (const dir of configDirs) {
  const relDir = relative(ROOT, dir) || '.'

  // The per-package convention is `eslint src`; a config dir without a src/
  // (e.g. the workspace root) has nothing of its own to lint.
  if (!existsSync(join(dir, 'src'))) {
    skipped.push(relDir)
    console.log(`\n==> Skipping ${relDir} (no src/)`)
    continue
  }

  console.log(
    `\n==> Linting ${relDir}/src (closest config: ${relDir}/eslint.config.*)`,
  )

  const result = spawnSync(
    process.execPath,
    [ESLINT_BIN, 'src', ...extraArgs],
    {
      cwd: dir,
      stdio: 'inherit',
    },
  )

  const status = result.status ?? 1
  if (status !== 0) {
    overall = status
    failed.push(relDir)
    console.log(`    ✗ ${relDir} reported problems`)
  } else {
    console.log(`    ✓ ${relDir} clean`)
  }
}

const linted = configDirs.length - skipped.length
console.log(`\n${'='.repeat(60)}`)
if (failed.length === 0) {
  console.log(
    `All ${linted} linted package(s) clean. (${skipped.length} skipped)`,
  )
} else {
  console.log(`${failed.length}/${linted} package(s) reported problems:`)
  for (const f of failed) console.log(`  - ${f}`)
}

if (missingConfig.length > 0) {
  overall = overall || 1
  console.log(
    `\n${missingConfig.length} package(s) have a src/ but no eslint.config.mjs (source would go unlinted):`,
  )
  for (const p of missingConfig) console.log(`  - ${p}`)
}

process.exit(overall)
