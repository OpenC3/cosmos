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

import type { Page } from '@playwright/test'
import type { Utilities } from '../../utilities'
import { expect, test } from '../fixture'

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
  // The hazardous prompt displays both the command description and the
  // hazardous description (see issue #3472)
  await expect(page.locator('.v-dialog')).toContainText(
    'Description: Clears counters on the INST instrument',
  )
  await expect(page.locator('.v-dialog')).toContainText(
    'Hazardous: Clearing counters may lose valuable information.',
  )
  await page.getByRole('button', { name: 'Cancel' }).click()
  await expect(page.locator('[data-test=state] input')).toHaveValue(
    /paused \d+s/,
  )
  await page.locator('[data-test=go-button]').click()
  await expect(page.locator('.v-dialog')).toContainText('Hazardous Command')
  await page.getByRole('dialog').getByRole('button', { name: 'Send' }).click()
  await expect(page.locator('[data-test=state] input')).toHaveValue('completed')
  await expectOutput(page, 'User input: Send')
  await expectOutput(page, 'cmd("INST CLEAR")')
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
  await expectOutput(page, '11 not in valid range')
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

// Language specific script snippets and expected output so the same
// interaction tests can run against both Ruby and Python
const languages = [
  {
    name: 'ruby',
    t: 'true',
    f: 'false',
    print: (expr: string) => `puts ${expr}`,
    wait: 'wait',
    blank: (v: string) => `puts "blank:#{${v}.empty?}"`,
    blankOut: 'blank:true',
    typed: (label: string, v: string) =>
      `puts "${label}:#{${v}} #{${v}.class}"`,
    types: { int: 'Integer', float: 'Float', string: 'String' },
    multiOut: 'Multiple input: ["abc123", "ghi789"]',
  },
  {
    name: 'python',
    t: 'True',
    f: 'False',
    print: (expr: string) => `print(${expr})`,
    wait: 'wait()',
    blank: (v: string) => `print(f"blank:{${v} == ''}")`,
    blankOut: 'blank:True',
    typed: (label: string, v: string) =>
      `print(f"${label}:{${v}} {type(${v}).__name__}")`,
    types: { int: 'int', float: 'float', string: 'str' },
    multiOut: "Multiple input: ['abc123', 'ghi789']",
  },
]
const cancelCases = [
  {
    method: 'ask',
    title: 'Enter value:',
    script: `value = ask("Enter value:")`,
    output: 'User input: COSMOS__CANCEL',
  },
  {
    method: 'ask_string',
    title: 'Enter string:',
    script: `value = ask_string("Enter string:")`,
    output: 'User input: COSMOS__CANCEL',
  },
  {
    method: 'message_box',
    title: 'Message select',
    script: `value = message_box("Message select", "ONE", "TWO")`,
    output: 'User input: COSMOS__CANCEL',
  },
  {
    method: 'vertical_message_box',
    title: 'Vertical select',
    script: `value = vertical_message_box("Vertical select", "FOUR", "FIVE")`,
    output: 'User input: COSMOS__CANCEL',
  },
  {
    method: 'combo_box',
    title: 'Combo select',
    script: `value = combo_box("Combo select", "abc123", "def456")`,
    output: 'User input: COSMOS__CANCEL',
  },
  {
    method: 'check_box',
    title: 'Check select',
    script: `value = check_box("Check select", "abc123", "def456")`,
    output: 'Multiple input: COSMOS__CANCEL',
  },
  {
    method: 'prompt',
    title: 'Continue?',
    script: `value = prompt("Continue?")`,
    output: 'User input: COSMOS__CANCEL',
  },
  {
    method: 'open_file_dialog',
    title: 'Open single file',
    script: `value = open_file_dialog("Open single file", "Choose file")`,
    output: 'File(s): COSMOS__CANCEL',
  },
  {
    method: 'open_files_dialog',
    title: 'Open multiple files',
    script: `value = open_files_dialog("Open multiple files", "Choose files")`,
    output: 'File(s): COSMOS__CANCEL',
  },
  {
    method: 'open_bucket_dialog',
    title: 'Open bucket file',
    script: `value = open_bucket_dialog("Open bucket file", "Choose file")`,
    output: 'Bucket file: COSMOS__CANCEL',
  },
]

async function expectOutput(page: Page, expectedOutput: string | RegExp) {
  await expect(page.locator('[data-test=output-messages]')).toContainText(expectedOutput)
}

async function scriptWithDialogCompletes(page: Page, scriptText: string, actions: () => Promise<void>, expectedOutput: string) {
  await page.locator('textarea').fill(scriptText)
  await page.locator('[data-test=start-button]').click()
  await expect(page.locator('.v-dialog')).toBeVisible({ timeout: 20000 })
  await actions()
  await expect(page.locator('[data-test=state] input')).toHaveValue('completed')
  await expectOutput(page, expectedOutput)
}

