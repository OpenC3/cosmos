/*
# Copyright 2022 OpenC3, Inc.
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
import { test, expect } from 'playwright-test-coverage'
import { Utilities } from '../../utilities'

let utils
test.beforeEach(async ({ page }) => {
    await page.goto('/tools/admin/plugins')
    await expect(page.locator('.v-app-bar')).toContainText('Administrator')
    await page.locator('.v-app-bar__nav-icon').click()
    utils = new Utilities(page)
})

test('shows and hides built-in tools', async ({ page }) => {
  await expect(page.locator('id=openc3-tool')).toContainText('openc3-demo')
  await expect(page.locator('id=openc3-tool')).not.toContainText('openc3-tool-admin')
  await expect(page.locator('id=openc3-tool')).not.toContainText('openc3-tool-autonomic')
  await expect(page.locator('id=openc3-tool')).not.toContainText('openc3-tool-base')
  await expect(page.locator('id=openc3-tool')).not.toContainText('openc3-tool-calendar')
  await expect(page.locator('id=openc3-tool')).not.toContainText('openc3-tool-cmdsender')
  await expect(page.locator('id=openc3-tool')).not.toContainText('openc3-tool-cmdtlmserver')
  await expect(page.locator('id=openc3-tool')).not.toContainText('openc3-tool-dataextractor')
  await expect(page.locator('id=openc3-tool')).not.toContainText('openc3-tool-dataviewer')
  await expect(page.locator('id=openc3-tool')).not.toContainText('openc3-tool-handbooks')
  await expect(page.locator('id=openc3-tool')).not.toContainText('openc3-tool-limitsmonitor')
  await expect(page.locator('id=openc3-tool')).not.toContainText('openc3-tool-packetviewer')
  await expect(page.locator('id=openc3-tool')).not.toContainText('openc3-tool-scriptrunner')
  await expect(page.locator('id=openc3-tool')).not.toContainText('openc3-tool-tablemanager')
  await expect(page.locator('id=openc3-tool')).not.toContainText('openc3-tool-tlmgrapher')
  await expect(page.locator('id=openc3-tool')).not.toContainText('openc3-tool-tlmviewer')

  await page.locator('text=Show Default Tools').click()
  await expect(page.locator('id=openc3-tool')).toContainText('openc3-demo')
  await expect(page.locator('id=openc3-tool')).toContainText('openc3-tool-admin')
  await expect(page.locator('id=openc3-tool')).toContainText('openc3-tool-autonomic')
  await expect(page.locator('id=openc3-tool')).toContainText('openc3-tool-base')
  await expect(page.locator('id=openc3-tool')).toContainText('openc3-tool-calendar')
  await expect(page.locator('id=openc3-tool')).toContainText('openc3-tool-cmdsender')
  await expect(page.locator('id=openc3-tool')).toContainText('openc3-tool-cmdtlmserver')
  await expect(page.locator('id=openc3-tool')).toContainText('openc3-tool-dataextractor')
  await expect(page.locator('id=openc3-tool')).toContainText('openc3-tool-dataviewer')
  await expect(page.locator('id=openc3-tool')).toContainText('openc3-tool-handbooks')
  await expect(page.locator('id=openc3-tool')).toContainText('openc3-tool-limitsmonitor')
  await expect(page.locator('id=openc3-tool')).toContainText('openc3-tool-packetviewer')
  await expect(page.locator('id=openc3-tool')).toContainText('openc3-tool-scriptrunner')
  await expect(page.locator('id=openc3-tool')).toContainText('openc3-tool-tablemanager')
  await expect(page.locator('id=openc3-tool')).toContainText('openc3-tool-tlmgrapher')
  await expect(page.locator('id=openc3-tool')).toContainText('openc3-tool-tlmviewer')
})

test('shows targets associated with plugins', async ({ page }) => {
  // Check that the openc3-demo contains the following targets:
  await expect(page.locator('[data-test=plugin-list] div[role=listitem]:has-text("openc3-demo")')).toContainText('EXAMPLE')
  await expect(page.locator('[data-test=plugin-list] div[role=listitem]:has-text("openc3-demo")')).toContainText('INST')
  await expect(page.locator('[data-test=plugin-list] div[role=listitem]:has-text("openc3-demo")')).toContainText('INST2')
  await expect(page.locator('[data-test=plugin-list] div[role=listitem]:has-text("openc3-demo")')).toContainText('SYSTEM')
  await expect(page.locator('[data-test=plugin-list] div[role=listitem]:has-text("openc3-demo")')).toContainText('TEMPLATED')
})

test('edits the plugin variables', async ({ page }) => {
  let plugin = await page.locator('[data-test=plugin-list] div[role=listitem]:has-text("openc3-demo") >> .v-list-item__title').textContent()
  // Handle a modified plugin to make local testing easier
  if (plugin.slice(0, 2) === '* ') {
    plugin = plugin.slice(2)
  }
  // Split off the unique timestamp because that changes on each install
  plugin = plugin.split('__')[0]
  console.log(plugin)
  // Edit then cancel
  await page.locator(`[data-test=plugin-list] div[role=listitem]:has-text("${plugin}") >> [data-test=edit-plugin]`).click()
  await expect(page.locator('.v-dialog')).toContainText('Variables')
  await page.locator('data-test=edit-cancel').click()
  await expect(page.locator('.v-dialog')).not.toBeVisible()
  // Edit and change a target name (forces re-install)
  await page.locator(`[data-test=plugin-list] div[role=listitem]:has-text("${plugin}") >> [data-test=edit-plugin]`).click()
  await expect(page.locator('.v-dialog')).toContainText('Variables')
  await page.locator('.v-dialog .v-input:has-text("example_target_name") >> input').fill("TEST_TGT")
  await page.locator('data-test=edit-submit').click()
  await expect(page.locator('[data-test=plugin-alert]')).toContainText('Started installing')
  let regexp = new RegExp(`Processing plugin_install: ${plugin}__.* - Running`)
  await expect(page.locator('[data-test=process-list]')).toContainText(regexp, {
    timeout: 20000,
  })
  // Ensure 'Running' goes away ... this allows for extra Complete message to be present
  await expect(page.locator('[data-test=process-list]')).not.toContainText(regexp, {
    timeout: 60000,
  })
  regexp = new RegExp(`Processing plugin_install: ${plugin}__.* - Complete`)
  await expect(page.locator('[data-test=process-list]')).toContainText(regexp)
  // Ensure the target list is updated to show the new name
  await expect(page.locator(`[data-test=plugin-list] div[role=listitem]:has-text("${plugin}")`)).not.toContainText('EXAMPLE')
  await expect(page.locator(`[data-test=plugin-list] div[role=listitem]:has-text("${plugin}")`)).toContainText('TEST_TGT')
  // Show the process output
  await page.locator(`[data-test=process-list] div[role=listitem]:has-text("${plugin}") >> [data-test=show-output]`).first().click()
  await expect(page.locator('.v-dialog--active')).toContainText('Process Output')
  await expect(page.locator('.v-dialog--active')).toContainText('Updating existing plugin')
  await page.locator('.v-dialog--active >> button:has-text("Ok")').click()
})
