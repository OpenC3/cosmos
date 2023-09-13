/*
# Copyright 2023 OpenC3, Inc.
# All Rights Reserved.
#
# This program is free software; you can modify and/or redistribute it
# under the terms of the GNU Affero General Public License
# as published by the Free Software Foundation; version 3 with
# attribution addendums as found in the LICENSE.txt
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU Affero General Public License for more details.
*/

// import { test as setup } from './fixture'
import { test as setup } from '@playwright/test'

import { STORAGE_STATE, ADMIN_STORAGE_STATE } from './../playwright.config'

setup('global setup', async ({ page }) => {
  await page.goto('/tools/cmdtlmserver')
  if (process.env.ENTERPRISE === '1') {
    await page.locator('input[name="username"]').fill('operator')
    await page.locator('input[name="password"]').fill('operator')
    await page.locator('input:has-text("Sign In")').click()
    await page.waitForURL('**/tools/cmdtlmserver')
    await new Promise((resolve) => setTimeout(resolve, 500))
    // Save signed-in state to 'storageState.json'.
    await page.context().storageState({ path: STORAGE_STATE })

    // On the initial load you might get the Clock out of sync dialog
    if (await page.getByText('Clock out of sync').isVisible()) {
      await page.locator("text=Don't show this again").click()
      await page.locator('button:has-text("Dismiss")').click()
    }

    const { chromium } = require('chromium') // Or 'chromium' or 'webkit'.
    ;(async () => {
      const browser = await chromium.launch()
      const adminPage = await browser.newPage()
      await adminPage.goto('/tools/cmdtlmserver')
      await new Promise((resolve) => setTimeout(resolve, 500))
      await adminPage.locator('input[name="username"]').fill('admin')
      await adminPage.locator('input[name="password"]').fill('admin')
      await adminPage.locator('input:has-text("Sign In")').click()
      await new Promise((resolve) => setTimeout(resolve, 500))
      // Save signed-in state to 'adminStorageState.json'.
      await adminPage.context().storageState({ path: ADMIN_STORAGE_STATE })

      await browser.close()
    })()
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
      await page.fill('data-test=new-password', 'password')
      await page.locator('button:has-text("Login")').click()
    } else {
      await page.fill('data-test=new-password', 'password')
      await page.fill('data-test=confirm-password', 'password')
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
})
