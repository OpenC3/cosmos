/*
# Copyright 2022 Ball Aerospace & Technologies Corp.
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
#
# Modified by OpenC3, Inc.
# All changes Copyright 2022, OpenC3, Inc.
# All Rights Reserved
*/

// @ts-check
import { test, expect } from './../fixture'

test.use({
  toolPath: '/tools/cmdtlmserver/cmd-packets',
  toolName: 'CmdTlmServer',
})

test('displays the list of command', async ({ page, utils }) => {
  // When we ask for just text there are no spaces
  await expect(page.locator('text=INSTABORT')).toBeVisible()
  await expect(page.locator('text=INSTCLEAR')).toBeVisible()
  await expect(page.locator('text=INSTCOLLECT')).toBeVisible()
  await expect(page.locator('text=EXAMPLESTART')).toBeVisible()
})

test('displays the command count', async ({ page, utils }) => {
  await page
    .locator(
      'div.v-card__title:has-text("Command Packets") >> input[type="text"]'
    )
    .fill('abort')
  await utils.sleep(2000) // Allow the table to filtered and telemetry settle
  const count = parseInt(
    await page
      .locator('[data-test=cmd-packets-table] >> tr td >> nth=2')
      .textContent()
  )
  // Send an ABORT command
  await page.goto('/tools/cmdsender/INST/ABORT')
  await page.locator('[data-test=select-send]').click()
  await expect(page.locator('main')).toContainText('cmd("INST ABORT") sent')
  await page
    .locator('[data-test="sender-history"] div')
    .filter({ hasText: 'cmd("INST ABORT")' })

  await page.goto('/tools/cmdtlmserver/cmd-packets')
  await page
    .locator(
      'div.v-card__title:has-text("Command Packets") >> input[type="text"]'
    )
    .fill('abort')
  await utils.sleep(2000) // Allow the table to filtered and telemetry settle
  const count2 = parseInt(
    await page
      .locator('[data-test=cmd-packets-table] >> tr td >> nth=2')
      .textContent()
  )
  expect(count2).toEqual(count + 1)
})

test('displays a raw command', async ({ page, utils }) => {
  await expect(page.locator('text=INSTABORT')).toBeVisible()
  await page
    .getByRole('row', { name: 'INST ABORT' })
    .getByRole('button', { name: 'View Raw' })
    .click()
  await expect(page.locator('.v-dialog')).toContainText(
    'Raw Command Packet: INST ABORT'
  )
  await expect(page.locator('.v-dialog')).toContainText('Received Time:')
  await expect(page.locator('.v-dialog')).toContainText('Count:')
  expect(await page.inputValue('.v-dialog textarea')).toMatch('Address')
  expect(await page.inputValue('.v-dialog textarea')).toMatch('00000000:')

  await utils.download(page, '[data-test=download]', function (contents) {
    expect(contents).toMatch('Raw Command Packet: INST ABORT')
    expect(contents).toMatch('Received Time:')
    expect(contents).toMatch('Count:')
    expect(contents).toMatch('Address')
    expect(contents).toMatch('00000000:')
  })
  await page.locator('.v-dialog').press('Escape')
  await expect(page.locator('.v-dialog')).not.toBeVisible()
})

test('links to command sender', async ({ page, utils }) => {
  await expect(page.locator('text=INSTCOLLECT')).toBeVisible()
  const [newPage] = await Promise.all([
    page.context().waitForEvent('page'),
    await page.locator('text=INSTCOLLECT >> td >> nth=4').click(),
  ])
  await expect(newPage.locator('.v-app-bar')).toContainText('Command Sender', {
    timeout: 30000,
  })
  await expect(newPage.locator('id=openc3-tool')).toContainText(
    'Starts a collect on the INST target'
  )
})
