/*
# Copyright 2025 OpenC3, Inc
# All Rights Reserved.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
# See LICENSE.md for more details.
*/

// @ts-check
import { test, expect } from './../fixture'

test.use({
  toolPath: '/tools/admin/tools',
  toolName: 'Administrator',
  storageState: 'adminStorageState.json',
})

test('displays tool names', async ({ page, utils }) => {
  await expect(page.locator('[data-test="toolList"]')).toContainText(
    'CmdTlmServer',
  )
  await expect(page.locator('[data-test="toolList"]')).toContainText(
    'CmdTlmServer',
  )
  await expect(page.locator('[data-test="toolList"]')).toContainText(
    'Limits Monitor',
  )
  await expect(page.locator('[data-test="toolList"]')).toContainText(
    'Command Sender',
  )
  await expect(page.locator('[data-test="toolList"]')).toContainText(
    'Script Runner',
  )
  await expect(page.locator('[data-test="toolList"]')).toContainText(
    'Packet Viewer',
  )
  await expect(page.locator('[data-test="toolList"]')).toContainText(
    'Telemetry Viewer',
  )
  await expect(page.locator('[data-test="toolList"]')).toContainText(
    'Telemetry Grapher',
  )
  await expect(page.locator('[data-test="toolList"]')).toContainText(
    'Data Extractor',
  )
  await expect(page.locator('[data-test="toolList"]')).toContainText(
    'Data Viewer',
  )
  await expect(page.locator('[data-test="toolList"]')).toContainText(
    'Handbooks',
  )
  await expect(page.locator('[data-test="toolList"]')).toContainText(
    'Table Manager',
  )
  if (process.env.ENTERPRISE === '1') {
    await expect(page.locator('[data-test="toolList"]')).toContainText(
      'Calendar',
    )
    await expect(page.locator('[data-test="toolList"]')).toContainText(
      'Autonomic',
    )
  }
})

test('adds a new tool', async ({ page, context, utils }) => {
  await page.getByLabel('Tool Icon').fill('mdi-file')
  await page.getByLabel('Tool Name').fill('OpenC3Home')
  await page.getByLabel('Tool Url').fill('https://openc3.com')
  await page.locator('[data-test="toolAdd"]').click()
  // Wait for the tool to be added before reloading
  await expect(page.locator('[data-test="toolList"]')).toContainText(
    'OpenC3Home',
  )
  await page.reload()
  const pagePromise = context.waitForEvent('page')
  await page.getByRole('link', { name: 'OpenC3Home' }).click()
  const newPage = await pagePromise
  await newPage.waitForURL('https://openc3.com/')
})
