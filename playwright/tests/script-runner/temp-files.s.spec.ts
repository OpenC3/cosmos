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

// @ts-check
import { test, expect } from './../fixture'

test.use({
  toolPath: '/tools/scriptrunner',
  toolName: 'Script Runner',
})

// This must be run in serial since it deletes all TEMP files
// and other tests may be creating TEMP files
test('can delete all temp files', async ({ page, utils }) => {
  // Create new file which when run will become a TEMP file
  await page.locator('textarea').fill('puts "temp11111111"')
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
  await expect(page.locator('#sr-controls')).toContainText(
    /__TEMP__\/\d{4}_\d{2}_\d{2}_\d{2}_\d{2}_\d{2}_\d{3}_\w{8}_temp.rb/,
  )
  let tempFile1 = await page.locator('[data-test=filename] input').inputValue()
  tempFile1 = tempFile1.split('/')[1]

  // New file
  await page.locator('[data-test=script-runner-file]').click()
  await page.locator('text=New File').click()
  await expect(page.locator('#sr-controls')).toContainText('<Untitled>')
  await page.locator('textarea').fill('puts "temp22222222"')
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
  await expect(page.locator('#sr-controls')).toContainText(
    /__TEMP__\/\d{4}_\d{2}_\d{2}_\d{2}_\d{2}_\d{2}_\d{3}_\w{8}_temp.rb/,
  )
  let tempFile2 = await page.locator('[data-test=filename] input').inputValue()
  tempFile2 = tempFile2.split('/')[1]
  expect(tempFile1).not.toEqual(tempFile2)

  // Open file
  await page.locator('[data-test=script-runner-file]').click()
  await page.locator('text=Open File').click()
  await utils.sleep(500) // Allow background data to fetch
  await page.locator('.v-dialog >> text=__TEMP__').click()
  await expect(page.locator(`.v-dialog >> text=${tempFile1}`)).toBeVisible()
  await expect(page.locator(`.v-dialog >> text=${tempFile2}`)).toBeVisible()

  await page
    .getByText('__TEMP__')
    .locator('xpath=..') // parent
    .getByRole('button')
    .click()
  await page.locator('[data-test="confirm-dialog-delete"]').click()
  await expect(page.locator('.v-dialog >> text=__TEMP__')).not.toBeVisible()
  await page.locator('[data-test="file-open-save-cancel-btn"]').click()

  // Open file
  await page.locator('[data-test=script-runner-file]').click()
  await page.locator('text=Open File').click()
  await utils.sleep(500) // Allow background data to fetch
  await expect(page.locator('.v-dialog')).toContainText('INST')
  await expect(page.locator('.v-dialog')).not.toContainText('__TEMP__')
  await page.locator('[data-test="file-open-save-cancel-btn"]').click()
})
