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
import { test, expect } from '../fixture'

test.use({
  toolPath: '/tools/scriptrunner',
  toolName: 'Script Runner',
})

test('prompts for hazardous commands', async ({ page, utils }) => {
  await page.locator('textarea').fill('cmd("INST CLEAR")')
  await page.locator('[data-test=start-button]').click()
  await expect(page.locator('.v-dialog')).toContainText('Hazardous Command', {
    timeout: 20000,
  })
  await page.getByRole('button', { name: 'Cancel' }).click()
  await expect(page.locator('[data-test=state] input')).toHaveValue(
    /paused \d+s/,
  )
  await page.locator('[data-test=go-button]').click()
  await expect(page.locator('.v-dialog')).toContainText('Hazardous Command')
  await page.getByRole('dialog').getByRole('button', { name: 'Send' }).click()
  await expect(page.locator('[data-test=state] input')).toHaveValue('completed')
  await expect(page.locator('[data-test=output-messages]')).toContainText(
    'User input: Send',
  )
  await expect(page.locator('[data-test=output-messages]')).toContainText(
    'cmd("INST CLEAR")',
  )
})

test('does not hazardous prompt for cmd_no_hazardous_check, cmd_no_checks', async ({
  page,
  utils,
}) => {
  await page.locator('textarea').fill(`cmd_no_hazardous_check("INST CLEAR")
cmd_no_checks("INST CLEAR")`)
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

test('errors for out of range command parameters', async ({ page, utils }) => {
  await page
    .locator('textarea')
    .fill(`cmd("INST COLLECT with DURATION 11, TYPE 'NORMAL'")`)
  await page.locator('[data-test=start-button]').click()
  await expect(page.locator('[data-test=state] input')).toHaveValue('error', {
    timeout: 20000,
  })
  await page.locator('[data-test=go-button]').click()
  await expect(page.locator('[data-test=state] input')).toHaveValue('completed')
  await expect(page.locator('[data-test=output-messages]')).toContainText(
    '11 not in valid range',
  )
})

test('does not out of range error for cmd_no_range_check, cmd_no_checks', async ({
  page,
  utils,
}) => {
  await page.locator('textarea')
    .fill(`cmd_no_range_check("INST COLLECT with DURATION 11, TYPE 'NORMAL'")
cmd_no_checks("INST COLLECT with DURATION 11, TYPE 'NORMAL'")`)
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

test('ask accepts default, password, and required', async ({ page, utils }) => {
  await page.locator('textarea').fill(`value = ask("Enter password:")
puts value
value = ask("Optionally enter password:", true)
puts "blank:#{value.empty?}"
value = ask("Enter default password:", 67890)
puts value
value = ask("Enter SECRET password:", false, true)
wait
puts value`)
  await page.locator('[data-test=start-button]').click()
  await expect(page.locator('.v-dialog')).toBeVisible({
    timeout: 20000,
  })
  await page.locator('.v-dialog >> button:has-text("Cancel")').click()
  await expect(page.locator('[data-test=output-messages]')).toContainText(
    'User input: COSMOS__CANCEL',
  )
  await expect(page.locator('[data-test=state] input')).toHaveValue(
    /paused \d+s/,
  )

  // Clicking go re-launches the dialog
  await page.locator('[data-test=go-button]').click()
  await expect(
    page.locator('.v-dialog >> button:has-text("Ok")'),
  ).toBeDisabled()
  await page.locator('.v-dialog >> input').fill('12345')
  await page.locator('.v-dialog >> button:has-text("Ok")').click()
  await expect(page.locator('[data-test=output-messages]')).toContainText(
    '12345',
  )
  // Now nothing is required so OK is enabled
  await expect(page.locator('.v-dialog >> button:has-text("Ok")')).toBeEnabled()
  await page.locator('.v-dialog >> button:has-text("Ok")').click()
  await expect(page.locator('[data-test=output-messages]')).toContainText(
    'blank:true',
  )
  // Verify the default value
  expect(await page.inputValue('[data-test=ask-value-input] input')).toMatch(
    '67890',
  )
  await page.locator('.v-dialog >> button:has-text("Ok")').click()
  await expect(page.locator('[data-test=output-messages]')).toContainText(
    '67890',
  )
  // Now type the secret password
  await page.locator('.v-dialog >> input').fill('abc123!')
  await page.locator('.v-dialog >> button:has-text("Ok")').click()

  await expect(page.locator('[data-test=state] input')).toHaveValue(
    /waiting \d+s/,
  )
  // Verify we're not outputting the secret password on input
  await expect(page.locator('[data-test=output-messages]')).not.toContainText(
    'abc123!',
  )
  // Once we restart we should see it since we print it
  await page.locator('[data-test=go-button]').click()
  await expect(page.locator('[data-test=state] input')).toHaveValue('completed')
  await expect(page.locator('[data-test=output-messages]')).toContainText(
    'abc123!',
  )
})

test('converts value for ask but not ask_string', async ({ page, utils }) => {
  await page.locator('textarea').fill(`value = ask("Enter integer:")
puts "int:#{value} #{value.class}"
value = ask("Enter float:")
puts "float:#{value} #{value.class}"
value = ask_string("Enter float:")
puts "string:#{value} #{value.class}"`)
  await page.locator('[data-test=start-button]').click()
  await expect(page.locator('.v-dialog')).toBeVisible({
    timeout: 20000,
  })
  await page.locator('.v-dialog >> input').fill('123')
  await page.locator('.v-dialog >> button:has-text("Ok")').click()
  await expect(page.locator('[data-test=output-messages]')).toContainText(
    'int:123 Integer',
  )
  await page.locator('.v-dialog >> input').fill('5.5')
  await page.locator('.v-dialog >> button:has-text("Ok")').click()
  await expect(page.locator('[data-test=output-messages]')).toContainText(
    'float:5.5 Float',
  )
  await page.locator('.v-dialog >> input').fill('5.5')
  await page.locator('.v-dialog >> button:has-text("Ok")').click()
  await expect(page.locator('[data-test=output-messages]')).toContainText(
    'string:5.5 String',
  )
  await expect(page.locator('[data-test=state] input')).toHaveValue('completed')
})

test('opens a dialog with buttons for message_box, vertical_message_box', async ({
  page,
  utils,
}) => {
  await page.locator('textarea')
    .fill(`value = message_box("Select", "ONE", "TWO", "THREE")
puts value
value = vertical_message_box("Select", "FOUR", "FIVE", "SIX")
puts value`)
  await page.locator('[data-test=start-button]').click()
  await expect(page.locator('.v-dialog')).toBeVisible({
    timeout: 20000,
  })
  await page.locator('.v-dialog >> button:has-text("Cancel")').click()
  await expect(page.locator('[data-test=output-messages]')).toContainText(
    'User input: COSMOS__CANCEL',
  )
  await expect(page.locator('[data-test=state] input')).toHaveValue(
    /paused \d+s/,
  )

  // Clicking Go re-launches the dialog
  await page.locator('[data-test=go-button]').click()
  await page.locator('.v-dialog >> button:has-text("TWO")').click()
  await page.locator('.v-dialog >> button:has-text("FOUR")').click()
  await expect(page.locator('[data-test=state] input')).toHaveValue('completed')
  await expect(page.locator('[data-test=output-messages]')).toContainText('TWO')
  await expect(page.locator('[data-test=output-messages]')).toContainText(
    'FOUR',
  )
})

test('opens a dialog with dropdowns for combo_box', async ({ page, utils }) => {
  await page
    .locator('textarea')
    .fill(
      `value = combo_box("Select value from combo", "abc123", "def456")\nputs value`,
    )
  await page.locator('[data-test=start-button]').click()
  await expect(page.locator('.v-dialog')).toBeVisible({
    timeout: 20000,
  })
  await page.locator('.v-dialog >> button:has-text("Cancel")').click()
  await expect(page.locator('[data-test=output-messages]')).toContainText(
    'User input: COSMOS__CANCEL',
  )
  await expect(page.locator('[data-test=state] input')).toHaveValue(
    /paused \d+s/,
  )

  // Clicking go re-launches the dialog
  await page.locator('[data-test=go-button]').click()
  await page.getByRole('combobox').filter({ hasText: 'Select' }).click()
  await expect(page.locator('[data-test=state] input')).toHaveValue(
    /waiting \d+s/,
  )
  await page.locator('div[role="listbox"] >> text=def456').click()
  await page.locator('.v-dialog >> button:has-text("Ok")').click()
  await expect(page.locator('[data-test=state] input')).toHaveValue('completed')
  await expect(page.locator('[data-test=output-messages]')).toContainText(
    'User input: def456',
  )
})

test('opens a dialog with checkboxes for check_box', async ({
  page,
  utils,
}) => {
  await page
    .locator('textarea')
    .fill(
      `value = check_box("Select values to enable", "abc123", "def456", "ghi789")\nputs value`,
    )
  await page.locator('[data-test=start-button]').click()
  await expect(page.locator('.v-dialog')).toBeVisible({
    timeout: 20000,
  })
  await page.locator('.v-dialog >> button:has-text("Cancel")').click()
  await expect(page.locator('[data-test=output-messages]')).toContainText(
    'Multiple input: COSMOS__CANCEL',
  )
  await expect(page.locator('[data-test=state] input')).toHaveValue(
    /paused \d+s/,
  )

  // Clicking go re-launches the dialog
  await page.locator('[data-test=go-button]').click()
  await expect(page.locator('[data-test=state] input')).toHaveValue(
    /waiting \d+s/,
  )
  await page.getByRole('checkbox', { name: 'abc123' }).check()
  await page.getByRole('checkbox', { name: 'ghi789' }).check()
  await page.locator('[data-test="prompt-ok"]').click()
  await expect(page.locator('[data-test=state] input')).toHaveValue('completed')
  await expect(page.locator('[data-test=output-messages]')).toContainText(
    'Multiple input: ["abc123", "ghi789"]',
  )
})

test('opens a dialog for prompt', async ({ page, utils }) => {
  // Default choices for prompt is Ok and Cancel
  await page.locator('textarea').fill(`value = prompt("Continue?")\nputs value`)
  await page.locator('[data-test=start-button]').click()
  await expect(page.locator('.v-dialog')).toBeVisible({
    timeout: 20000,
  })
  await expect(page.locator('.v-dialog')).toContainText('Continue?')
  await page.locator('.v-dialog >> button:has-text("Cancel")').click()
  await expect(page.locator('[data-test=output-messages]')).toContainText(
    'User input: COSMOS__CANCEL',
  )
  await expect(page.locator('[data-test=state] input')).toHaveValue(
    /paused \d+s/,
  )

  // Clicking Go re-executes the prompt
  await page.locator('[data-test=go-button]').click()
  await expect(page.locator('.v-dialog')).toContainText('Continue?')
  await page.locator('.v-dialog >> button:has-text("Ok")').click()
  await expect(page.locator('[data-test=output-messages]')).toContainText('Ok')
  await expect(page.locator('[data-test=state] input')).toHaveValue('completed')
})

async function openFile(page, utils, filename) {
  await page.locator('[data-test=script-runner-file]').click()
  await page.locator('text=Open File').click()
  await utils.sleep(500) // Allow background data to fetch
  await expect(
    page.locator('.v-dialog').getByText('INST2', { exact: true }),
  ).toBeVisible()
  let parts = filename.split('.')
  await page.locator('[data-test=file-open-save-search] input').fill(parts[0])
  await utils.sleep(100)
  await page
    .locator('[data-test=file-open-save-search] input')
    .fill(`.${parts[1]}`)
  await page.locator(`text=${filename}`).click()
  await page.locator('[data-test=file-open-save-submit-btn]').click()
  await expect(page.locator('.v-dialog')).not.toBeVisible()

  // Check for potential "<User> is editing this script"
  // This can happen if we had to do a retry on this test
  const someone = page.getByText('is editing this script')
  if (await someone.isVisible()) {
    await page.locator('[data-test="unlock-button"]').click()
    await page.locator('[data-test="confirm-dialog-force unlock"]').click()
  }
}

async function runScript(page, utils, filename) {
  await openFile(page, utils, filename)
  await page.locator('[data-test=start-button]').click()
  await expect(page.locator('.v-dialog')).toBeVisible({
    timeout: 20000,
  })
  await expect(page.locator('.v-dialog')).toContainText('Open a single file')
  await expect(page.locator('.v-dialog')).toContainText(
    'Choose something interesting',
  )
  await utils.sleep(500)
  await page.locator('.v-dialog >> button:has-text("Cancel")').click()
  await expect(page.locator('.v-dialog')).not.toBeVisible()
  await expect(page.locator('[data-test=state] input')).toHaveValue(
    /paused \d+s/,
  )
  await utils.sleep(500)
  // Clicking Go re-executes the prompt
  await page.locator('[data-test=go-button]').click()
  await expect(page.locator('.v-dialog')).toBeVisible()

  // Note that Promise.all prevents a race condition
  // between clicking and waiting for the file chooser.
  const [fileChooser] = await Promise.all([
    // It is important to call waitForEvent before click to set up waiting.
    page.waitForEvent('filechooser'),
    // Open the file chooser
    page.getByLabel('Choose File').first().click(),
  ])
  await fileChooser.setFiles('.prettierrc.js')
  await page.locator('.v-dialog >> button:has-text("Ok")').click()
  await utils.sleep(500)

  await expect(page.locator('.v-dialog')).toBeVisible()
  await expect(page.locator('.v-dialog')).toContainText('Open multiple files')
  // Note that Promise.all prevents a race condition
  // between clicking and waiting for the file chooser.
  const [fileChooser2] = await Promise.all([
    // It is important to call waitForEvent before click to set up waiting.
    page.waitForEvent('filechooser'),
    // Open the file chooser
    page.getByLabel('Choose File').first().click(),
  ])
  await fileChooser2.setFiles(['pnpm-workspace.yaml', 'reset_storage_state.sh'])
  await page.locator('.v-dialog >> button:has-text("Ok")').click()
  await utils.sleep(500)

  await expect(page.locator('.v-dialog')).toBeVisible()
  await expect(page.locator('.v-dialog')).toContainText(
    'Open a file from the buckets',
  )
  await page.getByText('config', { exact: true }).click()
  await page
    .locator('[data-test="bucket-item-DEFAULT"]')
    .getByText('DEFAULT')
    .click()
  await page
    .locator('[data-test="bucket-item-targets"]')
    .getByText('targets')
    .click()
  await page
    .locator('[data-test="bucket-item-INST2"]')
    .getByText('INST2')
    .click()
  await page.getByText('target.txt').click()
  await page.locator('[data-test="bucket-ok"]').click()

  await expect(page.locator('[data-test=state] input')).toHaveValue('completed')
  await expect(page.locator('[data-test=output-messages]')).toContainText(
    /File\(s\): \[['"].prettierrc.js['"]\]/,
  )
  // Verify something from .prettierrc.js
  await expect(page.locator('[data-test=output-messages]')).toContainText(
    'bracketSpacing: true',
  )
  await expect(page.locator('[data-test=output-messages]')).toContainText(
    /File\(s\): \[['"]pnpm-workspace.yaml['"], ['"]reset_storage_state.sh['"]\]/,
  )
  // Verify something from pnpm-workspace.yaml
  await expect(page.locator('[data-test=output-messages]')).toContainText(
    'nodeLinker: hoisted',
  )
  // Verify something from reset_storage_state.sh
  await expect(page.locator('[data-test=output-messages]')).toContainText(
    'Initialize an empty storageState',
  )
  await expect(page.locator('[data-test=output-messages]')).toContainText(
    'Reading DEFAULT/targets/INST2/target.txt',
  )
  // Verify something from INST2/target.txt
  await expect(page.locator('[data-test=output-messages]')).toContainText(
    'TELEMETRY inst_tlm_override.txt',
  )
}

test('test ruby prompts', async ({ page, utils }) => {
  await runScript(page, utils, 'file_dialog.rb')
})

test('test python prompts', async ({ page, utils }) => {
  await runScript(page, utils, 'file_dialog.py')
})

test('handles ruby crashes', async ({ page, utils }) => {
  // puts will resolve to Ruby
  await page.locator('textarea').fill(`puts "HI"\ndef def`)
  await page.locator('[data-test=start-button]').click()
  await expect(page.locator('[data-test=output-messages]')).toContainText(
    'SyntaxError',
  )
  await expect(page.locator('[data-test=state] input')).toHaveValue('crashed')
  await expect(page.locator('[data-test=start-button]')).toBeEnabled()
})

test('handles python crashes', async ({ page, utils }) => {
  // print will resolve to Python
  await page.locator('textarea').fill(`print "HI"`)
  await page.locator('[data-test=start-button]').click()
  await expect(page.locator('[data-test=output-messages]')).toContainText(
    'SyntaxError',
  )
  await expect(page.locator('[data-test=state] input')).toHaveValue('crashed')
  await expect(page.locator('[data-test=start-button]')).toBeEnabled()
})
