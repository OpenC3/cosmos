/*
# Copyright 2026 OpenC3, Inc.
# All Rights Reserved.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
# See LICENSE.md for more details.
*/

import type { Page } from '@playwright/test'
import * as fs from 'fs'
import { loadAsync } from 'jszip'
import { pickBy, values } from 'lodash'
import * as path from 'path'
import { expect, test } from './../fixture'

test.use({
  toolPath: '/tools/admin/plugins',
  toolName: 'Administrator',
  storageState: 'adminStorageState.json',
})

// The list of plugins that ship with COSMOS, parsed from the same file the
// backend uses so this test covers every entry. Entries marked
// "# Enterprise only" are only installed in the Enterprise edition.
const DEFAULT_PLUGINS_FILE = path.resolve(
  __dirname,
  '../../../openc3/data/config/default_plugins.yaml',
)
const defaultPlugins = fs
  .readFileSync(DEFAULT_PLUGINS_FILE, 'utf8')
  .split('\n')
  .filter((line) => line.startsWith('- '))
  .map((line) => ({
    name: line.slice(2).replace(/#.*/, '').trim(),
    enterpriseOnly: line.includes('Enterprise only'),
  }))
// Enterprise replaces these with openc3-enterprise-tool-base and
// openc3-cosmos-enterprise-tool-admin so they are not installed there
const coreOnly = ['openc3-cosmos-tool-admin', 'openc3-tool-base']
const installedDefaultPlugins = defaultPlugins
  .filter((plugin) =>
    process.env.ENTERPRISE === '1'
      ? !coreOnly.includes(plugin.name)
      : !plugin.enterpriseOnly,
  )
  .map((plugin) => plugin.name)

test('shows and hides built-in tools', async ({ page, utils }) => {
  expect(defaultPlugins.length).toBeGreaterThan(0)
  expect(installedDefaultPlugins.length).toBeGreaterThan(0)

  // Ensure we're showing all the rows in the table
  await page.getByRole('combobox').filter({ hasText: '10' }).click()
  await page.getByText('All', { exact: true }).click()
  const plugins = page.locator('id=openc3-tool')

  // Non default plugins are shown and no plugin from the default list is
  await expect(plugins).toContainText('openc3-cosmos-demo')
  for (const plugin of defaultPlugins) {
    await expect(plugins, `${plugin.name} should be hidden`).not.toContainText(
      plugin.name,
    )
  }

  // Showing the default tools shows every installed plugin from the list
  await page.locator('text=Show Default Tools').click()
  await expect(plugins).toContainText('openc3-cosmos-demo')
  for (const name of installedDefaultPlugins) {
    await expect(plugins, `${name} should be shown`).toContainText(name)
  }
})

test('downloads the demo plugin', async ({ page, utils }) => {
  const plugin = 'openc3-cosmos-demo'
  await page
    .locator('[data-test=plugin-list-item]')
    .filter({ hasText: plugin })
    .locator('[data-test=plugin-actions]')
    .click()
  const [download] = await Promise.all([
    page.waitForEvent('download'),
    page.locator('[data-test=download-plugin]').click(),
  ])
  const filename = download.suggestedFilename()
  expect(filename).toMatch(/openc3-cosmos-demo.*\.gem/)
  // Verify the download completes successfully and has content
  const path = await download.path()
  expect(path).toBeTruthy()
  const stat = fs.statSync(path!)
  expect(stat.size).toBeGreaterThan(0)
})

test('shows targets associated with plugins', async ({ page, utils }) => {
  // Check that the openc3-demo contains the following targets:
  await expect(
    page
      .locator('[data-test=plugin-list] div:has-text("openc3-cosmos-demo")')
      .first(),
  ).toContainText('EXAMPLE')
  await expect(
    page
      .locator('[data-test=plugin-list] div:has-text("openc3-cosmos-demo")')
      .first(),
  ).toContainText('INST')
  await expect(
    page
      .locator('[data-test=plugin-list] div:has-text("openc3-cosmos-demo")')
      .first(),
  ).toContainText('INST2')
  await expect(
    page
      .locator('[data-test=plugin-list] div:has-text("openc3-cosmos-demo")')
      .first(),
  ).toContainText('SYSTEM')
  await expect(
    page
      .locator('[data-test=plugin-list] div:has-text("openc3-cosmos-demo")')
      .first(),
  ).toContainText('TEMPLATED')
})

test('prompts before closing dirty plugin editor on ESC', async ({
  page,
  utils,
}) => {
  const plugin = 'openc3-cosmos-demo'
  // Open the edit dialog for the demo plugin
  await page
    .locator('[data-test=plugin-list-item]')
    .filter({ hasText: plugin })
    .locator('[data-test=plugin-actions]')
    .click()
  await page.locator('[data-test=edit-plugin]').click()
  await expect(page.locator('.v-dialog:has-text("Variables")')).toBeVisible()

  // Switch to the plugin.txt tab where the Ace editor is
  await page.getByRole('tab', { name: 'plugin.txt' }).click()
  await utils.sleep(500)

  // Press ESC without making changes - dialog should close immediately
  await page.keyboard.press('Escape')
  await expect(
    page.locator('.v-dialog:has-text("Variables")'),
  ).not.toBeVisible()

  // Reopen the edit dialog
  await page
    .locator('[data-test=plugin-list-item]')
    .filter({ hasText: plugin })
    .locator('[data-test=plugin-actions]')
    .click()
  await page.locator('[data-test=edit-plugin]').click()
  await expect(page.locator('.v-dialog:has-text("Variables")')).toBeVisible()

  // Switch to the plugin.txt tab
  await page.getByRole('tab', { name: 'plugin.txt' }).click()
  await utils.sleep(500)

  // Type something into the Ace editor to make it dirty
  await page.locator('.v-dialog .editor textarea').first().fill('# dirty edit')
  await utils.sleep(500)

  // Press ESC - should show the unsaved changes confirmation dialog
  await page.keyboard.press('Escape')
  await expect(page.getByText('You have unsaved changes')).toBeVisible()

  // Click Cancel to stay in the editor
  await page.locator('[data-test="confirm-dialog-cancel"]').click()
  // The plugin dialog should still be open
  await expect(page.locator('.v-dialog:has-text("Variables")')).toBeVisible()

  // Press ESC again to re-trigger the confirmation
  await page.keyboard.press('Escape')
  await expect(page.getByText('You have unsaved changes')).toBeVisible()

  // This time confirm closing without saving
  await page
    .locator('[data-test="confirm-dialog-close without saving"]')
    .click()
  // The plugin dialog should now be closed
  await expect(
    page.locator('.v-dialog:has-text("Variables")'),
  ).not.toBeVisible()
})

// Playwright requires a separate test.describe to then call test.use
test.describe(() => {
  // Must be the operator to modify files
  test.use({ storageState: 'storageState.json' })

  // This is generated by the playwright github workflow via .github/workflows/playwright.yml
  // Follow the steps there to generate a local copy for test
  const plugin = 'openc3-cosmos-pw-test'
  const pluginGem = 'openc3-cosmos-pw-test-1.0.0.gem'
  const pluginGem1 = 'openc3-cosmos-pw-test-1.0.1.gem'

  /** Waits for a plugin install / uninstall process to finish. Pass plain gem
   * file names; the optional `'__<TIMESTAMP>'` suffix that new installs append
   * is matched here.
   */
  async function waitForPluginProcess(
    page: Page,
    {
      alert,
      gem,
      process = 'plugin_install',
      previousCompleteCount = 0,
    }: {
      alert: string
      gem: string
      process?: string
      // Set when an earlier process for the same gem already shows Complete, so
      // that only a new Complete entry satisfies the wait
      previousCompleteCount?: number
    },
  ) {
    const processList = page.locator('[data-test=process-list]')
    await expect(page.locator('[data-test=plugin-alert]')).toContainText(alert)
    // The process can go so fast we can't count on 'Running' to be present so try catch this
    const runningRegexp = new RegExp(
      `Processing ${process}: ${gem}(__.*)? - Running`,
    )
    try {
      await expect(processList).toContainText(runningRegexp, {
        timeout: 30000,
      })
    } catch {}
    // Ensure no Running are left
    await expect(processList).not.toContainText(runningRegexp, {
      timeout: 30000,
    })
    const completeRegexp = new RegExp(
      `Processing ${process}: ${gem}(__.*)? - Complete`,
    )
    await expect(
      processList.locator('.v-list-item').filter({ hasText: completeRegexp }),
    ).toHaveCount(previousCompleteCount + 1, { timeout: 30000 })
  }

  test.afterEach('delete the installed plugin', async ({ page }) => {
    await page
      .locator('[data-test=plugin-list-item]')
      .filter({ hasText: plugin })
      .locator('[data-test=plugin-actions]')
      .click()
    await page.locator('[data-test=delete-plugin]').click()
    await expect(page.locator('.v-dialog')).toContainText('Confirm')
    await page.locator('[data-test=confirm-dialog-delete]').click()
    await expect(page.locator('.v-dialog:has-text("Modified")')).toBeVisible()
    // Check the delete box
    await page.locator('text=DELETE MODIFIED').click()
    await page.locator('data-test=modified-plugin-submit').click()

    await waitForPluginProcess(page, {
      alert: 'Removing plugin',
      gem: pluginGem1,
      process: 'plugin_uninstall',
    })
    await expect(page.locator(`[data-test=plugin-list]`)).not.toContainText(
      plugin,
    )
    // Show the process output
    await page
      .locator('[data-test=process-list]')
      .locator('.v-list-item')
      .filter({ hasText: 'plugin_uninstall' })
      .locator('[data-test=show-output]')
      .first()
      .click()
    await expect(page.locator('.v-dialog')).toContainText('Process Output')
    await expect(page.locator('.v-dialog')).toContainText(
      'PluginModel destroyed',
    )
    await page.locator('.v-dialog >> button:has-text("Ok")').click()
  })

  async function checkForSaveNewFile(page: Page, downloadTrigger: Promise<void>) {
    const [download] = await Promise.all([
      // Start waiting for the download
      page.waitForEvent('download'),
      // Download the modified plugin
      downloadTrigger,
    ])
    // Wait for the download process to complete
    const path = await download.path()
    const data = await fs.promises.readFile(path)
    const zip = await loadAsync(data)
    const files = values(pickBy(zip.files, (file, filename) => filename.includes('save_new.rb')))
    expect(files).toHaveLength(1)
    const fileData = await files[0]?.async('string')
    // Check the zip file contents
    // We should have the new script:
    expect(fileData).toBe('puts "modify the PW_TEST"')
  }

  test('installs, modifies, and deletes a plugin', async ({
    page,
    utils,
  }) => {
    test.setTimeout(5 * 60 * 1000) // 5 minutes
    // This test goes through the gamut of plugin functionality: install, upgrade, modify, delete.
    // It is one test so that it works with Playwright's parallelization and optional order randomization.

    // ==========================================
    // Section: INSTALL A PLUGIN
    // ==========================================

    // Note that Promise.all prevents a race condition
    // between clicking and waiting for the file chooser.
    const [installFileChooser] = await Promise.all([
      // It is important to call waitForEvent before click to set up waiting.
      page.waitForEvent('filechooser'),
      // Opens the file chooser.
      await page.getByRole('button', { name: 'Install From File' }).click(),
    ])
    await installFileChooser.setFiles(`./${plugin}/${pluginGem}`)
    await expect(page.locator('.v-dialog:has-text("Variables")')).toBeVisible()
    await page.locator('data-test=edit-submit').click()
    await waitForPluginProcess(page, {
      alert: 'Started installing',
      gem: pluginGem,
    })

    await expect(
      page.locator(`[data-test=plugin-list] tr:has-text("${plugin}")`).first(),
    ).toContainText('PW_TEST')
    // Show the process output
    await page
      .locator(
        `[data-test=process-list] div:has-text("${plugin}") >> [data-test=show-output]`,
      )
      .first()
      .click()
    await expect(page.getByRole('dialog')).toContainText('Process Output')
    await expect(page.getByRole('dialog')).toContainText(
      `Loading new plugin: ${pluginGem}`,
    )
    await page.getByRole('button', { name: 'Ok' }).click()

    // ==========================================
    // Section: MODIFY PLUGIN FILES
    // ==========================================

    // Check that there are no links (a) under the current plugin (no modified files)
    await expect(
      page.locator(
        `[data-test=plugin-list] div[role=listitem]:has-text("${plugin}") >> a`,
      ),
    ).toHaveCount(0)

    // Create a new script
    await page.goto('/tools/scriptrunner')
    await expect(page.locator('.v-app-bar')).toContainText('Script Runner')
    await page.locator('rux-icon-apps').getByRole('img').click()
    await page.locator('textarea').fill('puts "modify the PW_TEST"')
    await page.locator('[data-test=script-runner-file]').click()
    await page.locator('text=Save File').click()
    await expect(page.locator('text=File Save As')).toBeVisible()
    await utils.sleep(500) // Allow background data to fetch
    await page.getByText('PW_TEST', { exact: true }).click()
    await page.getByText('procedures', { exact: true }).click()
    const prepend = await page
      .locator('[data-test=file-open-save-filename] input')
      .inputValue()
    await page
      .locator('[data-test=file-open-save-filename] input')
      .fill(`${prepend}/save_new.rb`)
    await page.locator('[data-test=file-open-save-submit-btn]').click()
    if (
      await page.locator('[data-test=confirm-dialog-overwrite]').isVisible()
    ) {
      await page.locator('[data-test=confirm-dialog-overwrite]').click()
    }
    await expect(page.locator('#sr-controls')).toContainText(
      'PW_TEST/procedures/save_new.rb',
    )

    // Download the changes
    await page.goto('/tools/admin/plugins')
    await expect(page.locator('.v-app-bar')).toContainText('Administrator')
    await page.locator('rux-icon-apps').getByRole('img').click()

    // Check that we have a link to click
    await expect(
      page.locator('[data-test=plugin-list-item]').filter({ hasText: plugin }),
    ).toHaveCount(1)

    await checkForSaveNewFile(page, page
          .locator('[data-test=plugin-list-item]')
          .filter({ hasText: plugin })
          .locator('a')
          .click())

    // Download the changes from the targets tab
    await page.goto('/tools/admin/targets')
    await expect(page.locator('.v-app-bar')).toContainText('Administrator')
    await page.locator('rux-icon-apps').getByRole('img').click()

    await checkForSaveNewFile(page, page
        .locator('.v-list-item')
        .filter({ hasText: 'PW_TEST' })
        .getByRole('button')
        .nth(0)
        .click())

    await page.goto('/tools/admin/plugins')
    await expect(page.locator('.v-app-bar')).toContainText('Administrator')
    await page.locator('rux-icon-apps').getByRole('img').click()

    // ==========================================
    // Section: UPGRADE THE PLUGIN
    // ==========================================

    // Note that Promise.all prevents a race condition
    // between clicking and waiting for the file chooser.
    const [upgradeFileChooser] = await Promise.all([
      // It is important to call waitForEvent before click to set up waiting.
      page.waitForEvent('filechooser'),
      // Opens the file chooser.
      await page
        .locator('[data-test=plugin-list-item]')
        .filter({ hasText: plugin })
        .locator('[data-test=plugin-actions]')
        .click(),
      await page.locator('[data-test=upgrade-plugin]').click(),
    ])

    await upgradeFileChooser.setFiles(`./${plugin}/${pluginGem1}`)
    await expect(page.locator('.v-dialog:has-text("Variables")')).toBeVisible()
    await page.locator('data-test=edit-submit').click()
    await expect(page.locator('.v-dialog:has-text("Modified")')).toBeVisible()
    // Without Version History (Core, or Enterprise with it disabled) the
    // dialog offers to delete the modified files; check it to take the
    // plugin's version. With Version History there is no checkbox and the
    // plugin's version is taken, with the prior content versioned.
    const deleteModified = page.locator('text=DELETE MODIFIED')
    if (await deleteModified.isVisible()) {
      await deleteModified.click()
    }
    await page.locator('data-test=modified-plugin-submit').click()
    await waitForPluginProcess(page, {
      alert: 'Started installing',
      gem: pluginGem1,
    })

    // Check that there are no longer any links (modified targets)
    await expect(
      page.locator(
        `[data-test=plugin-list] div[role=listitem]:has-text("${plugin}") >> a`,
      ),
    ).toHaveCount(0)

    // ==========================================
    // Section: EDIT THE PLUGIN
    // ==========================================

    // Edit then cancel
    await page
      .locator('[data-test=plugin-list-item]')
      .filter({ hasText: plugin })
      .locator('[data-test=plugin-actions]')
      .click()
    await page.locator('[data-test=edit-plugin]').click()
    await expect(page.locator('.v-dialog:has-text("Variables")')).toBeVisible()
    await page.locator('data-test=edit-cancel').click()
    await expect(
      page.locator('.v-dialog:has-text("Variables")'),
    ).not.toBeVisible()
    // Edit and change a target name (forces re-install)
    await page
      .locator('[data-test=plugin-list-item]')
      .filter({ hasText: plugin })
      .locator('[data-test=plugin-actions]')
      .click()
    await page.locator('[data-test=edit-plugin]').click()
    await expect(page.locator('.v-dialog:has-text("Variables")')).toBeVisible()
    await page
      .locator(
        '.v-dialog:has-text("Variables") .v-input:has-text("pw_test_target_name") >> input',
      )
      .fill('NEW_TGT')
    const completeCount = await page
      .locator('[data-test=process-list] .v-list-item')
      .filter({
        hasText: new RegExp(`Processing plugin_install: ${pluginGem1}(__.*)? - Complete`),
      })
      .count()
    await page.locator('data-test=edit-submit').click()
    await waitForPluginProcess(page, {
      alert: 'Started installing',
      gem: pluginGem1,
      previousCompleteCount: completeCount,
    })
    // Ensure the target list is updated to show the new name
    // TODO: replace .nth(2) with a more robust selector, this is not robust to layout changes of plugin-list-item
    await expect(
      page.locator('[data-test=plugin-list-item]').filter({ hasText: plugin }).locator('div').nth(2),
    ).not.toContainText('PW_TEST')
    await expect(
      page.locator('[data-test=plugin-list-item]').filter({ hasText: plugin }).locator('div').nth(2),
    ).toContainText('NEW_TGT')
    // Show the process output
    await page
      .locator('[data-test=process-list]')
      .locator('.v-list-item')
      .filter({ hasText: plugin })
      .locator('[data-test=show-output]')
      .first()
      .click()
    await expect(page.locator('.v-dialog')).toContainText('Process Output')
    // TODO: Should this be Loading new or Updating existing?
    // await expect(page.locator('.v-dialog--active')).toContainText('Updating existing plugin')
    await page.locator('.v-dialog>> button:has-text("Ok")').click()

    // ==========================================
    // Section: CREATE A NEW SCREEN
    // ==========================================

    // Create a new screen so we have modifications to delete
    await page.goto('/tools/tlmviewer')
    await expect(page.locator('.v-app-bar')).toContainText('Telemetry Viewer')
    await page.locator('rux-icon-apps').getByRole('img').click()
    await page.locator('[data-test=select-target] i').click()
    await page.getByRole('option', { name: 'NEW_TGT', exact: true }).click()
    await utils.sleep(500)
    await page.locator('[data-test=new-screen]').click()
    await expect(
      page.locator(`.v-toolbar:has-text("New Screen")`),
    ).toBeVisible()
    await page.locator('[data-test=new-screen-name] input').fill('NEW_SCREEN')
    await page.getByRole('button', { name: 'Save' }).click()
    await expect(
      page.locator(`.v-toolbar:has-text("NEW_TGT NEW_SCREEN")`),
    ).toBeVisible()
    await page.goto('/tools/admin/plugins')
    await expect(page.locator('.v-app-bar')).toContainText('Administrator')
    await page.locator('rux-icon-apps').getByRole('img').click()
  })
})
