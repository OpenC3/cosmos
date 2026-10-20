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

import type { Browser, Page } from '@playwright/test'
import { test, expect } from './../fixture'

const ADMIN_STORAGE_STATE = 'adminStorageState.json'

test.use({
  toolPath: '/tools/admin/settings',
  toolName: 'Administrator',
  storageState: ADMIN_STORAGE_STATE,
})

// These settings are global and are consumed by plugin installs, Script Runner,
// and every page's layout, so a test that fails midway would otherwise leave
// them changed for later specs. Record them before the first test and put back
// anything that differs afterwards.
type OriginalSettings = {
  sourceUrl: string
  rubygemsUrl: string
  pypiUrl: string
  hideAstroClock: boolean
  topBanner: boolean
  language: 'Python' | 'Ruby'
  vimMode: boolean
}
let original: OriginalSettings | undefined

async function openSettings(browser: Browser, baseURL: string | undefined) {
  const context = await browser.newContext({
    storageState: ADMIN_STORAGE_STATE,
  })
  const page = await context.newPage()
  await page.goto(`${baseURL}/tools/admin/settings`, {
    waitUntil: 'domcontentloaded',
  })
  await expect(page.locator('.v-app-bar')).toContainText('Administrator', {
    timeout: 20000,
  })
  // Wait for the settings forms to populate before reading or writing them
  await expect(page.getByText('Pypi URL').first()).toBeVisible()
  return { context, page }
}

const urlInput = (page: Page, name: string) =>
  page.locator(`[data-test=${name}]`).locator('input')

async function readSettings(page: Page): Promise<OriginalSettings> {
  const language = await page
    .locator('[data-test=default-language]')
    .textContent()
  return {
    sourceUrl: await urlInput(page, 'source-url').inputValue(),
    rubygemsUrl: await urlInput(page, 'rubygems-url').inputValue(),
    pypiUrl: await urlInput(page, 'pypi-url').inputValue(),
    hideAstroClock: await page
      .getByRole('checkbox', { name: 'Hide Astro Clock' })
      .isChecked(),
    topBanner: await page
      .getByRole('checkbox', { name: 'Display top banner' })
      .isChecked(),
    language: language?.includes('Ruby') ? 'Ruby' : 'Python',
    vimMode: await page.getByRole('checkbox', { name: 'Vim mode' }).isChecked(),
  }
}

// Click a save button, wait for the save to persist, then reload so the next
// restore starts from what the server actually has.
async function save(page: Page, saveButton: string) {
  await page.locator(`[data-test=${saveButton}]`).click()
  await expect(page.getByText('Saved!').first()).toBeVisible()
  await page.reload()
  await expect(page.getByText('Pypi URL').first()).toBeVisible()
}

async function restoreSettings(page: Page, want: OriginalSettings) {
  const urls: [string, string, string][] = [
    ['source-url', 'save-source-url', want.sourceUrl],
    ['rubygems-url', 'save-rubygems-url', want.rubygemsUrl],
    ['pypi-url', 'save-pypi-url', want.pypiUrl],
  ]
  for (const [name, saveButton, value] of urls) {
    if ((await urlInput(page, name).inputValue()) !== value) {
      await urlInput(page, name).fill(value)
      await save(page, saveButton)
    }
  }

  const astro = page.getByRole('checkbox', { name: 'Hide Astro Clock' })
  if ((await astro.isChecked()) !== want.hideAstroClock) {
    await astro.setChecked(want.hideAstroClock)
    await save(page, 'save-astro-settings')
  }

  const banner = page.getByRole('checkbox', { name: 'Display top banner' })
  if ((await banner.isChecked()) !== want.topBanner) {
    await banner.setChecked(want.topBanner)
    await save(page, 'save-classification-banner')
  }

  const language = await page
    .locator('[data-test=default-language]')
    .textContent()
  const vim = page.getByRole('checkbox', { name: 'Vim mode' })
  if (
    !language?.includes(want.language) ||
    (await vim.isChecked()) !== want.vimMode
  ) {
    await page.locator('[data-test=default-language]').click()
    await page
      .locator(`.v-list-item-title:has-text("${want.language}")`)
      .click()
    await vim.setChecked(want.vimMode)
    await save(page, 'save-editor-settings')
  }
}

