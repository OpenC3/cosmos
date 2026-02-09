/*
# Copyright 2022 Ball Aerospace & Technologies Corp.
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
#
# Modified by OpenC3, Inc.
# All changes Copyright 2026, OpenC3, Inc.
# All Rights Reserved
*/

import { Page, expect } from '@playwright/test'
import * as fs from 'fs'
export class Utilities {
  readonly page: Page
  constructor(page: Page) {
    this.page = page
  }

  async sleep(time) {
    await new Promise((resolve) => setTimeout(resolve, time))
  }

  async selectTargetPacketItem(target: string, packet?: string, item?: string) {
    // On mount the component calls get_target_names() and auto-selects the
    // first target. The selection text element only renders once that API
    // call returns and a value is chosen, so wait for it before interacting.
    await expect(
      this.page.locator(
        '[data-test="select-target"] .v-autocomplete__selection-text',
      ),
    ).toBeVisible()
    // After auto-selecting a target, updatePackets() temporarily disables
    // the dropdowns (internalDisabled=true). Wait for that to finish so we
    // don't open the menu only to have it close mid-interaction.
    await expect(this.page.locator('[data-test="select-target"]')).toBeEnabled()
    await this.page.locator('[data-test=select-target]').click()
    await this.page.getByRole('option', { name: target, exact: true }).click()
    await expect(
      this.page.locator('[data-test="select-target"]'),
    ).toContainText(target)
    // If the target changed, Vue's synchronous reactivity sets
    // internalDisabled=true before Playwright's click resolves.
    // If re-selected, packets are already loaded and this passes immediately.
    await expect(this.page.locator('[data-test="select-packet"]')).toBeEnabled()

    if (packet) {
      await this.page.locator('[data-test=select-packet]').click()
      await this.page.getByRole('option', { name: packet, exact: true }).click()
      await expect(
        this.page.locator('[data-test="select-packet"]'),
      ).toContainText(packet)
      // Wait for item dropdown to be enabled if it exists. When a packet
      // changes, updateItems() sets internalDisabled=true until items load.
      const itemDropdown = this.page.locator('[data-test="select-item"]')
      if ((await itemDropdown.count()) > 0) {
        await expect(itemDropdown).toBeEnabled()
      }

      if (item) {
        await this.page.locator('[data-test=select-item] i').click()
        // Need to fill the item to allow filtering since the item list can be long
        await this.page
          .getByRole('combobox', { name: 'Select Item' })
          .fill(item)
        await this.page.getByRole('option', { name: item, exact: true }).click()
        await expect(
          this.page.locator('[data-test="select-item"]'),
        ).toContainText(item)
      }
    }
  }

  async addTargetPacketItem(target: string, packet?: string, item?: string) {
    await this.selectTargetPacketItem(target, packet, item)
    await this.page.locator('[data-test=select-send]').click()
  }

  async download(
    page: any,
    locator: any,
    validator?: { (contents: any) },
    encoding: string = 'utf-8',
  ) {
    const [download] = await Promise.all([
      // Start waiting for the download
      page.waitForEvent('download'),
      // Initiate the download
      page.locator(locator).click(),
    ])
    // Wait for the download process to complete
    const path = await download.path()
    const contents = await fs.readFileSync(path, {
      encoding: encoding,
    })
    if (validator) {
      validator(contents)
    }
  }

  async inputValue(page, locator, regex) {
    // Poll since inputValue is immediate
    await expect
      .poll(async () => {
        return await page.inputValue(locator)
      })
      .toMatch(regex)
  }

  async dropdownSelectedValue(page, locator, regex) {
    await expect
      .poll(async () => {
        return await page
          .locator(locator + ' .v-autocomplete__selection-text')
          .innerText()
      })
      .toMatch(regex)
  }
}
