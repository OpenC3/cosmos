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
  toolPath: '/tools/admin/routers',
  toolName: 'Administrator',
  storageState: 'adminStorageState.json',
})

test('displays interface names', async ({ page, utils }) => {
  expect(await page.getByRole('list')).toContainText('INST_ROUTER')
})

test('displays interface details', async ({ page, utils }) => {
  await page
    .getByRole('listitem')
    .filter({ hasText: 'INST_ROUTER' })
    .getByRole('button')
    .click()
  expect(await page.locator('.editor')).toContainText('"name": "INST_ROUTER"')
  await utils.download(page, '[data-test="downloadIcon"]', function (contents) {
    expect(contents).toContain('"name": "INST_ROUTER"')
  })
  await page.getByRole('button', { name: 'Ok' }).click()
})
