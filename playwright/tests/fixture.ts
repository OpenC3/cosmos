/*
# Copyright 2026 OpenC3, Inc.
# All Rights Reserved.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
# See LICENSE.md for more details.
*/

import { expect, test as base } from '@playwright/test'
import { Utilities } from '../utilities'
import { CoverageReport } from 'monocart-coverage-reports'
import coverageOptions from '../coverage.config.mjs'

// V8 coverage is Chromium-only and only collected when COVERAGE is set,
// so normal runs pay no profiler overhead. Requires bundles built with
// sourcemaps: `vite build --mode coverage` (see tool vite.config.js).
const collectCoverage = (browserName: string) =>
  !!process.env.COVERAGE && browserName === 'chromium'

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
      // resetOnNavigation: false keeps counters across the reloads and
      // route changes our tests perform constantly
      await page.coverage.startJSCoverage({ resetOnNavigation: false })
    }
    // Disable alert toast popups before the first navigation so the
    // Notifications component reads it on load (localStorage.notoast === 'true'
    // means "don't toast"). Runs on every page in the context, so it survives
    // reloads too.
    if (disableToasts) {
      await context.addInitScript(() => {
        // Runs in every frame, including sandboxed iframes (e.g. the screen
        // ButtonWidget command sandbox) whose opaque origin has no localStorage
        // access - guard so we don't throw a SecurityError there.
        try {
          window.localStorage.setItem('notoast', 'true')
        } catch {
          // Sandboxed/cross-origin frame: nothing to disable here.
        }
      })
    }
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
        if (username === 'admin') {
          await page.locator('input[name="username"]').fill('admin')
          await page.locator('input[name="password"]').fill('admin')
          await Promise.all([
            page.waitForURL(`${baseURL}${toolPath}`),
            page.locator('button:has-text("Sign In")').click(),
          ])
          await page.context().storageState({ path: 'adminStorageState.json' })
        } else {
          await page.locator('input[name="username"]').fill('operator')
          await page.locator('input[name="password"]').fill('operator')
          await Promise.all([
            page.waitForURL(`${baseURL}${toolPath}`),
            page.locator('button:has-text("Sign In")').click(),
          ])
          await page.context().storageState({ path: 'storageState.json' })
        }
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
      const coverage = await page.coverage.stopJSCoverage()
      // Appends raw V8 data to coverage/.cache (safe across workers AND
      // separate `playwright test` invocations); generate-coverage.mjs
      // merges everything into one report at the end of `pnpm test`
      await new CoverageReport(coverageOptions).add(coverage)
    }
  },
})
export { expect } from '@playwright/test'
