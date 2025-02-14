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
import { test, expect } from './fixture'

test.use({
  toolPath: '/tools/packetviewer',
  toolName: 'Packet Viewer',
})

// Checks the ITEM value against a regular expression.
async function matchItem(page, item, regex) {
  // Poll since inputValue is immediate
  await expect
    .poll(async () => {
      return await page.inputValue(`tr:has(td div:text-is("${item}")) input`)
    })
    .toMatch(regex)
}

test('displays INST HEALTH_STATUS and polls the api', async ({
  page,
  utils,
}) => {
  // Verify we can hit it using the route
  await page.goto('/tools/packetviewer/INST/HEALTH_STATUS')
  await expect(page.locator('.v-app-bar')).toContainText('Packet Viewer')
  await utils.dropdownSelectedValue(page, '[data-test=select-target]', 'INST')
  await utils.dropdownSelectedValue(
    page,
    '[data-test=select-packet]',
    'HEALTH_STATUS',
  )
  await expect(page.locator('id=openc3-tool')).toContainText(
    'Health and status',
  ) // Description

  page.on('request', (request) => {
    expect(request.url()).toMatch('/openc3-api/api')
  })
  page.on('response', (response) => {
    expect(response.status()).toBe(200)
  })
  await utils.sleep(2000)
})

test('selects a target and packet to display', async ({ page, utils }) => {
  await utils.selectTargetPacketItem('INST', 'IMAGE')
  await utils.dropdownSelectedValue(page, '[data-test=select-target]', 'INST')
  await utils.dropdownSelectedValue(page, '[data-test=select-packet]', 'IMAGE')
  await expect(page.locator('id=openc3-tool')).toContainText(
    'Packet with image data',
  )
  await expect(page.locator('id=openc3-tool')).toContainText('BYTES')
})

test('gets help info', async ({ page, utils }) => {
  await utils.selectTargetPacketItem('INST', 'IMAGE')
  await page.locator('.v-data-table-footer > i').hover()
  await expect(page.getByText('Name with * indicates DERIVED')).toBeVisible()
  await expect(page.getByText('Right click name to pin item')).toBeVisible()
  await expect(
    page.getByText('Right click value for details / graph'),
  ).toBeVisible()

  const [newPage] = await Promise.all([
    page.context().waitForEvent('page'),
    await page.getByRole('link', { name: 'DERIVED' }).click(),
  ])
  await newPage.waitForURL('**/docs/configuration/telemetry#derived-items')
})

test('gets details with right click', async ({ page, utils }) => {
  await utils.selectTargetPacketItem('INST', 'HEALTH_STATUS')
  await page
    .getByRole('cell', { name: 'TEMP1', exact: true })
    .locator('xpath=..') // parent row
    .locator('[data-test="value"]')
    .click({
      button: 'right',
    })
  await page.getByText('Details', { exact: true }).click()
  await expect(page.locator('.v-overlay--active')).toBeVisible()
  await expect(page.locator('.v-overlay--active')).toContainText(
    'INST HEALTH_STATUS TEMP1',
  )
  // Check that a few of the details are there ... that proves the API request
  await expect(page.locator('.v-overlay--active')).toContainText('UINT')
  await expect(page.locator('.v-overlay--active')).toContainText(
    'PolynomialConversion',
  )
  await expect(page.locator('.v-overlay--active')).toContainText('CELSIUS')
  await expect(page.locator('.v-overlay--active')).toContainText(
    'ExampleLimitsResponse',
  )

  // Get out of the details dialog
  await page.locator('[data-test="notifications"]').click({ force: true })
  await expect(page.locator('.v-overlay--active')).not.toBeVisible()

  // Scroll to the top to allow better right click
  await page.mouse.wheel(0, 0)
  await utils.sleep(100)
  await page
    .getByRole('row', { name: 'PACKET_TIMESECONDS' })
    .locator('[data-test="value"]')
    .click({
      button: 'right',
    })
  await page.getByText('Details', { exact: true }).click()
  await expect(page.locator('.v-overlay--active')).toBeVisible()
  await expect(page.locator('.v-overlay--active')).toContainText(
    'INST HEALTH_STATUS PACKET_TIMESECONDS',
  )
  // Check that a few of the details are there ... that proves the API request
  await expect(page.locator('.v-overlay--active')).toContainText('DERIVED')
  await expect(page.locator('.v-overlay--active')).toContainText(
    'PacketTimeSecondsConversion',
  )
})

