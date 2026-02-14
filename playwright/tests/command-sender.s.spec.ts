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

test.use({
  toolPath: '/tools/cmdsender',
  toolName: 'Command Sender',
})

// In order to test parameter conversions we have to look at the raw buffer
// Thus we send the INST SET PARAMS command which has a parameter conversion,
// check the raw buffer, then send it with parameter conversions disabled,
// and re-check the raw buffer for a change.
// This test has to run serially because other tests which send SETPARAMS commands
// will break it due to the way we check the command buffer with get_cmd_buffer
test('disable parameter conversions', async ({ page, utils }) => {
  await page.locator('[data-test="clear-history"]').click()
  await utils.selectTargetPacketItem('INST', 'SETPARAMS')
  await expect(page.locator('main')).toContainText('Sets numbered parameters')
  await expect(page.locator('main')).toContainText('Value 1 setting') // Ensures the params are rendered
  await page.locator('[data-test="select-send"]').click()
  await page.locator('rux-icon-apps').getByRole('img').click()

  await page.locator('text=Script Runner').click()
  await expect(page.locator('.v-app-bar')).toContainText('Script Runner')
  await page
    .locator('textarea')
    .fill('puts get_cmd_buffer("INST", "SETPARAMS")["buffer"].formatted')
  await page.locator('[data-test=start-button]').click()
  await expect(page.locator('[data-test=state] input')).toHaveValue(
    'Connecting...',
    {
      timeout: 5000,
    },
  )
  await expect(page.locator('[data-test=state] input')).toHaveValue(
    'completed',
    {
      timeout: 20000,
    },
  )
  await expect(page.locator('[data-test=output-messages]')).toContainText(
    '00000010: 02 00',
  )

  await page.locator('text=Command Sender').click()
  await expect(page.locator('.v-app-bar')).toContainText('Command Sender')
  await page.locator('[data-test=command-sender-mode]').click()
  await page.locator('text=Disable Parameter').click()
  await page.locator('[data-test=command-sender-mode]').click()

  await utils.selectTargetPacketItem('INST', 'SETPARAMS')
  await expect(page.locator('main')).toContainText('Sets numbered parameters')
  await expect(page.locator('main')).toContainText('Value 1 setting') // Ensures the params are rendered
  await page.locator('[data-test="select-send"]').click()
  await expect(page.locator('main')).toContainText(
    'cmd_raw("INST SETPARAMS with VALUE1 1, VALUE2 1, VALUE3 1, VALUE4 1, VALUE5 1, BIGINT 0") sent',
  )
  await page.locator('[data-test=sender-history] div').filter({
    hasText:
      'cmd_raw("INST SETPARAMS with VALUE1 1, VALUE2 1, VALUE3 1, VALUE4 1, VALUE5 1, BIGINT 0")',
  })

  // Disable range checks just to verify the command history 'cmd_raw_no_range_check'
  await page.locator('[data-test=command-sender-mode]').click()
  await page.locator('text=Ignore Range Checks').click()
  await page.locator('[data-test=command-sender-mode]').click()
  await page.locator('[data-test="select-send"]').click()
  await expect(page.locator('main')).toContainText(
    'cmd_raw_no_range_check("INST SETPARAMS with VALUE1 1, VALUE2 1, VALUE3 1, VALUE4 1, VALUE5 1, BIGINT 0") sent',
  )
  await page.locator('[data-test=sender-history] div').filter({
    hasText:
      'cmd_raw_no_range_check("INST SETPARAMS with VALUE1 1, VALUE2 1, VALUE3 1, VALUE4 1, VALUE5 1, BIGINT 0")',
  })

  await page.locator('text=Script Runner').click()
  await expect(page.locator('.v-app-bar')).toContainText('Script Runner')
  // Should load the previous script so we can just click start
  await page.locator('[data-test=start-button]').click()
  await expect(page.locator('[data-test=state] input')).toHaveValue(
    'Connecting...',
    {
      timeout: 5000,
    },
  )
  await expect(page.locator('[data-test=state] input')).toHaveValue(
    'completed',
    {
      timeout: 20000,
    },
  )
  await expect(page.locator('[data-test=output-messages]')).toContainText(
    '00000010: 01 00',
  )
})
