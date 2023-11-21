/*
# Copyright 2023 OpenC3, Inc.
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
*/

/* Per https://github.com/anishkny/playwright-test-coverage/blob/main/LICENSE
   The code marked Copyright (c) 2021 Anish Karandikar has the following license:

  MIT License

  Copyright (c) 2021 Anish Karandikar

  Permission is hereby granted, free of charge, to any person obtaining a copy
  of this software and associated documentation files (the "Software"), to deal
  in the Software without restriction, including without limitation the rights
  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
  copies of the Software, and to permit persons to whom the Software is
  furnished to do so, subject to the following conditions:

  The above copyright notice and this permission notice shall be included in all
  copies or substantial portions of the Software.

  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
  SOFTWARE.
*/

import { expect, test as base } from '@playwright/test'
import { Utilities } from '../utilities'

// Copyright (c) 2021 Anish Karandikar
const fs = require('fs')
const path = require('path')
const crypto = require('crypto')
const istanbulTempDir = process.env.ISTANBUL_TEMP_DIR
  ? path.resolve(process.env.ISTANBUL_TEMP_DIR)
  : path.join(process.cwd(), '.nyc_output')
function generateUUID() {
  return crypto.randomBytes(16).toString('hex')
}
// End Copyright

// Extend the page fixture to goto the OpenC3 tool and wait for potential
// redirect to authentication login (Enterprise only).
// Login and click the hamburger nav icon to close the navigation drawer
export const test = base.extend<{
  context: any
  utils: Utilities
  toolPath: string
  toolName: string
}>({
  toolPath: '/tools/cmdtlmserver',
  toolName: 'CmdTlmServer',
  utils: async ({ context, baseURL, toolPath, toolName, page }, use) => {
    await page.goto(`${baseURL}${toolPath}`, { waitUntil: 'domcontentloaded' })
    let utils = new Utilities(page)
    if (process.env.ENTERPRISE === '1') {
      const signin = page.getByText('Sign in to your account')
      const tool = page.locator(`.v-app-bar:has-text('${toolName}')`)
      await expect(signin.or(tool)).toBeVisible()
      if (await signin.isVisible()) {
        if (page.url().includes('admin')) {
          await page.locator('input[name="username"]').fill('admin')
          await page.locator('input[name="password"]').fill('admin')
          await Promise.all([
            page.waitForURL(`${baseURL}${toolPath}`),
            page.locator('input:has-text("Sign In")').click(),
          ])
          await page.context().storageState({ path: 'adminStorageState.json' })
        } else {
          await page.locator('input[name="username"]').fill('operator')
          await page.locator('input[name="password"]').fill('operator')
          await Promise.all([
            page.waitForURL(`${baseURL}${toolPath}`),
            page.locator('input:has-text("Sign In")').click(),
          ])
          await page.context().storageState({ path: 'storageState.json' })
        }
      }
    }
    await expect(page.locator('.v-app-bar')).toContainText(toolName, {
      timeout: 20000,
    })
    await page.locator('#openc3-app-toolbar path').click()
    await expect(page.locator('#openc3-nav-drawer')).toBeHidden()

    // Copyright (c) 2021 Anish Karandikar
    await context.addInitScript(() =>
      window.addEventListener('beforeunload', () =>
        window.collectIstanbulCoverage(JSON.stringify(window.__coverage__)),
      ),
    )
    await fs.promises.mkdir(istanbulTempDir, { recursive: true })
    await context.exposeFunction('collectIstanbulCoverage', (coverageJSON) => {
      if (coverageJSON)
        fs.writeFileSync(
          path.join(
            istanbulTempDir,
            `playwright_coverage_${generateUUID()}.json`,
          ),
          coverageJSON,
        )
    })
    // End Copyright

    // This is like a yield in a Ruby block where we call back to the
    // test and execute the individual test code
    await use(utils)

    // Copyright (c) 2021 Anish Karandikar
    for (const page of context.pages()) {
      await page.evaluate(() =>
        window.collectIstanbulCoverage(JSON.stringify(window.__coverage__)),
      )
    }
    // End Copyright
  },
})
export { expect } from '@playwright/test'
