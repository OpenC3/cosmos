/*
# Copyright 2022 OpenC3. Inc
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
  toolPath: '/tools/cmdsender',
  toolName: 'Command Sender',
})

test('sends a command as operator but not as viewer', async ({
  page,
  utils,
}) => {
  await utils.selectTargetPacketItem('INST', 'ABORT')
  await page.locator('button:has-text("Send")').click()
  await expect(page.locator('main')).toContainText('cmd("INST ABORT") sent')

  await page.locator('[data-test=user-menu]').click()
  await Promise.all([
    page.waitForNavigation(),
    page.locator('button:has-text("Logout")').click(),
  ])

  await page.locator('input[name="username"]').fill('viewer')
  await page.locator('input[name="password"]').fill('viewer')
  await Promise.all([
    page.waitForNavigation(),
    page.locator('input:has-text("Sign In")').click(),
  ])

  await utils.selectTargetPacketItem('INST', 'ABORT')
  await page.locator('button:has-text("Send")').click()
  await page.locator(
    'span:has-text("Error sending INST ABORT due to OpenC3::AuthError")'
  )
  await page.locator('[data-test=error-dialog-ok]').click()
})
