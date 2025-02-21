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
  toolPath: '/tools/admin/settings',
  toolName: 'Administrator',
  storageState: 'adminStorageState.json',
})

test('resets clock sync warning suppression', async ({ page, utils }) => {
  await page.evaluate(
    `window.localStorage['suppresswarning__clock_out_of_sync_with_server'] = true`,
  )
  await page.reload()
  await expect(page.getByText('Clock out of sync with server')).toBeVisible()
  await page.getByText('Select All Warnings').click()
  await page.locator('[data-test=reset-suppressed-warnings]').click()
  await expect(page.locator('id=openc3-tool')).toContainText(
    'No warnings to reset',
  )
})

test('clears default configs', async ({ page, utils }) => {
  // Visit PacketViewer and change a setting
  await page.goto('/tools/packetviewer')
  await expect(page.locator('.v-app-bar')).toContainText('Packet Viewer')
  await page.locator('[data-test=packet-viewer-view]').click()
  await page.locator('text=Show Ignored').click()
  await utils.sleep(100)
  await page.goto('/tools/admin/settings')
  await expect(page.locator('.v-app-bar')).toContainText('Administrator')
  await expect(page.locator('id=openc3-tool')).toContainText('Packet viewer')
  await page.getByText('Select All Configs').click()
  await page.locator('[data-test=clear-default-configs]').click()
  await expect(page.locator('id=openc3-tool')).not.toContainText(
    'Packet viewer',
  )
})

test('hides the astro clock', async ({ page, utils }) => {
  await expect(page.locator('.rux-clock')).toBeVisible()
  await page.getByText('Hide Astro Clock').click()
  await page.locator('[data-test=save-astro-settings]').click()
  await page.reload()
  await expect(page.locator('.rux-clock')).not.toBeVisible()
  await page.getByText('Hide Astro Clock').click()
  await page.locator('[data-test=save-astro-settings]').click()
  await page.reload()
  await expect(page.locator('.rux-clock')).toBeVisible()
})

// Change time zone is tested in the individual apps

test('sets a classification banner', async ({ page, utils }) => {
  const bannerText = 'Test Classification Banner'
  const bannerHeight = '32'
  const bannerTextColor = 'Orange'
  const bannerBackgroundColor = '123'
  await page.check('text=Display top banner')
  await page
    .locator('[data-test="classification-banner-text"]')
    .locator('input')
    .fill(bannerText)
  await page
    .locator('[data-test=classification-banner-top-height]')
    .locator('input')
    .fill(bannerHeight)
  await page
    .locator('[data-test="classification-banner-background-color"]')
    .click()
  // Not sure why this didn't work:
  // await page.getByRole('option', { name: 'Custom' }).click()
  await page.locator('.v-list-item-title:has-text("Custom")').click()
  // Wait for the menu to collapse so the next menu doesn't select it
  await expect(
    page.locator('.v-list-item-title:has-text("Custom")'),
  ).not.toBeVisible()
  await page
    .locator('[data-test="classification-banner-custom-background-color"]')
    .locator('input')
    .fill(bannerBackgroundColor)
  await page.locator('[data-test="classification-banner-font-color"]').click()
  await page
    .locator(`.v-list-item-title:has-text("${bannerTextColor}")`)
    .click()
  await page.locator('[data-test=save-classification-banner]').click()
  await page.reload()
  await expect(page.locator('#app')).toHaveAttribute(
    'style',
    // Chrome doesn't have spaces after the colon and Firefox does
    new RegExp(
      `--classification-text:\\s?"${bannerText}"; --classification-font-color:\\s?${bannerTextColor.toLowerCase()}; --classification-background-color:\\s?#${bannerBackgroundColor}; --classification-height-top:\\s?${bannerHeight}px; --classification-height-bottom:\\s?0px;`,
    ),
  )
  // Disable the classification banner
  await page.uncheck('text=Display top banner')
  await page.locator('[data-test=save-classification-banner]').click()
  await page.reload()
  await expect(page.locator('#app')).not.toHaveAttribute(
    'style',
    `--classification-text`,
  )
})

test('changes the source url', async ({ page, utils }) => {
  await page
    .locator('[data-test=source-url]')
    .locator('input')
    .fill('https://openc3.com')
  await page.locator('[data-test=save-source-url]').click()
  await page.reload()
  await expect(page.locator('footer a')).toHaveAttribute(
    'href',
    'https://openc3.com',
  )
})

test('changes the rubygems url', async ({ page, utils }) => {
  await page
    .locator('[data-test=rubygems-url]')
    .locator('input')
    .fill('https://myrubygems.com')
  await page.locator('[data-test=save-rubygems-url]').click()
  await page.reload()
  await expect(
    page.locator('[data-test="rubygems-url"]').locator('input'),
  ).toHaveValue('https://myrubygems.com')
})

test('changes the pypi url', async ({ page, utils }) => {
  await page
    .locator('[data-test=pypi-url]')
    .locator('input')
    .fill('https://mypypi.com')
  await page.locator('[data-test=save-pypi-url]').click()
  await page.reload()
  await expect(
    page.locator('[data-test="pypi-url"]').locator('input'),
  ).toHaveValue('https://mypypi.com')
})
