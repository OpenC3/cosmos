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
  toolPath: '/tools/admin/interfaces',
  toolName: 'Administrator',
  storageState: 'adminStorageState.json',
})

test('displays interface names', async ({ page, utils }) => {
  await expect(page.getByText('INST_INT')).toBeVisible()
  await expect(page.getByText('INST2_INT')).toBeVisible()
  await expect(page.getByText('EXAMPLE_INT')).toBeVisible()
  await expect(page.getByText('TEMPLATED_INT')).toBeVisible()
  // SYSTEM has no interface
  await expect(page.getByText('SYSTEM')).not.toBeVisible()
})

test('displays interface details', async ({ page, utils }) => {
  await page.locator('[aria-label="Show Interface Details"]').first().click()
  await expect(page.locator('.editor')).toContainText('"name": "EXAMPLE_INT"')
  await utils.download(page, '[data-test="downloadIcon"]', function (contents) {
    expect(contents).toContain('"name": "EXAMPLE_INT"')
  })
  await page.getByRole('button', { name: 'Ok' }).click()
})
