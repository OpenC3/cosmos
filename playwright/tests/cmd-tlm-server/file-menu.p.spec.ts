/*
# Copyright 2022 Ball Aerospace & Technologies Corp.
# All Rights Reserved.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
# See LICENSE.md for more details.
#
# Modified by OpenC3, Inc.
# All changes Copyright 2026, OpenC3, Inc.
# All Rights Reserved
*/

import { test, expect } from './../fixture'

test.use({
  toolPath: '/tools/cmdtlmserver',
  toolName: 'CmdTlmServer',
})

// Changing the polling rate is fraught with danger because it's all
// about waiting for changes and detecting changes. It mostly works
// but we skip it since it's fairly flaky.
test.skip('changes the polling rate', async ({ page, utils }) => {
  await page.locator('[data-test=cmdtlmserver-file]').click()
  await page.locator('[data-test=cmdtlmserver-file-options]').click()
  await page.locator('.v-dialog input').fill('5000')
  await page.locator('.v-dialog input').press('Enter')
  await page.locator('.v-dialog').press('Escape')
  await utils.sleep(1000)
  let rxbytes = await page.$('tr:has-text("INST_INT") td >> nth=7')
  const count1 = await rxbytes?.textContent()
  await utils.sleep(2500)
  expect(await rxbytes?.textContent()).toBe(count1)
  await utils.sleep(2500)
  // Now it's been more than 5s so it shouldn't match
  expect(await rxbytes?.textContent()).not.toBe(count1)
  // Set it back to 1000
  await page.locator('[data-test=cmdtlmserver-file]').click()
  await page.locator('[data-test=cmdtlmserver-file-options]').click()
  await page.locator('.v-dialog input').fill('1000')
  await page.locator('.v-dialog input').press('Enter')
  await page.locator('.v-dialog').press('Escape')
})

test('stops posting to the api after closing', async ({ page, utils }) => {
  // Only count the Interfaces tab's polling requests. Counting every request
  // the page makes is flaky because unrelated periodic traffic (auth token
  // refresh, notifications, cable reconnects) can fire at any time.
  const isPoll = (url: string, postData: string | null) =>
    url.includes('/openc3-api/api') &&
    !!postData?.includes('"get_all_interface_info"')
  let requestCount = 0
  page.on('request', (request) => {
    if (isPoll(request.url(), request.postData())) {
      requestCount++
    }
  })
  // Wait for polling to actually start rather than assuming it has after a
  // fixed sleep. App boot can take longer than that on a loaded CI runner.
  await page.waitForRequest((request) =>
    isPoll(request.url(), request.postData()),
  )
  // Navigating away must tear down the polling interval
  await page.goto('/tools/tablemanager') // No get_all_interface_info requests
  await expect(page.locator('.v-app-bar')).toContainText('Table Manager')
  const count = requestCount
  await utils.sleep(2000) // Allow potential API requests to happen
  expect(requestCount).toBe(count) // no change
})
