/*
# Copyright 2026 OpenC3, Inc.
# All Rights Reserved.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
# See LICENSE.md for more details.
#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.
*/

import type { Page } from '@playwright/test'
import { expect, test } from './../fixture'

// The gem is built by `./playwright.sh build-plugin` from
// fixtures/pw-offline-pyproject.toml, which sets [tool.openc3]
// offline_install = true and depends only on pycowsay. The build bundled
// pycowsay's wheel into the gem, and this test checks that installing the gem
// uses that bundle: uvinstall's offline path, the plugin venv, and the shared
// UV cache that the Packages tab lists.
const plugin = 'openc3-cosmos-pw-offline'
const pluginGem = 'openc3-cosmos-pw-offline-1.0.0.gem'

test.use({
  toolPath: '/tools/admin/plugins',
  toolName: 'Administrator',
  storageState: 'adminStorageState.json',
})

async function waitForProcess(page: Page, process: string) {
  const processList = page.locator('[data-test=process-list]')
  const running = new RegExp(
    `Processing ${process}: ${pluginGem}(__.*)? - Running`,
  )
  // Ensure no Running are left; it can finish before Running ever renders
  await expect(processList).not.toContainText(running, { timeout: 60000 })
  await expect(processList).toContainText(
    new RegExp(`Processing ${process}: ${pluginGem}(__.*)? - Complete`),
    { timeout: 60000 },
  )
}

// utils is unused, but requesting it runs the fixture that navigates to
// toolPath (and signs in on Enterprise). Without it the page stays blank.
test('installs an offline_install plugin from its bundled wheels', async ({
  page,
  utils,
}) => {
  test.setTimeout(5 * 60 * 1000)

  const [fileChooser] = await Promise.all([
    page.waitForEvent('filechooser'),
    page.getByRole('button', { name: 'Install From File' }).click(),
  ])
  await fileChooser.setFiles(`./${plugin}/${pluginGem}`)
  await expect(page.locator('.v-dialog:has-text("Variables")')).toBeVisible()
  await page.locator('data-test=edit-submit').click()
  await expect(page.locator('[data-test=plugin-alert]')).toContainText(
    'Started installing',
  )
  await waitForProcess(page, 'plugin_install')

  // The install log shows uvinstall took the bundled-wheel path, which never
  // contacts an index, and that it succeeded
  await page
    .locator('[data-test=process-list] .v-list-item')
    .filter({ hasText: `plugin_install: ${pluginGem}` })
    .locator('[data-test=show-output]')
    .first()
    .click()
  const output = page.locator('.v-dialog:has-text("Process Output")')
  await expect(output).toContainText('Installing bundled wheels from')
  await expect(output).toContainText('Bundled wheels installed successfully')
  await output.locator('button:has-text("Ok")').click()

  // pycowsay is in the plugin's own venv and in the shared UV cache. Every
  // group starts collapsed, so expanding one at a time scopes each check.
  // Match the full name: PW_TEST installs cowsay, a different package.
  await page.goto('/tools/admin/packages', { waitUntil: 'domcontentloaded' })
  const packages = page.locator('[data-test=packageList]')
  const pycowsay = packages
    .locator('.v-list-item')
    .filter({ hasText: 'pycowsay==0.0.0.2' })
  const venvHeader = packages
    .locator('.plugin-header')
    .filter({ hasText: plugin })
  await venvHeader.click()
  await expect(pycowsay).toHaveCount(1)
  await venvHeader.click()
  await expect(pycowsay).toHaveCount(0)
  await packages
    .locator('.plugin-header')
    .filter({ hasText: '[/gems/uv]' })
    .click()
  await expect(pycowsay).toHaveCount(1)

  // Uninstall so a rerun starts clean
  await page.goto('/tools/admin/plugins', { waitUntil: 'domcontentloaded' })
  await page
    .locator('[data-test=plugin-list-item]')
    .filter({ hasText: plugin })
    .locator('[data-test=plugin-actions]')
    .click()
  await page.locator('[data-test=delete-plugin]').click()
  await page.locator('[data-test=confirm-dialog-delete]').click()
  await waitForProcess(page, 'plugin_uninstall')
  await expect(page.locator('[data-test=plugin-list]')).not.toContainText(
    plugin,
  )
})
