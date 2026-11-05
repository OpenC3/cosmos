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

import { test, expect } from './../fixture'

test.use({
  toolPath: '/tools/scriptrunner',
  toolName: 'Script Runner',
})

test('clears the editor on File->New', async ({ page, utils }) => {
  // Have to fill on an editable area like the textarea
  await page.locator('textarea').fill('this is a test')
  await utils.sleep(1000)
  await expect(page.locator('.editor')).toContainText('this is a test')
  await page.locator('[data-test=script-runner-file]').click()
  await page.locator('text=New File').click()
  // Confirmation dialog
  await page.locator('text=You have unsaved changes').click()
  await page.locator('button:has-text("Continue")').click()
  await expect(page.locator('.editor')).not.toContainText('this is a test')
})

test('open a file', async ({ page, utils }) => {
  await page.locator('[data-test=script-runner-file]').click()
  await page.locator('text=Open File').click()
  await expect(page.getByText('INST2', { exact: true })).toBeVisible()
  await page
    .locator('[data-test=file-open-save-search] input')
    .fill('disconnect.rb')
  await expect(page.locator('text=disconnect.rb')).toBeVisible()
  await page.locator('text=disconnect.rb').click()
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
  await expect(page.getByText('INST2', { exact: true })).toBeVisible()
  await page
    .locator('[data-test=file-open-save-search] input')
    .fill('metadata.py')
  await expect(page.locator('text=metadata.py')).toBeVisible()
  await page.locator('text=metadata.py').click()
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

  // If the file already exists from a previous parallel run, handle the overwrite dialog
  const overwriteDialog = page.locator(
    'text=Are you sure you want to overwrite',
  )
  if (await overwriteDialog.isVisible({ timeout: 1000 }).catch(() => false)) {
    await overwriteDialog.click()
    await page.locator('button:has-text("Overwrite")').click()
  }

  await expect(
    page.getByRole('dialog').filter({ hasText: 'File Save As...' }),
  ).not.toBeVisible()
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
  const file = 'INST/procedures/save_overwrite.rb'

  await page.locator('textarea').fill('puts "File Save overwrite"')
  await page.locator('[data-test=script-runner-file]').click()
  await page.locator('text=Save File').click()
  await expect(page.locator('text=File Save As')).toBeVisible()
  await page.locator('[data-test=file-open-save-filename] input').fill(file)
  const saved = utils.saveComplete(file)
  await page.locator('[data-test=file-open-save-submit-btn]').click()

  // If the file already exists from a previous parallel run, handle the overwrite dialog
  const overwriteDialog = page.locator(
    'text=Are you sure you want to overwrite',
  )
  if (await overwriteDialog.isVisible({ timeout: 1000 }).catch(() => false)) {
    await overwriteDialog.click()
    await page.locator('button:has-text("Overwrite")').click()
  }

  await expect(
    page.getByRole('dialog').filter({ hasText: 'File Save As...' }),
  ).not.toBeVisible()
  // Wait for save to complete before continuing
  await saved
  await expect(page.locator('#sr-controls')).toContainText(file)

  await page.locator('textarea').fill('# comment1')
  // The ' *' is fileModified: proof the editor registered the edit before we
  // ask it to save.
  await expect(page.locator('#sr-controls')).toContainText(`${file} *`)
  const savedFromMenu = utils.saveComplete(file)
  await page.locator('[data-test=script-runner-file]').click()
  await page.locator('text=Save File').click()
  // Wait for save to complete before continuing
  await savedFromMenu

  await page.locator('textarea').fill('# comment2')
  await expect(page.locator('#sr-controls')).toContainText(`${file} *`)
  const savedFromCtrlS = utils.saveComplete(file)
  await utils.ctrlS()
  await savedFromCtrlS

  // File->Save As
  await page.locator('[data-test=script-runner-file]').click()
  await page.locator('text=Save As...').click()
  // The dialog builds its tree from the listing once in created(). The submit
  // button is enabled exactly when every target has finished loading
  // (disableButtons === false), and until then success() silently no-ops, so
  // this is the gate for clicking SAVE.
  await expect(
    page.locator('[data-test=file-open-save-submit-btn]'),
  ).toBeEnabled()
  await expect(
    page.locator('[data-test=file-open-save-filename] input'),
  ).toHaveValue(file)
  const resaved = utils.saveComplete(file)
  await page.locator('[data-test=file-open-save-submit-btn]').click()
  // Confirmation dialog
  await page.locator('text=Are you sure you want to overwrite').click()
  await page.locator('button:has-text("Overwrite")').click()
  // Wait for the save itself, not the snackbar, so the delete below cannot
  // race the POST that rewrites the file.
  await resaved

  // Delete the file
  await page.locator('[data-test=script-runner-file]').click()
  await page.locator('text=Delete File').click()
  await expect(page.locator('text=Permanently delete file')).toBeVisible()
  await page.locator('button:has-text("Delete")').click()
})

