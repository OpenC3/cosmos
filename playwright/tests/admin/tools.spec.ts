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
  toolPath: '/tools/admin/tools',
  toolName: 'Administrator',
  storageState: 'adminStorageState.json',
})

test('displays tool names', async ({ page, utils }) => {
  expect(await page.getByRole('list')).toContainText('CmdTlmServer')
  expect(await page.getByRole('list')).toContainText('Limits Monitor')
  expect(await page.getByRole('list')).toContainText('Command Sender')
  expect(await page.getByRole('list')).toContainText('Script Runner')
  expect(await page.getByRole('list')).toContainText('Packet Viewer')
  expect(await page.getByRole('list')).toContainText('Telemetry Viewer')
  expect(await page.getByRole('list')).toContainText('Telemetry Grapher')
  expect(await page.getByRole('list')).toContainText('Data Extractor')
  expect(await page.getByRole('list')).toContainText('Data Viewer')
  expect(await page.getByRole('list')).toContainText('Handbooks')
  expect(await page.getByRole('list')).toContainText('Table Manager')
  expect(await page.getByRole('list')).toContainText('Calendar')
  expect(await page.getByRole('list')).toContainText('Autonomic')
})

test('adds a new tool', async ({ page, utils }) => {
  await page.getByLabel('Tool Icon').fill('mdi-file')
  await page.getByLabel('Tool Name').fill('OpenC3Home')
  await page.getByLabel('Tool Url').fill('https://openc3.com')
  await page.locator('[data-test="toolAdd"]').click()
  await page.reload()
  await page.getByRole('link', { name: 'OpenC3Home' }).click()
  await page.waitForURL('https://openc3.com/');
})
