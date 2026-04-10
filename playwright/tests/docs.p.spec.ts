/*
# Copyright 2026 OpenC3, Inc.
# All Rights Reserved.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
# See LICENSE.md for more details.
*/

// @ts-check
import { test, expect } from './fixture'

// Start with a tool so we can use the fixture
// Navigating directly to the static docs doesn't include the NavBar
test.use({
  toolPath: '/tools/cmdtlmserver',
  toolName: 'CmdTlmServer',
})

test('verify documentation pages and search', async ({ page, utils }) => {
  await page.locator('rux-icon-apps path').click()
  await page.getByRole('link', { name: 'Documentation' }).click()

  await page
    .locator('iframe[title="Documentation"]')
    .contentFrame()
    .getByRole('contentinfo')
    .getByRole('link', { name: 'Documentation' })
    .click()
  await expect(
    page
      .locator('iframe[title="Documentation"]')
      .contentFrame()
      .getByText('Notes are handy pieces of'),
  ).toBeVisible()

  // Search for STATE, click the Telemetry result, and verify the contents
  await page
    .locator('iframe[title="Documentation"]')
    .contentFrame()
    .getByRole('searchbox', { name: 'Search' })
    .fill('STATE')
  await page
    .locator('iframe[title="Documentation"]')
    .contentFrame()
    .getByText('Telemetry STATE STATE STATE')
    .click()
  await expect(
    page
      .locator('iframe[title="Documentation"]')
      .contentFrame()
      .getByRole('heading', { name: 'STATEDirect link to STATE' }),
  ).toBeVisible()
  await expect(
    page
      .locator('iframe[title="Documentation"]')
      .contentFrame()
      .getByText('Defines a key/value pair for the current item'),
  ).toBeVisible()

  // Search for CRC Protocol, click the Protocols result, and verify the contents
  await page
    .locator('iframe[title="Documentation"]')
    .contentFrame()
    .getByRole('searchbox', { name: 'Search' })
    .fill('CRC Protocol')
  await page
    .locator('iframe[title="Documentation"]')
    .contentFrame()
    .getByText('Protocols CRC Protocol CRC')
    .click()
  await expect(
    page
      .locator('iframe[title="Documentation"]')
      .contentFrame()
      .getByRole('heading', { name: 'CRC ProtocolDirect link to' }),
  ).toBeVisible()
  await expect(
    page
      .locator('iframe[title="Documentation"]')
      .contentFrame()
      .getByText('The CRC protocol can add CRCs'),
  ).toBeVisible()
})
