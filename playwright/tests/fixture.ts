/*
# Copyright 2026 OpenC3, Inc.
# All Rights Reserved.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
# See LICENSE.md for more details.
*/

import { writeFile } from 'node:fs/promises'
import { expect, test as base } from '@playwright/test'
import { Utilities } from '../utilities'
import { CoverageReport } from 'monocart-coverage-reports'
import coverageOptions from '../coverage.config.mjs'
import { ADMIN_STORAGE_STATE, STORAGE_STATE } from '../playwright.config'

// V8 coverage is Chromium-only and only collected when COVERAGE=1,
// so normal runs pay no profiler overhead. Requires bundles built with
// sourcemaps: `vite build --mode coverage` (see tool vite.config.js).
const collectCoverage = (browserName: string) =>
  process.env.COVERAGE === '1' && browserName === 'chromium'

// resetOnNavigation: false keeps counters across the reloads and route changes
// our tests perform constantly. Never let coverage bookkeeping fail a test.
const startCoverage = async (page: any) => {
  try {
    await page.coverage.startJSCoverage({ resetOnNavigation: false })
  } catch {
    // Page already closed or navigated away - nothing to profile.
  }
}

const stopCoverage = async (page: any) => {
  try {
    const coverage = await page.coverage.stopJSCoverage()
    // Appends raw V8 data to coverage/.cache (safe across workers AND
    // separate `playwright test` invocations); generate-coverage.mjs
    // merges everything into one report at the end of `pnpm test`
    await new CoverageReport(coverageOptions).add(coverage)
  } catch {
    // Page closed (directly or by context teardown) before we could read it.
    // Swallow so we don't mask the real test failure.
  }
}

// localStorage keys the fixture or a spec injects to drive UI preferences
// rather than authentication. These must never reach the shared storage state
// files: every context is created from those files, so a persisted notoast
// silently disables alert toasts for the whole run (Notifications.vue reads
// localStorage.notoast on load) and a persisted toastPosition changes where the
// toaster renders.
const UI_PREF_KEYS = new Set(['notoast', 'toastPosition'])

// Persist just the signed-in session, dropping the UI preference keys above.
const saveAuthState = async (context: any, path: string) => {
  const state = await context.storageState()
  for (const origin of state.origins || []) {
    origin.localStorage = (origin.localStorage || []).filter(
      (item: { name: string }) => !UI_PREF_KEYS.has(item.name),
    )
  }
  await writeFile(path, JSON.stringify(state))
}

// Extend the page fixture to goto the OpenC3 tool and wait for potential
// redirect to authentication login (Enterprise only).
// Login and click the hamburger nav icon to close the navigation drawer.
export const test = base.extend<{
  context: any
  utils: Utilities
  toolPath: string
  toolName: string
  disableToasts: boolean
}>({
  toolPath: '/tools/cmdtlmserver',
  toolName: 'CmdTlmServer',
  // By default every test disables alert toast popups so they can't intercept
  // clicks. Toasts are gated by per-browser localStorage (reset each test), so
  // this must live in the fixture. The notifications spec opts out.
  disableToasts: true,
  utils: async (
    { context, baseURL, toolPath, toolName, page, disableToasts, browserName },
    use,
  ) => {
    if (collectCoverage(browserName)) {
      await startCoverage(page)
      // Specs also open secondary pages (context.newPage() and screen popups);
      // profile those too or their bundles are missing from the report.
      context.on('page', startCoverage)
    }
    // Set the alert toast preference before the first navigation so the
    // Notifications component reads it on load (localStorage.notoast === 'true'
    // means "don't toast"). Runs on every page in the context, so it survives
    // reloads too. Always write the value rather than only setting it when
    // disabling: contexts start from storageState.json, which can already carry
    // a notoast from a previous test, and a spec that opts out (notifications)
    // needs it actually removed.
    await context.addInitScript((disable: boolean) => {
      // Runs in every frame, including sandboxed iframes (e.g. the screen
      // ButtonWidget command sandbox) whose opaque origin has no localStorage
      // access - guard so we don't throw a SecurityError there.
      try {
        if (disable) {
          window.localStorage.setItem('notoast', 'true')
        } else {
          window.localStorage.removeItem('notoast')
        }
      } catch {
        // Sandboxed/cross-origin frame: nothing to set here.
      }
    }, disableToasts)
    await page.goto(`${baseURL}${toolPath}`, { waitUntil: 'domcontentloaded' })
    let utils = new Utilities(page)
    if (process.env.ENTERPRISE === '1') {
      const signin = page.getByText('Sign in to your account')
      const tool = page.locator(`.v-app-bar:has-text('${toolName}')`)
      await expect(signin.or(tool)).toBeVisible({ timeout: 20000 })
      if (await signin.isVisible()) {
        // Tests tagged with @admin will use admin credentials, otherwise operator
        let username = 'operator'
        let password = 'operator'
        if (
          test.info().tags.includes('@admin') ||
          page.url().includes('admin')
        ) {
          username = 'admin'
          password = 'admin'
        }
        // Persisting the refreshed session is load-bearing, not just a cache:
        // the admin/operator choice above is inferred from the @admin tag or an
        // 'admin' tool path, so a spec that only sets
        // `storageState: adminStorageState.json` (e.g. systemhealth) would come
        // back through here as *operator* if its saved session had gone stale.
        // Keeping the file fresh is what stops that. Safe because every spec
        // that logs out mid-test runs in the single-worker *.s.spec.ts batch, so
        // these fixed paths are never written by two workers at once.
        await page.locator('input[name="username"]').fill(username)
        await page.locator('input[name="password"]').fill(password)
        await Promise.all([
          page.waitForURL(`${baseURL}${toolPath}`),
          page.locator('button:has-text("Sign In")').click(),
        ])
        await saveAuthState(
          page.context(),
          username === 'admin' ? ADMIN_STORAGE_STATE : STORAGE_STATE,
        )
      }
    }
    await expect(page.locator('.v-app-bar')).toContainText(toolName, {
      timeout: 20000,
    })
    await page.locator('rux-icon-apps').getByRole('img').click()
    await expect(page.locator('#openc3-nav-drawer')).not.toBeInViewport()

    // This is like a yield in a Ruby block where we call back to the
    // test and execute the individual test code
    await use(utils)

    if (collectCoverage(browserName)) {
      context.off('page', startCoverage)
      // Only pages still open can be read; ones the test closed itself are lost.
      for (const open of context.pages()) {
        await stopCoverage(open)
      }
    }
  },
})
export { expect } from '@playwright/test'
