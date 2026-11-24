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

import { type Page, type Response, expect } from '@playwright/test'
import * as fs from 'node:fs'
export class Utilities {
  readonly page: Page
  constructor(page: Page) {
    this.page = page
  }

  async sleep(time) {
    await new Promise((resolve) => setTimeout(resolve, time))
  }

  // Call a JSON-RPC API method (e.g. inject_tlm) as the signed in user and
  // return its result. Fails the test if the call returns an error. JSON has no
  // NaN or Infinity, so pass those as { json_class: 'Float', raw: 'NaN' }.
  async api(
    method: string,
    params: unknown[],
    keywordParams: Record<string, unknown> = {},
  ): Promise<unknown> {
    const json = await this.page.evaluate(
      async ({ method, params, keywordParams }) => {
        const response = await fetch('/openc3-api/api', {
          method: 'POST',
          headers: {
            Authorization: localStorage.openc3Token,
            'Content-Type': 'application/json-rpc',
          },
          body: JSON.stringify({
            jsonrpc: '2.0',
            method,
            params,
            id: 1,
            keyword_params: { scope: 'DEFAULT', ...keywordParams },
          }),
        })
        return await response.json()
      },
      { method, params, keywordParams },
    )
    expect(json.error, `${method} returned an error`).toBeUndefined()
    return json.result
  }

  // Sign in through the Keycloak form (Enterprise) and wait until the app is
  // back with a token for this user.
  //
  // Waits for the form itself rather than a '**/auth/**' URL, and for the token
  // rather than a '**/tools/<tool>/**' URL: the form's own URL carries the tool
  // path in its redirect_uri, so URL globs can match on either side of the sign
  // in. A sign in that doesn't take then fails here, showing the page it's on,
  // instead of somewhere later in the test.
  async signIn(username: string, password: string = username) {
    await expect(
      this.page.getByRole('heading', { name: 'Sign in to your account' }),
    ).toBeVisible({ timeout: 20000 })
    await this.page.locator('input[name="username"]').fill(username)
    await this.page.locator('input[name="password"]').fill(password)
    await this.page.getByRole('button', { name: 'Sign In' }).click()
    await expect(this.page.locator('.v-app-bar')).toBeVisible({
      timeout: 20000,
    })
    await expect
      .poll(() => this.signedInUser(), {
        message: `signed in as ${username}`,
        timeout: 20000,
      })
      .toBe(username)
  }

  // Username in the app's current token, or undefined when there isn't one
  async signedInUser(): Promise<string | undefined> {
    try {
      return await this.page.evaluate(() => {
        const token = localStorage.openc3Token
        if (!token) return undefined
        const payload = token
          .split('.')[1]
          .replaceAll('-', '+')
          .replaceAll('_', '/')
        return JSON.parse(atob(payload)).preferred_username
      })
    } catch {
      // Mid-navigation the page has no context to evaluate in; poll again
      return undefined
    }
  }

  // Log out from the user menu in the app bar
  async logout() {
    await this.page.locator('[data-test="user-menu"]').click()
    await this.page.getByRole('button', { name: 'Logout', exact: true }).click()
  }

