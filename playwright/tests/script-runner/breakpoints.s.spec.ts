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

import { test, expect } from '../fixture'

test.use({
  toolPath: '/tools/scriptrunner',
  toolName: 'Script Runner',
})

// Run this file's tests sequentially in one worker (overrides fullyParallel).
// Breakpoints are stored server-side per filename and 'remembers breakpoints
// and clears all' hits /script-api/breakpoints/delete/all, which wipes the
// breakpoint 'sets and clears breakpoints' just saved if they overlap.
test.describe.configure({ mode: 'default' })

test('sets and clears breakpoints', async ({ page, utils }) => {
  await page.locator('textarea').fill(`puts "a"
puts "b"
puts "c"
puts "d"
puts "e"`)
  await page.locator('.ace_gutter-cell').nth(2).click({ force: true })

  await page.locator('[data-test=start-button]').click()
  await expect(page.locator('[data-test=state] input')).toHaveValue(
    'breakpoint',
    {
      timeout: 20000,
    },
  )
  await page.locator('[data-test=go-button]').click()
  await expect(page.locator('[data-test=state] input')).toHaveValue(
    'completed',
    {
      timeout: 20000,
    },
  )
  await expect(page.locator('[data-test=start-button]')).toBeEnabled()
  await utils.sleep(500) // Allow script to fully complete

  // Disable the breakpoint
  await page.locator('.ace_gutter-cell').nth(2).click({ force: true })
  await page.locator('[data-test=start-button]').click()
  await expect(page.locator('[data-test=state] input')).toHaveValue(
    'Connecting...',
    {
      timeout: 5000,
    },
  )
  await expect(page.locator('[data-test=state] input')).toHaveValue(
    'completed',
    {
      timeout: 20000,
    },
  )
})

test('remembers breakpoints and clears all', async ({ page, utils }) => {
  await page.locator('[data-test=script-runner-file]').click()
  await page.locator('text=Open File').click()
  await utils.sleep(500)
  await page
    .locator('[data-test=file-open-save-search] input')
    .fill('checks.rb')
  await page.locator('text=checks >> nth=0').click() // nth=0 because INST, INST2
  await page.locator('[data-test=file-open-save-submit-btn]').click()
  await expect(page.locator('#sr-controls')).toContainText(
    `INST/procedures/checks.rb`,
  )
  await utils.sleep(1000) // Clicking on the ace gutters requires a little wait
  await page.locator('.ace_gutter-cell').nth(1).click({ force: true })
  await page.locator('.ace_gutter-cell').nth(3).click({ force: true })
  await page.locator('[data-test=script-runner-file]').click()
  await page.locator('text=Save File').click()
  await utils.sleep(200) // Allow the save to take place
  await page.reload()
  await utils.sleep(1000) // allow page to reload
  // Reloading the page should bring up the previous script
  await expect(page.locator('#sr-controls')).toContainText(
    `INST/procedures/checks.rb`,
  )

  await expect(page.locator('.ace_gutter-cell').nth(1)).toHaveClass(
    'ace_gutter-cell ace_breakpoint',
  )
  await expect(page.locator('.ace_gutter-cell').nth(3)).toHaveClass(
    'ace_gutter-cell ace_breakpoint',
  )

  await page.locator('[data-test=script-runner-script]').click()
  await page.getByText('Delete All Breakpoints').click()
  await page.locator('.v-dialog >> button:has-text("Delete")').click()

  await expect(page.locator('.ace_gutter-cell').nth(1)).toHaveClass(
    'ace_gutter-cell ',
  )
  await expect(page.locator('.ace_gutter-cell').nth(3)).toHaveClass(
    'ace_gutter-cell ',
  )
})