for (const L of languages) {
  test.describe(`${L.name} user input`, () => {
    test.describe('happy path', () => {
      test('ask accepts default, password, and required', async ({
        page,
        utils,
      }) => {
        await scriptWithDialogCompletes(page,
          `value = ask("Enter password:")
${L.print('value')}
value = ask("Optionally enter password:", ${L.t})
${L.blank('value')}
value = ask("Enter default password:", 67890)
${L.print('value')}
value = ask("Enter SECRET password:", ${L.f}, ${L.t})
${L.wait}
${L.print('value')}`,
          async () => {
            // Required so Ok is disabled until something is entered
            const okButton = page.locator('.v-dialog >> button:has-text("Ok")')
            await expect(okButton).toBeDisabled()
            await page.locator('.v-dialog >> input').fill('12345')
            await okButton.click()
            await expectOutput(page, '12345')
            // Now nothing is required so OK is enabled
            await expect(okButton).toBeEnabled()
            await okButton.click()
            await expectOutput(page, L.blankOut)
            // Verify the default value
            expect(
              await page.inputValue('[data-test=ask-value-input] input'),
            ).toMatch('67890')
            await okButton.click()
            await expectOutput(page, '67890')
            // Now type the secret password
            await page.locator('.v-dialog >> input').fill('abc123!')
            await okButton.click()

            await expect(page.locator('[data-test=state] input')).toHaveValue(/waiting \d+s/)
            // Verify we're not outputting the secret password on input
            await expect(
              page.locator('[data-test=output-messages]'),
            ).not.toContainText('abc123!')
            // Once we continue we should see it since we print it
            await page.locator('[data-test=go-button]').click()
          },
          'abc123!'
        )
      })

      test('converts value for ask but not ask_string', async ({
        page,
        utils,
      }) => {
        await scriptWithDialogCompletes(page,
          `value = ask("Enter integer:")
${L.typed('int', 'value')}
value = ask("Enter float:")
${L.typed('float', 'value')}
value = ask_string("Enter float:")
${L.typed('string', 'value')}`,
          async () => {
            await page.locator('.v-dialog >> input').fill('123')
            await page.locator('.v-dialog >> button:has-text("Ok")').click()
            await expectOutput(page, `int:123 ${L.types.int}`)
            await page.locator('.v-dialog >> input').fill('5.5')
            await page.locator('.v-dialog >> button:has-text("Ok")').click()
            await expectOutput(page, `float:5.5 ${L.types.float}`)
            await page.locator('.v-dialog >> input').fill('5.5')
            await page.locator('.v-dialog >> button:has-text("Ok")').click()
          },
          `string:5.5 ${L.types.string}`
        )
      })

      test('message_box returns the clicked button', async ({ page, utils }) => {
        await scriptWithDialogCompletes(
          page,
          `value = message_box("Select", "ONE", "TWO", "THREE")\n${L.print('value')}`,
          () => page.locator('.v-dialog >> button:has-text("TWO")').click(),
          'User input: TWO',
        )
      })

      test('vertical_message_box returns the clicked button', async ({
        page,
        utils,
      }) => {
        await scriptWithDialogCompletes(
          page,
          `value = vertical_message_box("Select", "FOUR", "FIVE", "SIX")\n${L.print('value')}`,
          () => page.locator('.v-dialog >> button:has-text("FIVE")').click(),
          'User input: FIVE',
        )
      })

      test('combo_box returns the selected value', async ({ page, utils }) => {
        await scriptWithDialogCompletes(
          page,
          `value = combo_box("Select value from combo", "abc123", "def456")\n${L.print('value')}`,
          async () => {
            await page.getByRole('combobox').filter({ hasText: 'Select' }).click()
            await page.locator('div[role="listbox"] >> text=def456').click()
            await page.locator('.v-dialog >> button:has-text("Ok")').click()
          },
          'User input: def456',
        )
      })

      test('check_box returns the checked values', async ({ page, utils }) => {
        await scriptWithDialogCompletes(
          page,
          `value = check_box("Select values to enable", "abc123", "def456", "ghi789")\n${L.print('value')}`,
          async () => {
            await page.getByRole('checkbox', { name: 'abc123' }).check()
            await page.getByRole('checkbox', { name: 'ghi789' }).check()
            await page.locator('[data-test="prompt-ok"]').click()
          },
          L.multiOut,
        )
      })

      test('prompt returns the clicked button', async ({ page, utils }) => {
        // Default choices for prompt is Ok and Cancel
        await scriptWithDialogCompletes(
          page,
          `value = prompt("Continue?")\n${L.print('value')}`,
          async () => {
            await expect(page.locator('.v-dialog')).toContainText('Continue?', {
              timeout: 20000,
            })
            await page.locator('.v-dialog >> button:has-text("Ok")').click()
          },
          'Ok',
        )
      })
    })

    test.describe('canceling prompts', () => {
      // Each method is cancelled in its own test: Cancel closes the dialog,
      // pauses the script at the prompt and Go re-displays the same dialog
      for (const c of cancelCases) {
        test(`${c.method}`, async ({ page, utils }) => {
          await page.locator('textarea').fill(`${c.script}
${L.print('value')}`)
          await page.locator('[data-test=start-button]').click()
          await expect(page.locator('.v-dialog')).toContainText(c.title, {
            timeout: 20000,
          })
          await utils.sleep(500)
          await page.locator('.v-dialog >> button:has-text("Cancel")').click()
          await expect(page.locator('.v-dialog')).not.toBeVisible()
          await expectOutput(page, c.output)
          await expect(page.locator('[data-test=state] input')).toHaveValue(
            /paused \d+s/,
          )

          // Clicking Go re-launches the dialog
          await page.locator('[data-test=go-button]').click()
          await expect(page.locator('.v-dialog')).toContainText(c.title)

          // Dismiss the dialog and stop the script
          await page.locator('.v-dialog >> button:has-text("Cancel")').click()
          await expect(page.locator('.v-dialog')).not.toBeVisible()
          await page.locator('[data-test=stop-button]').click()
          await expect(page.locator('[data-test=state] input')).toHaveValue(
            'stopped',
          )
        })
      }
    })
  })
}

