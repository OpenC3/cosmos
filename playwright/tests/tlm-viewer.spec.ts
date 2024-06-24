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
  toolPath: '/tools/tlmviewer',
  toolName: 'Telemetry Viewer',
})

test.beforeEach(async ({ page, utils }) => {
  // Throw exceptions on any pageerror events
  page.on('pageerror', (exception) => {
    throw exception
  })
})

async function showScreen(page, target, screen, callback = null) {
  await page.locator('div[role="button"]:has-text("Select Target")').click()
  await page.locator(`.v-list-item__title:text-is("${target}")`).click()
  await page.locator('div[role="button"]:has-text("Select Screen")').click()
  await page.locator(`.v-list-item__title:text-is("${screen}")`).click()
  await page.locator('[data-test="show-screen"]').click()
  await expect(
    page.locator(`.v-system-bar:has-text("${target} ${screen}")`),
  ).toBeVisible()
  if (callback) {
    await callback()
  }
  await page.locator('[data-test=close-screen-icon]').click()
  await expect(
    page.locator(`.v-system-bar:has-text("${target} ${screen}")`),
  ).not.toBeVisible()
}

test('changes targets', async ({ page, utils }) => {
  // Must use regex for name because INST is auto selected
  await page.getByRole('button', { name: /Select Target/ }).click()
  await page.getByText('SYSTEM').click()
  await expect(page.getByRole('listbox')).not.toBeVisible()
  await page.getByRole('button', { name: 'Select Screen' }).click()
  await expect(page.getByRole('listbox')).toHaveText('STATUS')
  await expect(page.getByRole('listbox')).not.toHaveText('ADCS')
})

test('displays INST ADCS', async ({ page, utils }) => {
  await showScreen(page, 'INST', 'ADCS')
})

test('displays INST ARRAY', async ({ page, utils }) => {
  await showScreen(page, 'INST', 'ARRAY')
})

test('displays INST BLOCK', async ({ page, utils }) => {
  await showScreen(page, 'INST', 'BLOCK')
})

test('displays INST COMMANDING', async ({ page, utils }) => {
  await showScreen(page, 'INST', 'COMMANDING', async function () {
    await page.getByRole('button', { name: 'NORMAL' }).click()
    await page.getByRole('option', { name: 'NORMAL' }).click()
    await page.getByRole('button', { name: 'Start Collect' }).click()
    // Send clear command which is hazardous
    await page.getByRole('button', { name: 'Send' }).click()
    await expect(
      page.getByText('Warning: Command is Hazardous. Send?'),
    ).toBeVisible()
    await page.getByRole('dialog').getByRole('button', { name: 'Send' }).click()

    await page.getByRole('button', { name: 'collect.rb' }).click()
    await page.getByText('checks.rb').click()
    const page1Promise = page.waitForEvent('popup')
    await page.getByRole('button', { name: 'Run Script' }).click()
    const page1 = await page1Promise
    await expect(page1.locator('[data-test=state]')).toHaveValue('error', {
      timeout: 30000,
    })
    await page1.locator('[data-test="stop-button"]').click()
    await page1.close()
  })
})

test('displays INST GRAPHS', async ({ page, utils }) => {
  await showScreen(page, 'INST', 'GRAPHS')
})

test('displays INST GROUND', async ({ page, utils }) => {
  await showScreen(page, 'INST', 'GROUND')
})

test('displays INST HS', async ({ page, utils }) => {
  await showScreen(page, 'INST', 'HS', async function () {
    await expect(page.locator('text=Health and Status')).toBeVisible()
    await page.locator('[data-test=minimize-screen-icon]').click()
    await expect(page.locator('text=Health and Status')).not.toBeVisible()
    await page.locator('[data-test=maximize-screen-icon]').click()
    await expect(page.locator('text=Health and Status')).toBeVisible()
  })
})

test('displays INST IMAGE', async ({ page, utils }) => {
  await showScreen(page, 'INST', 'IMAGE')
})

test('displays INST LATEST', async ({ page, utils }) => {
  await showScreen(page, 'INST', 'LATEST')
})

test('displays INST LAUNCHER', async ({ page, utils }) => {
  await page.locator('div[role="button"]:has-text("Select Target")').click()
  await page.locator(`.v-list-item__title:text-is("INST")`).click()
  await page.locator('div[role="button"]:has-text("Select Screen")').click()
  await page.locator(`.v-list-item__title:text-is("LAUNCHER")`).click()
  await expect(
    page.locator('.v-system-bar:has-text("INST LAUNCHER")'),
  ).toBeVisible()
  await page.getByRole('button', { name: 'HS', exact: true }).click()
  await expect(page.locator('.v-system-bar:has-text("INST HS")')).toBeVisible()
  await page.getByRole('button', { name: 'CMD', exact: true }).click()
  await expect(
    page.locator('.v-system-bar:has-text("INST COMMANDING")'),
  ).toBeVisible()
  await page.getByRole('button', { name: 'GROUND', exact: true }).click()
  await expect(
    page.locator('.v-system-bar:has-text("INST GROUND")'),
  ).toBeVisible()
  await page.getByRole('button', { name: 'Close HS & CMD' }).click()
  await expect(
    page.locator('.v-system-bar:has-text("INST HS")'),
  ).not.toBeVisible()
  await expect(
    page.locator('.v-system-bar:has-text("INST COMMANDING")'),
  ).not.toBeVisible()
  await expect(
    page.locator('.v-system-bar:has-text("INST GROUND")'),
  ).toBeVisible()
  await page.getByRole('button', { name: 'Close All' }).click()
  await expect(
    page.locator('.v-system-bar:has-text("INST GROUND")'),
  ).not.toBeVisible()
  await expect(
    page.locator('.v-system-bar:has-text("INST LAUNCHER")'),
  ).not.toBeVisible()
})

