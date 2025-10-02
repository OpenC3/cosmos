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
# All changes Copyright 2025, OpenC3, Inc.
# All Rights Reserved
*/

// @ts-check
import { test, expect } from './../fixture'

test.use({
  toolPath: '/tools/scriptrunner',
  toolName: 'Script Runner',
})

test('finds text on page', async ({ page, utils }) => {
  // Have to fill on an editable area like the textarea
  let string = `openc3 is a command and control system
openc3 can send commands and execute scripts
openc3 is everything I thought it could be`
  await page.locator('textarea').fill(string)
  await page.locator('[data-test=script-runner-edit]').click()
  await page.locator('[data-test=script-runner-edit-find] >> text=Find').click()
  await page.locator('[placeholder="Search for"]').fill('openc3')
  await expect(page.locator('text=1 of 3')).toBeVisible()
  await page.locator('textarea').press('Escape')

  await page.locator('[data-test=script-runner-edit]').click()
  await page
    .locator('[data-test=script-runner-edit-replace] >> text=Replace')
    .click()
  await page.locator('[placeholder="Search for"]').fill('openc3')
  await page.locator('[placeholder="Replace with"]').fill('OpenC3')
  await page.locator('text=All').nth(1).click() // Replace All
  await page.locator('textarea').press('Escape')
  if (process.platform === 'darwin') {
    await page.locator('textarea').press('Meta+F') // Ctrl-S save
  } else {
    await page.locator('textarea').press('Control+F') // Ctrl-S save
  }
  await page.locator('[placeholder="Search for"]').fill('openc3')
  await expect(page.locator('text=1 of 3')).toBeVisible()
  await page.locator('text=Aa').click()
  await expect(page.locator('text=0 of 0')).toBeVisible()
})

test('inserts and edits commands', async ({ page, utils }) => {
  // await page.locator('textarea').click({ button: 'right' })
  await page.locator('.ace_content').click({
    button: 'right',
  })
  await page.getByText('Insert Command').click()
  await utils.selectTargetPacketItem('INST', 'ABORT')
  await page.getByRole('button', { name: 'Insert Command' }).click()

  await page.locator('.ace_content').click({
    button: 'right',
  })
  await page.getByText('Insert Command').click()
  await utils.selectTargetPacketItem('INST', 'COLLECT')
  await page
    .locator('[data-test="cmd-param-select"]')
    .getByRole('combobox')
    .first()
    .click()
  await page.getByRole('option', { name: 'NORMAL' }).click()
  await page.getByRole('button', { name: 'Insert Command' }).click()

  await expect(page.locator('.ace_content')).toContainText(
    'cmd("INST ABORT")\n',
  )
  await expect(page.locator('.ace_content')).toContainText(
    'cmd("INST COLLECT with TYPE \'NORMAL\', DURATION 1, OPCODE 0xAB, TEMP 0")\n',
  )
})