async function openFile(page: Page, utils: Utilities, filename: string) {
  await page.locator('[data-test=script-runner-file]').click()
  await page.locator('text=Open File').click()
  await utils.sleep(500) // Allow background data to fetch
  await expect(
    page.locator('.v-dialog').getByText('INST2', { exact: true }),
  ).toBeVisible()
  await page.locator('[data-test=file-open-save-search] input').fill(filename)
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

// Open the file chooser, select files and click Ok.
// Note that Promise.all prevents a race condition
// between clicking and waiting for the file chooser.
async function chooseFiles(page: Page, utils: Utilities, files: string | string[]) {
  const [fileChooser] = await Promise.all([
    // It is important to call waitForEvent before click to set up waiting.
    page.waitForEvent('filechooser'),
    // Open the file chooser
    page.getByLabel('Choose File').first().click(),
  ])
  await fileChooser.setFiles(files)
  await page.locator('.v-dialog >> button:has-text("Ok")').click()
  await utils.sleep(500)
}

async function runScript(page: Page, utils: Utilities, filename: string) {
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

  await chooseFiles(page, utils, '.prettierrc.js')

  await expect(page.locator('.v-dialog')).toBeVisible()
  await expect(page.locator('.v-dialog')).toContainText('Open multiple files')
  await chooseFiles(page, utils, [
    'pnpm-workspace.yaml',
    'reset_storage_state.sh',
  ])

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

  await expect(page.locator('.v-dialog')).toBeVisible()
  await expect(page.locator('.v-dialog')).toContainText('Pick a procedure')
  if (filename.endsWith('.rb')) {
    await page.getByText('checks.rb').click()
  } else {
    await page.getByText('checks.py').click()
  }
  await page.locator('[data-test="bucket-ok"]').click()

  await expect(page.locator('[data-test=state] input')).toHaveValue('completed')
  await expectOutput(page, /File\(s\): \[['"].prettierrc.js['"]\]/,)
  // Verify something from .prettierrc.js
  await expectOutput(page, 'bracketSpacing: true')
  await expectOutput(page, /File\(s\): \[['"]pnpm-workspace.yaml['"], ['"]reset_storage_state.sh['"]\]/)
  // Verify something from reset_storage_state.sh
  await expectOutput(page, 'Initialize an empty storageState')
  await expectOutput(page, 'Reading DEFAULT/targets/INST2/target.txt')
  // Verify something from INST2/target.txt
  await expectOutput(page, 'TELEMETRY inst_tlm_override.txt')
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
  await expectOutput(page, 'SyntaxError')
  await expect(page.locator('[data-test=state] input')).toHaveValue('crashed')
  await expect(page.locator('[data-test=start-button]')).toBeEnabled()
})

test('handles python crashes', async ({ page, utils }) => {
  // print will resolve to Python
  await page.locator('textarea').fill(`print "HI"`)
  await page.locator('[data-test=start-button]').click()
  await expectOutput(page, 'SyntaxError')
  await expect(page.locator('[data-test=state] input')).toHaveValue('crashed')
  await expect(page.locator('[data-test=start-button]')).toBeEnabled()
})
