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
import { test, expect } from './../fixture'

test.use({
  toolPath: '/tools/scriptrunner',
  toolName: 'Script Runner',
})

test('clears the editor on File->New', async ({ page, utils }) => {
  // Have to fill on an editable area like the textarea
  await page.locator('textarea').fill('this is a test')
  // But can't check on the textarea because it has an input
  await expect(page.locator('.editor')).toContainText('this is a test')
  await page.locator('[data-test=script-runner-file]').click()
  await page.locator('text=New File').click()
  await expect(page.locator('.editor')).not.toContainText('this is a test')
})

test('open a file', async ({ page, utils }) => {
  await page.locator('[data-test=script-runner-file]').click()
  await page.locator('text=Open File').click()
  await utils.sleep(500) // Allow background data to fetch
  await expect(page.getByText('INST2', { exact: true })).toBeVisible()
  await utils.sleep(100)
  await page.locator('[data-test=file-open-save-search] input').fill('dis')
  await utils.sleep(100)
  await page.locator('[data-test=file-open-save-search] input').fill('con')
  await utils.sleep(100)
  await page.locator('[data-test=file-open-save-search] input').fill('nect')
  await utils.sleep(100)
  await page.locator('text=disconnect >> nth=0').click() // nth=0 because INST, INST2
  await page.locator('[data-test=file-open-save-submit-btn]').click()
  await expect(page.locator('.v-dialog')).not.toBeVisible()
  await expect(page.locator('#sr-controls')).toContainText(
    `INST/procedures/disconnect.rb`,
  )

  // Reload and verify the file is still there
  await page.reload()
  await utils.sleep(1000) // allow page to reload
  await expect(page.locator('#sr-controls')).toContainText(
    `INST/procedures/disconnect.rb`,
  )
  await page.locator('[data-test=script-runner-file]').click()
  await page.locator('text=Open File').click()
  await utils.sleep(500) // Allow background data to fetch
  await expect(page.getByText('INST2', { exact: true })).toBeVisible()
  await utils.sleep(100)
  await page.locator('[data-test=file-open-save-search] input').fill('meta')
  await utils.sleep(100)
  await page.locator('[data-test=file-open-save-search] input').fill('data')
  await utils.sleep(100)
  await page.locator('text=metadata >> nth=1').click() // nth=0 because INST, INST2
  await page.locator('[data-test=file-open-save-submit-btn]').click()
  await expect(page.locator('.v-dialog')).not.toBeVisible()
  await expect(page.locator('#sr-controls')).toContainText(
    `INST2/procedures/metadata.py`,
  )

  // Verify the recent files menu
  await page.locator('[data-test=script-runner-file]').click()
  await page.getByText('Open Recent').hover()
  await expect(page.locator('text=INST/procedures/disconnect.rb')).toBeVisible()
  await expect(
    page.locator(
      '.v-list-item-title:has-text("INST/procedures/disconnect.rb")',
    ),
  ).toBeVisible()
  await expect(
    page.locator('.v-list-item-title:has-text("INST2/procedures/metadata.py")'),
  ).toBeVisible()
  await page
    .locator('.v-list-item-title:has-text("INST/procedures/disconnect.rb")')
    .click()
  await expect(page.locator('#sr-controls')).toContainText(
    `INST/procedures/disconnect.rb`,
  )
})

test('open a file using url param', async ({ page, utils }) => {
  await page.goto('/tools/scriptrunner?file=INST2/procedures/collect.py', {
    waitUntil: 'domcontentloaded',
  })
  await expect(page.locator('.v-app-bar')).toContainText('Script Runner')
  await expect(page.locator('#sr-controls')).toContainText(
    `INST2/procedures/collect.py`,
  )
  // Lots of things we could check but just verify a little
  await expect(
    page
      .locator('pre')
      .filter({ hasText: 'INST2/procedures/utilities/collect.py' })
      .first(),
  ).toBeVisible()
})