test('stops posting to the api after closing', async ({ page, utils }) => {
  await utils.selectTargetPacketItem('INST', 'ADCS')
  let requestCount = 0
  page.on('request', () => {
    requestCount++
  })
  await utils.sleep(2000)
  // Commenting out the next two lines causes the test to fail
  await page.goto('/tools/tablemanager') // No API requests
  await expect(page.locator('.v-app-bar')).toContainText('Table Manager')
  const count = requestCount
  await utils.sleep(2000) // Allow potential API requests to happen
  expect(requestCount).toBe(count) // no change
})

// Changing the polling rate is fraught with danger because it's all
// about waiting for changes and detecting changes
test('changes the polling rate', async ({ page, utils }) => {
  await utils.selectTargetPacketItem('INST', 'HEALTH_STATUS')
  await page.locator('[data-test=packet-viewer-file]').click()
  await page.locator('[data-test=packet-viewer-file-options]').click()
  await page
    .locator('.v-dialog [data-test=refresh-interval] input')
    .fill('5000')
  await page
    .locator('.v-dialog [data-test=refresh-interval] input')
    .press('Enter')
  await page.locator('.v-dialog').press('Escape')
  const received = parseInt(await page.inputValue('tr:has-text("RECEIVED_COUNT") input'))
  await utils.sleep(7000)
  const received2 = parseInt(await page.inputValue('tr:has-text("RECEIVED_COUNT") input'))
  expect(received2 - received).toBeLessThanOrEqual(6) // Allow slop
  expect(received2 - received).toBeGreaterThanOrEqual(4) // Allow slop
  // Set it back
  await page.locator('[data-test=packet-viewer-file]').click()
  await page.locator('[data-test=packet-viewer-file-options]').click()
  await page
    .locator('.v-dialog [data-test=refresh-interval] input')
    .fill('1000')
  await page
    .locator('.v-dialog [data-test=refresh-interval] input')
    .press('Enter')
  await page.locator('.v-dialog').press('Escape')
})

//
// Test the View menu
//
test('displays formatted items with units by default', async ({
  page,
  utils,
}) => {
  await utils.selectTargetPacketItem('INST', 'HEALTH_STATUS')
  // Check for exactly 3 decimal points followed by units
  await matchItem(page, 'TEMP1', /^-?\d+\.\d{3}\s\S$/)
})

test('displays formatted items with units', async ({ page, utils }) => {
  await utils.selectTargetPacketItem('INST', 'HEALTH_STATUS')
  await page.locator('[data-test="search"] input').fill('TEMP1')
  await page.locator('[data-test=packet-viewer-view]').click()
  await page.locator('text=Formatted Items with Units').click()
  // Check for exactly 3 decimal points followed by units
  await matchItem(page, 'TEMP1', /^-?\d+\.\d{3}\s\S$/)
})

test('displays raw items', async ({ page, utils }) => {
  await utils.selectTargetPacketItem('INST', 'HEALTH_STATUS')
  await page.locator('[data-test="search"] input').fill('TEMP1')
  await page.locator('[data-test=packet-viewer-view]').click()
  await page.locator('text=Raw').click()
  // // Check for a raw number 1 to 99999
  await matchItem(page, 'TEMP1', /^\d{1,5}$/)
})

test('displays converted items', async ({ page, utils }) => {
  await utils.selectTargetPacketItem('INST', 'HEALTH_STATUS')
  await page.locator('[data-test="search"] input').fill('TEMP1')
  await page.locator('[data-test=packet-viewer-view]').click()
  await page.locator('text=Converted').click()
  // Check for unformatted decimal points (4+)
  await matchItem(page, 'TEMP1', /^-?\d+\.\d{4,}$/)
})

test('displays formatted items', async ({ page, utils }) => {
  await utils.selectTargetPacketItem('INST', 'HEALTH_STATUS')
  await page.locator('[data-test="search"] input').fill('TEMP1')
  await page.locator('[data-test=packet-viewer-view]').click()
  // Use text-is because we have to match exactly since there is
  // also a 'Formatted Items with Units' option
  await page.locator(':text-is("Formatted Items")').click()
  // Check for exactly 3 decimal points
  await matchItem(page, 'TEMP1', /^-?\d+\.\d{3}$/)
})

