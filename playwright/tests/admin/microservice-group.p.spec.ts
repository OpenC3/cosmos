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
import { expect, test } from './../fixture'

test.use({
  toolPath: '/tools/admin/plugins',
  toolName: 'Administrator',
  storageState: 'adminStorageState.json',
})

// Built by ./playwright.sh build-plugin. PW_GRP1 (Ruby) and PW_GRP2 (Python)
// both declare MICROSERVICE_GROUP PW_GROUP.
const plugin = 'openc3-cosmos-pw-group'
const pluginGem = 'openc3-cosmos-pw-group-1.0.0.gem'
// Each target keeps its own microservices, run in the group's shared processes
const groupMicroservices = [
  'DEFAULT__MULTIGROUP__PW_GROUP',
  'DEFAULT__PYMULTIGROUP__PW_GROUP',
  'DEFAULT__DECOM__PW_GRP1',
  'DEFAULT__PACKETLOG__PW_GRP1',
  'DEFAULT__TSDB__PW_GRP1',
  'DEFAULT__DECOM__PW_GRP2',
  'DEFAULT__PACKETLOG__PW_GRP2',
  'DEFAULT__TSDB__PW_GRP2',
]
// Installing and removing the group's targets one at a time takes a while
const timeout = 120000

async function uninstall(page: Page) {
  await page.goto('/tools/admin/plugins')
  await page
    .locator('[data-test=plugin-list-item]')
    .filter({ hasText: plugin })
    .locator('[data-test=plugin-actions]')
    .click()
  await page.locator('[data-test=delete-plugin]').click()
  // No target files are modified so this goes straight to the uninstall
  // without the "Modified" dialog
  await page.locator('[data-test=confirm-dialog-delete]').click()
  // The plugin is removed from the list once the uninstall is done
  await expect(page.locator('[data-test=plugin-list]')).not.toContainText(
    plugin,
    { timeout },
  )
}

// utils is unused but requesting it makes the fixture open toolPath
test('targets in a microservice group share microservices', async ({
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

  try {
    // The group's processes replace each target's own MULTI
    await page.goto('/tools/admin/microservices')
    const list = page.locator('[data-test="microserviceList"]')
    // PW_GRP2 is the last target installed, so once all of these are running
    // the install has stopped restarting the group's processes
    for (const name of groupMicroservices) {
      await expect(
        list.locator('.v-list-item').filter({ hasText: name }),
      ).toContainText('RUNNING', { timeout })
    }
    for (const name of ['DEFAULT__MULTI__PW_GRP1', 'DEFAULT__MULTI__PW_GRP2']) {
      await expect(list).not.toContainText(name)
    }
    // Shown under the group's header and their parent
    await expect(
      list
        .locator('[data-test="microservice-group"]')
        .filter({ hasText: 'Microservice Group: PW_GROUP' }),
    ).toBeVisible()

    // Data for both targets flows through their decom microservices in the
    // shared processes. inject_tlm and build_cmd are both handled by decom.
    await page.goto('/tools/scriptrunner')
    await expect(page.locator('.v-app-bar')).toContainText('Script Runner')
    await page.locator('textarea')
      .fill(`# Retry in case a group microservice is still restarting
def inject(target, value)
  3.times do |i|
    return inject_tlm(target, "STATUS", { "VALUE" => value })
  rescue => e
    raise e if i == 2
    wait(5)
  end
end
inject("PW_GRP1", 1.5)
inject("PW_GRP2", 2.5)
wait_check("PW_GRP1 STATUS VALUE == 1.5", 30)
wait_check("PW_GRP2 STATUS VALUE == 2.5", 30)
puts "PW_GRP1 #{build_cmd("PW_GRP1 EXAMPLE with VALUE 1")['packet_name']}"
puts "PW_GRP2 #{build_cmd("PW_GRP2 EXAMPLE with VALUE 2")['packet_name']}"`)
    await page.locator('[data-test=start-button]').click()
    await expect(page.locator('[data-test=state] input')).toHaveValue(
      'completed',
      { timeout },
    )
    const output = page.locator('[data-test=output-messages]')
    await expect(output).toContainText('PW_GRP1 EXAMPLE')
    await expect(output).toContainText('PW_GRP2 EXAMPLE')
  } finally {
    await uninstall(page)
  }

  // The group's processes are removed with its last target
  await page.goto('/tools/admin/microservices')
  const list = page.locator('[data-test="microserviceList"]')
  await expect(list).toContainText('DEFAULT__INTERFACE__INST2_INT')
  await expect(list).not.toContainText('PW_GROUP', { timeout })
  await expect(list).not.toContainText('PW_GRP')
})
