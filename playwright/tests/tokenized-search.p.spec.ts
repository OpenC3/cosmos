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

import { test, expect } from './fixture'

// TargetPacketItemChooser is shared by Packet Viewer, Command Sender, Data
// Extractor, Data Viewer and others. Telemetry Grapher is used as the host
// here because it shows all three dropdowns (target, packet and item), so one
// spec can cover the whole component.
test.use({
  toolPath: '/tools/tlmgrapher',
  toolName: 'Telemetry Grapher',
})

// Open a chooser dropdown and type a query into it
async function searchDropdown(page, field: string, query: string) {
  await expect(page.locator(`[data-test="${field}"] input`)).toBeEnabled()
  await page.locator(`[data-test=${field}]`).click()
  await page.locator(`[data-test="${field}"] input`).fill(query)
}

test('finds a packet with tokens typed in any order', async ({
  page,
  utils,
}) => {
  await utils.selectTargetPacketItem('INST')

  // A single token still behaves the way it always has, matching every packet
  // that contains it
  await searchDropdown(page, 'select-packet', 'stat')
  await expect(
    page.getByRole('option', { name: 'HEALTH_STATUS', exact: true }),
  ).toBeVisible()
  await expect(
    page.getByRole('option', { name: 'THROUGHPUT_STATUS', exact: true }),
  ).toBeVisible()

  // Adding a second token narrows it down, in either order
  await page.locator('[data-test="select-packet"] input').fill('heal stat')
  await expect(page.getByRole('option')).toHaveText(['HEALTH_STATUS'])
  await page.locator('[data-test="select-packet"] input').fill('stat heal')
  await expect(page.getByRole('option')).toHaveText(['HEALTH_STATUS'])

  await page.getByRole('option', { name: 'HEALTH_STATUS', exact: true }).click()
  await expect(page.locator('[data-test=select-packet]')).toContainText(
    'HEALTH_STATUS',
  )
})

test('finds a packet despite typos', async ({ page, utils }) => {
  await utils.selectTargetPacketItem('INST')

  // Transposed characters
  await searchDropdown(page, 'select-packet', 'hael stat')
  await expect(page.getByRole('option')).toHaveText(['HEALTH_STATUS'])

  // A dropped character
  await page.locator('[data-test="select-packet"] input').fill('heal sat')
  await expect(page.getByRole('option')).toHaveText(['HEALTH_STATUS'])

  // Both tokens mistyped at once
  await page.locator('[data-test="select-packet"] input').fill('healht statsu')
  await expect(page.getByRole('option')).toHaveText(['HEALTH_STATUS'])
})

test('requires every token to match', async ({ page, utils }) => {
  await utils.selectTargetPacketItem('INST')

  // HEALTH_STATUS matches "heal" but nothing matches "xyz", so the whole
  // query matches nothing rather than falling back to a partial match
  await searchDropdown(page, 'select-packet', 'heal xyz')
  await expect(page.getByRole('option')).toHaveCount(0)
})

test('ranks exact matches above typo matches', async ({ page, utils }) => {
  await utils.selectTargetPacketItem('INST', 'HEALTH_STATUS')

  await searchDropdown(page, 'select-item', 'ground2status')

  // GROUND1STATUS is one typo away from the query so it matches too, and it
  // sorts first alphabetically. Ranking has to put the exact match on top
  // because auto-select-first makes the top option the one Enter picks.
  await expect(
    page.getByRole('option', { name: 'GROUND1STATUS', exact: true }),
  ).toBeVisible()
  await expect(page.getByRole('option').first()).toHaveText('GROUND2STATUS')

  await page.locator('[data-test="select-item"] input').press('Enter')
  await expect(page.locator('[data-test=select-item]')).toContainText(
    'GROUND2STATUS',
  )
})

// Data Extractor is the only tool that enables glob mode, which swaps the
// packet and item dropdowns from v-autocomplete to v-combobox. A combobox
// keeps its model in sync with the text as it is typed rather than only on
// selection, so it needs its own coverage.
test.describe('with wildcards enabled', () => {
  test.use({
    toolPath: '/tools/dataextractor',
    toolName: 'Data Extractor',
  })

  async function enableWildcards(page, utils) {
    await expect(page.locator('.v-app-bar')).toContainText('Data Extractor')
    await page.locator('[data-test=data-extractor-mode]').click()
    await page.getByText('Allow Wildcards').click()
    await page.keyboard.press('Escape')
    await utils.selectTargetPacketItem('INST')
    await page.locator('[data-test=select-packet]').click()
  }

  test('accepts a tokenized query in a combobox', async ({ page, utils }) => {
    await enableWildcards(page, utils)

    // pressSequentially rather than fill: a combobox rewrites its own input
    // whenever the model changes, and a fill() is discarded. Typing is also
    // what catches a guard that reacts to the space between tokens.
    await page
      .locator('[data-test="select-packet"] input')
      .pressSequentially('heal stat')
    await expect(page.locator('[data-test="select-packet"] input')).toHaveValue(
      'heal stat',
    )
    await expect(page.getByRole('option')).toHaveText(['HEALTH_STATUS'])
  })

  test('does not keep a query as the selection', async ({ page, utils }) => {
    await enableWildcards(page, utils)
    await page
      .locator('[data-test="select-packet"] input')
      .pressSequentially('heal stat')

    // Moving focus away without picking an option must not leave the query
    // behind as though it were a packet name
    await page.locator('[data-test=select-target] input').click()
    await expect(
      page.locator('[data-test="select-packet"] input'),
    ).not.toHaveValue('heal stat')
  })
})
