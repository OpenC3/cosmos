/*
# Copyright 2025 OpenC3, Inc.
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
*/

// @ts-check
import { test, expect } from './../fixture'
import * as fs from 'fs'

test.use({
  toolPath: '/tools/admin/plugins',
  toolName: 'Administrator',
  storageState: 'adminStorageState.json',
})

test('shows and hides built-in tools', async ({ page, utils }) => {
  await expect(page.locator('id=openc3-tool')).toContainText(
    'openc3-cosmos-demo',
  )
  if (process.env.ENTERPRISE === '1') {
    await expect(page.locator('id=openc3-tool')).not.toContainText(
      'openc3-cosmos-enterprise-tool-admin',
    )
    await expect(page.locator('id=openc3-tool')).not.toContainText(
      'openc3-enterprise-tool-base',
    )
    await expect(page.locator('id=openc3-tool')).not.toContainText(
      'openc3-cosmos-tool-autonomic',
    )
    await expect(page.locator('id=openc3-tool')).not.toContainText(
      'openc3-cosmos-tool-calendar',
    )
    await expect(page.locator('id=openc3-tool')).not.toContainText(
      'openc3-cosmos-tool-cmdhistory',
    )
    await expect(page.locator('id=openc3-tool')).not.toContainText(
      'openc3-cosmos-tool-grafana',
    )
  } else {
    await expect(page.locator('id=openc3-tool')).not.toContainText(
      'openc3-cosmos-tool-admin',
    )
    await expect(page.locator('id=openc3-tool')).not.toContainText(
      'openc3-tool-base',
    )
  }
  await expect(page.locator('id=openc3-tool')).not.toContainText(
    'openc3-cosmos-tool-cmdsender',
  )
  await expect(page.locator('id=openc3-tool')).not.toContainText(
    'openc3-cosmos-tool-cmdtlmserver',
  )
  await expect(page.locator('id=openc3-tool')).not.toContainText(
    'openc3-cosmos-tool-dataextractor',
  )
  await expect(page.locator('id=openc3-tool')).not.toContainText(
    'openc3-cosmos-tool-dataviewer',
  )
  await expect(page.locator('id=openc3-tool')).not.toContainText(
    'openc3-cosmos-tool-docs',
  )
  await expect(page.locator('id=openc3-tool')).not.toContainText(
    'openc3-cosmos-tool-handbooks',
  )
  await expect(page.locator('id=openc3-tool')).not.toContainText(
    'openc3-cosmos-tool-iframe',
  )
  await expect(page.locator('id=openc3-tool')).not.toContainText(
    'openc3-cosmos-tool-limitsmonitor',
  )
  await expect(page.locator('id=openc3-tool')).not.toContainText(
    'openc3-cosmos-tool-packetviewer',
  )
  await expect(page.locator('id=openc3-tool')).not.toContainText(
    'openc3-cosmos-tool-scriptrunner',
  )
  await expect(page.locator('id=openc3-tool')).not.toContainText(
    'openc3-cosmos-tool-tablemanager',
  )
  await expect(page.locator('id=openc3-tool')).not.toContainText(
    'openc3-cosmos-tool-tlmgrapher',
  )
  await expect(page.locator('id=openc3-tool')).not.toContainText(
    'openc3-cosmos-tool-tlmviewer',
  )

  await page.locator('text=Show Default Tools').click()
  await expect(page.locator('id=openc3-tool')).toContainText(
    'openc3-cosmos-demo',
  )
  if (process.env.ENTERPRISE === '1') {
    await expect(page.locator('id=openc3-tool')).toContainText(
      'openc3-cosmos-enterprise-tool-admin',
    )
    await expect(page.locator('id=openc3-tool')).toContainText(
      'openc3-enterprise-tool-base',
    )
    await expect(page.locator('id=openc3-tool')).toContainText(
      'openc3-cosmos-tool-autonomic',
    )
    await expect(page.locator('id=openc3-tool')).toContainText(
      'openc3-cosmos-tool-calendar',
    )
    await expect(page.locator('id=openc3-tool')).toContainText(
      'openc3-cosmos-tool-cmdhistory',
    )
    await expect(page.locator('id=openc3-tool')).toContainText(
      'openc3-cosmos-tool-grafana',
    )
  } else {
    await expect(page.locator('id=openc3-tool')).toContainText(
      'openc3-cosmos-tool-admin',
    )
    await expect(page.locator('id=openc3-tool')).toContainText(
      'openc3-tool-base',
    )
  }
  await expect(page.locator('id=openc3-tool')).toContainText(
    'openc3-cosmos-tool-cmdsender',
  )
  await expect(page.locator('id=openc3-tool')).toContainText(
    'openc3-cosmos-tool-cmdtlmserver',
  )
  await expect(page.locator('id=openc3-tool')).toContainText(
    'openc3-cosmos-tool-dataextractor',
  )
  await expect(page.locator('id=openc3-tool')).toContainText(
    'openc3-cosmos-tool-dataviewer',
  )
  await expect(page.locator('id=openc3-tool')).toContainText(
    'openc3-cosmos-tool-docs',
  )
  await expect(page.locator('id=openc3-tool')).toContainText(
    'openc3-cosmos-tool-handbooks',
  )
  await expect(page.locator('id=openc3-tool')).toContainText(
    'openc3-cosmos-tool-iframe',
  )
  await expect(page.locator('id=openc3-tool')).toContainText(
    'openc3-cosmos-tool-limitsmonitor',
  )
  await expect(page.locator('id=openc3-tool')).toContainText(
    'openc3-cosmos-tool-packetviewer',
  )
  await expect(page.locator('id=openc3-tool')).toContainText(
    'openc3-cosmos-tool-scriptrunner',
  )
  await expect(page.locator('id=openc3-tool')).toContainText(
    'openc3-cosmos-tool-tablemanager',
  )
  await expect(page.locator('id=openc3-tool')).toContainText(
    'openc3-cosmos-tool-tlmgrapher',
  )
  await expect(page.locator('id=openc3-tool')).toContainText(
    'openc3-cosmos-tool-tlmviewer',
  )
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

// Playwright requires a separate test.describe to then call test.use
test.describe(() => {
  // Must be the operator to modify files
  test.use({ storageState: 'storageState.json' })

  test('installs, modifies, and deletes a plugin', async ({ page, utils }) => {
    // This test goes through the gamut of plugin functionality: install, upgrade, modify, delete.
    // It is one test so that it works with Playwright's parallelization and optional order randomization.

    // This is generated by the playwright github workflow via .github/workflows/playwright.yml
    // Follow the steps there to generate a local copy for test
    const plugin = 'openc3-cosmos-pw-test'
    const pluginGem = 'openc3-cosmos-pw-test-1.0.0.gem'
    const pluginGem1 = 'openc3-cosmos-pw-test-1.0.1.gem'

    // ==========================================
    // Section: INSTALL A PLUGIN
    // ==========================================

    // Note that Promise.all prevents a race condition
    // between clicking and waiting for the file chooser.
    const [installFileChooser] = await Promise.all([
      // It is important to call waitForEvent before click to set up waiting.
      page.waitForEvent('filechooser'),
      // Opens the file chooser.
      await page.getByRole('button', { name: 'Install New Plugin' }).click(),
    ])
    await installFileChooser.setFiles(`./${plugin}/${pluginGem}`)
    await expect(page.locator('.v-dialog:has-text("Variables")')).toBeVisible()
    await page.locator('data-test=edit-submit').click()
    await expect(page.locator('[data-test=plugin-alert]')).toContainText(
      'Started installing',
    )
    // Plugin install can go so fast we can't count on 'Running' to be present so try catch this
    let installRegexp = new RegExp(
      `Processing plugin_install: ${pluginGem}__.* - Running`,
    )
    try {
      await expect(page.locator('[data-test=process-list]')).toContainText(
        installRegexp,
        {
          timeout: 30000,
        },
      )
    } catch {}
    // Ensure no Running are left
    await expect(page.locator('[data-test=process-list]')).not.toContainText(
      installRegexp,
      {
        timeout: 30000,
      },
    )
    // Check for Complete
    installRegexp = new RegExp(
      `Processing plugin_install: ${pluginGem} - Complete`,
    )
    await expect(page.locator('[data-test=process-list]')).toContainText(
      installRegexp,
    )

    await expect(
      page.locator(`[data-test=plugin-list] div:has-text("${plugin}")`).first(),
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
    await page
      .locator('.v-list-group:has-text("PW_TEST")')
      .first()
      .getByRole('button')
      .click()
    await page
      .locator('.v-list-group:has-text("PW_TEST")')
      .first()
      .locator('.v-list-item:has-text("procedures")')
      .click()
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

    const [download1] = await Promise.all([
      // Start waiting for the download
      page.waitForEvent('download'),
      // Download the modified plugin
      page
        .locator('[data-test=plugin-list-item]')
        .filter({ hasText: plugin })
        .locator('a')
        .click(),
    ])
    // Wait for the download process to complete
    const JSZip = require('jszip')
    const path1 = await download1.path()
    fs.readFile(path1!, function (err, data) {
      if (err) throw err
      JSZip.loadAsync(data).then(function (zip) {
        Object.keys(zip.files).forEach(function (filename) {
          zip.files[filename].async('string').then(function (fileData) {
            // Check the zip file contents
            // We should have the new script:
            if (filename.includes('save_new.rb')) {
              expect(fileData).toBe('puts "modify the PW_TEST"')
            }
          })
        })
      })
    })

    // Download the changes from the targets tab
    await page.goto('/tools/admin/targets')
    await expect(page.locator('.v-app-bar')).toContainText('Administrator')
    await page.locator('rux-icon-apps').getByRole('img').click()

    const [download2] = await Promise.all([
      // Start waiting for the download
      page.waitForEvent('download'),
      // Initiate the download
      page
        .locator('.v-list-item')
        .filter({ hasText: 'PW_TEST' })
        .getByRole('button')
        .nth(0)
        .click(),
    ])
    // Wait for the download process to complete
    const path2 = await download2.path()
    fs.readFile(path2!, function (err, data) {
      if (err) throw err
      JSZip.loadAsync(data).then(function (zip) {
        Object.keys(zip.files).forEach(function (filename) {
          zip.files[filename].async('string').then(function (fileData) {
            // Check the zip file contents
            // We should have the new script:
            if (filename.includes('save_new.rb')) {
              expect(fileData).toBe('puts "modify the PW_TEST"')
            }
            // We should have the new screen:
            // if (filename.includes('new_screen.txt')) {
            //   expect(fileData).toContain('SCREEN')
            // }
          })
        })
      })
    })

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
        .locator('.v-list-item')
        .filter({ hasText: plugin })
        .locator('[data-test=upgrade-plugin]')
        .click(),
    ])

    await upgradeFileChooser.setFiles(`./${plugin}/${pluginGem1}`)
    await expect(page.locator('.v-dialog:has-text("Variables")')).toBeVisible()
    await page.locator('data-test=edit-submit').click()
    await expect(page.locator('.v-dialog:has-text("Modified")')).toBeVisible()
    // Check the delete box
    await page.locator('text=DELETE MODIFIED').click()
    await page.locator('data-test=modified-plugin-submit').click()
    await expect(page.locator('[data-test=plugin-alert]')).toContainText(
      'Started installing',
    )
    // Plugin install can go so fast we can't count on 'Running' to be present so try catch this
    let upgradeRegexp = new RegExp(
      `Processing plugin_install: ${pluginGem}__.* - Running`,
    )
    try {
      await expect(page.locator('[data-test=process-list]')).toContainText(
        upgradeRegexp,
        {
          timeout: 30000,
        },
      )
    } catch {}
    // Ensure no Running are left
    await expect(page.locator('[data-test=process-list]')).not.toContainText(
      upgradeRegexp,
      {
        timeout: 30000,
      },
    )
    // Check for Complete
    upgradeRegexp = new RegExp(
      `Processing plugin_install: ${pluginGem1} - Complete`,
    )
    await expect(page.locator('[data-test=process-list]')).toContainText(
      upgradeRegexp,
    )

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
      .locator('.v-list-item')
      .filter({ hasText: plugin })
      .locator('[data-test=edit-plugin]')
      .click()
    await expect(page.locator('.v-dialog:has-text("Variables")')).toBeVisible()
    await page.locator('data-test=edit-cancel').click()
    await expect(
      page.locator('.v-dialog:has-text("Variables")'),
    ).not.toBeVisible()
    // Edit and change a target name (forces re-install)
    await page
      .locator('.v-list-item')
      .filter({ hasText: plugin })
      .locator('[data-test=edit-plugin]')
      .click()
    await expect(page.locator('.v-dialog:has-text("Variables")')).toBeVisible()
    await page
      .locator(
        '.v-dialog:has-text("Variables") .v-input:has-text("pw_test_target_name") >> input',
      )
      .fill('NEW_TGT')
    await page.locator('data-test=edit-submit').click()
    await expect(page.locator('[data-test=plugin-alert]')).toContainText(
      'Started installing',
    )
    // Plugin install can go so fast we can't count on 'Running' to be present so try catch this
    let editRegexp = new RegExp(
      `Processing plugin_install: ${pluginGem}__.* - Running`,
    )
    try {
      await expect(page.locator('[data-test=process-list]')).toContainText(
        editRegexp,
        {
          timeout: 30000,
        },
      )
    } catch {}
    // Ensure no Running are left
    await expect(page.locator('[data-test=process-list]')).not.toContainText(
      editRegexp,
      {
        timeout: 30000,
      },
    )
    // Check for Complete ... note new installs append '__<TIMESTAMP>'
    editRegexp = new RegExp(
      `Processing plugin_install: ${pluginGem1}__.* - Complete`,
    )
    await expect(page.locator('[data-test=process-list]')).toContainText(
      editRegexp,
    )
    // Ensure the target list is updated to show the new name
    await expect(
      page
        .locator('[data-test=plugin-list]')
        .locator('.v-list-item')
        .filter({ hasText: plugin }),
    ).not.toContainText('PW_TEST')
    await expect(
      page
        .locator('[data-test=plugin-list]')
        .locator('.v-list-item')
        .filter({ hasText: plugin }),
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

    // ==========================================
    // Section: DELETE THE PLUGIN
    // ==========================================
    await page
      .locator('[data-test=plugin-list]')
      .locator('.v-list-item')
      .filter({ hasText: plugin })
      .locator('[data-test=delete-plugin]')
      .click()
    await expect(page.locator('.v-dialog')).toContainText('Confirm')
    await page.locator('[data-test=confirm-dialog-delete]').click()
    await expect(page.locator('.v-dialog:has-text("Modified")')).toBeVisible()
    // Check the delete box
    await page.locator('text=DELETE MODIFIED').click()
    await page.locator('data-test=modified-plugin-submit').click()

    await expect(page.locator('[data-test=plugin-alert]')).toContainText(
      'Removing plugin',
    )
    // Plugin uninstall can go so fast we can't count on 'Running' to be present so try catch this
    let regexp = new RegExp(
      `Processing plugin_install: ${pluginGem1}__.* - Running`,
    )
    try {
      await expect(page.locator('[data-test=process-list]')).toContainText(
        regexp,
        {
          timeout: 30000,
        },
      )
    } catch {}
    // Ensure no Running are left
    await expect(page.locator('[data-test=process-list]')).not.toContainText(
      regexp,
      {
        timeout: 30000,
      },
    )
    // Check for Complete ... note new installs append '__<TIMESTAMP>'
    regexp = new RegExp(
      `Processing plugin_uninstall: ${pluginGem1}__.* - Complete`,
    )
    await expect(page.locator('[data-test=process-list]')).toContainText(regexp)
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
})
