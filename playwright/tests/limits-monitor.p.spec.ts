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

// @ts-check
import { test, expect } from './fixture'
import { format } from 'date-fns'

test.use({
  toolPath: '/tools/limitsmonitor',
  toolName: 'Limits Monitor',
})

// await page.getByRole('cell', { name: 'playwright' }).click();

test('changes the limits set', async ({ page, utils }) => {
  expect(await page.getByLabel('Current Limits Set').inputValue()).toBe(
    'DEFAULT',
  )
  await page.locator('[data-test="limits-monitor-file"]').click()
  await page
    .locator('[data-test="limits-monitor-file-change-limits-set"]')
    .click()
  await page.getByRole('dialog').locator('[data-test="limits-set"]').click()
  await page.getByRole('option', { name: 'TVAC' }).click()
  await page.getByRole('button', { name: 'Ok' }).click()
  // Poll since inputValue is immediate
  await expect
    .poll(async () => page.getByLabel('Current Limits Set').inputValue(), {
      timeout: 15000,
    })
    .toBe('TVAC')

  await expect(page.locator('[data-test=limits-events]')).toContainText(
    'Setting Limits Set: TVAC',
  )
  await page.locator('[data-test="limits-monitor-file"]').click()
  await page
    .locator('[data-test="limits-monitor-file-change-limits-set"]')
    .click()
  await page.getByRole('dialog').locator('[data-test="limits-set"]').click()
  await page.getByRole('option', { name: 'DEFAULT' }).click()
  await page.getByRole('button', { name: 'Ok' }).click()
  // Poll since inputValue is immediate
  await expect
    .poll(async () => page.getByLabel('Current Limits Set').inputValue(), {
      timeout: 15000,
    })
    .toBe('DEFAULT')
  await expect(page.locator('[data-test=limits-events]')).toContainText(
    'Setting Limits Set: DEFAULT',
  )
})

test('saves, opens, and resets the configuration', async ({ page, utils }) => {
  await expect
    .poll(
      () =>
        page
          .locator('[data-test=limits-table]')
          .getByText("GROUND1STATUS")
          .count(),
      {
        timeout: 60000,
      },
    )
    .toBeGreaterThan(0)
  await expect
    .poll(
      () =>
        page
          .locator('[data-test=limits-table]')
          .getByText("GROUND2STATUS")
          .count(),
      {
        timeout: 60000,
      },
    )
    .toBeGreaterThan(0)

  // Ignore so we have something to check
  // Open the menu and click "Ignore Item"
  await page
    .locator('[data-test=limits-table]')
    .getByText("GROUND1STATUS")
    .first()
    .locator('xpath=ancestor::tr')
    .getByRole('button')
    .click()
  // Wait for menu to be visible and then click the option
  await page.waitForSelector('.v-list-item:has-text("Ignore Item")')
  await page.click('.v-list-item:has-text("Ignore Item")')

  await page
    .locator('[data-test=limits-table]')
    .getByText("GROUND2STATUS")
    .first()
    .locator('xpath=ancestor::tr')
    .getByRole('button')
    .click()
  // Wait for menu to be visible and then click the option
  await page.waitForSelector('.v-list-item:has-text("Ignore Item")')
  await page.click('.v-list-item:has-text("Ignore Item")')
  expect(await page.inputValue('[data-test=overall-state] input')).toMatch(
    'Some items ignored',
  )

  await page.locator('[data-test=limits-monitor-file]').click()
  await page.locator('text=Save Configuration').click()
  await page.getByLabel('Configuration Name').fill('playwright')
  await page.locator('button:has-text("Ok")').click()

  await page.locator('[data-test=limits-monitor-file]').click()
  await page.locator('text=Open Configuration').click()
  await page.locator(`td:has-text("playwright")`).click()
  await page.locator('button:has-text("Ok")').click()
  await page.getByRole('button', { name: 'Dismiss' }).click({ timeout: 20000 })

  await page.locator('[data-test=limits-monitor-file]').click()
  await page.locator('text=Show Ignored').click()
  await expect(
    page.locator('div[role="dialog"]:has-text("Ignored Items")'),
  ).toContainText('GROUND1STATUS')
  await expect(
    page.locator('div[role="dialog"]:has-text("Ignored Items")'),
  ).toContainText('GROUND2STATUS')
  await page.locator('button:has-text("Ok")').click()

  // Reset this test configuration
  await page.locator('[data-test=limits-monitor-file]').click()
  await page.locator('text=Reset Configuration').click()
  await utils.sleep(200) // Allow menu to close
  expect(await page.inputValue('[data-test=overall-state] input')).not.toMatch(
    'Some items ignored',
  )

  // Delete this test configuration
  await page.locator('[data-test=limits-monitor-file]').click()
  await page.locator('text=Open Configuration').click()
  await page
    .locator(`tr:has-text("playwright") [data-test=item-delete]`)
    .click()
  await page.locator('button:has-text("Delete")').click()
  await page.locator('[data-test=open-config-cancel-btn]').click()
})

