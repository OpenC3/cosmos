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
# All changes Copyright 2023, OpenC3, Inc.
# All Rights Reserved
*/

// @ts-check
import { test, expect } from './fixture'

test.use({
  toolPath: '/tools/dataviewer',
  toolName: 'Data Viewer',
})

async function addComponent(page, utils, target, packet) {
  await page.locator('[data-test=new-tab]').click()
  await utils.selectTargetPacketItem(target, packet)
  await page.locator('[data-test=select-send]').click() // add the packet to the list
  await page.locator('[data-test=add-component]').click()
}

test('saves the configuration', async ({ page, utils }) => {
  await addComponent(page, utils, 'INST', 'ADCS')
  await page.locator('[data-test="tab"]').click({
    button: 'right',
  })
  await page.locator('[data-test="context-menu-rename"]').click()
  await page.locator('[data-test="rename-tab-input"]').fill('Test1')
  await page.locator('[data-test="rename"]').click()
  await expect(page.getByRole('tab', { name: 'Test1' })).toBeVisible()
  // Change a display setting
  await page.locator('[data-test=history-component-open-settings]').click()
  await expect(page.locator('[data-test=display-settings-card]')).toBeVisible()
  await page
    .locator('[data-test=history-component-settings-history]')
    .fill('200')
  await page.locator('#openc3-menu >> text=Data Viewer').click({ force: true })

  // Add a new component with a different type
  await page.locator('[data-test=new-tab]').click()
  await page.getByRole('button', { name: 'COSMOS Raw/Decom' }).click()
  await page.getByText('Current Time').click()
  await utils.selectTargetPacketItem('INST', 'HEALTH_STATUS')
  await page.locator('[data-test=select-send]').click() // add the packet to the list
  await page.locator('[data-test=add-component]').click()
  await page.locator('[data-test="tab"]').nth(1).click({
    button: 'right',
  })
  await page.locator('[data-test="context-menu-rename"]').click()
  await page.locator('[data-test="rename-tab-input"]').fill('Test2')
  await page.locator('[data-test="rename"]').click()
  await expect(page.getByRole('tab', { name: 'Test2' })).toBeVisible()

  await page.locator('[data-test="data-viewer-file"]').click()
  await page.locator('text=Save Configuration').click()
  await page
    .locator('[data-test="name-input-save-config-dialog"]')
    .fill('playwright')
  await page.locator('button:has-text("Ok")').click()
  await expect(page.getByText(`Saved configuration: playwright`)).toBeVisible()
})

test('opens and resets the configuration', async ({ page, utils }) => {
  // Open the config
  await page.locator('[data-test="data-viewer-file"]').click()
  await page.locator('text=Open Configuration').click()
  await page.locator(`td:has-text("playwright")`).click()
  await page.locator('button:has-text("Ok")').click()
  await page.getByRole('button', { name: 'Dismiss' }).click({ timeout: 20000 })

  // Verify the config
  await page.getByRole('tab', { name: 'Test1' }).click()
  await expect(page.getByText('COSMOS Raw/Decom')).toBeVisible()
  // Verify display setting
  await page.locator('[data-test=history-component-open-settings]').click()
  await expect(page.locator('[data-test=display-settings-card]')).toBeVisible()
  expect(
    await page.inputValue('[data-test=history-component-settings-history]'),
  ).toMatch('200')
  await page.locator('#openc3-menu >> text=Data Viewer').click({ force: true })
  await expect(
    page.locator('[data-test=display-settings-card]'),
  ).not.toBeVisible()
  await page.getByRole('tab', { name: 'Test2' }).click()
  await expect(page.getByText('Current Time:')).toBeVisible()

  // Reset this test configuration
  await page.locator('[data-test=data-viewer-file]').click()
  await page.locator('text=Reset Configuration').click()
  await utils.sleep(200) // Allow menu to close
  await expect(page.getByText("You're not viewing any packets")).toBeVisible()

  // Delete this test configuration
  await page.locator('[data-test="data-viewer-file"]').click()
  await page.locator('text=Open Configuration').click()
  await page
    .locator(`tr:has-text("playwright") [data-test=item-delete]`)
    .click()
  await page.locator('button:has-text("Delete")').click()
  await page.locator('[data-test=open-config-cancel-btn]').click()
})

test('adds a raw packet to a new tab', async ({ page, utils }) => {
  await addComponent(page, utils, 'INST', 'ADCS')
  await page.locator('[data-test=start-button]').click()
  await utils.sleep(500)
  expect(
    await page.inputValue('[data-test=history-component-text-area]'),
  ).toMatch('Received seconds:')
  expect(
    await page.inputValue('[data-test=history-component-text-area]'),
  ).toMatch('00000010:')
  expect(
    await page.inputValue('[data-test=history-component-text-area]'),
  ).toMatch('00000020:')
})

