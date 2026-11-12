/*
# Copyright 2026 OpenC3, Inc.
# All Rights Reserved.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
# See LICENSE.md for more details.
*/

import { test, expect } from './../fixture'

test.use({
  toolPath: '/tools/admin/microservices',
  toolName: 'Administrator',
  storageState: 'adminStorageState.json',
})

test('displays microservice names', async ({ page, utils }) => {
  // Look for the INST2 microservices
  await expect(page.locator('[data-test="microserviceList"]')).toContainText(
    'DEFAULT__CLEANUP__INST2',
  )
  await expect(page.locator('[data-test="microserviceList"]')).toContainText(
    'DEFAULT__COMMANDLOG__INST2',
  )
  await expect(page.locator('[data-test="microserviceList"]')).toContainText(
    'DEFAULT__DECOM__INST2',
  )
  await expect(page.locator('[data-test="microserviceList"]')).toContainText(
    'DEFAULT__INTERFACE__INST2_INT',
  )
  // The demo targets run in the DEMO microservice group's processes instead of
  // their own MULTI (MICROSERVICE_GROUP DEMO)
  await expect(page.locator('[data-test="microserviceList"]')).toContainText(
    'DEFAULT__MULTIGROUP__DEMO',
  )
  await expect(
    page.locator('[data-test="microserviceList"]'),
  ).not.toContainText('DEFAULT__MULTI__INST2')
  await expect(page.locator('[data-test="microserviceList"]')).toContainText(
    'DEFAULT__PACKETLOG__INST2',
  )
})

test('groups microservices under their parent and microservice group', async ({
  page,
  utils,
}) => {
  const list = page.locator('[data-test="microserviceList"]')
  const group = list
    .locator('[data-test="microservice-group"]')
    .filter({ hasText: 'Microservice Group: DEMO' })
  await expect(group).toBeVisible()
  // The Ruby process runs INST2's logging and cleanup, the Python process
  // runs its decom and TSDB
  const ruby = ['DEFAULT__CLEANUP__INST2', 'DEFAULT__PACKETLOG__INST2']
  const python = ['DEFAULT__DECOM__INST2', 'DEFAULT__TSDB__INST2']
  await expect(list).toContainText(ruby[0] as string)

  // Collapsing a parent hides its children but not the parent
  await list
    .getByRole('button', { name: 'Collapse DEFAULT__MULTIGROUP__DEMO' })
    .click()
  for (const name of ruby) {
    await expect(list).not.toContainText(name)
  }
  for (const name of [...python, 'DEFAULT__MULTIGROUP__DEMO']) {
    await expect(list).toContainText(name)
  }
  await list
    .getByRole('button', { name: 'Expand DEFAULT__MULTIGROUP__DEMO' })
    .click()
  await expect(list).toContainText(ruby[0] as string)

  // Collapsing the group hides its processes and everything in them
  await group
    .getByRole('button', { name: 'Collapse microservice group DEMO' })
    .click()
  for (const name of [
    ...ruby,
    ...python,
    'DEFAULT__MULTIGROUP__DEMO',
    'DEFAULT__PYMULTIGROUP__DEMO',
  ]) {
    await expect(list).not.toContainText(name)
  }
  // Microservices outside the group are still shown
  await expect(list).toContainText('DEFAULT__INTERFACE__INST2_INT')
  await group
    .getByRole('button', { name: 'Expand microservice group DEMO' })
    .click()
  await expect(list).toContainText('DEFAULT__PYMULTIGROUP__DEMO')
})

test('displays microservice details', async ({ page, utils }) => {
  // Target the specific microservice's details button rather than a positional
  // nth() so the assertion is stable regardless of how many (and which)
  // microservices are present or their sort order.
  await page
    .locator('[data-test="microserviceList"]')
    .locator('.v-list-item')
    .filter({ hasText: 'DEFAULT__CLEANUP__INST2' })
    .locator('[aria-label="Show Microservice Details"]')
    .click()
  await expect(page.locator('.editor')).toContainText(
    '"name": "DEFAULT__CLEANUP__INST2"',
  )
  await page.getByRole('button', { name: 'Ok' }).click()
})

test('stops and starts microservices', async ({ page, utils }) => {
  test.slow()
  await page
    .locator('.v-list-item')
    .filter({ hasText: 'DEFAULT__USER__OPENC3-EXAMPLE' })
    .locator('.mdi-stop')
    .click()
  await page.locator('[data-test="confirm-dialog-stop"]').click()
  await expect(
    page
      .locator('.v-list-item')
      .filter({ hasText: 'DEFAULT__USER__OPENC3-EXAMPLE' }),
  ).toContainText('Enabled: False')

  // Check the CmdTlmServer log messages
  await page.goto('/tools/cmdtlmserver', {
    waitUntil: 'domcontentloaded',
  })
  await expect(page.locator('[data-test=log-messages]')).toContainText(
    'DEFAULT__USER__OPENC3-EXAMPLE stopped',
  )

  await page.goto('/tools/admin/microservices', {
    waitUntil: 'domcontentloaded',
  })
  await page
    .locator('.v-list-item')
    .filter({ hasText: 'DEFAULT__USER__OPENC3-EXAMPLE' })
    .locator('.mdi-play')
    .click()
  await page.locator('[data-test="confirm-dialog-restart"]').click()
  await expect(
    page
      .locator('.v-list-item')
      .filter({ hasText: 'DEFAULT__USER__OPENC3-EXAMPLE' }),
  ).toContainText('Enabled: True')

  // Check the CmdTlmServer log messages
  await page.goto('/tools/cmdtlmserver', {
    waitUntil: 'domcontentloaded',
  })
  await expect(page.locator('[data-test=log-messages]')).toContainText(
    'DEFAULT__USER__OPENC3-EXAMPLE started',
  )
})