// TargetFile.all marks a file with a trailing '*' when a targets_modified copy
// exists alongside the plugin's original. The marker is display-only -- the
// server strips it back off in TargetFile.body -- so it must never reach the
// Filename field. TargetFile.create does NOT strip it, so a marker that gets
// submitted writes a literal '*' object into the bucket that body() then
// resolves to the unmarked file, silently hiding the saved data.
test('strips the modified marker on Save As', async ({ page, utils }) => {
  const original = 'INST/procedures/throughput_test.rb'

  // reloadFile() issues this on mount. Registered before the goto so the
  // response can't land before we're listening.
  const bodyLoaded = utils.fileLoaded(original)

  // throughput_test.rb is used by no other spec, and deleting it at the end
  // removes only the targets_modified copy, restoring the plugin's original.
  await page.goto(`/tools/scriptrunner?file=${original}`, {
    waitUntil: 'domcontentloaded',
  })
  await expect(page.locator('.v-app-bar')).toContainText('Script Runner')
  // #sr-controls shows the filename as soon as it is read off the route query,
  // before reloadFile() has awaited the body -- and saveFile() refuses to run
  // at all while that load is in flight (saveAllowed === false). Asserting on
  // the editor contents is not an option: a targets_modified copy left behind
  // by an earlier run makes them unpredictable. So wait for the response, then
  // for the Start button, which setFile() re-enables in the same tick it
  // installs the contents. The response wait is what makes the button check
  // meaningful -- startOrGoDisabled defaults to false, so on its own it could
  // pass before reloadFile() had set it.
  await bodyLoaded
  await expect(page.locator('[data-test=start-button]')).toBeEnabled()

  // Write a comment to mark the file as modified, then save it so the marker appears in the listing.
  await page.locator('textarea').fill('# comment2')
  // The ' *' is fileModified: proof the editor registered the edit before we
  // ask it to save.
  await expect(page.locator('#sr-controls')).toContainText(`${original} *`)
  const saved = utils.saveComplete(original)
  await utils.ctrlS()
  // The targets_modified copy -- and so the '*' in the listing the dialog is
  // about to fetch -- does not exist until this response lands. The dialog
  // builds its tree once in created() and never refreshes, so opening it early
  // means the marker never shows up at all.
  await saved

  await page.locator('[data-test=script-runner-file]').click()
  await page.locator('text=Save As...').click()
  // The dialog builds its tree from the listing on created(), and the submit
  // button is enabled exactly when every target has finished loading
  // (disableButtons === false). That gates reading the tree, reading the
  // field (each loadFiles() completion re-assigns it from inputFilename) and
  // clicking SAVE (success() no-ops while the buttons are disabled).
  await expect(
    page.locator('[data-test=file-open-save-submit-btn]'),
  ).toBeEnabled()
  await expect(
    page.locator('[data-test=file-open-save-filename] input'),
  ).toHaveValue(original)

  await page
    .locator('[data-test=file-open-save-search] input')
    .fill('throughput_test.rb')
  // Precondition: without the marker actually present in the tree this test
  // would pass no matter what the dialog does with it.
  const marked = page
    .locator('.tree-container')
    .getByText('throughput_test.rb*', { exact: true })
  await expect(marked).toBeVisible()

  // Selecting the marked file must fill in the clean path. toHaveValue is an
  // exact match, so a trailing '*' fails here.
  await marked.click()
  await expect(
    page.locator('[data-test=file-open-save-filename] input'),
  ).toHaveValue(original)

  // And the overwrite confirmation quotes the clean path, not the marked one
  const resaved = utils.saveComplete(original)
  await page.locator('[data-test=file-open-save-submit-btn]').click()
  await expect(page.getByText(`overwrite: ${original}`)).toBeVisible()
  await page.locator('button:has-text("Overwrite")').click()

  await expect(
    page.getByRole('dialog').filter({ hasText: 'File Save As...' }),
  ).not.toBeVisible()
  // Wait for the save itself, not the snackbar, so the delete below cannot
  // race the POST that rewrites the file.
  await resaved
  await expect(page.locator('#sr-controls')).toContainText(original)

  // Delete the targets_modified copy so the plugin's original is restored
  await page.locator('[data-test=script-runner-file]').click()
  await page.locator('text=Delete File').click()
  await expect(page.locator('text=Permanently delete file')).toBeVisible()
  await page.locator('button:has-text("Delete")').click()
  // newFile() only runs once the delete POST resolves, so this confirms the
  // cleanup actually happened rather than leaving the copy behind.
  await expect(page.locator('#sr-controls')).toContainText('<Untitled>')
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

  // If the file already exists from a previous parallel run, handle the overwrite dialog
  const overwriteDialog = page.locator(
    'text=Are you sure you want to overwrite',
  )
  if (await overwriteDialog.isVisible({ timeout: 1000 }).catch(() => false)) {
    await overwriteDialog.click()
    await page.locator('button:has-text("Overwrite")').click()
  }

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
