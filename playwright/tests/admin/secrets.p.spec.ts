/*
# Copyright 2025 OpenC3, Inc.
# All Rights Reserved.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
# See LICENSE.md for more details.
*/

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
  // Scope to the HIDDEN secret's own row: the list may contain other secrets
  // (e.g. a bridge's private key), so filtering the whole list and grabbing a
  // button matches multiple. The per-row v-list-item isolates this secret.
  await page
    .locator('[data-test="secretList"]')
    .locator('.v-list-item')
    .filter({ hasText: 'HIDDEN' })
    .getByRole('button')
    .click()
  await page.locator('[data-test="confirm-dialog-cancel"]').click()
  await expect(page.locator('[data-test="secretList"]')).toContainText('HIDDEN')
  await page
    .locator('[data-test="secretList"]')
    .locator('.v-list-item')
    .filter({ hasText: 'HIDDEN' })
    .getByRole('button')
    .click()
  await page.locator('[data-test="confirm-dialog-delete"]').click()
  await expect(page.getByText('Removed secret HIDDEN')).toBeVisible()
})