test('displays INST LIMITS', async ({ page, utils }) => {
  await showScreen(page, 'INST', 'LIMITS')
})

test('displays INST OTHER', async ({ page, utils }) => {
  await showScreen(page, 'INST', 'OTHER')
})

test('displays INST PARAMS', async ({ page, utils }) => {
  await showScreen(page, 'INST', 'PARAMS')
})

test('displays INST ROLLUP', async ({ page, utils }) => {
  await showScreen(page, 'INST', 'ROLLUP')
})

test('displays INST SIMPLE', async ({ page, utils }) => {
  const text = 'TEST' + Math.floor(Math.random() * 10000)
  await showScreen(page, 'INST', 'SIMPLE', async function () {
    await expect(page.locator(`text=${text}`)).not.toBeVisible()
    await page.locator('[data-test=edit-screen-icon]').click()
    await page.locator('textarea').fill(`
    SCREEN AUTO AUTO 0.5
    LABEL ${text}
    BIG INST HEALTH_STATUS TEMP2
    `)
    await page.locator('button:has-text("Save")').click()
    await expect(page.locator(`text=${text}`)).toBeVisible()
    await page.locator('[data-test=edit-screen-icon]').click()
    await expect(
      page.locator(`.v-system-bar:has-text("Edit Screen")`),
    ).toBeVisible()
    await utils.download(
      page,
      '[data-test=download-screen-icon]',
      function (contents) {
        expect(contents).toContain(`LABEL ${text}`)
        expect(contents).toContain('BIG INST HEALTH_STATUS TEMP2')
      },
    )
    await page.locator('button:has-text("Cancel")').click()
    await expect(
      page.locator(`.v-system-bar:has-text("Edit Screen")`),
    ).not.toBeVisible()
  })
})

test('displays INST TABS', async ({ page, utils }) => {
  await showScreen(page, 'INST', 'TABS')
})

test('displays INST WEB', async ({ page, utils }) => {
  await showScreen(page, 'INST', 'WEB')
})

// Create the screen name as upcase because OpenC3 upcases the name
let screen = 'SCREEN' + Math.floor(Math.random() * 10000)
test('creates new blank screen', async ({ page, utils }) => {
  await page.locator('[data-test="new-screen"]').click()
  await expect(
    page.locator(`.v-system-bar:has-text("New Screen")`),
  ).toBeVisible()
  await page
    .getByRole('dialog')
    .getByRole('button', { name: 'Select Target INST' })
    .click()
  await page.getByText('INST2').click()
  // Check trying to create an existing screen
  await page.locator('[data-test="new-screen-name"]').fill('adcs')
  await expect(page.locator('.v-dialog')).toContainText(
    'Screen ADCS already exists!',
  )
  await page.locator('[data-test="new-screen-name"]').fill(screen)
  await page.getByRole('button', { name: 'Save' }).click()
  await expect(
    page.locator(`.v-system-bar:has-text("INST2 ${screen}")`),
  ).toBeVisible()
})

test('creates new screen based on packet', async ({ page, utils }) => {
  await page.locator('[data-test="new-screen"]').click()
  await expect(
    page.locator(`.v-system-bar:has-text("New Screen")`),
  ).toBeVisible()
  await page.locator('[data-test="new-screen-packet"]').click()
  await page.getByRole('option', { name: 'HEALTH_STATUS' }).click()
  expect(await page.inputValue('[data-test=new-screen-name]')).toMatch(
    'health_status',
  )
  await page.getByRole('button', { name: 'Save' }).click()
  await expect(
    page.locator(`.v-system-bar:has-text("INST HEALTH_STATUS")`),
  ).toBeVisible()
})

test('deletes new screens', async ({ page, utils }) => {
  await deleteScreen(page, 'INST2', screen)
  await deleteScreen(page, 'INST', 'HEALTH_STATUS')
})

async function deleteScreen(page, target, screen) {
  await page.locator('div[role="button"]:has-text("Select Target")').click()
  await page.locator(`.v-list-item__title:text-is("${target}")`).click()
  await page.locator('div[role="button"]:has-text("Select Screen")').click()
  await page.locator(`.v-list-item__title:text-is("${screen}")`).click()
  await expect(
    page.locator(`.v-system-bar:has-text("${target} ${screen}")`),
  ).toBeVisible()
  await page.locator('[data-test=edit-screen-icon]').click()
  await page.locator('[data-test=delete-screen-icon]').click()
  await page.locator('button:has-text("Delete")').click()
  await page.locator('div[role="button"]:has-text("Select Screen")').click()
  await expect(
    page.locator(`.v-list-item__title:text-is("${screen}")`),
  ).not.toBeVisible()
}
