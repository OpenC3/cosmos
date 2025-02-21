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
  toolPath: '/tools/admin/targets',
  toolName: 'Administrator',
  storageState: 'adminStorageState.json',
})

test('displays target names and associated plugin', async ({ page, utils }) => {
  await expect(page.locator('[data-test="targetList"]')).toContainText('INST')
  await expect(page.locator('[data-test="targetList"]')).toContainText('INST2')
  await expect(page.locator('[data-test="targetList"]')).toContainText('SYSTEM')
  await expect(page.locator('[data-test="targetList"]')).toContainText(
    'EXAMPLE',
  )
  await expect(page.locator('[data-test="targetList"]')).toContainText(
    'TEMPLATED',
  )
  await expect(page.locator('[data-test="targetList"]')).toContainText(
    /Plugin: openc3-cosmos-demo-\d{1,2}\.\d{1,2}\.\d{1,2}/,
  )
})

test('displays target details', async ({ page, utils }) => {
  await page.locator('.mdi-eye').nth(1).click()
  await expect(page.locator('.editor')).toContainText('"name": "INST"')
  await utils.download(page, '[data-test="downloadIcon"]', function (contents) {
    expect(contents).toContain('"name": "INST"')
  })
  await page.getByRole('button', { name: 'Ok' }).click()
})

// NOTE: Downloading modified files from the target is performed in plugins.spec.ts
