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
