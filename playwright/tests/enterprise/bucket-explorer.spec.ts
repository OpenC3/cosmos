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

// @ts-check
import { test, expect } from './../fixture'

test.use({
  toolPath: '/tools/bucketexplorer',
  toolName: 'Bucket Explorer',
  storageState: 'adminStorageState.json',
})

test('enterprise upload and delete', async ({ page, utils }) => {
  // Admin can upload and delete anywhere but normal users can not
  await page.getByText('config').click()
  await expect(page).toHaveURL(/.*\/tools\/bucketexplorer\/config%2F/)
  await expect(page.locator('[data-test="file-path"]')).toHaveText('/')
  await utils.sleep(500) // Ensure the table is rendered before getting the count
  let count = await page.locator('tbody > tr').count()

  // Note that Promise.all prevents a race condition
  // between clicking and waiting for the file chooser.
  const [fileChooser1] = await Promise.all([
    // It is important to call waitForEvent before click to set up waiting.
    page.waitForEvent('filechooser'),
    // Opens the file chooser.
    await page.getByRole('button', { name: 'prepended action' }).click(),
  ])
  await fileChooser1.setFiles('package.json')
  await expect(page.locator('tbody > tr')).toHaveCount(count + 1)
  await expect(page.getByRole('cell', { name: 'package.json' })).toBeVisible()
  await page
    .locator('tr:has-text("package.json") [data-test="delete-file"]')
    .click()
  await page.locator('[data-test="confirm-dialog-delete"]').click()
  await expect(page.locator('tbody > tr')).toHaveCount(count)

  // Switch to the operator
  await page.getByRole('button', { name: 'The Admin' }).click()
  await page.getByRole('button', { name: 'Logout' }).click()
  await page.waitForURL('**/auth/**')
  await page.locator('input[name="username"]').fill('operator')
  await page.locator('input[name="password"]').fill('operator')
  await page.getByRole('button', { name: 'Sign In' }).click()
  await page.waitForURL('**/tools/bucketexplorer/**')

  // Note that Promise.all prevents a race condition
  // between clicking and waiting for the file chooser.
  const [fileChooser2] = await Promise.all([
    // It is important to call waitForEvent before click to set up waiting.
    page.waitForEvent('filechooser'),
    // Opens the file chooser.
    await page.getByRole('button', { name: 'prepended action' }).click(),
  ])
  await fileChooser2.setFiles('package.json')
  await expect(page.getByText('Unauthorized')).toBeVisible()
})
