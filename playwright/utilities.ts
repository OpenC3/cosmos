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
# All changes Copyright 2025, OpenC3, Inc.
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
    await this.page.locator('[data-test=select-target]').click()
    await this.page.getByRole('option', { name: target, exact: true }).click()
    await expect(
      this.page.locator('[data-test="select-target"]'),
    ).toContainText(target)
    if (packet) {
      await this.sleep(500) // Wait for packets to populate
      await this.page.locator('[data-test=select-packet]').click()
      await this.page.getByRole('option', { name: packet, exact: true }).click()
      await expect(
        this.page.locator('[data-test="select-packet"]'),
      ).toContainText(packet)
      if (item) {
        await this.sleep(500) // Wait for items to populate
        await this.page.locator('[data-test=select-item] i').click()
        // Need to fill the item to allow filtering since the item list can be long
        await this.page.getByLabel('Select Item').fill(item)
        await this.page.getByRole('option', { name: item, exact: true }).click()
        await expect(
          this.page.locator('[data-test="select-item"]'),
        ).toContainText(item)
      } else {
        // If we're only selecting a packet wait for items to populate
        await this.sleep(500)
      }
    } else {
      // If we're only selecting a target wait for packets to populate
      await this.sleep(500)
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
