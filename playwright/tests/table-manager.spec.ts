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

test.use({
  toolPath: '/tools/tablemanager',
  toolName: 'Table Manager',
})

//
// Test the File menu
//
test('creates a single binary file', async ({ page, utils }) => {
  await page.locator('[data-test=table-manager-file]').click()
  await page.locator('text=New').click()
  await expect(page.locator('.v-dialog')).toBeVisible()
  await utils.sleep(500) // Allow file dialog to fully render
  await page.locator('[data-test=file-open-save-search] input').fill('MCCon')
  await utils.sleep(500)
  await page.locator('[data-test=file-open-save-search] input').fill('fig')
  await page.locator('text=MCConfig >> nth=0').click() // nth=0 because INST, INST2
  await page.locator('[data-test="file-open-save-submit-btn"]').click()
  await expect(page.locator('id=openc3-tool')).toContainText('MC_CONFIGURATION')
  await expect(page.locator('.v-tab')).toHaveCount(1)
  await expect(
    page.locator('[data-test=definition-filename] input'),
  ).toHaveValue('INST/tables/config/MCConfigurationTable_def.txt')
  expect(await page.inputValue('[data-test=filename] input')).toMatch(
    'INST/tables/bin/MCConfigurationTable.bin',
  )
})

test('edits a binary file', async ({ page, utils }) => {
  await page.locator('[data-test=table-manager-file]').click()
  await page.locator('text=New').click() // Create new since we're editing
  await expect(page.locator('.v-dialog')).toBeVisible()
  await utils.sleep(500) // Allow file dialog to fully render
  await page
    .locator('[data-test=file-open-save-search] input')
    .fill('ConfigTables_')
  await page.locator('text=ConfigTables_ >> nth=0').click() // nth=0 because INST, INST2
  await page.locator('[data-test=file-open-save-submit-btn]').click()
  await expect(page.locator('id=openc3-tool')).toContainText('MC_CONFIGURATION')
  await expect(page.locator('id=openc3-tool')).toContainText('TLM_MONITORING')
  await expect(page.locator('id=openc3-tool')).toContainText('PPS_SELECTION')
  await expect(page.locator('.v-tab')).toHaveCount(3)
  expect(
    await page.locator('[data-test=definition-filename] input').inputValue(),
  ).toMatch('INST/tables/config/ConfigTables_def.txt')
  expect(await page.locator('[data-test=filename] input').inputValue()).toMatch(
    'INST/tables/bin/ConfigTables.bin',
  )

  // Verify original contents
  await utils.download(
    page,
    '[data-test=download-file-report]',
    function (contents) {
      expect(contents).toContain('ConfigTables.bin')
      expect(contents).toContain('MC_CONFIGURATION')
      expect(contents).toContain('SCRUB_REGION_1_START_ADDR, 0x0')
      expect(contents).toContain('TLM_MONITORING')
      expect(contents).toContain(
        '1, 0, 0, BITS, 0, 0, LESS_THAN, NO_ACTION_REQUIRED, ALL_MODES, UNSIGNED',
      )
      expect(contents).toContain('PPS_SELECTION')
      expect(contents).toContain('PRIMARY_PPS, CHECKED')
      expect(contents).toContain('REDUNDANT_PPS, UNCHECKED')
    },
  )

  await page.locator('text=MC_CONFIGURATION').click()
  await page
    .getByRole('row', { name: '1 SCRUB_REGION_1_START_ADDR' })
    .locator('[data-test="table-item-text-field"] input')
    .fill('0xabcdef')

  await page.locator('text=TLM_MONITORING').click()
  await expect(page.locator('id=openc3-tool')).toContainText('THRESHOLD')
  await page
    .locator(
      '[data-test=TLM_MONITORING] tr:nth-child(1) td:nth-child(2) [data-test=table-item-text-field] input',
    )
    .fill('1')
  await page
    .locator(
      '[data-test=TLM_MONITORING] tr:nth-child(1) td:nth-child(3) [data-test=table-item-text-field] input',
    )
    .fill('2')
  await page
    .locator('[data-test=TLM_MONITORING] tr:nth-child(1)')
    .getByRole('combobox')
    .filter({ hasText: 'BITS' })
    .click()
  await page.locator('text=BYTE').click()
  await expect(
    page.locator('[data-test=TLM_MONITORING] tr:nth-child(1) td:nth-child(4)'),
  ).toContainText('BYTE')
  await page
    .locator(
      '[data-test=TLM_MONITORING] tr:nth-child(1) td:nth-child(5) [data-test=table-item-text-field] input',
    )
    .fill('3')
  await page
    .locator(
      '[data-test=TLM_MONITORING] tr:nth-child(1) td:nth-child(6) [data-test=table-item-text-field] input',
    )
    .fill('4')
  await page
    .locator('[data-test=TLM_MONITORING] tr:nth-child(1)')
    .getByRole('combobox')
    .filter({ hasText: 'LESS_THAN' })
    .click()
  await page.locator('text=GREATER_THAN').click()
  await expect(
    page.locator('[data-test=TLM_MONITORING] tr:nth-child(1) td:nth-child(7)'),
  ).toContainText('GREATER_THAN')
  await page
    .locator('[data-test=TLM_MONITORING] tr:nth-child(1)')
    .getByRole('combobox')
    .filter({ hasText: 'NO_ACTION_REQUIRED' })
    .click()
  await page.locator('text=INITIATE_RESET').click()
  await expect(
    page.locator('[data-test=TLM_MONITORING] tr:nth-child(1) td:nth-child(8)'),
  ).toContainText('INITIATE_RESET')
  await page
    .locator('[data-test=TLM_MONITORING] tr:nth-child(1)')
    .getByRole('combobox')
    .filter({ hasText: 'ALL_MODES' })
    .click()
  await page.locator('text=SAFE_MODE').click()
  await expect(
    page.locator('[data-test=TLM_MONITORING] tr:nth-child(1) td:nth-child(9)'),
  ).toContainText('SAFE_MODE')

  await page.locator('text=PPS_SELECTION').click()
  await page
    .getByRole('row', { name: '1 PRIMARY_PPS' })
    .locator('[type="checkbox"]')
    .click()
  await page
    .getByRole('row', { name: '2 REDUNDANT_PPS' })
    .locator('[type="checkbox"]')
    .click()

  await page.locator('[data-test=table-manager-file]').click()
  await page.locator('text=Save File').click()
  await utils.sleep(5000) // Saving takes some time

  // Check for new values
  await utils.download(
    page,
    '[data-test=download-file-report]',
    function (contents) {
      expect(contents).toContain('ConfigTables.bin')
      expect(contents).toContain('MC_CONFIGURATION')
      expect(contents).toContain('SCRUB_REGION_1_START_ADDR, 0xABCDEF')
      expect(contents).toContain('TLM_MONITORING')
      expect(contents).toContain(
        '1, 1, 2, BYTE, 3, 4, GREATER_THAN, INITIATE_RESET, SAFE_MODE',
      )
      expect(contents).toContain('PPS_SELECTION')
      expect(contents).toContain('PRIMARY_PPS, UNCHECKED')
      expect(contents).toContain('REDUNDANT_PPS, CHECKED')
    },
  )
})

