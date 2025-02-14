/*
# Copyright 2022 Ball Aerospace & Technologies Corp.
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
#
# Modified by OpenC3, Inc.
# All changes Copyright 2025, OpenC3, Inc.
# All Rights Reserved
*/

// @ts-check
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
  let requestCount = 0
  page.on('request', () => {
    requestCount++
  })
  await utils.sleep(2000)
  // Commenting out the next two lines causes the test to fail
  await page.goto('/tools/tablemanager') // No API requests
  await expect(page.locator('.v-app-bar')).toContainText('Table Manager')
  const count = requestCount
  await utils.sleep(2000) // Allow potential API requests to happen
  expect(requestCount).toBe(count) // no change
})
