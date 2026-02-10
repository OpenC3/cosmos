/*
# Copyright 2022 Ball Aerospace & Technologies Corp.
# All Rights Reserved.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
# See LICENSE.md for more details.
#
# Modified by OpenC3, Inc.
# All changes Copyright 2026, OpenC3, Inc.
# All Rights Reserved
*/

// @ts-check
import { test, expect } from './../fixture'

test.use({
  toolPath: '/tools/cmdtlmserver/interfaces',
  toolName: 'CmdTlmServer',
})

test('disconnects and connects an interface', async ({ page, utils }) => {
  await expect(
    page.locator('tr:has-text("INST2_INT") td >> nth=2'),
  ).toContainText('CONNECTED')
  await page.locator('tr:has-text("INST2_INT") td >> nth=1').click()
  await expect(
    page.locator('tr:has-text("INST2_INT") td >> nth=2'),
  ).toContainText('DISCONNECTED')
  await expect(page.locator('[data-test=log-messages]')).toContainText(
    'INST2_INT: Disconnect',
  )
  await page.locator('tr:has-text("INST2_INT") td >> nth=1').click()
  await expect(
    page.locator('tr:has-text("INST2_INT") td >> nth=2'),
  ).toContainText('CONNECTED')
  await expect(page.locator('[data-test=log-messages]')).toContainText(
    'INST2_INT: Connection Success',
  )
})