test('opens and searches file', async ({ page, utils }) => {
  await page.locator('[data-test=table-manager-file]').click()
  await page.locator('text=Open File').click()
  await utils.sleep(500) // Allow background data to fetch
  await page
    .locator('[data-test=file-open-save-search] input')
    .fill('ConfigTables')
  await utils.sleep(100)
  await page.locator('[data-test=file-open-save-search] input').fill('.bin')
  await page.locator('text=ConfigTables >> nth=0').click()
  await page.locator('[data-test=file-open-save-submit-btn]').click()
  await expect(page.locator('id=openc3-tool')).toContainText('MC_CONFIGURATION')
  await expect(page.locator('id=openc3-tool')).toContainText('TLM_MONITORING')
  await expect(page.locator('id=openc3-tool')).toContainText('PPS_SELECTION')
  await expect(page.locator('.v-tab')).toHaveCount(3)
  expect(
    await page.locator('[data-test=definition-filename] input').inputValue(),
  ).toMatch('INST/tables/config/ConfigTables_def.txt')
  expect(await page.locator('[data-test=filename] input').inputValue()).toMatch(
    'INST/tables/bin/ConfigTables.bin',
  )

  // Test searching
  await expect(page.locator('tr')).toHaveCount(12)
  await page.locator('text=Items >> input').fill('UNEDIT')
  await expect.poll(() => page.locator('tr').count()).toBe(4)
  await expect(page.locator('tr >> input >> nth=0')).toBeDisabled()
  await expect(page.locator('tr >> input >> nth=1')).toBeDisabled()
  await expect(page.locator('tr >> input >> nth=2')).toBeDisabled()
  await page.locator('text=Items >> input').fill('')
  await expect.poll(() => page.locator('tr').count()).toBe(12)
})

