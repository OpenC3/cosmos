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
import type { Utilities } from '../../utilities'
import { expect } from '../fixture'

// Opens the raw packet dialog from a packet's row and checks the dump and its
// download. `title` is the dialog title, e.g. 'Raw Telemetry Packet: INST MECH'.
export async function viewRawPacket(
  page: Page,
  utils: Utilities,
  row: string,
  title: string,
) {
  await page
    .getByRole('row', { name: row })
    .getByRole('button', { name: 'View Raw' })
    .click()
  const dialog = page.locator('.raw-dialog')
  await expect(dialog).toContainText(title)
  await expect(dialog).toContainText('Received Time:')
  await expect(dialog).toContainText('Count:')
  // The header renders before the first buffer fetch returns, so retry until
  // the dump replaces the 'No Data' placeholder
  const dump = page.locator('.raw-dialog textarea')
  await expect(dump).toHaveValue(/Address/)
  await expect(dump).toHaveValue(/00000000:/)

  await utils.download(page, '[data-test=download]', function (contents) {
    expect(contents).toMatch(title)
    expect(contents).toMatch('Received Time:')
    expect(contents).toMatch('Count:')
    expect(contents).toMatch('Address')
    expect(contents).toMatch('00000000:')
  })
}