test('adds a decom packet to a new tab', async ({ page, utils }) => {
  await page.locator('[data-test=new-tab]').click()
  await utils.selectTargetPacketItem('INST', 'ADCS')
  await page.locator('label:has-text("Decom")').click()
  await page.locator('[data-test=add-packet-value-type]').click()
  await page.getByRole('option', { name: 'CONVERTED' }).click()
  await page.locator('[data-test=select-send]').click() // add the packet to the list
  await page.locator('[data-test=add-component]').click()
  await page.locator('[data-test=start-button]').click()
  await utils.sleep(500)
  expect(
    await page.inputValue('[data-test=history-component-text-area]'),
  ).toMatch('POSX:')
  expect(
    await page.inputValue('[data-test=history-component-text-area]'),
  ).toMatch('POSY:')
  expect(
    await page.inputValue('[data-test=history-component-text-area]'),
  ).toMatch('POSZ:')
  expect(
    await page.inputValue('[data-test=history-component-text-area]'),
  ).not.toMatch('00000010:')
})

test('adds a custom component a new tab', async ({ page, utils }) => {
  await page.locator('[data-test=new-tab]').click()
  await page.locator('[data-test="select-component"]').click()
  await page.getByText('Quaternion').click()
  await utils.selectTargetPacketItem('INST', 'ADCS')
  await page.locator('label:has-text("Decom")').click()
  await page.locator('[data-test=select-send]').click() // add the packet to the list
  await page.locator('[data-test=add-component]').click()

  await page.locator('[data-test=start-button]').click()
  await utils.sleep(500)
  expect(
    await page.inputValue('[data-test=history-component-text-area]'),
  ).toMatch(/(.*\n)+Magnitude:.*/)
  await page.locator('[data-test=history-component-search]').fill('Magnitude:')
  // Poll since inputValue is immediate
  await expect
    .poll(async () => {
      return await page.inputValue('[data-test=history-component-text-area]')
    })
    .toMatch(/^Magnitude:.*$/)
})

test('renames a tab', async ({ page, utils }) => {
  await addComponent(page, utils, 'INST', 'ADCS')
  await page.locator('[data-test=tab]').click({ button: 'right' })
  await page.locator('[data-test=context-menu-rename] > div').click()
  await page.locator('[data-test=rename-tab-input]').fill('Testing tab name')
  await page.locator('[data-test=rename]').click()
  await expect(page.locator('.v-tab')).toHaveText('Testing tab name')
  await page.locator('[data-test=tab]').click({ button: 'right' })
  await page.locator('[data-test=context-menu-rename] > div').click()
  await page.locator('[data-test=rename-tab-input]').fill('Cancel this')
  await page.locator('[data-test=cancel-rename]').click()
  await expect(page.locator('.v-tab')).toHaveText('Testing tab name')
})

test('deletes a component and tab', async ({ page, utils }) => {
  await addComponent(page, utils, 'INST', 'ADCS')
  await expect(
    page.getByRole('tab', { name: 'INST ADCS [ RAW ]' }),
  ).toBeVisible()
  await page.locator('[data-test=delete-component]').click()
  await expect(page.locator('.v-card > .v-card__title').first()).toHaveText(
    "You're not viewing any packets",
  )
})

test('controls playback', async ({ page, utils }) => {
  await addComponent(page, utils, 'INST', 'ADCS')
  await page.locator('[data-test=start-button]').click()
  await utils.sleep(1000) // Allow a few packets to come in
  await page.locator('[data-test=history-component-play-pause]').click()
  await utils.sleep(500) // Ensure it's stopped and draws the last packet contents
  let content: string = await page.inputValue(
    '[data-test=history-component-text-area]',
  )
  // Step back and forth
  await page.getByLabel('prepended action').click()
  expect(content).not.toEqual(
    await page.inputValue('[data-test=history-component-text-area]'),
  )
  await page.getByLabel('appended action').click()
  expect(content).toEqual(
    await page.inputValue('[data-test=history-component-text-area]'),
  )
  // Resume
  await page.locator('[data-test=history-component-play-pause]').click()
  expect(content).not.toEqual(
    await page.inputValue('[data-test=history-component-text-area]'),
  )
  // Stop
  await page.locator('[data-test="stop-button"]').click()
  await utils.sleep(500) // Ensure it's stopped and draws the last packet contents
  content = await page.inputValue('[data-test=history-component-text-area]')
  await utils.sleep(500) // Wait for potential changes
  expect(content).toEqual(
    await page.inputValue('[data-test=history-component-text-area]'),
  )
})