test.beforeAll(async ({ browser, baseURL }) => {
  const { context, page } = await openSettings(browser, baseURL)
  original = await readSettings(page)
  await context.close()
})

test.afterAll(async ({ browser, baseURL }) => {
  if (!original) return
  const { context, page } = await openSettings(browser, baseURL)
  await restoreSettings(page, original)
  await context.close()
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
  await page.locator('rux-icon-apps').getByRole('img').click()
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
  await expect(page.getByText('Saved!')).toBeVisible()
  await page.reload()
  // Wait for the page to re-render
  await expect(page.getByText('Hide Astro Clock')).toBeVisible()
  await expect(page.locator('.rux-clock')).not.toBeVisible()
  await page.getByText('Hide Astro Clock').click()
  await page.locator('[data-test=save-astro-settings]').click()
  await expect(page.getByText('Saved!')).toBeVisible()
  await page.reload()
  await expect(page.getByText('Hide Astro Clock')).toBeVisible()
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
  await expect(page.getByText('Saved!').first()).toBeVisible()
  await page.reload()
  await expect(page.locator('#app')).toHaveAttribute(
    'style',
    // Chrome doesn't have spaces after the colon and Firefox does
    new RegExp(
      `--classification-text:\\s?"${bannerText}"; --classification-font-color:\\s?${bannerTextColor.toLowerCase()}; --classification-background-color:\\s?#${bannerBackgroundColor}; --classification-height-top:\\s?${bannerHeight}px; --classification-height-bottom:\\s?0px;`,
    ),
  )
  // The saved height must repopulate the form, not reset to the 20px default
  await expect(
    page
      .locator('[data-test=classification-banner-top-height]')
      .locator('input'),
  ).toHaveValue(bannerHeight)
  // Saving an unrelated change must not clobber the stored height
  await page.locator('[data-test="classification-banner-font-color"]').click()
  await page.locator('.v-list-item-title:has-text("Green")').click()
  await page.locator('[data-test=save-classification-banner]').click()
  await expect(page.getByText('Saved!').first()).toBeVisible()
  await page.reload()
  await expect(page.locator('#app')).toHaveAttribute(
    'style',
    new RegExp(`--classification-height-top:\\s?${bannerHeight}px;`),
  )
  // Disable the classification banner
  await page.uncheck('text=Display top banner')
  await page.locator('[data-test=save-classification-banner]').click()
  await expect(page.getByText('Saved!').first()).toBeVisible()
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
  // Wait for the save to actually persist before reloading; reloading while the
  // set_setting request is still in flight aborts it and the value is lost.
  await expect(page.getByText('Saved!').first()).toBeVisible()
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
  // Wait for the save to actually persist before reloading; reloading while the
  // set_setting request is still in flight aborts it and the value is lost.
  await expect(page.getByText('Saved!').first()).toBeVisible()
  await page.reload()
  await expect(page.getByText('Rubygems URL').first()).toBeVisible()
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
  // Wait for the save to actually persist before reloading; reloading while the
  // set_setting request is still in flight aborts it and the value is lost.
  await expect(page.getByText('Saved!').first()).toBeVisible()
  await page.reload()
  await expect(page.getByText('Pypi URL').first()).toBeVisible()
  await expect(
    page.locator('[data-test="pypi-url"]').locator('input'),
  ).toHaveValue('https://mypypi.com')
})

