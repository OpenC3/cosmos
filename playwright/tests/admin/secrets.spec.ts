/*
# Copyright 2023 OpenC3, Inc
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
  toolPath: '/tools/admin/secrets',
  toolName: 'Administrator',
  storageState: 'adminStorageState.json',
})

test('creates a secret', async ({ page, utils }) => {
  await page.getByLabel('Secret Name').fill('HIDDEN')
  await page.getByLabel('Secret Value', { exact: true }).fill('something')
  await page.locator('[data-test="secretUpload"]').click()
  await expect(page.locator('[data-test="secretList"]')).toContainText('HIDDEN')
  await page
    .locator('[data-test="secretList"]')
    .filter({ hasText: 'HIDDEN' })
    .getByRole('button')
    .click()
  await page.locator('[data-test="confirm-dialog-cancel"]').click()
  await expect(page.locator('[data-test="secretList"]')).toContainText('HIDDEN')
  await page
    .locator('[data-test="secretList"]')
    .filter({ hasText: 'HIDDEN' })
    .getByRole('button')
    .click()
  await page.locator('[data-test="confirm-dialog-delete"]').click()
  await expect(page.getByText('Removed secret HIDDEN')).toBeVisible()
})
