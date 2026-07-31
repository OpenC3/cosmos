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

  // Clear every alert toast currently on screen.
  //
  // Clicking an individual toast's dismiss button is fragile three ways, all of
  // which have been seen failing in CI on one action:
  //   - vuetify-sonner stacks toasts and animates them in and out, so the button
  //     is reported "element is not stable" for as long as the stack is moving
  //   - a newer toast sits on top of an older one, so the click is refused with
  //     "<other toast> subtree intercepts pointer events"
  //   - toasts auto-dismiss, so the button can detach mid-click ("element was
  //     detached from the DOM")
  // dispatchEvent bypasses hit-testing and the stability wait entirely, so an
  // overlapping or animating toast can't block it. Toasts disappearing on their
  // own is the desired end state, so a detached button is not an error.
  //
  // Assert on the toast text separately (and before calling this) when the toast
  // itself is part of what a test is verifying -- this is cleanup, not a check.
  async dismissToasts() {
    const dismiss = this.page.locator('[data-test="dismiss-toast"]')
    // Bounded rather than while(count) so a toast stream can't spin forever.
    for (let i = 0; i < 20; i++) {
      if ((await dismiss.count()) === 0) return
      try {
        await dismiss.first().dispatchEvent('click', {}, { timeout: 2000 })
      } catch {
        // Auto-dismissed between the count and the dispatch; nothing to do.
      }
    }
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
    await this.sleep(100) // Give the menu a little more time to load

    if (packet) {
      await this.page.locator('[data-test=select-packet]').click()
      // Filter since the packet list can be long; typing collapses the
      // virtualized v-list so the target option stays stable during click
      // (otherwise the option can detach from the DOM mid-render).
      //
      // Target the input via data-test rather than getByRole('combobox', {
      // name: 'Select Packet' }). Vuetify's generated input ids can collide, and
      // when they do this input's aria-labelledby resolves to the app bar's
      // Scope label instead of its own: the a11y tree reports
      // `combobox "Scope": ABORT` with "Select Packet" left as an unassociated
      // generic node, so the by-name lookup matches nothing and fill() times out.
      await this.page.locator('[data-test="select-packet"] input').fill(packet)
      await this.page.getByRole('option', { name: packet, exact: true }).click()
      await expect(
        this.page.locator('[data-test="select-packet"]'),
      ).toContainText(packet)

      if (item) {
        // Wait for items to load after packet change
        await expect(
          this.page.locator('[data-test="select-item"] input'),
        ).toBeEnabled()
        await this.sleep(100) // Give the menu a little more time to load

        await this.page.locator('[data-test=select-item] i').click()
        // Fill to filter since the item list can be long. data-test rather than
        // by accessible name, for the same id-collision reason as the packet
        // input above.
        await this.page.locator('[data-test="select-item"] input').fill(item)
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
