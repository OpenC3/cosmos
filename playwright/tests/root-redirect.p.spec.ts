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

// The base tool's router sends the root URL to the first shown tool other than
// Admin. When nothing else is shown (e.g. a plugin install failed partway
// through init) it must fall back to the default tool instead of throwing.
// Enterprise CI runs this spec too, which covers the Enterprise router.
test('redirects the root URL to the default tool when only Admin is shown', async ({
  page,
  baseURL,
  utils,
}) => {
  await page.route('**/openc3-api/tools/all*', async (route) => {
    await route.fulfill({
      json: {
        Base: { name: 'Base', url: '/tools/base', shown: false },
        Admin: { name: 'Admin', url: '/tools/admin', shown: true },
      },
    })
  })
  await page.goto(`${baseURL}/`, { waitUntil: 'domcontentloaded' })
  await expect(page).toHaveURL(`${baseURL}/tools/cmdtlmserver`)
  await expect(page.locator('.v-app-bar')).toContainText('CmdTlmServer')
})
