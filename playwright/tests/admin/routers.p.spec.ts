/*
# Copyright 2025 OpenC3, Inc
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

// @ts-check
import { test, expect } from './../fixture'

test.use({
  toolPath: '/tools/admin/routers',
  toolName: 'Administrator',
  storageState: 'adminStorageState.json',
})

test('displays router names', async ({ page, utils }) => {
  await expect(page.getByText('INST_ROUTER')).toBeVisible()
})

test('displays router details', async ({ page, utils }) => {
  await page.locator('[aria-label="Show Router Details"]').first().click()
  await expect(page.locator('.editor')).toContainText('"name": "INST_ROUTER"')
  await utils.download(page, '[data-test="downloadIcon"]', function (contents) {
    expect(contents).toContain('"name": "INST_ROUTER"')
  })
  await page.getByRole('button', { name: 'Ok' }).click()
})
