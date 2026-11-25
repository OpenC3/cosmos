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

import { test, expect } from './fixture'

test.use({
  toolPath: '/tools/cmdsender',
  toolName: 'Command Sender',
})

// The bytes of the last INST SETPARAMS command sent, straight from the API
function setparamsBuffer(page) {
  return page.evaluate(async () => {
    const response = await fetch('/openc3-api/api', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json-rpc',
        Authorization: localStorage.openc3Token,
      },
      body: JSON.stringify({
        jsonrpc: '2.0',
        method: 'get_cmd_buffer',
        params: ['INST', 'SETPARAMS'],
        id: 1,
        keyword_params: { scope: 'DEFAULT' },
      }),
    })
    const { result } = await response.json()
    return result.buffer.raw
  })
}

async function toggleMode(page, mode) {
  await page.locator('[data-test=command-sender-mode]').click()
  await page.getByText(mode).click()
  await page.locator('[data-test=command-sender-mode]').click()
}

// In order to test parameter conversions we have to look at the raw buffer.
// INST SETPARAMS has a parameter conversion, so send it, check the buffer,
// then send it with parameter conversions disabled and check it changed.
// This is serial because other tests send SETPARAMS too, which would change
// the buffer get_cmd_buffer returns. Every other Command Sender test is
// parallel (command-sender.p.spec.ts).
test('disable parameter conversions', async ({ page, utils }) => {
  await page.locator('[data-test="clear-history"]').click()
  await utils.selectTargetPacketItem('INST', 'SETPARAMS')
  await expect(page.locator('main')).toContainText('Value 1 setting') // Ensures the params are rendered
  await page.locator('[data-test="select-send"]').click()
  await expect(page.locator('main')).toContainText(
    'cmd("INST SETPARAMS with VALUE1 1, VALUE2 1, VALUE3 1, VALUE4 1, VALUE5 1, BIGINT 0") sent',
  )
  // VALUE1 1 is converted to 2
  await expect
    .poll(async () => (await setparamsBuffer(page)).slice(16, 18))
    .toEqual([2, 0])

  await toggleMode(page, 'Disable Parameter')
  await page.locator('[data-test="select-send"]').click()
  await page.getByRole('dialog').getByRole('button', { name: 'Send' }).click() // Hazardous confirm
  await expect(page.locator('main')).toContainText(
    'cmd_raw("INST SETPARAMS with VALUE1 1, VALUE2 1, VALUE3 1, VALUE4 1, VALUE5 1, BIGINT 0") sent',
  )
  // Sent raw, so VALUE1 stays 1
  await expect
    .poll(async () => (await setparamsBuffer(page)).slice(16, 18))
    .toEqual([1, 0])

  // With range checks ignored too the history shows cmd_raw_no_range_check
  await toggleMode(page, 'Ignore Range Checks')
  await page.locator('[data-test="select-send"]').click()
  await page.getByRole('dialog').getByRole('button', { name: 'Send' }).click() // Hazardous confirm
  await expect(page.locator('main')).toContainText(
    'cmd_raw_no_range_check("INST SETPARAMS with VALUE1 1, VALUE2 1, VALUE3 1, VALUE4 1, VALUE5 1, BIGINT 0") sent',
  )
  await expect(page.locator('[data-test=history-entry]').first()).toContainText(
    'cmd_raw_no_range_check("INST SETPARAMS',
  )
  await expect
    .poll(async () => (await setparamsBuffer(page)).slice(16, 18))
    .toEqual([1, 0])
})
