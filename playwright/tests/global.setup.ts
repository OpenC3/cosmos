/*
# Copyright 2026 OpenC3, Inc.
# All Rights Reserved.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
# See LICENSE.md for more details.
*/

import { test as setup, expect, Page } from '@playwright/test'
import { STORAGE_STATE, ADMIN_STORAGE_STATE } from './../playwright.config'

// Take the demo sim targets out of QUIET mode. The demo boots quiet
// (INST/lib/sim_inst.rb @quiet = true, INST2/lib/sim_inst.py self.quiet = True),
// and QUIET suppresses every limits violation: temps cycle inside in-limits
// bands, GROUND1STATUS/GROUND2STATUS are pinned CONNECTED, PARAMS VALUE2/VALUE4
// write 0 (GREEN) and the NaN/Infinity injection into TEMP2 is disabled. Specs
// that assert on red/yellow limits (limits-monitor, data-extractor's NaN checks,
// the enterprise autonomic TEMP1 == RED_HIGH and GROUND2STATUS != CONNECTED
// triggers) need it off. QUIET is sim-microservice global state, so setting it
// once per playwright invocation is enough.
//
// The command is only sent after the interfaces report CONNECTED below;
// commanding while they are still coming up gets a 500 from the API.
async function resetQuiet(page: Page) {
  for (const target of ['INST', 'INST2']) {
    const status = await page.evaluate(async (target) => {
      const response = await fetch('/openc3-api/api', {
        method: 'POST',
        headers: {
          Authorization: localStorage.openc3Token,
          'Content-Type': 'application/json-rpc',
          manual: 'true',
        },
        body: JSON.stringify({
          jsonrpc: '2.0',
          method: 'cmd',
          params: `${target} QUIET with STATE FALSE`,
          id: 1,
          keyword_params: { scope: 'DEFAULT' },
        }),
      })
      return response.status
    }, target)
    expect(status).toBe(200)
  }
}

// init.sh loads the demo plugin well before the rest of the tools, so
// "INST_INT is CONNECTED" is not a signal that plugin installation has
// finished. A tool that is not yet in /openc3-api/map.json is never registered
// with single-spa, and tool-base renders its catch-all 404 instead - which is
// what specs see as `.v-app-bar` never containing the tool name. Wait for the
// last tool each init.sh installs before running anything.
async function waitForTools(page: Page) {
  // Keep in sync with the tail of openc3-cosmos-init/init.sh and
  // openc3-cosmos-enterprise-init/init.sh. Only inline tools get an import map
  // entry, so the marker is the last *inline* tool each script loads: docs and
  // grafana are url-based (iframe) tools and never appear here.
  const required = ['@openc3/tool-bucketexplorer']
  if (process.env.ENTERPRISE === '1') {
    required.push('@openc3/tool-logexplorer')
  }
  await expect
    .poll(
      async () => {
        const response = await page.request.get('/openc3-api/map.json')
        if (!response.ok()) return []
        const imports = (await response.json()).imports || {}
        return required.filter((tool) => tool in imports)
      },
      {
        message: `waiting for ${required.join(', ')} in the import map`,
        timeout: 180000,
      },
    )
    .toEqual(required)
}

// Wait for the services to deploy and the demo interfaces to connect. This runs
// here rather than in a separate spec so that any single-file run
// (e.g. `pnpm playwright test ./tests/command-sender.p.spec.ts
// --project=chromium`) also gets a connected, non-QUIET demo.
async function waitForBuild(page: Page) {
  await expect(page.locator('.v-app-bar')).toContainText('CmdTlmServer')
  // Check the 3rd column (nth starts at 0) on the row containing INST_INT says CONNECTED
  await expect(
    page
      .locator('[data-test="interfaces-table"]')
      .locator('tr:has-text("INST_INT") td >> nth=2'),
  ).toContainText('CONNECTED', {
    timeout: 120000,
  })
  await expect(
    page
      .locator('[data-test="interfaces-table"]')
      .locator('tr:has-text("INST2_INT") td >> nth=2'),
  ).toContainText('CONNECTED', {
    timeout: 60000,
  })
}

setup('global setup', async ({ page }) => {
  // 8 minutes to build, deploy and connect: waitForTools can spend up to 3
  // minutes waiting out plugin installation before waitForBuild's own
  // 120s + 60s interface waits even start.
  setup.setTimeout(8 * 60 * 1000)
  await page.goto('/tools/cmdtlmserver')
  if (process.env.ENTERPRISE === '1') {
    await page.getByLabel('Username or email').fill('operator')
    await page.getByLabel('Password', { exact: true }).fill('operator')
    await page.getByRole('button', { name: 'Sign In' }).click()
    await page.waitForURL('**/tools/cmdtlmserver')
    await expect(page.locator('nav:has-text("CmdTlmServer")')).toBeVisible()
    // Save signed-in state to 'storageState.json'.
    await page.context().storageState({ path: STORAGE_STATE })

    // On the initial load you might get the Clock out of sync dialog
    if (await page.getByText('Clock out of sync').isVisible()) {
      await page.locator("text=Don't show this again").click()
      await page.locator('button:has-text("Dismiss")').click()
    }

    // Logout and log back in as admin
    await page.getByText('The Operator', { exact: true }).click()
    await page.getByRole('button', { name: 'Logout', exact: true }).click()
    await page.waitForURL('**/auth/**')
    await page.getByLabel('Username or email').fill('admin')
    await page.getByLabel('Password', { exact: true }).fill('admin')
    await page.getByRole('button', { name: 'Sign In' }).click()
    await page.waitForURL('**/tools/cmdtlmserver')
    await expect(page.locator('nav:has-text("CmdTlmServer")')).toBeVisible()
    // Save signed-in state to 'adminStorageState.json'.
    await page.context().storageState({ path: ADMIN_STORAGE_STATE })
  } else {
    // Wait for the nav bar to populate
    for (let i = 0; i < 10; i++) {
      await page
        .locator('nav:has-text("CmdTlmServer")')
        .waitFor({ timeout: 30000 })
      // If we don't see CmdTlmServer then refresh the page
      if (!(await page.$('nav:has-text("CmdTlmServer")'))) {
        await page.reload()
        await new Promise((resolve) => setTimeout(resolve, 500))
      }
    }
    if (await page.getByText('Enter the password').isVisible()) {
      await page.getByLabel('Password').fill('password')
      await page.locator('button:has-text("Login")').click()
    } else {
      await page.getByLabel('New Password').fill('password')
      await page.getByLabel('Confirm Password').fill('password')
      await page.click('data-test=set-password')
    }
    await new Promise((resolve) => setTimeout(resolve, 500))

    // Save signed-in state to 'storageState.json' and adminStorageState to match Enterprise
    await page.context().storageState({ path: STORAGE_STATE })
    await page.context().storageState({ path: ADMIN_STORAGE_STATE })

    // On the initial load you might get the Clock out of sync dialog
    if (await page.getByText('Clock out of sync').isVisible()) {
      await page.locator("text=Don't show this again").click()
      await page.locator('button:has-text("Dismiss")').click()
    }
  }

  await waitForTools(page)
  await waitForBuild(page)
  await resetQuiet(page)
})