test('downloads binary, definition, report', async ({ page, utils }) => {
  await page.locator('[data-test=table-manager-file]').click()
  await page.locator('text=Open File').click()
  await utils.sleep(500) // Allow background data to fetch
  await page
    .locator('[data-test=file-open-save-search] input')
    .fill('ConfigTables')
  await utils.sleep(100)
  await page.locator('[data-test=file-open-save-search] input').fill('.bin')
  await page.locator('text=ConfigTables >> nth=0').click()
  await page.locator('[data-test=file-open-save-submit-btn]').click()
  await utils.download(page, '[data-test=download-file-binary]')
  await utils.download(
    page,
    '[data-test=download-file-definition]',
    function (contents) {
      expect(contents).toContain('TABLEFILE')
    },
  )
  await utils.download(
    page,
    '[data-test=download-file-report]',
    function (contents) {
      expect(contents).toContain('ConfigTables.bin')
    },
  )
  await page.locator('text=PPS_SELECTION').click()
  await utils.download(
    page,
    '[data-test="PPS_SELECTION"] [data-test=download-table-binary]',
    function (contents) {
      expect(contents.length).toBe(2)
    },
    'binary',
  )
  await utils.download(
    page,
    '[data-test="PPS_SELECTION"] [data-test=download-table-definition]',
    function (contents) {
      expect(contents).toContain('TABLE "PPS_Selection"')
    },
  )
  await utils.download(
    page,
    '[data-test="PPS_SELECTION"] [data-test=download-table-report]',
    function (contents) {
      expect(contents).toContain('PPS_SELECTION')
    },
  )
})