test('handles File->Save new file', async ({ page, utils }) => {
  await page.locator('textarea').fill('puts "File Save new File"')
  await page.locator('[data-test=script-runner-file]').click()
  await page.locator('text=Save File').click()
  // New files automatically open File Save As
  await expect(page.locator('text=File Save As')).toBeVisible()
  await utils.sleep(500) // Allow background data to fetch
  await page
    .locator('[data-test=file-open-save-filename] input')
    .fill('save_new.rb')
  await expect(
    page.locator('text=save_new.rb is not a valid filename'),
  ).toBeVisible()
  await page.getByText('INST', { exact: true }).click()
  await page.getByText('procedures', { exact: true }).click()
  const prepend = await page
    .locator('[data-test=file-open-save-filename] input')
    .inputValue()
  await page
    .locator('[data-test=file-open-save-filename] input')
    .fill(`${prepend}/save_new.rb`)
  await page.locator('[data-test=file-open-save-submit-btn]').click()
  await expect(page.locator('#sr-controls')).toContainText(
    'INST/procedures/save_new.rb',
  )

  // Delete the file
  await page.locator('[data-test=script-runner-file]').click()
  await page.locator('text=Delete File').click()
  await expect(page.locator('text=Permanently delete file')).toBeVisible()
  await page.locator('button:has-text("Delete")').click()
})

test('handles File Save overwrite', async ({ page, utils }) => {
  await page.locator('textarea').fill('puts "File Save overwrite"')
  await page.locator('[data-test=script-runner-file]').click()
  await page.locator('text=Save File').click()
  await page
    .locator('[data-test=file-open-save-filename] input')
    .fill('INST/procedures/save_overwrite.rb')
  await page.locator('[data-test=file-open-save-submit-btn]').click()
  await expect(page.locator('#sr-controls')).toContainText(
    'INST/procedures/save_overwrite.rb',
  )

  await page.locator('textarea').fill('# comment1')
  await page.locator('[data-test=script-runner-file]').click()
  await page.locator('text=Save File').click()
  await page.locator('textarea').fill('# comment2')
  if (process.platform === 'darwin') {
    await page.locator('textarea').press('Meta+S') // Ctrl-S save
  } else {
    await page.locator('textarea').press('Control+S') // Ctrl-S save
  }

  // File->Save As
  await page.locator('[data-test=script-runner-file]').click()
  await page.locator('text=Save As...').click()
  await expect(
    page.locator('text=INST/procedures/save_overwrite.rb'),
  ).toBeVisible()
  await page.locator('[data-test=file-open-save-submit-btn]').click()
  // Confirmation dialog
  await page.locator('text=Are you sure you want to overwrite').click()
  await page.locator('button:has-text("Overwrite")').click()

  // Delete the file
  await page.locator('[data-test=script-runner-file]').click()
  await page.locator('text=Delete File').click()
  await expect(page.locator('text=Permanently delete file')).toBeVisible()
  await page.locator('button:has-text("Delete")').click()
})

test('handles Download', async ({ page, utils }) => {
  await page.locator('textarea').fill('download this')
  await page.locator('[data-test=script-runner-file]').click()
  await page.locator('text=Save File').click()
  await page.fill(
    '[data-test=file-open-save-filename] input',
    'INST/download.txt',
  )
  await page.locator('[data-test=file-open-save-submit-btn]').click()
  await expect(page.locator('#sr-controls')).toContainText('INST/download.txt')
  // Download the file
  await page.locator('[data-test=script-runner-file]').click()
  await utils.download(
    page,
    '[data-test=script-runner-file-download]',
    function (contents) {
      expect(contents).toContain('download this')
    },
  )

  // Delete the file
  await page.locator('[data-test=script-runner-file]').click()
  await page.locator('text=Delete File').click()
  await expect(page.locator('text=Permanently delete file')).toBeVisible()
  await page.locator('button:has-text("Delete")').click()
})

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
  await expect(page.locator('[data-test=state] input')).toHaveValue('stopped', {
    timeout: 20000,
  })
  await expect(page.locator('#sr-controls')).toContainText(
    /__TEMP__\/\d{4}_\d{2}_\d{2}_\d{2}_\d{2}_\d{2}_\d{3}_temp.rb/,
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
  await expect(page.locator('[data-test=state] input')).toHaveValue('stopped', {
    timeout: 20000,
  })
  await expect(page.locator('#sr-controls')).toContainText(
    /__TEMP__\/\d{4}_\d{2}_\d{2}_\d{2}_\d{2}_\d{2}_\d{3}_temp.rb/,
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
