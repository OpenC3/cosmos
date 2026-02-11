/*
# Copyright 2025 OpenC3, Inc
# All Rights Reserved.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
# See LICENSE.md for more details.
*/

// @ts-check
import { test, expect } from './../fixture'

test.use({
  toolPath: '/tools/admin/redis',
  toolName: 'Administrator',
  storageState: 'adminStorageState.json',
})

test('sends redis commands', async ({ page, utils }) => {
  await page.getByText('Persistent').click()
  await page.getByLabel('Redis command').fill('ping')
  await page.getByLabel('Redis command').press('Enter')
  await expect(page.locator('table')).toContainText('PersistentpingPONG')
  await page.getByText('Ephemeral').click()
  await page.getByLabel('Redis command').press('Enter')
  await expect(page.locator('table')).toContainText('EphemeralpingPONG')
})
