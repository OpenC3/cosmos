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
  toolPath: '/tools/admin/targets',
  toolName: 'Administrator',
  storageState: 'adminStorageState.json',
})

test('displays target names and associated plugin', async ({ page, utils }) => {
  expect(await page.getByRole('list')).toContainText('INST')
  expect(await page.getByRole('list')).toContainText('INST2')
  expect(await page.getByRole('list')).toContainText('SYSTEM')
  expect(await page.getByRole('list')).toContainText('EXAMPLE')
  expect(await page.getByRole('list')).toContainText('TEMPLATED')
  expect(await page.getByRole('list')).toContainText(
    /Plugin: openc3-cosmos-demo-\d+\.\d+\.\d+/
  )
})

test('displays target details', async ({ page, utils }) => {
  await page
    .getByRole('listitem')
    .filter({ hasText: /^INST/ })
    .nth(0)
    .getByRole('button', { name: '󰈈' })
    .click()
  expect(await page.locator('.editor')).toContainText('"name": "INST"')
  await utils.download(page, '[data-test="downloadIcon"]', function (contents) {
    expect(contents).toContain('"name": "INST"')
  })
  await page.locator('[data-test="editCancelBtn"]').click()
})

// NOTE: Downloading modified files from the target is performed in plugins.spec.ts
