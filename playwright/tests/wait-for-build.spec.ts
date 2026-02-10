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
import { test, expect } from './fixture'

test('waits for the services to deploy and connect', async ({
  page,
  utils,
}) => {
  test.setTimeout(5 * 60 * 1000) // 5 minutes
  await page.goto('/tools/cmdtlmserver')
  await expect(page.locator('.v-app-bar')).toContainText('CmdTlmServer')
  // Check the 3rd column (nth starts at 0) on the row containing INST_INT says CONNECTED
  await expect(
    page
      .locator('[data-test="interfaces-table"]')
      .locator('tr:has-text("INST_INT") td >> nth=2'),
  ).toContainText('CONNECTED', {
    timeout: 120000,
  })
  await expect(
    page
      .locator('[data-test="interfaces-table"]')
      .locator('tr:has-text("INST2_INT") td >> nth=2'),
  ).toContainText('CONNECTED', {
    timeout: 60000,
  })
})
