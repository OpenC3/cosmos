/*
# Copyright 2024 OpenC3, Inc.
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
import { test, expect } from './../fixture'
import { parse, addMinutes, subMinutes, isWithinInterval } from 'date-fns'

test.use({
  toolPath: '/tools/cmdtlmserver',
  toolName: 'CmdTlmServer',
})

test('displays in local or UTC time', async ({ page, utils }) => {
  // Allow the table to populate
  await expect(page.locator('[data-test=log-messages]')).toContainText('INFO')
  // First row is the header: Index, Name, Value so grab second (1)
  const now = new Date()
  let dateString =
    (
      await page
        .locator('[data-test="log-messages"]')
        .locator('tr')
        .nth(1)
        .locator('td')
        .nth(0)
        .textContent()
    )?.trim() || ''
  let date = parse(dateString, 'yyyy-MM-dd HH:mm:ss.SSS', now)
  expect(
    isWithinInterval(date, {
      start: subMinutes(now, 5),
      end: addMinutes(now, 5),
    }),
  ).toBeTruthy()

  // Switch to UTC
  await page.goto('/tools/admin/settings')
  await expect(page.locator('.v-app-bar')).toContainText('Administrator')
  await page.locator('[data-test=time-zone]').click()
  await page.getByRole('option', { name: 'UTC' }).click()
  await page.locator('[data-test="save-time-zone"]').click()

  await page.goto('/tools/cmdtlmserver')
  await expect(page.locator('.v-app-bar')).toContainText('CmdTlmServer')
  // Allow the table to populate
  await expect(page.locator('[data-test=log-messages]')).toContainText('INFO')
  // First row is the header: Index, Name, Value so grab second (1)
  dateString =
    (
      await page
        .locator('[data-test="log-messages"]')
        .locator('tr')
        .nth(1)
        .locator('td')
        .nth(0)
        .textContent()
    )?.trim() || ''
  // The date is now in UTC but we parse it like it is local time
  date = parse(dateString, 'yyyy-MM-dd HH:mm:ss.SSS', now)
  // so subtrack off the timezone offset to get it back to local time
  date = subMinutes(date, now.getTimezoneOffset())

  expect(
    isWithinInterval(date, {
      start: subMinutes(now, 5),
      end: addMinutes(now, 5),
    }),
  ).toBeTruthy()

  // Switch back to local time
  await page.goto('/tools/admin/settings')
  await expect(page.locator('.v-app-bar')).toContainText('Administrator')
  await page.locator('[data-test=time-zone]').click()
  await page.getByRole('option', { name: 'local' }).click()
  await page.locator('[data-test="save-time-zone"]').click()
})