test('shows ignored items', async ({ page, utils }) => {
  await utils.selectTargetPacketItem('INST', 'HEALTH_STATUS')
  await page.locator('[data-test=packet-viewer-view]').click()
  await page.locator('text=Display Derived').click()
  await expect(page.locator('text=Display Derived')).not.toBeVisible()
  await expect(page.getByRole('cell', { name: 'CCSDSVER' })).not.toBeVisible()
  await page.locator('[data-test=packet-viewer-view]').click()
  await page.locator('text=Show Ignored').click()
  await expect(page.locator('text=Show Ignored')).not.toBeVisible()
  await expect(page.getByRole('cell', { name: 'CCSDSVER' })).toBeVisible()
  await page.locator('[data-test=packet-viewer-view]').click()
  await page.locator('text=Show Ignored').click()
  await expect(page.getByRole('cell', { name: 'CCSDSVER' })).not.toBeVisible()
})

test('displays derived first', async ({ page, utils }) => {
  await utils.selectTargetPacketItem('INST', 'HEALTH_STATUS')
  // First row (0) is the header: Index, Name, Value
  await expect(page.locator('tr').nth(1)).toContainText('PACKET_TIMESECONDS')
  await page.locator('[data-test=packet-viewer-view]').click()
  await page.locator('text=Display Derived').click()
  await expect(page.locator('text=Display Derived')).not.toBeVisible()
  await expect(page.locator('tr').nth(1)).toContainText('TIMESEC')
  // Check 2 because TIMESEC is included in PACKET_<TIMESEC>ONDS
  // so the first check could result in a false positive
  await expect(page.locator('tr').nth(2)).toContainText('TIMEUS')
})

test('pins items to the top of the list', async ({ page, utils }) => {
  await utils.selectTargetPacketItem('INST', 'HEALTH_STATUS')
  // Default sort order
  await expect(page.locator('tr').nth(1)).toContainText('PACKET_TIMESECONDS *')

  await page.getByText('PACKET_TIME *').click({
    button: 'right',
  })
  await page.getByText('Pin Item', { exact: true }).click()
  await expect(page.locator('tr').nth(1)).toContainText('PACKET_TIME *')
  // Verify pin is not affected by sorting
  await page.getByText('Name', { exact: true }).click()
  await expect(page.locator('tr').nth(1)).toContainText('PACKET_TIME *')
  await page.getByText('Name', { exact: true }).click()
  await expect(page.locator('tr').nth(1)).toContainText('PACKET_TIME *')
  await page.getByText('Name', { exact: true }).click()
  await expect(page.locator('tr').nth(1)).toContainText('PACKET_TIME *')
  await page.getByText('Value', { exact: true }).click()
  await expect(page.locator('tr').nth(1)).toContainText('PACKET_TIME *')
  await page.getByText('Value', { exact: true }).click()
  await expect(page.locator('tr').nth(1)).toContainText('PACKET_TIME *')
  await page.getByText('Value', { exact: true }).click()
  await expect(page.locator('tr').nth(1)).toContainText('PACKET_TIME *')

  await page.locator('[data-test="search"] input').fill('GROUND')
  await expect(page.locator('tr').nth(1)).toContainText('PACKET_TIME *')
  await page.getByText('GROUND1STATUS', { exact: true }).click({
    button: 'right',
  })
  await page.getByText('Pin Item', { exact: true }).click()
  await page.locator('[data-test="search"] input').fill('')
  // Default sort order is packet order so PACKET_TIME is first
  await expect(page.locator('tr').nth(1)).toContainText('PACKET_TIME *')
  await expect(page.locator('tr').nth(2)).toContainText('GROUND1STATUS')

  await page.getByText('GROUND1STATUS', { exact: true }).click({
    button: 'right',
  })
  await page.getByText('Unpin Item').click()
  await expect(page.locator('tr').nth(1)).toContainText('PACKET_TIME *')
  await expect(page.locator('tr').nth(2)).not.toContainText('GROUND1STATUS')

  await page.locator('[data-test="packet-viewer-file"]').click()
  await page.getByText('Reset Configuration').click()
  // Return to default sort order
  await expect(page.locator('tr').nth(1)).toContainText('PACKET_TIMESECONDS *')
})
