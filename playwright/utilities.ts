/*
# Copyright 2022 Ball Aerospace & Technologies Corp.
# All Rights Reserved.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
# See LICENSE.md for more details.
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
    // Wait for component initialization to complete.
    // The component sets internalDisabled=true on creation and only clears it
    // after both target names and initial packet names load from the API.
    // This disables the actual <input> elements inside each v-autocomplete.
    await expect(
      this.page.locator('[data-test="select-target"] input'),
    ).toBeEnabled()

    await this.page.locator('[data-test=select-target]').click()
    await this.page.getByRole('option', { name: target, exact: true }).click()
    await expect(
      this.page.locator('[data-test="select-target"]'),
    ).toContainText(target)

    // Wait for packets to load after target change (internalDisabled cycle)
    await expect(
      this.page.locator('[data-test="select-packet"] input'),
    ).toBeEnabled()

    if (packet) {
      await this.page.locator('[data-test=select-packet]').click()
      await this.page.getByRole('option', { name: packet, exact: true }).click()
      await expect(
        this.page.locator('[data-test="select-packet"]'),
      ).toContainText(packet)

      if (item) {
        // Wait for items to load after packet change
        await expect(
          this.page.locator('[data-test="select-item"] input'),
        ).toBeEnabled()
        await this.page.locator('[data-test=select-item] i').click()
        // Fill to filter since the item list can be long
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
    await expect(this.page.locator('[data-test=select-send]')).toBeEnabled()
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
