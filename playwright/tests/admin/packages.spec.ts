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
import { test, expect } from '../fixture'

test.use({
  toolPath: '/tools/admin/packages',
  toolName: 'Administrator',
  storageState: 'adminStorageState.json',
})

test('displays gem names', async ({ page, utils }) => {
  await expect(page.locator('[data-test=packageList]')).toContainText(
    /openc3-cosmos-demo-\d{1,2}\.\d{1,2}\.\d{1,2}.*\.gem/,
  )
  await expect(page.locator('[data-test=packageList]')).toContainText(
    /openc3-cosmos-tool-cmdsender-\d{1,2}\.\d{1,2}\.\d{1,2}.*\.gem/,
  )
})

// TODO:
// test('uploads and removes a gem', async ({ page, utils }) => {})