test('temporarily hides items', async ({ page, utils }) => {
  // Since we're checking count() which is instant we need to poll
  await expect
    .poll(
      () => page.locator('[data-test=limits-table]').getByText("TEMP1").count(),
      {
        timeout: 60000,
      },
    )
    .toBe(2)

  // Hide both TEMP1s
  await page
    .locator('[data-test=limits-table]')
    .getByText("TEMP1")
    .first()
    .locator('xpath=ancestor::tr')
    .getByRole('button')
    .click()
  // Wait for menu to be visible and then click the option
  await page.waitForSelector('.v-list-item:has-text("Temporarily Hide Item")')
  await page.click('.v-list-item:has-text("Temporarily Hide Item")')

  await page
    .locator('[data-test=limits-table]')
    .getByText("TEMP1")
    .first()
    .locator('xpath=ancestor::tr')
    .getByRole('button')
    .click()
  // Wait for menu to be visible and then click the option
  await page.waitForSelector('.v-list-item:has-text("Temporarily Hide Item")')
  await page.click('.v-list-item:has-text("Temporarily Hide Item")')

  // Now wait for them to come back
  // Since we're checking count() which is instant we need to poll
  await expect
    .poll(
      () => page.locator('[data-test=limits-table]').getByText("TEMP1").count(),
      {
        timeout: 60000,
      },
    )
    .toBe(2)
})

test('ignores items', async ({ page, utils }) => {
  test.setTimeout(300000) // 5 min
  await expect
    .poll(
      () => page.locator('[data-test=limits-table]').getByText("TEMP1").count(),
      {
        timeout: 60000,
      },
    )
    .toBe(2)

  // Ignore both TEMP1s
  await page
    .locator('[data-test=limits-table]')
    .getByText("TEMP1")
    .first()
    .locator('xpath=ancestor::tr')
    .getByRole('button')
    .click()
  // Wait for menu to be visible and then click the option
  await page.waitForSelector('.v-list-item:has-text("Ignore Item")')
  await page.click('.v-list-item:has-text("Ignore Item")')

  await page
    .locator('[data-test=limits-table]')
    .getByText("TEMP1")
    .first()
    .locator('xpath=ancestor::tr')
    .getByRole('button')
    .click()
  // Wait for menu to be visible and then click the option
  await page.waitForSelector('.v-list-item:has-text("Ignore Item")')
  await page.click('.v-list-item:has-text("Ignore Item")')
  await expect(
    page.locator('[data-test=limits-table]').getByText("TEMP1"),
  ).not.toBeVisible()
  expect(await page.inputValue('[data-test=overall-state] input')).toMatch(
    'Some items ignored',
  )

  // Check the menu
  await page.locator('[data-test=limits-monitor-file]').click()
  await page.locator('text=Show Ignored').click()
  await expect(page.locator('.v-dialog')).toContainText('TEMP1')
  // Clear all ignored
  await page.locator('button:has-text("Clear All")').click()
  await page.locator('button:has-text("Ok")').click()
  await expect(page.locator('.v-dialog')).not.toBeInViewport()

  await page.locator('[data-test=limits-monitor-file]').click()
  await page.locator('text=Show Ignored').click()
  await expect(page.locator('.v-dialog')).not.toContainText('TEMP1')
  await page.locator('button:has-text("Ok")').click()
  await expect(page.locator('.v-dialog')).not.toBeVisible()
  // Wait for the TEMP1 to show up again
  await expect
    .poll(
      () => page.locator('[data-test=limits-table]').getByText("TEMP1").count(),
      {
        timeout: 60000,
      },
    )
    .toBe(2)
})

test('ignores entire packets', async ({ page, utils }) => {
  // The INST and INST2 targets both have VALUE2 and VALUE4 as red
  await expect(
    page.locator('[data-test=limits-table]').getByText("VALUE2")
  ).toHaveCount(2)
  await expect(
    page.locator('[data-test=limits-table]').getByText("VALUE4")
  ).toHaveCount(2)

  // Ignore the entire VALUE2 packet
  await page
    .locator('[data-test=limits-table]')
    .getByText("VALUE2")
    .first()
    .locator('xpath=ancestor::tr')
    .getByRole('button')
    .click()
  // Wait for menu to be visible and then click the option
  await page.waitForSelector('.v-list-item:has-text("Ignore Entire Packet")')
  await page.click('.v-list-item:has-text("Ignore Entire Packet")')
  await expect(
    page.locator('[data-test=limits-table]').getByText("VALUE2")
  ).toHaveCount(1)
  await expect(
    page.locator('[data-test=limits-table]').getByText("VALUE4")
  ).toHaveCount(1)

  // Check the menu
  await page.locator('[data-test=limits-monitor-file]').click()
  await page.locator('text=Show Ignored').click()
  await expect(page.locator('.v-dialog')).toContainText('PARAMS') // INST[2] PARAMS
  // Find the items and delete them to restore them
  await page.locator('[data-test=remove-ignore-0]').click()
  await expect(page.locator('.v-dialog')).not.toContainText('PARAMS') // INST[2] PARAMS
  await page.locator('button:has-text("Ok")').click()

  // Now we find both items again
  await expect
    .poll(
      () => page.locator('[data-test=limits-table]').getByText("VALUE2").count(),
      {
        timeout: 10000,
      },
    )
    .toBe(2)
  await expect
    .poll(
      () => page.locator('[data-test=limits-table]').getByText("VALUE4").count(),
      {
        timeout: 10000,
      },
    )
    .toBe(2)
})

test('displays the limits log', async ({ page, utils }) => {
  // Just verify we see dates and the various red, yellow, green states
  await expect(page.locator('[data-test=limits-events]')).toContainText(
    format(new Date(), 'yyyy-MM-dd'),
  )
  // These have long timeouts just to allow the demo to hit another limit
  await expect(page.locator('[data-test=limits-events]')).toContainText('RED', {
    timeout: 15000,
  })
  await expect(page.locator('[data-test=limits-events]')).toContainText(
    'YELLOW',
    { timeout: 15000 },
  )
  await expect(page.locator('[data-test=limits-events]')).toContainText(
    'GREEN',
    { timeout: 15000 },
  )
})