test('changes display settings', async ({ page, utils }) => {
  await addComponent(page, utils, 'INST', 'ADCS')
  await page.locator('[data-test=start-button]').click()
  await utils.sleep(1000) // Allow a few packets to come in
  await page.locator('[data-test=history-component-open-settings]').click()
  await expect(page.locator('[data-test=display-settings-card]')).toBeVisible()
  await page.getByText('Show timestamp').click()
  expect(
    await page.inputValue('[data-test=history-component-text-area]'),
  ).not.toMatch('Received seconds:')
  await page.getByText('Show timestamp').click()
  expect(
    await page.inputValue('[data-test=history-component-text-area]'),
  ).toMatch('Received seconds:')
  await page.getByText('Show ASCII').click()
  expect(
    await page.inputValue('[data-test=history-component-text-area]'),
  ).toMatch(
    /(\s\w\w){16}\s?(?!\s)/, // per https://regex101.com/
  )
  await page.getByText('Show ASCII').click()
  expect(
    await page.inputValue('[data-test=history-component-text-area]'),
  ).toMatch(
    /(\s\w\w){16}\s{4}\S*/, // per https://regex101.com/
  )
  await page.getByText('Show line address').click()
  expect(
    await page.inputValue('[data-test=history-component-text-area]'),
  ).not.toMatch(/00000000:/)
  await page.getByText('Show line address').click()
  expect(
    await page.inputValue('[data-test=history-component-text-area]'),
  ).toMatch(/00000000:/)
  await page
    .locator('[data-test=history-component-settings-num-bytes]')
    .fill('8')
  expect(
    await page.inputValue('[data-test=history-component-text-area]'),
  ).toMatch(
    /(\s\w\w){8}\s{4}\S*/, // per https://regex101.com/
  )

  expect(
    await page.inputValue('[data-test=history-component-text-area]'),
  ).not.toMatch(/Received seconds:(.*\n)+.*Received seconds:/)
  await page
    .locator('[data-test=history-component-settings-num-packets]')
    .fill('2')
  await utils.sleep(100)
  expect(
    await page.inputValue('[data-test=history-component-text-area]'),
  ).toMatch(
    /Received seconds:(.*\n)+.*Received seconds:/, // per https://regex101.com/
  )
})

test('downloads a file', async ({ page, utils }) => {
  await addComponent(page, utils, 'INST', 'ADCS')
  await page.locator('[data-test=start-button]').click()
  await utils.sleep(1000) // Allow a few packets to come in
  await page.locator('[data-test=history-component-play-pause]').click()

  const textarea = await page.inputValue(
    '[data-test=history-component-text-area]',
  )
  await utils.download(
    page,
    '[data-test=history-component-download]',
    function (contents) {
      expect(contents).toEqual(textarea)
    },
  )
})

test('validates start and end time inputs', async ({ page, utils }) => {
  // validate start date
  await page.locator('[data-test=start-date]').fill('')
  await expect(page.getByText('Required')).toBeVisible()
  // Even though the format is mm/dd/yyyy we enter the date like yyyy-mm-dd
  await page.locator('[data-test=start-date]').fill('2020-01-01')
  await expect(page.getByText('Required')).not.toBeVisible()
  await expect(page.getByText('Invalid')).not.toBeVisible()
  // validate start time
  await page.locator('[data-test=start-time]').fill('')
  await expect(page.getByText('Required')).toBeVisible()
  await page.locator('[data-test=start-time]').fill('12:15:15')
  await expect(page.getByText('Required')).not.toBeVisible()
  await expect(page.getByText('Invalid')).not.toBeVisible()

  // validate end date
  await page.locator('[data-test=end-date]').fill('')
  // end date is optional so no Required message
  await expect(page.getByText('Required')).not.toBeVisible()
  // Even though the format is mm/dd/yyyy we enter the date like yyyy-mm-dd
  await page.locator('[data-test=end-date]').fill('2020-01-01')
  await expect(page.getByText('Invalid')).not.toBeVisible()
  // validate end time
  await page.locator('[data-test=end-time]').fill('12:15:16')
  await expect(page.getByText('Required')).not.toBeVisible()
  await expect(page.getByText('Invalid')).not.toBeVisible()
})

test('validates start and end time values', async ({ page, utils }) => {
  // validate future start date
  await page.locator('[data-test=start-date]').fill('4000-01-01')
  await page.locator('[data-test=start-time]').fill('12:15:15')
  await page.locator('[data-test=start-button]').click()
  await expect(page.locator('.warning')).toContainText(
    'Start date/time is in the future!',
  )

  // validate start/end time equal to each other
  await page.locator('[data-test=start-date]').fill('2020-01-01')
  await page.locator('[data-test=start-time]').fill('12:15:15')
  await page.locator('[data-test=end-date]').fill('2020-01-01')
  await page.locator('[data-test=end-time]').fill('12:15:15')
  await page.locator('[data-test=start-button]').click()
  await expect(page.locator('.warning')).toContainText(
    'Start date/time is equal to end date/time!',
  )

  // validate future end date
  await page.locator('[data-test=start-date]').fill('2020-01-01')
  await page.locator('[data-test=start-time]').fill('12:15:15')
  await page.locator('[data-test=end-date]').fill('4000-01-01')
  await page.locator('[data-test=end-time]').fill('12:15:15')
  await page.locator('[data-test=start-button]').click()
  await expect(page.locator('.warning')).toContainText(
    'Note: End date/time is greater than current date/time. Data will continue to stream in real-time until 4000-01-01 12:15:15 is reached.',
  )
})
