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
  toolPath: '/tools/cmdtlmserver/tlm-packets',
  toolName: 'CmdTlmServer',
})

test('displays the list of telemetry', async ({ page, utils }) => {
  // When we ask for just text there are no spaces
  await expect(page.locator('text=EXAMPLESTATUS')).toBeVisible()
  await expect(page.locator('text=INSTADCS')).toBeVisible()
  await expect(page.locator('text=INSTHEALTH_STATUS')).toBeVisible()
})

test('displays the packet count', async ({ page, utils }) => {
  await expect(page.locator('text=INSTHEALTH_STATUS')).toBeVisible()
  await utils.sleep(2000) // Allow the telemetry to be fetched
  const hsCountStr = await page.locator('text=INSTHEALTH_STATUS >> td >> nth=2').textContent()
  if (hsCountStr === null) {
    throw new Error("Unable to get HEALTH_STATUS packet count")
  }
  expect(parseInt(hsCountStr)).toBeGreaterThan(50)
  const adcsCountStr = await page.locator('text=INSTADCS >> td >> nth=2').textContent()
  if (adcsCountStr === null) {
    throw new Error("Unable to get HEALTH_STATUS packet count")
  }
  expect(parseInt(adcsCountStr)).toBeGreaterThan(500)
})

test('displays raw packets', async ({ page, utils }) => {
  await expect(page.locator('text=INSTHEALTH_STATUS')).toBeVisible()
  await page
    .getByRole('row', { name: 'INST MECH' })
    .getByRole('button', { name: 'View Raw' })
    .click()
  await expect(page.locator('.raw-dialog')).toContainText(
    'Raw Telemetry Packet: INST MECH',
  )
  await expect(page.locator('.raw-dialog')).toContainText('Received Time:')
  await expect(page.locator('.raw-dialog')).toContainText('Count:')
  expect(await page.inputValue('.raw-dialog textarea')).toMatch('Address')
  expect(await page.inputValue('.raw-dialog textarea')).toMatch('00000000:')

  await utils.download(page, '[data-test=download]', function (contents) {
    expect(contents).toMatch('Raw Telemetry Packet: INST MECH')
    expect(contents).toMatch('Received Time:')
    expect(contents).toMatch('Count:')
    expect(contents).toMatch('Address')
    expect(contents).toMatch('00000000:')
  })

  // Open another raw packet to show we can display more than one
  await page
    .getByRole('row', { name: 'INST PARAMS' })
    .getByRole('button', { name: 'View Raw' })
    .click()
  await expect(page.locator('.raw-dialog')).toHaveCount(2)
  await expect(page.locator('.raw-dialog').nth(1)).toContainText(
    'Raw Telemetry Packet: INST PARAMS',
  )
  await page.locator('[data-test=close]').nth(1).click()
  await expect(page.locator('.raw-dialog')).toHaveCount(1)
  await page.locator('[data-test=close]').click()
  await expect(page.locator('.raw-dialog')).not.toBeVisible()
})

test('links to packet viewer', async ({ page, utils }) => {
  await expect(page.locator('text=INSTHEALTH_STATUS')).toBeVisible()
  const [newPage] = await Promise.all([
    page.context().waitForEvent('page'),
    await page.locator('text=INSTHEALTH_STATUS >> td >> nth=4').click(),
  ])
  await expect(newPage.locator('.v-app-bar')).toContainText('Packet Viewer', {
    timeout: 30000,
  })
  await expect(newPage.locator('id=openc3-tool')).toContainText(
    'Health and status from the INST target',
  )
})