  // Log out and sign back in as another user (Enterprise)
  async switchUser(username: string, password: string = username) {
    await this.logout()
    await this.signIn(username, password)
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

  // Call the JSON-RPC API as the logged in user
  async api(method: string, params: any[], keywordParams = {}) {
    return await this.page.evaluate(
      async ({ method, params, keywordParams }) => {
        const response = await fetch('/openc3-api/api', {
          method: 'POST',
          headers: {
            Authorization: localStorage.openc3Token,
            'Content-Type': 'application/json-rpc',
            manual: 'true',
          },
          body: JSON.stringify({
            jsonrpc: '2.0',
            method,
            params,
            id: 1,
            keyword_params: { scope: 'DEFAULT', ...keywordParams },
          }),
        })
        return response.json()
      },
      { method, params, keywordParams },
    )
  }

  // The DEMO receives every packet at its packet time, so inject an
  // INST MEMDUMP whose received time is different. It's stored, so it skips
  // the CVT and the realtime streams and only lands in the TSDB, which keeps it
  // out of every other test. Returns once the TSDB has it.
  async injectReceivedTimeMemdump(
    offset: number,
    packetTime: Date,
    receivedTime: Date,
  ) {
    const injected = await this.api(
      'inject_tlm',
      [
        'INST',
        'MEMDUMP',
        { TIMESEC: packetTime.getTime() / 1000, TIMEUS: 0, OFFSET: offset },
      ],
      {
        type: 'RAW',
        stored: true,
        received_time: receivedTime.getTime() * 1_000_000, // nanoseconds
      },
    )
    expect(injected.error).toBeUndefined()

    // The TSDB microservice flushes periodically so wait for the row to land
    const range = {
      start_time: new Date(packetTime.getTime() - 1000).toISOString(),
      end_time: new Date(packetTime.getTime() + 1000).toISOString(),
    }
    await expect
      .poll(
        async () =>
          JSON.stringify(
            await this.api(
              'get_tlm_values',
              [['INST__MEMDUMP__OFFSET__RAW']],
              range,
            ),
          ),
        { timeout: 30000 },
      )
      .toContain(`${offset}`)
  }

  async download(
    page: Page,
    locator: string,
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
    const contents = fs.readFileSync(path, {
      encoding: encoding,
    })
    if (validator) {
      validator(contents)
    }
  }

  async inputValue(page: Page, locator: string, regex: RegExp) {
    // Poll since inputValue is immediate
    await expect
      .poll(async () => {
        return await page.inputValue(locator)
      })
      .toMatch(regex)
  }

  async dropdownSelectedValue(page: Page, locator: string, regex: RegExp) {
    await expect
      .poll(async () => {
        return await page
          .locator(locator + ' .v-autocomplete__selection-text')
          .innerText()
      })
      .toMatch(regex)
  }

  // Press the editor's save shortcut (Cmd-S on macOS, Ctrl-S elsewhere).
  // Pair with saveComplete() -- the keypress only fires the request.
  async ctrlS() {
    await this.page
      .locator('textarea')
      .press(process.platform === 'darwin' ? 'Meta+S' : 'Control+S')
  }

  // Resolves once the server has accepted the save of `filename`.
  //
  // Register it BEFORE the action that triggers the save and await it after,
  // so the listener exists before the response can land:
  //
  //   const saved = utils.saveComplete(file)
  //   await utils.ctrlS()
  //   await saved
  //
  // The "Saving..." snackbar cannot serve as this gate: ScriptRunner sets
  // showSave *after* issuing the POST and leaves it up for 2s after success,
  // so `expect(getByText('Saving...')).not.toBeVisible()` passes vacuously on
  // a starved runner and lets the next step race the in-flight save. That
  // matters most before opening a file dialog, which builds its tree from a
  // one-shot listing fetch and never refreshes it.
  saveComplete(filename: string): Promise<Response> {
    return this.scriptApiResponse(filename, 'POST')
  }

  // Resolves once ScriptRunner's reloadFile() fetch of `filename` has
  // returned, i.e. the contents are about to be installed in the editor.
  fileLoaded(filename: string): Promise<Response> {
    return this.scriptApiResponse(filename, 'GET')
  }

  // Match the pathname exactly rather than by substring: the '/delete',
  // '/lock' and '/syntax' endpoints all sit under the script's own path and
  // would otherwise resolve the wrong wait. Requiring 200 means a missing
  // file fails the wait instead of quietly letting the test continue.
  private scriptApiResponse(
    filename: string,
    method: 'GET' | 'POST',
  ): Promise<Response> {
    return this.page.waitForResponse(
      (response) =>
        new URL(response.url()).pathname ===
          `/script-api/scripts/${filename}` &&
        response.request().method() === method &&
        response.status() === 200,
    )
  }
}
