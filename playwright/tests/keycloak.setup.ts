/*
# Copyright 2025 OpenC3. Inc
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

// @ts-check
import { test } from '@playwright/test'

test('configure keycloak', async ({ page }) => {
  // Log into keycloak and setup the client redirect
  await page.goto(process.env.KEYCLOAK_URL)
  await page.getByLabel('Username or email').fill('admin')
  await page.getByLabel('Password', { exact: true }).fill('admin')
  await page.getByRole('button', { name: 'Sign In' }).click()
  await page.getByTestId('realmSelector').click()
  await page.getByRole('menuitem', { name: 'openc3' }).click()
  await page.getByRole('link', { name: 'Clients' }).click()
  await page.getByRole('link', { name: 'api' }).click()
  await page.getByTestId('redirectUris0').fill(process.env.REDIRECT_URL)
  await page.getByTestId('settings-save').click()
})
