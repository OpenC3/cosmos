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
import { test, expect } from './../fixture'

test.use({
  toolPath: '/tools/admin/microservices',
  toolName: 'Administrator',
  storageState: 'adminStorageState.json',
})

test('displays microservice names', async ({ page, utils }) => {
  // There are 9 microservices per target so look for the INST2 list
  await expect(page.locator('[data-test="microserviceList"]')).toContainText(
    'DEFAULT__CLEANUP__INST2',
  )
  await expect(page.locator('[data-test="microserviceList"]')).toContainText(
    'DEFAULT__COMMANDLOG__INST2',
  )
  await expect(page.locator('[data-test="microserviceList"]')).toContainText(
    'DEFAULT__DECOMCMDLOG__INST2',
  )
  await expect(page.locator('[data-test="microserviceList"]')).toContainText(
    'DEFAULT__DECOMLOG__INST2',
  )
  await expect(page.locator('[data-test="microserviceList"]')).toContainText(
    'DEFAULT__DECOM__INST2',
  )
  await expect(page.locator('[data-test="microserviceList"]')).toContainText(
    'DEFAULT__INTERFACE__INST2_INT',
  )
  await expect(page.locator('[data-test="microserviceList"]')).toContainText(
    'DEFAULT__MULTI__INST2',
  )
  await expect(page.locator('[data-test="microserviceList"]')).toContainText(
    'DEFAULT__PACKETLOG__INST2',
  )
  await expect(page.locator('[data-test="microserviceList"]')).toContainText(
    'DEFAULT__REDUCER__INST2',
  )
})

test('displays microservice details', async ({ page, utils }) => {
  await page.locator('[aria-label="Show Microservice Details"]').nth(2).click()
  await expect(page.locator('.editor')).toContainText(
    '"name": "DEFAULT__CLEANUP__INST2"',
  )
  await utils.download(page, '[data-test="downloadIcon"]', function (contents) {
    expect(contents).toContain('"name": "DEFAULT__CLEANUP__INST2"')
  })
  await page.getByRole('button', { name: 'Ok' }).click()
})

test('stops and starts microservices', async ({ page, utils }) => {
  await page
    .locator('.v-list-item')
    .filter({ hasText: 'DEFAULT__USER__OPENC3-EXAMPLE' })
    .locator('.mdi-stop')
    .click()
  await page.locator('[data-test="confirm-dialog-stop"]').click()
  await expect(
    page
      .locator('.v-list-item')
      .filter({ hasText: 'DEFAULT__USER__OPENC3-EXAMPLE' }),
  ).toContainText('Enabled: False')

  // Check the CmdTlmServer log messages
  await page.goto('/tools/cmdtlmserver', {
    waitUntil: 'domcontentloaded',
  })
  await expect(page.locator('[data-test=log-messages]')).toContainText(
    'DEFAULT__USER__OPENC3-EXAMPLE stopped',
  )

  await page.goto('/tools/admin/microservices', {
    waitUntil: 'domcontentloaded',
  })
  await page
    .locator('.v-list-item')
    .filter({ hasText: 'DEFAULT__USER__OPENC3-EXAMPLE' })
    .locator('.mdi-play')
    .click()
  await page.locator('[data-test="confirm-dialog-start"]').click()
  await expect(
    page
      .locator('.v-list-item')
      .filter({ hasText: 'DEFAULT__USER__OPENC3-EXAMPLE' }),
  ).toContainText('Enabled: True')

  // Check the CmdTlmServer log messages
  await page.goto('/tools/cmdtlmserver', {
    waitUntil: 'domcontentloaded',
  })
  await expect(page.locator('[data-test=log-messages]')).toContainText(
    'DEFAULT__USER__OPENC3-EXAMPLE started',
  )
})
