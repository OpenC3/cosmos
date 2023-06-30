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
  toolPath: '/tools/admin/microservices',
  toolName: 'Administrator',
  storageState: 'adminStorageState.json',
})

test('displays microservice names', async ({ page, utils }) => {
  // There are 9 microservices per target so look for the INST2 list
  expect(await page.getByRole('list')).toContainText('DEFAULT__CLEANUP__INST2')
  expect(await page.getByRole('list')).toContainText(
    'DEFAULT__COMMANDLOG__INST2'
  )
  expect(await page.getByRole('list')).toContainText(
    'DEFAULT__DECOMCMDLOG__INST2'
  )
  expect(await page.getByRole('list')).toContainText('DEFAULT__DECOMLOG__INST2')
  expect(await page.getByRole('list')).toContainText('DEFAULT__DECOM__INST2')
  expect(await page.getByRole('list')).toContainText(
    'DEFAULT__INTERFACE__INST2_INT'
  )
  expect(await page.getByRole('list')).toContainText('DEFAULT__MULTI__INST2')
  expect(await page.getByRole('list')).toContainText(
    'DEFAULT__PACKETLOG__INST2'
  )
  expect(await page.getByRole('list')).toContainText('DEFAULT__REDUCER__INST2')
})

test('displays microservice details', async ({ page, utils }) => {
  await page
    .getByRole('listitem')
    .filter({ hasText: 'DEFAULT__CLEANUP__INST2' })
    .getByRole('button')
    .click()
  expect(await page.locator('.editor')).toContainText(
    '"name": "DEFAULT__CLEANUP__INST2"'
  )
  await utils.download(page, '[data-test="downloadIcon"]', function (contents) {
    expect(contents).toContain('"name": "DEFAULT__CLEANUP__INST2"')
  })
  await page.locator('[data-test="editCancelBtn"]').click()
})