test('changes scripting settings', async ({ page, utils }) => {
  test.slow()

  // Verify default setting is python
  await expect(page.locator('[data-test=default-language]')).toContainText(
    'Python',
  )

  // Change the default to Ruby
  await page.locator('[data-test=default-language]').click()
  await page.locator('.v-list-item-title:has-text("Ruby")').click()
  // Enable Vim mode
  await page.getByRole('checkbox', { name: 'Vim mode' }).check()
  await page.locator('[data-test=save-editor-settings]').click()

  // Wait for the save to actually persist before reloading; reloading while the
  // set_setting request is still in flight aborts it and the value is lost.
  await expect(page.getByText('Saved!').first()).toBeVisible()

  // Verify Ruby setting
  await page.reload()
  await expect(page.locator('[data-test=default-language]')).toContainText(
    'Ruby',
  )
  await expect(page.getByRole('checkbox', { name: 'Vim mode' })).toBeChecked()

  // Navigate to Script Runner to verify it uses Ruby
  await page.goto('/tools/scriptrunner')
  await expect(page.locator('.v-app-bar')).toContainText('Script Runner')
  await page.locator('[data-test=script-runner-file]').click()
  await page.locator('text=New File').click()
  await expect(page.locator('textarea')).toHaveText('')

  // Type something in Vim mode and verify it works
  await page.locator('.ace_editor').click()
  await page.keyboard.press('i') // Enter insert mode
  await page.keyboard.type('# Test vim mode')
  await page.keyboard.press('Escape') // Exit insert mode

  // Verify the text was inserted
  let editorContent = await page.evaluate(() => {
    const editor = window.ace.edit(document.querySelector('.ace_editor'))
    return editor.getValue()
  })
  await expect(editorContent).toContain('# Test vim mode')

  await page.locator('[data-test=start-button]').click()
  await expect(page.locator('[data-test=state] input')).toHaveValue(
    'completed',
    {
      timeout: 20000,
    },
  )
  let filename = await page.locator('[data-test=filename] input').inputValue()
  await expect(filename).toContain('.rb') // Should be Ruby

  // Verify the setting affects the validate parameter in Command Sender
  await page.goto('/tools/cmdsender/INST/ABORT/')
  await page.locator('[data-test="command-sender-mode"]').click()
  await page
    .getByRole('checkbox', { name: 'Disable Command Validation' })
    .check()
  await page.locator('[data-test="select-send"]').click()
  await page
    .locator('[data-test=sender-history] div')
    .filter({ hasText: 'cmd("INST ABORT", validate: false)' })

  // Reset to Python as default
  await page.goto('/tools/admin/settings')
  await page.locator('[data-test=default-language]').click()
  await page.locator('.v-list-item-title:has-text("Python")').click()
  await page.locator('[data-test=save-editor-settings]').click()
  // Disable Vim mode
  await page.getByRole('checkbox', { name: 'Vim mode' }).uncheck()
  await page.locator('[data-test=save-editor-settings]').click()

  // Navigate to Script Runner to verify it uses Python
  await page.goto('/tools/scriptrunner')
  await expect(page.locator('.v-app-bar')).toContainText('Script Runner')
  await page.locator('[data-test=script-runner-file]').click()
  await page.locator('text=New File').click()
  await expect(page.locator('textarea')).toHaveText('')

  // Type something in regular mode and verify it works
  await page.locator('.ace_editor').click()
  await page.keyboard.type('# Test normal mode')

  // Verify the text was inserted
  editorContent = await page.evaluate(() => {
    const editor = window.ace.edit(document.querySelector('.ace_editor'))
    return editor.getValue()
  })
  await expect(editorContent).toContain('# Test normal mode')

  await page.locator('[data-test=start-button]').click()
  await expect(page.locator('[data-test=state] input')).toHaveValue(
    'completed',
    {
      timeout: 20000,
    },
  )
  // Get the name of the running script
  filename = await page.locator('[data-test=filename] input').inputValue()
  await expect(filename).toContain('.py') // Should be Python

  // Verify the setting affects the validate parameter in Command Sender
  await page.goto('/tools/cmdsender/INST/ABORT/')
  await page.locator('[data-test="command-sender-mode"]').click()
  await page
    .getByRole('checkbox', { name: 'Disable Command Validation' })
    .check()
  await page.locator('[data-test="select-send"]').click()
  await page
    .locator('[data-test=sender-history] div')
    .filter({ hasText: 'cmd("INST ABORT", validate=False)' })
})
