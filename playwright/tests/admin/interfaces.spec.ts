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
  toolPath: '/tools/admin/interfaces',
  toolName: 'Administrator',
  storageState: 'adminStorageState.json',
})

test('displays interface names', async ({ page, utils }) => {
  expect(await page.getByText('INST_INT')).toBeVisible()
  expect(await page.getByText('INST2_INT')).toBeVisible()
  expect(await page.getByText('EXAMPLE_INT')).toBeVisible()
  expect(await page.getByText('TEMPLATED_INT')).toBeVisible()
  // SYSTEM has no interface
  expect(await page.getByText('SYSTEM')).not.toBeVisible()
})

test('displays interface details', async ({ page, utils }) => {
  await page.getByRole('button', { name: '󰈈' }).first().click()
  expect(await page.locator('.editor')).toContainText('"name": "EXAMPLE_INT"')
  await utils.download(page, '[data-test="downloadIcon"]', function (contents) {
    expect(contents).toContain('"name": "EXAMPLE_INT"')
  })
  await page.getByRole('button', { name: 'Ok' }).click()
})