test('save as and delete', async ({ page, utils }) => {
  await page.locator('[data-test=table-manager-file]').click()
  await page.locator('text=Open File').click()
  await utils.sleep(500) // Allow background data to fetch
  await expect(page.locator('.v-dialog')).toBeVisible()
  await page
    .locator('[data-test=file-open-save-search] input')
    .fill('ConfigTables')
  await utils.sleep(100)
  await page.locator('[data-test=file-open-save-search] input').fill('.bin')
  await page
    .locator('.v-list-item')
    .filter({ hasText: 'ConfigTables.bin' })
    .first()
    .click()
  await page.locator('[data-test=file-open-save-submit-btn]').click()
  if (await page.locator('[data-test=confirm-dialog-overwrite]').isVisible()) {
    await page.locator('[data-test=confirm-dialog-overwrite]').click()
  }
  await expect(page.locator('id=openc3-tool')).toContainText('MC_CONFIGURATION')
  // These checks are all with regex because sometimes the file will be edited and have a * at the end
  await expect(page.locator('[data-test=filename] input')).toHaveValue(
    /INST\/tables\/bin\/ConfigTables\.bin/,
  )
  await expect(
    page.locator('[data-test=definition-filename] input'),
  ).toHaveValue(/INST\/tables\/config\/ConfigTables_def\.txt/)

  await page.locator('[data-test=table-manager-file]').click()
  await page.locator('text=Save As').click()
  await expect(page.locator('.v-dialog')).toBeVisible()
  await page
    .locator('[data-test=file-open-save-filename] input')
    .fill('INST/tables/bin/ConfigTables2.bin')
  await page.locator('[data-test=file-open-save-submit-btn]').click()
  if (await page.locator('[data-test=confirm-dialog-overwrite]').isVisible()) {
    await page.locator('[data-test=confirm-dialog-overwrite]').click()
  }
  await expect(page.locator('[data-test=filename] input')).toHaveValue(
    /INST\/tables\/bin\/ConfigTables2\.bin/,
  )
  await expect(
    page.locator('[data-test=definition-filename] input'),
  ).toHaveValue(/INST\/tables\/config\/ConfigTables_def\.txt/)

  // Verify we can open it cleanly
  await page.locator('[data-test=table-manager-file]').click()
  await page.locator('text=Open File').click()
  await utils.sleep(500) // Allow background data to fetch
  await expect(page.locator('.v-dialog')).toBeVisible()
  await page
    .locator('[data-test=file-open-save-search] input')
    .fill('ConfigTables2')
  await utils.sleep(100)
  await page.locator('[data-test=file-open-save-search] input').fill('.bin')
  await page.getByRole('listbox').getByText('ConfigTables2.bin').click()
  await page.locator('[data-test=file-open-save-submit-btn]').click()
  if (await page.locator('[data-test=confirm-dialog-overwrite]').isVisible()) {
    await page.locator('[data-test=confirm-dialog-overwrite]').click()
  }
  await expect(page.locator('id=openc3-tool')).toContainText('MC_CONFIGURATION')
  await expect(page.locator('[data-test=filename] input')).toHaveValue(
    /INST\/tables\/bin\/ConfigTables2\.bin/,
  )
  await expect(
    page.locator('[data-test=definition-filename] input'),
  ).toHaveValue(/INST\/tables\/config\/ConfigTables_def\.txt/)

  // Save As to something that doesn't match the definition file convention
  await page.locator('[data-test=table-manager-file]').click()
  await page.locator('text=Save As').click()
  await expect(page.locator('.v-dialog')).toBeVisible()
  await page
    .locator('[data-test=file-open-save-filename] input')
    .fill('INST/tables/bin/Binary.bin')
  await page.locator('[data-test=file-open-save-submit-btn]').click()
  if (await page.locator('[data-test=confirm-dialog-overwrite]').isVisible()) {
    await page.locator('[data-test=confirm-dialog-overwrite]').click()
  }
  await expect(page.locator('[data-test=filename] input')).toHaveValue(
    /INST\/tables\/bin\/Binary\.bin/,
  )
  await expect(
    page.locator('[data-test=definition-filename] input'),
  ).toHaveValue(/INST\/tables\/config\/ConfigTables_def\.txt/)

  // Now try to open it and be required to select the definition file
  await page.locator('[data-test=table-manager-file]').click()
  await page.locator('text=Open File').click()
  await utils.sleep(500) // Allow background data to fetch
  await expect(page.locator('.v-dialog')).toBeVisible()
  await page.locator('[data-test=file-open-save-search] input').fill('Binary')
  await utils.sleep(100)
  await page.locator('[data-test=file-open-save-search] input').fill('.bin')
  await page.locator('text=Binary.bin').click()
  await page.locator('[data-test=file-open-save-submit-btn]').click()
  if (await page.locator('[data-test=confirm-dialog-overwrite]').isVisible()) {
    await page.locator('[data-test=confirm-dialog-overwrite]').click()
  }
  await page
    .locator('[data-test=file-open-save-search] input')
    .fill('ConfigTables_def')
  await page.locator('text=ConfigTables_def >> nth=0').click()
  await page.locator('[data-test=file-open-save-submit-btn]').click()
  if (await page.locator('[data-test=confirm-dialog-overwrite]').isVisible()) {
    await page.locator('[data-test=confirm-dialog-overwrite]').click()
  }
  await expect(page.locator('id=openc3-tool')).toContainText('MC_CONFIGURATION')
  await expect(page.locator('[data-test=filename] input')).toHaveValue(
    /INST\/tables\/bin\/Binary\.bin/,
  )
  await expect(
    page.locator('[data-test=definition-filename] input'),
  ).toHaveValue(/INST\/tables\/config\/ConfigTables_def\.txt/)

  // Now delete the file
  await page.locator('[data-test=table-manager-file]').click()
  await page.locator('text=Open File').click()
  await utils.sleep(500) // Allow background data to fetch
  await page
    .locator('[data-test=file-open-save-search] input')
    .fill('ConfigTables2')
  await utils.sleep(100)
  await page.locator('[data-test=file-open-save-search] input').fill('.bin')
  await page.getByRole('listbox').getByText('ConfigTables2.bin').click()
  await page.locator('[data-test=file-open-save-submit-btn]').click()
  if (await page.locator('[data-test=confirm-dialog-overwrite]').isVisible()) {
    await page.locator('[data-test=confirm-dialog-overwrite]').click()
  }
  await expect(page.locator('id=openc3-tool')).toContainText('MC_CONFIGURATION')
  await expect(page.locator('[data-test=filename] input')).toHaveValue(
    /INST\/tables\/bin\/ConfigTables2\.bin/,
  )
  await expect(
    page.locator('[data-test=definition-filename] input'),
  ).toHaveValue(/INST\/tables\/config\/ConfigTables_def\.txt/)

  await page.locator('[data-test=table-manager-file]').click()
  await page.locator('text=Delete File').click()
  await expect(page.locator('text=Permanently delete file')).toBeVisible()
  await page.locator('button:has-text("Delete")').click()
})
