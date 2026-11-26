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

import { test, expect } from './fixture'

test.use({
  toolPath: '/tools/cmdsender',
  toolName: 'Command Sender',
})

// Helper function to select a parameter dropdown
async function selectValue(page, param, value) {
  // Use exact text match with colon suffix to avoid partial matches (e.g., ARRAY1 vs ARRAY1_LENGTH)
  let row = page.locator(`tr:has(td:text-is("${param}"))`)
  await row.locator('[data-test=cmd-param-select]').click({ force: true })
  await page.getByRole('option', { name: value }).click()
}

// Helper function to set parameter value
async function setValue(page, param, value) {
  // Use exact text match with colon suffix to avoid partial matches (e.g., ARRAY1 vs ARRAY1_LENGTH)
  await page
    .locator(`tr:has(td:text-is("${param}")) [data-test=cmd-param-value] input`)
    .first()
    .fill(value)
  // Trigger the update handler that sets the drop down by pressing Enter
  await page
    .locator(`tr:has(td:text-is("${param}")) [data-test=cmd-param-value] input`)
    .first()
    .press('Enter')
  await checkValue(page, param, value)
}

// Helper function to check parameter value
async function checkValue(page, param, value) {
  // Use exact text match with colon suffix to avoid partial matches (e.g., ARRAY1 vs ARRAY1_LENGTH)
  await expect(
    page.locator(
      `tr:has(td:text-is("${param}")) [data-test=cmd-param-value] input`,
    ),
  ).toHaveValue(value)
}

// Helper function to toggle a Command Sender mode menu option
async function toggleMode(page, mode) {
  await page.locator('[data-test=command-sender-mode]').click()
  await page.getByText(mode).click()
  await page.locator('[data-test=command-sender-mode]').click()
}

// Helper function to send the command and confirm the hazardous dialog,
// optionally checking the dialog's warning message first
async function sendHazardousCmd(page, warning?: string) {
  await page.locator('[data-test="select-send"]').click()
  if (warning) {
    await expect(page.getByRole('dialog')).toContainText(warning)
  }
  await page.getByRole('dialog').getByRole('button', { name: 'Send' }).click()
}

// Helper function to check the command was sent and added to the history
async function checkSent(page, cmd) {
  await expect(page.locator('main')).toContainText(`${cmd} sent`)
  await checkHistory(page, cmd)
}

// Helper function to check command history
async function checkHistory(page, value) {
  await expect(page.locator('[data-test=sender-history]')).toContainText(value)
}

// The history entries, newest first
function historyEntries(page) {
  return page.locator('[data-test=history-entry]')
}

// Helper function to load a history entry into the form (it never sends)
async function loadFromHistory(page, cmd, name) {
  await historyEntries(page).filter({ hasText: cmd }).first().click()
  await expect(page.locator('[data-test=sender-status]')).toContainText(
    `Loaded ${name}, press Send to send it`,
  )
}

// The Script line: the form's command as scripted
function commandLine(page) {
  return page.locator('[data-test=command-line] textarea').first()
}

// The Script line and its hint or error
function commandLinePanel(page) {
  return page.locator('[data-test=command-line-panel]')
}

// Helper function to type a command in the Script line and press Enter to
// load it into the form (it never sends)
async function pasteCommand(page, cmd) {
  await commandLine(page).fill(cmd)
  await commandLine(page).press('Enter')
}

// Paste text the way the browser does for Mod+V, on the focused element
async function pasteOnPage(page, text) {
  await page.evaluate((pasted) => {
    const data = new DataTransfer()
    data.setData('text/plain', pasted)
    const target = document.activeElement || document.body
    target.dispatchEvent(
      new ClipboardEvent('paste', { clipboardData: data, bubbles: true }),
    )
  }, text)
}

// Helper function to paste a command over the whole Script line, which loads
// it into the form (it never sends)
async function pasteLine(page, cmd) {
  await commandLine(page).focus()
  await commandLine(page).selectText()
  await pasteOnPage(page, cmd)
}

//
// Test the basic functionality of the application
//
test('selects a target and packet', async ({ page, utils }) => {
  await utils.selectTargetPacketItem('INST', 'ABORT')
  await expect(page.locator('main')).toContainText(
    'Aborts a collect on the INST instrument',
  )
  await page.locator('[data-test="select-send"]').click()
  await expect(page.locator('main')).toContainText('cmd("INST ABORT") sent')
  // Sending it again counts the sends
  await page.locator('[data-test="select-send"]').click()
  await expect(page.locator('main')).toContainText(
    'cmd("INST ABORT") sent. (2)',
  )
  await page.locator('[data-test="select-send"]').click()
  await expect(page.locator('main')).toContainText(
    'cmd("INST ABORT") sent. (3)',
  )
  // Test the autocomplete by typing in a command
  await page.locator('[data-test=select-packet]').click()
  await page.locator('[data-test=select-packet] input[type="text"]').fill('COL')
  await page.locator('span:has-text("COL")').click()
  await expect(page.locator('main')).toContainText('Starts a collect')
  // The status described the previous command, so it's cleared
  await expect(page.locator('[data-test=sender-status]')).toHaveText('')
})

test('displays INST COLLECT using the route', async ({ page, utils }) => {
  await page.goto('/tools/cmdsender/INST/COLLECT/')
  await expect(page.locator('.v-app-bar')).toContainText('Command Sender')
  await utils.dropdownSelectedValue(page, '[data-test="select-target"]', 'INST')
  await utils.dropdownSelectedValue(
    page,
    '[data-test="select-packet"]',
    'COLLECT',
  )
  await expect(page.locator('main')).toContainText('Starts a collect')
  await expect(page.locator('main')).toContainText('Parameters')
  await expect(page.locator('main')).toContainText('DURATION')
})

test('displays state parameters with drop downs', async ({ page, utils }) => {
  await utils.selectTargetPacketItem('INST', 'COLLECT')
  await selectValue(page, 'TYPE', 'SPECIAL')
  await checkValue(page, 'TYPE', '1')
  await selectValue(page, 'TYPE', 'NORMAL')
  await checkValue(page, 'TYPE', '0')
})

test('displays unset required states in hex', async ({ page, utils }) => {
  await utils.selectTargetPacketItem('INST', 'COLLECT')
  // TYPE is required so it starts unset, which used to break its editor in
  // hex mode and leave the cell empty
  await toggleMode(page, 'Display State Values in Hex')
  await expect(
    page.locator('tr:has(td:text-is("TYPE")) [data-test=cmd-param-select]'),
  ).toBeVisible()
  await checkValue(page, 'TYPE', '')
  await selectValue(page, 'TYPE', 'SPECIAL')
  await checkValue(page, 'TYPE', '0x1')
  await selectValue(page, 'TYPE', 'NORMAL')
  await checkValue(page, 'TYPE', '0x0')
})

test('shows ignored parameters', async ({ page, utils }) => {
  await utils.selectTargetPacketItem('INST', 'ABORT')
  await expect(page.locator('main')).toContainText(
    'Aborts a collect on the INST instrument',
  )
  // All the ABORT parameters are ignored so the table shouldn't appear
  await expect(page.locator('main')).not.toContainText('Parameters')
  await toggleMode(page, 'Show Ignored')
  await expect(page.locator('main')).toContainText('Parameters')
  await expect(page.locator('main')).toContainText('CCSDSVER')
})

test('disables command validation', async ({ page, utils }) => {
  await page.locator('[data-test="clear-history"]').click()
  await utils.selectTargetPacketItem('INST', 'TIME_OFFSET')
  await toggleMode(page, 'Disable Command Validation')
  await page.locator('[data-test="select-send"]').click()
  await expect(page.locator('main')).toContainText(
    'cmd("INST TIME_OFFSET with SECONDS 0, IP_ADDRESS \'127.0.0.1\'", validate=False) sent',
  )
})

test('searches state parameter drop downs', async ({ page, utils }) => {
  await utils.selectTargetPacketItem('INST', 'COLLECT')
  const row = page.locator('tr:has(td:text-is("TYPE"))')
  const input = row.locator('[data-test=cmd-param-select] input')
  // Typing filters the states and Enter picks the first match
  await input.click()
  await input.fill('spec')
  await expect(page.getByRole('option', { name: 'SPECIAL' })).toBeVisible()
  await expect(page.getByRole('option', { name: 'NORMAL' })).not.toBeVisible()
  await input.press('Enter')
  await checkValue(page, 'TYPE', '1')
  // Clearing the text keeps the selected state
  await input.click()
  await input.fill('')
  await input.press('Tab')
  await checkValue(page, 'TYPE', '1')
  await expect(row.locator('.v-autocomplete__selection-text')).toHaveText(
    'SPECIAL',
  )
})

test('displays parameter units, ranges and description', async ({
  page,
  utils,
}) => {
  await utils.selectTargetPacketItem('INST', 'COLLECT')
  let row = page.locator('tr:has-text("TEMP")')
  await expect(row.locator('td >> nth=2')).toContainText('C')
  await expect(row.locator('td >> nth=3')).toContainText('0..25')
  await expect(row.locator('td >> nth=4')).toContainText('Collect temperature')
})

test('warns for hazardous commands', async ({ page, utils }) => {
  await page.locator('[data-test="clear-history"]').click()
  await utils.selectTargetPacketItem('INST', 'CLEAR')
  await expect(page.locator('main')).toContainText(
    'Clears counters on the INST instrument',
  )
  // The hazardous description is shown by the Send button (see issue 3472)
  await expect(page.locator('[data-test="command-hazardous"]')).toContainText(
    'Hazardous: Clearing counters may lose valuable information.',
  )
  await page.locator('[data-test="select-send"]').click()
  await expect(page.getByRole('dialog')).toContainText(
    'Warning: Command INST CLEAR is Hazardous. Send?',
  )
  // The hazardous confirmation dialog shows both the command description and
  // the hazardous description (see issue 3472)
  await expect(page.getByRole('dialog')).toContainText(
    'Description: Clears counters on the INST instrument',
  )
  await expect(page.getByRole('dialog')).toContainText(
    'Hazardous: Clearing counters may lose valuable information.',
  )
  await page.getByRole('button', { name: 'Cancel' }).click()
  await expect(page.locator('main')).toContainText('Hazardous command not sent')
  await sendHazardousCmd(page)
  await checkSent(page, 'cmd("INST CLEAR")')

  // Disable range checks to confirm history output
  await toggleMode(page, 'Ignore Range Checks')

  // A hazardous command notes that range checks are also ignored
  await sendHazardousCmd(
    page,
    'Warning: Command INST CLEAR is Hazardous and range checks are ignored. Send?',
  )
  await checkSent(page, 'cmd_no_range_check("INST CLEAR")')

  // Disable parameter conversions to confirm history output
  await toggleMode(page, 'Disable Parameter')

  await sendHazardousCmd(
    page,
    'Warning: Command INST CLEAR is Hazardous and range checks are ignored and parameter conversions are disabled. Send?',
  )
  await checkSent(page, 'cmd_raw_no_range_check("INST CLEAR")')

  // Enable range checks to confirm history output
  await toggleMode(page, 'Ignore Range Checks')

  await sendHazardousCmd(
    page,
    'Warning: Command INST CLEAR is Hazardous and parameter conversions are disabled. Send?',
  )
  await checkSent(page, 'cmd_raw("INST CLEAR")')
})

test('warns for required parameters', async ({ page, utils }) => {
  await utils.selectTargetPacketItem('INST', 'COLLECT')
  await expect(page.locator('main')).toContainText(
    'Starts a collect on the INST target',
  )
  await page.locator('[data-test="select-send"]').click()
  // Break apart the checks so we have output flexibility in the future
  await expect(page.locator('.v-dialog')).toContainText('Error sending')
  await expect(page.locator('.v-dialog')).toContainText('INST COLLECT TYPE')
  await expect(page.locator('.v-dialog')).toContainText('not given')
  await page.locator('button:has-text("Ok")').click()
})

// INST SET_PASSWORD USERNAME is a REQUIRED STRING with a nil default,
// see https://github.com/OpenC3/cosmos/issues/4210
test('reports required string parameters as not given', async ({
  page,
  utils,
}) => {
  await utils.selectTargetPacketItem('INST', 'SET_PASSWORD')
  await expect(page.locator('main')).toContainText('Set Password Command')
  // Required parameters start empty rather than showing null
  const username = page.locator(
    'tr:has(td:text-is("USERNAME")) [data-test=cmd-param-value] input',
  )
  await expect(username).toHaveValue('')
  await expect(username).toHaveAttribute('placeholder', 'Required')

  await page.locator('[data-test="select-send"]').click()
  await expect(page.locator('.v-dialog')).toContainText(
    "Required command parameter 'INST SET_PASSWORD USERNAME' not given",
  )
  await expect(page.locator('.v-dialog')).not.toContainText('does not fit')
  await page.locator('button:has-text("Ok")').click()

  await setValue(page, 'USERNAME', 'operator')
  await page.locator('[data-test="select-send"]').click()
  await checkHistory(
    page,
    `cmd("INST SET_PASSWORD with USERNAME 'operator', PASSWORD_STR '*****'`,
  )
})

test('warns for hazardous parameters', async ({ page, utils }) => {
  await page.locator('[data-test="clear-history"]').click()
  await utils.selectTargetPacketItem('INST', 'COLLECT')
  await expect(page.locator('main')).toContainText(
    'Starts a collect on the INST target',
  )
  await selectValue(page, 'TYPE', 'SPECIAL')
  // Hazardous states are highlighted in yellow
  await expect(
    page
      .locator('tr:has(td:text-is("TYPE"))')
      .locator('.v-autocomplete__selection-text'),
  ).toHaveCSS('color', 'rgb(255, 220, 0)')
  // The hazardous indicator is shown even without a hazardous description,
  // and the command panel is outlined without moving the table
  await expect(page.locator('[data-test="command-hazardous"]')).toHaveText(
    'Hazardous',
  )
  await expect(page.locator('.cs-command')).toHaveClass(/ring-caution/)
  await selectValue(page, 'TYPE', 'NORMAL')
  await expect(page.locator('[data-test="command-hazardous"]')).toHaveCount(0)
  await expect(page.locator('.cs-command')).not.toHaveClass(/ring-caution/)
  await selectValue(page, 'TYPE', 'SPECIAL')
  await page.locator('[data-test="select-send"]').click()
  await page.getByRole('button', { name: 'Cancel' }).click()
  await expect(page.locator('main')).toContainText('Hazardous command not sent')
  await sendHazardousCmd(page)
  // Ensure the state is used, e.g. 'SPECIAL' and not the value
  await checkSent(
    page,
    'cmd("INST COLLECT with TYPE \'SPECIAL\', DURATION 1, OPCODE 171, TEMP 0")',
  )
})

test('handles float values and scientific notation', async ({
  page,
  utils,
}) => {
  await page.locator('[data-test="clear-history"]').click()
  await utils.selectTargetPacketItem('INST', 'FLTCMD')
  await expect(page.locator('main')).toContainText(
    'Command with float parameters',
  )
  await setValue(page, 'FLOAT32', '123.456')
  await setValue(page, 'FLOAT64', '12e3')
  await page.locator('[data-test="select-send"]').click()
  await checkSent(
    page,
    'cmd("INST FLTCMD with FLOAT32 123.456, FLOAT64 12000")',
  )
})

test('handles NaN and Infinite values', async ({ page, utils }) => {
  await page.locator('[data-test="clear-history"]').click()
  await utils.selectTargetPacketItem('INST', 'FLTCMD')
  await expect(page.locator('main')).toContainText(
    'Command with float parameters',
  )
  await setValue(page, 'FLOAT32', 'NAN')
  await setValue(page, 'FLOAT64', 'nan')
  await page.locator('[data-test="select-send"]').click()
  // Dialog should pop up with error
  await expect(page.locator('.v-dialog')).toContainText('not in valid range')
  await page.locator('button:has-text("Ok")').click()
  // Disable range checks
  await toggleMode(page, 'Ignore Range Checks')
  await sendHazardousCmd(page)

  await checkSent(
    page,
    'cmd_no_range_check("INST FLTCMD with FLOAT32 NaN, FLOAT64 NaN")',
  )

  await setValue(page, 'FLOAT32', 'INFINITY')
  await setValue(page, 'FLOAT64', '-infinity')
  await sendHazardousCmd(page)
  await checkSent(
    page,
    'cmd_no_range_check("INST FLTCMD with FLOAT32 Infinity, FLOAT64 -Infinity")',
  )
})

test('handles big integers', async ({ page, utils }) => {
  await page.locator('[data-test="clear-history"]').click()
  // Send a different command: INST SETPARAMS
  await utils.selectTargetPacketItem('INST', 'SETPARAMS')
  await expect(page.locator('main')).toContainText('Sets numbered parameters')
  // Set the BIGINT value to the maximum value
  let value = '18446744073709551615'
  await setValue(page, 'BIGINT', value)
  await page.locator('[data-test="select-send"]').click()
  await checkSent(
    page,
    `cmd("INST SETPARAMS with VALUE1 1, VALUE2 1, VALUE3 1, VALUE4 1, VALUE5 1, BIGINT ${value}")`,
  )
  // Check the screen
  await expect(
    page
      .getByText('P4!@#$%^&*?:')
      .locator('xpath=..') // parent row
      .locator('[data-test="value"] input'),
  ).toHaveValue(value)

  // Set the BIGINT value to value from https://github.com/OpenC3/cosmos/issues/1928
  value = '1740684371613049856'
  await setValue(page, 'BIGINT', value)
  await page.locator('[data-test="select-send"]').click()
  await checkSent(
    page,
    `cmd("INST SETPARAMS with VALUE1 1, VALUE2 1, VALUE3 1, VALUE4 1, VALUE5 1, BIGINT ${value}")`,
  )
  // Check the screen
  await expect(
    page
      .getByText('P4!@#$%^&*?:')
      .locator('xpath=..') // parent row
      .locator('[data-test="value"] input'),
  ).toHaveValue(value)

  value = '0' // Set the BIGINT value to 0 for later tests
  await setValue(page, 'BIGINT', value)
  await page.locator('[data-test="select-send"]').click()
  await checkSent(
    page,
    `cmd("INST SETPARAMS with VALUE1 1, VALUE2 1, VALUE3 1, VALUE4 1, VALUE5 1, BIGINT ${value}")`,
  )
  // Check the screen
  await expect(
    page
      .getByText('P4!@#$%^&*?:')
      .locator('xpath=..') // parent row
      .locator('[data-test="value"] input'),
  ).toHaveValue(value)
})

test('handles array values', async ({ page, utils }) => {
  await page.locator('[data-test="clear-history"]').click()
  await utils.selectTargetPacketItem('INST', 'ARYCMD')
  await expect(page.locator('main')).toContainText(
    'Command with array parameter',
  )
  await setValue(page, 'ARRAY', '10')
  await page.locator('[data-test="select-send"]').click()
  await expect(page.locator('.v-dialog')).toContainText('must be an Array')
  await page.locator('button:has-text("Ok")').click()
  await setValue(page, 'ARRAY', '[1,2,3,4]')
  await page.locator('[data-test="select-send"]').click()
  await checkSent(page, 'cmd("INST ARYCMD with ARRAY [ 1, 2, 3, 4 ], CRC 0")')
})

test('handles string values', async ({ page, utils }) => {
  await utils.selectTargetPacketItem('INST', 'ASCIICMD')
  await expect(page.locator('main')).toContainText('Enumerated ASCII command')
  await checkValue(page, 'STRING', 'NOOP')
  await page.locator('[data-test="select-send"]').click()
  await expect(page.locator('main')).toContainText(
    "cmd(\"INST ASCIICMD with STRING 'NOOP', BINARY 0xDEADBEEF, ASCII '0xDEADBEEF'\")",
  )
  await selectValue(page, 'STRING', 'ARM LASER')
  await checkValue(page, 'STRING', 'ARM LASER')
  await page.locator('[data-test="select-send"]').click()
  // ARM LASER is hazardous so ack
  await page.getByRole('dialog').getByRole('button', { name: 'Send' }).click()
  await expect(page.locator('main')).toContainText(
    "cmd(\"INST ASCIICMD with STRING 'ARM LASER', BINARY 0xDEADBEEF, ASCII '0xDEADBEEF'\")",
  )
  // Enter a custom binary value
  await selectValue(page, 'STRING', 'NOOP')
  await setValue(page, 'BINARY', '0xBA5EBA11')
  await page.locator('[data-test="select-send"]').click()
  await expect(page.locator('main')).toContainText(
    "cmd(\"INST ASCIICMD with STRING 'NOOP', BINARY 0xBA5EBA11, ASCII '0xDEADBEEF'\")",
  )
})

test('gets details with right click', async ({ page, utils }) => {
  await utils.selectTargetPacketItem('INST', 'COLLECT')
  await expect(page.locator('main')).toContainText(
    'Starts a collect on the INST target',
  )
  await page.locator('text=Collect type').click({ button: 'right' })
  await page.locator('text=Details').click()
  await expect(page.locator('.v-dialog')).toContainText('INST COLLECT TYPE')
  await utils.sleep(500) // Or we might miss the escape press
  await page.locator('.v-dialog').press('Escape')
  await expect(page.locator('.v-dialog')).not.toBeVisible()
})

test('loads commands from history without sending', async ({ page, utils }) => {
  await page.locator('[data-test="clear-history"]').click()
  await utils.selectTargetPacketItem('INST', 'CLEAR')
  await expect(page.locator('main')).toContainText(
    'Clears counters on the INST instrument',
  )
  await sendHazardousCmd(page)
  await checkSent(page, 'cmd("INST CLEAR")')
  await expect(historyEntries(page)).toHaveCount(1)

  // Send a different command: INST SETPARAMS
  await utils.selectTargetPacketItem('INST', 'SETPARAMS')
  await expect(page.locator('main')).toContainText('Sets numbered parameters')
  await expect(page.locator('main')).toContainText('Value 1 setting') // Ensures the params are rendered
  await page.locator('[data-test="select-send"]').click()
  await checkSent(
    page,
    'cmd("INST SETPARAMS with VALUE1 1, VALUE2 1, VALUE3 1, VALUE4 1, VALUE5 1, BIGINT 0")',
  )

  // Clicking a history entry loads it into the form but doesn't send it
  await loadFromHistory(page, 'cmd("INST CLEAR")', 'INST CLEAR')
  await utils.dropdownSelectedValue(
    page,
    '[data-test="select-packet"]',
    'CLEAR',
  )
  await expect(page).toHaveURL(/\/tools\/cmdsender\/INST\/CLEAR/)
  await expect(historyEntries(page)).toHaveCount(2)
  // Sending it adds a new entry on top: the history is a log of every send
  await sendHazardousCmd(page)
  await expect(page.locator('main')).toContainText('cmd("INST CLEAR") sent')
  await expect(historyEntries(page)).toHaveCount(3)
  await expect(historyEntries(page).first()).toHaveText('cmd("INST CLEAR")')

  // Load SETPARAMS, edit a value in the form and send it
  await loadFromHistory(page, 'cmd("INST SETPARAMS', 'INST SETPARAMS')
  await checkValue(page, 'VALUE1', '1')
  await setValue(page, 'BIGINT', '5')
  await page.locator('[data-test="select-send"]').click()
  await expect(page.locator('main')).toContainText(
    'cmd("INST SETPARAMS with VALUE1 1, VALUE2 1, VALUE3 1, VALUE4 1, VALUE5 1, BIGINT 5") sent.',
  )
  await expect(historyEntries(page)).toHaveText([
    'cmd("INST SETPARAMS with VALUE1 1, VALUE2 1, VALUE3 1, VALUE4 1, VALUE5 1, BIGINT 5")',
    'cmd("INST CLEAR")',
    'cmd("INST SETPARAMS with VALUE1 1, VALUE2 1, VALUE3 1, VALUE4 1, VALUE5 1, BIGINT 0")',
    'cmd("INST CLEAR")',
  ])

  // Reload page and verify history still exists
  await page.reload()
  await expect(page.locator('.v-app-bar')).toContainText('Command Sender')
  await expect(historyEntries(page)).toHaveCount(4)
  // Clear history and verify cleared
  await page.locator('[data-test="clear-history"]').click()
  await expect(historyEntries(page)).toHaveCount(0)
})

test('hazardous commands from history', async ({ page, utils }) => {
  await page.locator('[data-test="clear-history"]').click()
  await utils.selectTargetPacketItem('INST', 'CLEAR')
  await expect(page.locator('main')).toContainText(
    'Clears counters on the INST instrument',
  )
  // The Send button shows the command is hazardous before it's pressed
  await expect(page.locator('[data-test="select-send"]')).toHaveClass(
    /bg-warning/,
  )
  await sendHazardousCmd(page)
  await checkSent(page, 'cmd("INST CLEAR")')
  // Send a different command: INST ASCIICMD
  await utils.selectTargetPacketItem('INST', 'ASCIICMD')
  await expect(page.locator('main')).toContainText('Enumerated ASCII command')
  await selectValue(page, 'STRING', 'ARM LASER')
  await checkValue(page, 'STRING', 'ARM LASER')
  await sendHazardousCmd(page)
  await expect(page.locator('main')).toContainText(
    "cmd(\"INST ASCIICMD with STRING 'ARM LASER', BINARY 0xDEADBEEF, ASCII '0xDEADBEEF'\")",
  )
  // Loading from the history asks nothing until Send, then describes the
  // loaded command
  await loadFromHistory(page, 'cmd("INST CLEAR")', 'INST CLEAR')
  await expect(page.getByRole('dialog')).toHaveCount(0)
  await page.locator('[data-test="select-send"]').click()
  await expect(page.getByRole('dialog')).toContainText(
    'Warning: Command INST CLEAR is Hazardous. Send?',
  )
  await expect(page.getByRole('dialog')).toContainText(
    'Description: Clears counters on the INST instrument',
  )
  await expect(
    page.getByRole('dialog').locator('[data-test=hazardous-description]'),
  ).toContainText('Clearing counters may lose valuable information.')
  await page.getByRole('dialog').getByRole('button', { name: 'Send' }).click()
  await expect(page.locator('main')).toContainText('cmd("INST CLEAR") sent')
  // Strings, binary and states load back exactly
  await loadFromHistory(page, 'INST ASCIICMD', 'INST ASCIICMD')
  await checkValue(page, 'STRING', 'ARM LASER')
  await sendHazardousCmd(page)
  await expect(page.locator('main')).toContainText(
    "cmd(\"INST ASCIICMD with STRING 'ARM LASER', BINARY 0xDEADBEEF, ASCII '0xDEADBEEF'\") sent",
  )
})

test('pastes a command into the form', async ({ page, utils }) => {
  await page.locator('[data-test="clear-history"]').click()
  await utils.selectTargetPacketItem('INST', 'ABORT')
  await expect(commandLine(page)).toHaveValue('cmd("INST ABORT")')

  // Pasting over the line fills in the form but doesn't send
  await pasteLine(
    page,
    'cmd("INST COLLECT with TYPE \'SPECIAL\', DURATION 3, TEMP 2.5")',
  )
  await expect(page.locator('[data-test=sender-status]')).toContainText(
    'Loaded INST COLLECT, press Send to send it',
  )
  await utils.dropdownSelectedValue(
    page,
    '[data-test="select-packet"]',
    'COLLECT',
  )
  await checkValue(page, 'DURATION', '3')
  await checkValue(page, 'TEMP', '2.5')
  // The line shows the whole command Send sends
  await expect(commandLine(page)).toHaveValue(
    'cmd("INST COLLECT with TYPE \'SPECIAL\', DURATION 3, OPCODE 171, TEMP 2.5")',
  )
  await expect(historyEntries(page)).toHaveCount(0)
  await sendHazardousCmd(page)
  await checkSent(
    page,
    'cmd("INST COLLECT with TYPE \'SPECIAL\', DURATION 3, OPCODE 171, TEMP 2.5")',
  )

  // File > Paste Command selects the line, so a paste replaces it. The Mode
  // menu decides how it's sent, so a different method is noted.
  await page.locator('[data-test=command-sender-file]').click()
  await page.getByText('Paste Command').click()
  await expect(commandLine(page)).toBeFocused()
  await pasteOnPage(
    page,
    'cmd_raw_no_range_check("INST ABORT", validate=False)',
  )
  await expect(page.locator('[data-test=sender-status]')).toContainText(
    'it was written as cmd_raw_no_range_check but the Mode menu sends cmd',
  )
  await expect(page.locator('[data-test=sender-status]')).toContainText(
    'validate false was not applied',
  )
  // The line shows how Send sends it
  await expect(commandLine(page)).toHaveValue('cmd("INST ABORT")')
  await expect(historyEntries(page)).toHaveCount(1)
  // Picking a different command clears the status
  await utils.selectTargetPacketItem('INST', 'CLEAR')
  await expect(page.locator('[data-test=sender-status]')).not.toContainText(
    'Loaded',
  )
})

test('shows the form as a script line', async ({ page, utils }) => {
  await page.context().grantPermissions(['clipboard-read', 'clipboard-write'])
  await utils.selectTargetPacketItem('INST', 'COLLECT')
  // TYPE is required and not set yet, so Send wouldn't send it either
  await expect(commandLine(page)).toHaveValue(
    'cmd("INST COLLECT with DURATION 1, OPCODE 171, TEMP 0")',
  )
  await expect(commandLinePanel(page)).toContainText('Follows the form')
  // It follows the parameters as they change
  await selectValue(page, 'TYPE', 'NORMAL')
  await setValue(page, 'DURATION', '5')
  await expect(commandLine(page)).toHaveValue(
    `cmd("INST COLLECT with TYPE 'NORMAL', DURATION 5, OPCODE 171, TEMP 0")`,
  )
  // and the Mode menu
  await toggleMode(page, 'Ignore Range Checks')
  await expect(commandLine(page)).toHaveValue(/^cmd_no_range_check\("/)
  await toggleMode(page, 'Ignore Range Checks')
  await toggleMode(page, 'Disable Parameter Conversions')
  await expect(commandLine(page)).toHaveValue(
    'cmd_raw("INST COLLECT with TYPE 0, DURATION 5, OPCODE 171, TEMP 0")',
  )
  await toggleMode(page, 'Disable Parameter Conversions')
  await toggleMode(page, 'Disable Command Validation')
  await expect(commandLine(page)).toHaveValue(
    `cmd("INST COLLECT with TYPE 'NORMAL', DURATION 5, OPCODE 171, TEMP 0", validate=False)`,
  )
  await toggleMode(page, 'Disable Command Validation')
  // Copy puts it on the clipboard, ready for a script
  await page.locator('[data-test=command-line-copy]').click()
  await expect(page.locator('[data-test=command-line-copy]')).toHaveAttribute(
    'title',
    'Copied',
  )
  expect(await page.evaluate(() => navigator.clipboard.readText())).toBe(
    `cmd("INST COLLECT with TYPE 'NORMAL', DURATION 5, OPCODE 171, TEMP 0")`,
  )
  // What Send sends is what the line showed
  await page.locator('[data-test="select-send"]').click()
  await checkSent(
    page,
    `cmd("INST COLLECT with TYPE 'NORMAL', DURATION 5, OPCODE 171, TEMP 0")`,
  )

  // Obfuscated values are masked, as the history masks them
  await utils.selectTargetPacketItem('INST', 'SET_PASSWORD')
  await expect(page.locator('main')).toContainText('Set Password Command')
  await setValue(page, 'PASSWORD_STR', 'secret')
  await expect(commandLine(page)).toHaveValue(/PASSWORD_STR '\*\*\*\*\*'/)
  await expect(commandLine(page)).not.toHaveValue(/secret/)
})

test('loads valid script lines', async ({ page, utils }) => {
  await page.locator('[data-test="clear-history"]').click()
  await utils.selectTargetPacketItem('INST', 'ABORT')

  // A state's value selects the state; numbers are written as sent
  await pasteLine(
    page,
    'cmd("INST COLLECT with TYPE 1, DURATION 2.5, TEMP 1e1")',
  )
  await expect(page.locator('[data-test=sender-status]')).toContainText(
    'Loaded INST COLLECT, press Send to send it.',
  )
  await expect(
    page.locator('tr:has(td:text-is("TYPE")) [data-test=cmd-param-select]'),
  ).toContainText('SPECIAL')
  await checkValue(page, 'DURATION', '2.5')
  await expect(commandLine(page)).toHaveValue(
    `cmd("INST COLLECT with TYPE 'SPECIAL', DURATION 2.5, OPCODE 171, TEMP 10")`,
  )

  // Bare command text with strings, binary and a string with a quote
  await pasteLine(
    page,
    `INST ASCIICMD with STRING 'FIRE LASER', BINARY 0xCAFE, ASCII "it's"`,
  )
  await expect(page.locator('[data-test=sender-status]')).toContainText(
    'Loaded INST ASCIICMD',
  )
  await checkValue(page, 'BINARY', '0xCAFE')
  await expect(commandLine(page)).toHaveValue(
    String.raw`cmd("INST ASCIICMD with STRING 'FIRE LASER', BINARY 0xCAFE, ASCII \"it's\"")`,
  )

  // Ruby without parentheses, with an array
  await pasteLine(page, 'cmd "INST ARYCMD with ARRAY [1, 2, 3]"')
  await expect(page.locator('[data-test=sender-status]')).toContainText(
    'Loaded INST ARYCMD',
  )
  await expect(commandLine(page)).toHaveValue(
    'cmd("INST ARYCMD with ARRAY [ 1, 2, 3 ], CRC 0")',
  )

  // A trailing comment is ignored
  await pasteLine(page, 'cmd("INST CLEAR") # clear the counters')
  await expect(page.locator('[data-test=sender-status]')).toContainText(
    'Loaded INST CLEAR',
  )
  await expect(commandLine(page)).toHaveValue('cmd("INST CLEAR")')

  // A BOOL stays a boolean rather than becoming the string 'false'
  await pasteLine(page, 'cmd("INST JSONCMD with ITEM6 false")')
  await expect(page.locator('[data-test=sender-status]')).toContainText(
    'Loaded INST JSONCMD',
  )
  await expect(commandLine(page)).toHaveValue(/ITEM6 false,/)

  // Parameters the command doesn't have are skipped and noted
  await pasteLine(page, 'cmd("INST ABORT with NOPE 1")')
  await expect(page.locator('[data-test=sender-status]')).toContainText(
    'NOPE not parameters of INST ABORT, skipped',
  )
  await expect(commandLine(page)).toHaveValue('cmd("INST ABORT")')
  await expect(page.locator('[data-test="select-send"]')).toBeEnabled()
  await expect(historyEntries(page)).toHaveCount(0)
})

test('reports invalid script lines', async ({ page, utils }) => {
  await utils.selectTargetPacketItem('INST', 'COLLECT')
  await selectValue(page, 'TYPE', 'NORMAL')
  await setValue(page, 'DURATION', '3')
  const formLine = `cmd("INST COLLECT with TYPE 'NORMAL', DURATION 3, OPCODE 171, TEMP 0")`
  await expect(commandLine(page)).toHaveValue(formLine)

  for (const [line, error] of [
    ['cmd("INST NOPE")', 'Unable to load INST NOPE'],
    ['cmd("NOPE ABORT")', 'Unable to load NOPE ABORT'],
    ['cmd("INST", "ABORT")', 'Only the single string form is supported'],
    ['tlm("INST HEALTH_STATUS TEMP1")', 'Unknown command method tlm'],
    ['cmd("INST ABORT"', 'Missing the closing parenthesis'],
    ['cmd("INST ABORT)', 'Unterminated string'],
    ['INST', 'Both Target Name and Command Name must be given'],
    ['cmd("INST COLLECT with")', "'with' must be followed by parameters"],
    ['cmd("INST COLLECT with DURATION")', 'Missing value for DURATION'],
    [
      'cmd("INST COLLECT with DURATION 1 TEMP 2")',
      'Missing comma in command parameters',
    ],
    ['cmd("INST ABORT", validate: maybe)', 'validate must be true or false'],
    ['cmd("INST ABORT", 5)', 'Invalid keyword argument: 5'],
  ]) {
    await pasteCommand(page, line)
    await expect(commandLinePanel(page)).toContainText(error)
    // The line keeps what was typed, to fix it, and the form is unchanged
    await expect(commandLine(page)).toHaveValue(line)
    await expect(page.locator('[data-test="select-send"]')).toBeDisabled()
  }
  await utils.dropdownSelectedValue(
    page,
    '[data-test="select-packet"]',
    'COLLECT',
  )
  await checkValue(page, 'DURATION', '3')

  // Typing clears the error until the line is loaded again
  await commandLine(page).press('End')
  await commandLine(page).press('Backspace')
  await expect(commandLinePanel(page)).not.toContainText('Invalid keyword')
  await expect(commandLinePanel(page)).toContainText('Not loaded')

  // An empty line has nothing to load
  await pasteCommand(page, '')
  await expect(commandLinePanel(page)).toContainText('Enter a command to load')

  // A paste over the whole line reports its error too
  await pasteLine(page, 'cmd("INST NOPE")')
  await expect(commandLinePanel(page)).toContainText('Unable to load INST NOPE')
  await expect(page.locator('[data-test="select-send"]')).toBeDisabled()

  // Esc puts back the form's command, and Send sends the form
  await commandLine(page).press('Escape')
  await expect(commandLine(page)).toHaveValue(formLine)
  await expect(commandLinePanel(page)).not.toContainText('Unable to load')
  await expect(commandLinePanel(page)).toContainText('Follows the form')
  await page.locator('[data-test="select-send"]').click()
  await checkSent(page, formLine)
})

test('edits the script line', async ({ page, utils }) => {
  await page.locator('[data-test="clear-history"]').click()
  await utils.selectTargetPacketItem('INST', 'COLLECT')
  await selectValue(page, 'TYPE', 'NORMAL')
  const formLine = `cmd("INST COLLECT with TYPE 'NORMAL', DURATION 1, OPCODE 171, TEMP 0")`
  await expect(commandLine(page)).toHaveValue(formLine)

  // An edit isn't in the form until Enter, so Send is off
  await commandLine(page).fill(formLine.replace('DURATION 1', 'DURATION 7'))
  await expect(commandLinePanel(page)).toContainText('Not loaded')
  await expect(page.locator('[data-test="select-send"]')).toBeDisabled()
  await checkValue(page, 'DURATION', '1')
  // Esc undoes it
  await commandLine(page).press('Escape')
  await expect(commandLine(page)).toHaveValue(formLine)
  await expect(page.locator('[data-test="select-send"]')).toBeEnabled()

  // Enter loads it
  await commandLine(page).fill(formLine.replace('DURATION 1', 'DURATION 7'))
  await commandLine(page).press('Enter')
  await expect(page.locator('[data-test=sender-status]')).toContainText(
    'Loaded INST COLLECT',
  )
  await checkValue(page, 'DURATION', '7')
  await expect(commandLinePanel(page)).toContainText('Follows the form')
  await expect(page.locator('[data-test="select-send"]')).toBeEnabled()

  // Changing the form drops an edit that wasn't loaded: the form is sent
  await commandLine(page).fill('cmd("INST ABORT")')
  await setValue(page, 'TEMP', '5')
  await expect(commandLine(page)).toHaveValue(
    `cmd("INST COLLECT with TYPE 'NORMAL', DURATION 7, OPCODE 171, TEMP 5")`,
  )
  await expect(page.locator('[data-test="select-send"]')).toBeEnabled()
  await expect(historyEntries(page)).toHaveCount(0)

  // Editing the line keeps the obfuscated values it masks
  await utils.selectTargetPacketItem('INST', 'SET_PASSWORD')
  await expect(page.locator('main')).toContainText('Set Password Command')
  await setValue(page, 'USERNAME', 'operator')
  await setValue(page, 'PASSWORD_STR', 'secret')
  const line = await commandLine(page).inputValue()
  await commandLine(page).fill(line.replace("'operator'", "'admin'"))
  await commandLine(page).press('Enter')
  await expect(page.locator('[data-test=sender-status]')).toContainText(
    'Loaded INST SET_PASSWORD',
  )
  await checkValue(page, 'USERNAME', `'admin'`)
  await checkValue(page, 'PASSWORD_STR', 'secret')
  // but a pasted command's ***** is unknown, so it's asked for
  await pasteLine(page, await commandLine(page).inputValue())
  await expect(page.locator('[data-test=sender-status]')).toContainText(
    'the history hides the value',
  )
  await checkValue(page, 'PASSWORD_STR', '')
})

test('opens the help dialogs', async ({ page, utils }) => {
  await page.locator('[data-test=command-sender-help]').click()
  await page.getByText('Keyboard Shortcuts').click()
  await expect(page.locator('[data-test=help-dialog-shortcuts]')).toContainText(
    'Load a command from the clipboard into the form',
  )
  await page.locator('[data-test=help-dialog-ok]').click()
  await page.locator('[data-test=command-sender-help]').click()
  await page.getByText('Using Command Sender').click()
  await expect(page.locator('[data-test=help-dialog-guide]')).toContainText(
    'Hazardous commands',
  )
  await page.locator('[data-test=help-dialog-ok]').click()
  await expect(page.locator('[data-test=help-dialog-guide]')).toHaveCount(0)
})

test('pastes and steps through the history with the keyboard', async ({
  page,
  utils,
}) => {
  await page.locator('[data-test="clear-history"]').click()
  await utils.selectTargetPacketItem('INST', 'ABORT')
  await page.locator('[data-test="select-send"]').click()
  await checkSent(page, 'cmd("INST ABORT")')
  await utils.selectTargetPacketItem('INST', 'SETPARAMS')
  await expect(page.locator('main')).toContainText('Value 1 setting')
  await page.locator('[data-test="select-send"]').click()
  await expect(page.locator('main')).toContainText(
    'cmd("INST SETPARAMS with VALUE1 1, VALUE2 1, VALUE3 1, VALUE4 1, VALUE5 1, BIGINT 0") sent',
  )

  // Mod+V with no field selected loads the text through the Script line
  await page.locator('[data-test=history-count]').click()
  await pasteOnPage(page, `cmd("INST COLLECT with TYPE 'NORMAL', DURATION 4")`)
  await expect(page.locator('[data-test=sender-status]')).toContainText(
    'Loaded INST COLLECT, press Send to send it',
  )
  await checkValue(page, 'DURATION', '4')
  await expect(commandLine(page)).toHaveValue(
    `cmd("INST COLLECT with TYPE 'NORMAL', DURATION 4, OPCODE 171, TEMP 0")`,
  )

  // Pasting in a field pastes there instead
  await page
    .locator('tr:has(td:text-is("TEMP")) [data-test=cmd-param-value] input')
    .click()
  await pasteOnPage(page, 'cmd("INST ABORT")')
  await utils.dropdownSelectedValue(
    page,
    '[data-test="select-packet"]',
    'COLLECT',
  )

  // Alt+Down / Alt+Up load older / newer history commands, never sending
  await page.locator('[data-test=history-count]').click()
  await page.keyboard.press('Alt+ArrowDown')
  await expect(page.locator('[data-test=sender-status]')).toContainText(
    'Loaded INST SETPARAMS',
  )
  await page.keyboard.press('Alt+ArrowDown')
  await expect(page.locator('[data-test=sender-status]')).toContainText(
    'Loaded INST ABORT',
  )
  await utils.dropdownSelectedValue(
    page,
    '[data-test="select-packet"]',
    'ABORT',
  )
  await page.keyboard.press('Alt+ArrowUp')
  await expect(page.locator('[data-test=sender-status]')).toContainText(
    'Loaded INST SETPARAMS',
  )
  await expect(historyEntries(page)).toHaveCount(2)
})

// https://github.com/OpenC3/cosmos/issues/3550: a single quoted cmd() line
// used to become an empty command ("Invalid number of arguments (0) passed to
// get_cmd_hazardous()")
test('pastes commands written with single quotes', async ({ page, utils }) => {
  await page.locator('[data-test="clear-history"]').click()
  await utils.selectTargetPacketItem('INST', 'CLEAR')
  await pasteCommand(page, "cmd('INST ABORT')")
  await expect(page.locator('[data-test=sender-status]')).toContainText(
    'Loaded INST ABORT, press Send to send it',
  )
  await utils.dropdownSelectedValue(
    page,
    '[data-test="select-packet"]',
    'ABORT',
  )
  await page.locator('[data-test="select-send"]').click()
  await checkSent(page, 'cmd("INST ABORT")')

  // Single quoted with double quoted values and a single quoted queue keyword
  await pasteCommand(
    page,
    `cmd('INST COLLECT with TYPE "NORMAL", DURATION 2', queue='None')`,
  )
  await expect(page.locator('[data-test=sender-status]')).toContainText(
    'Loaded INST COLLECT, press Send to send it',
  )
  await checkValue(page, 'DURATION', '2')
})

test('leaves off a pasted queue that does not exist', async ({
  page,
  utils,
}) => {
  await utils.selectTargetPacketItem('INST', 'ABORT')
  await pasteCommand(page, 'cmd("INST CLEAR", queue: "NO_SUCH_QUEUE")')
  await expect(page.locator('[data-test=sender-status]')).toContainText(
    `queue "NO_SUCH_QUEUE" doesn't exist, the queue is None`,
  )
  // It used to be selected even though it isn't in the queue list, which is
  // disabled when there are no queues, so it couldn't be changed back
  await expect(page.locator('[data-test=select-queue]')).toContainText('None')
  await expect(page.locator('[data-test=select-queue]')).not.toContainText(
    'NO_SUCH_QUEUE',
  )
})

test('loads the queue a history command was sent with', async ({
  page,
  utils,
}) => {
  const queue = `CMDSENDER_TEST_${Date.now()}`
  const queueApi = (method) =>
    page.evaluate(
      async ({ queue, method }) => {
        const response = await fetch(
          `/openc3-api/queues/${queue}?scope=DEFAULT`,
          { method, headers: { Authorization: localStorage.openc3Token } },
        )
        if (!response.ok) {
          throw new Error(`${method} queue failed: ${response.status}`)
        }
      },
      { queue, method },
    )
  await queueApi('POST')
  try {
    // The queue list loads with the page
    await page.reload()
    await expect(page.locator('.v-app-bar')).toContainText('Command Sender')
    await page.locator('[data-test="clear-history"]').click()

    // Send one command to the queue and one directly
    await utils.selectTargetPacketItem('INST', 'ABORT')
    await page.locator('[data-test=select-queue]').click()
    await page.getByRole('option', { name: queue }).click()
    await page.locator('[data-test="select-send"]').click()
    await expect(historyEntries(page).first()).toContainText(queue)
    await utils.selectTargetPacketItem('INST', 'SETPARAMS')
    await expect(page.locator('main')).toContainText('Value 1 setting')
    await page.locator('[data-test=select-queue]').click()
    await page.getByRole('option', { name: 'None' }).click()
    await page.locator('[data-test="select-send"]').click()
    await expect(historyEntries(page)).toHaveCount(2)
    await expect(historyEntries(page).first()).not.toContainText(queue)

    // Loading the queued command selects its queue
    await loadFromHistory(page, 'INST ABORT', 'INST ABORT')
    await expect(page.locator('[data-test=select-queue]')).toContainText(queue)
    // Loading the direct command sets it back to None. It used to keep the
    // queue, so pressing Send would have queued a command sent directly.
    await loadFromHistory(page, 'INST SETPARAMS', 'INST SETPARAMS')
    await expect(page.locator('[data-test=select-queue]')).toContainText('None')
    await expect(page.locator('[data-test=select-queue]')).not.toContainText(
      queue,
    )
  } finally {
    await queueApi('DELETE')
  }
})

test('asks for obfuscated values loaded from the history', async ({
  page,
  utils,
}) => {
  await page.locator('[data-test="clear-history"]').click()
  await utils.selectTargetPacketItem('INST', 'SET_PASSWORD')
  await expect(page.locator('main')).toContainText('Set Password Command')
  // USERNAME is REQUIRED
  await setValue(page, 'USERNAME', 'operator')
  await page.locator('[data-test="select-send"]').click()
  await expect(page.locator('[data-test=sender-status]')).toContainText('sent')
  await expect(historyEntries(page).first()).toContainText(
    "PASSWORD_STR '*****'",
  )

  // The history hides the values, so Send refuses rather than sending the
  // defaults in their place
  await loadFromHistory(page, 'SET_PASSWORD', 'INST SET_PASSWORD')
  await checkValue(page, 'PASSWORD_STR', '')
  await page.locator('[data-test="select-send"]').click()
  await expect(page.locator('.v-dialog')).toContainText(
    'Enter PASSWORD_STR, PASSWORD_UINT',
  )
  await page.locator('[data-test=error-dialog-ok]').click()
  await expect(historyEntries(page)).toHaveCount(1)

  // Toggling Show Ignored Parameters reloads the rows but keeps what's in the
  // form: an entered value, and the obfuscated values still waiting
  await checkValue(page, 'USERNAME', `'operator'`)
  await setValue(page, 'USERNAME', 'admin')
  await toggleMode(page, 'Show Ignored')
  await checkValue(page, 'USERNAME', 'admin')
  await checkValue(page, 'PASSWORD_STR', '')
  await page.locator('[data-test="select-send"]').click()
  await expect(page.locator('.v-dialog')).toContainText('Enter PASSWORD_STR')
  await page.locator('[data-test=error-dialog-ok]').click()
  await toggleMode(page, 'Show Ignored')
  await expect(historyEntries(page)).toHaveCount(1)

  // Once entered they send
  for (const [param, value] of [
    ['PASSWORD_STR', 'secret'],
    ['PASSWORD_UINT', '1'],
    ['PASSWORD_BIG_UINT', '2'],
    ['PASSWORD_INT', '3'],
    ['PASSWORD_FLOAT', '4'],
    ['PASSWORD_BLOCK', '0xAB'],
    ['ARRAY', '[1, 2]'],
  ]) {
    await setValue(page, param, value)
  }
  await page.locator('[data-test="select-send"]').click()
  await expect(historyEntries(page)).toHaveCount(2)

  // ***** is only the history's mask for obfuscated parameters; pasted for
  // any other it's the value
  await pasteCommand(page, `cmd("INST SET_PASSWORD with USERNAME '*****'")`)
  await expect(page.locator('[data-test=sender-status]')).toContainText(
    'Loaded INST SET_PASSWORD',
  )
  await checkValue(page, 'USERNAME', `'*****'`)
})

test('reloads history commands with double quotes', async ({ page, utils }) => {
  await page.locator('[data-test="clear-history"]').click()
  await utils.selectTargetPacketItem('INST', 'ASCIICMD')
  await expect(page.locator('main')).toContainText('Enumerated ASCII command')
  await setValue(page, 'ASCII', 'say "hi"')
  await page.locator('[data-test="select-send"]').click()
  // Escaped as in a script string literal
  await expect(historyEntries(page).first()).toContainText(
    `ASCII 'say \\"hi\\"'`,
  )
  await utils.selectTargetPacketItem('INST', 'ABORT')
  await loadFromHistory(page, 'ASCIICMD', 'INST ASCIICMD')
  await checkValue(page, 'ASCII', `'say "hi"'`)
})

test('copies and clears the history', async ({ page, utils }) => {
  await page.context().grantPermissions(['clipboard-read', 'clipboard-write'])
  await page.locator('[data-test="clear-history"]').click()
  await utils.selectTargetPacketItem('INST', 'ABORT')
  await page.locator('[data-test="select-send"]').click()
  await checkSent(page, 'cmd("INST ABORT")')
  // Copy puts the command on the clipboard, ready for a script
  await historyEntries(page).first().hover()
  await page.locator('[data-test=history-copy]').first().click()
  await expect(
    page.locator('[data-test=history-copy]').first(),
  ).toHaveAttribute('title', 'Copied')
  expect(await page.evaluate(() => navigator.clipboard.readText())).toBe(
    'cmd("INST ABORT")',
  )
  // File > Clear History empties it
  await page.locator('[data-test=command-sender-file]').click()
  await page.getByText('Clear History').click()
  await expect(historyEntries(page)).toHaveCount(0)
})

test('shows the ignored parameters a history command was sent with', async ({
  page,
  utils,
}) => {
  await page.locator('[data-test="clear-history"]').click()
  await utils.selectTargetPacketItem('INST', 'ABORT')
  await toggleMode(page, 'Show Ignored')
  await expect(page.locator('main')).toContainText('CCSDSVER')
  await page.locator('[data-test="select-send"]').click()
  await expect(historyEntries(page).first()).toContainText('CCSDSVER')
  // Hide them again and pick another command
  await toggleMode(page, 'Show Ignored')
  await utils.selectTargetPacketItem('INST', 'CLEAR')
  await expect(page.locator('tr:has(td:text-is("CCSDSVER"))')).toHaveCount(0)
  // Loading the command shows them, so the form matches what was sent
  await loadFromHistory(page, 'INST ABORT', 'INST ABORT')
  await expect(
    page.locator(
      'tr:has(td:text-is("CCSDSVER")) [data-test=cmd-param-value] input',
    ),
  ).toHaveValue('0')
})

test('migrates the old history', async ({ page, utils }) => {
  await page.evaluate(() => {
    localStorage.removeItem('command_sender__history_v2')
    localStorage.setItem(
      'command_sender__history',
      'cmd("INST ABORT")\ncmd("INST CLEAR")',
    )
  })
  await page.reload()
  await expect(page.locator('.v-app-bar')).toContainText('Command Sender')
  await expect(historyEntries(page)).toHaveText([
    'cmd("INST ABORT")',
    'cmd("INST CLEAR")',
  ])
  await loadFromHistory(page, 'cmd("INST ABORT")', 'INST ABORT')
})

//
// Test the range checks, this doesn't affect the UI so can be run in parallel with the other tests
//
test('ignores normal range checks', async ({ page, utils }) => {
  await page.locator('[data-test="clear-history"]').click()
  await utils.selectTargetPacketItem('INST', 'COLLECT')
  await selectValue(page, 'TYPE', 'NORMAL') // Ensure TYPE is set since its required
  await page.locator('[data-test="select-send"]').click()
  await expect(page.locator('main')).toContainText(
    'cmd("INST COLLECT with TYPE \'NORMAL\', DURATION 1, OPCODE 171, TEMP 0")',
  )
  await checkHistory(
    page,
    'cmd("INST COLLECT with TYPE \'NORMAL\', DURATION 1, OPCODE 171, TEMP 0")',
  )
  await setValue(page, 'TEMP', '100')
  await page.locator('[data-test="select-send"]').click()
  // Dialog should pop up with error
  await expect(page.locator('.v-dialog')).toContainText(
    "Error sending INST COLLECT due to RuntimeError: Command parameter 'INST COLLECT TEMP' = 100 not in valid range of 0.0 to 25.0",
  )
  await page.locator('button:has-text("Ok")').click()
  // Disable range checks
  await toggleMode(page, 'Ignore Range Checks')
  // Ignoring range checks makes every command hazardous
  await sendHazardousCmd(
    page,
    'Warning: Command INST COLLECT is considered Hazardous because range checks are ignored. Send?',
  )
  await checkSent(
    page,
    'cmd_no_range_check("INST COLLECT with TYPE \'NORMAL\', DURATION 1, OPCODE 171, TEMP 100")',
  )

  // Enable range checks
  await toggleMode(page, 'Ignore Range Checks')
  await utils.selectTargetPacketItem('EXAMPLE', 'START')
  await expect(page.locator('main')).toContainText(
    'Starts something on the example target',
  )
  // Load the command sent without range checks; the Mode menu now checks them
  await loadFromHistory(page, 'TEMP 100', 'INST COLLECT')
  await expect(page.locator('[data-test=sender-status]')).toContainText(
    'it was written as cmd_no_range_check but the Mode menu sends cmd',
  )
  await checkValue(page, 'TEMP', '100')
  await setValue(page, 'TEMP', '50')
  await page.locator('[data-test="select-send"]').click()
  // Dialog should pop up with error
  await expect(page.locator('.v-dialog')).toContainText(
    "Error sending INST COLLECT due to RuntimeError: Command parameter 'INST COLLECT TEMP' = 50 not in valid range of 0.0 to 25.0",
  )
  await page.locator('button:has-text("Ok")').click()
})

test('ignores hazardous range checks', async ({ page, utils }) => {
  await page.locator('[data-test="clear-history"]').click()
  await utils.selectTargetPacketItem('INST', 'COLLECT')
  await selectValue(page, 'TYPE', 'SPECIAL') // Special is hazardous
  await setValue(page, 'TEMP', '100')
  await sendHazardousCmd(page)
  // Dialog should pop up with error
  await expect(page.locator('.v-dialog:has-text("Error")')).toContainText(
    'not in valid range',
  )
  await page.locator('button:has-text("Ok")').click()
  // Disable range checks
  await toggleMode(page, 'Ignore Range Checks')
  // The dialog also notes that range checks are ignored
  await sendHazardousCmd(
    page,
    'Warning: Command INST COLLECT is Hazardous and range checks are ignored. Send?',
  )
  await checkSent(
    page,
    'cmd_no_range_check("INST COLLECT with TYPE \'SPECIAL\', DURATION 1, OPCODE 171, TEMP 100")',
  )
})

test('confirms commands when ignoring range checks', async ({
  page,
  utils,
}) => {
  await page.locator('[data-test="clear-history"]').click()
  await utils.selectTargetPacketItem('INST', 'COLLECT')
  await selectValue(page, 'TYPE', 'NORMAL')
  await toggleMode(page, 'Ignore Range Checks')

  // Cancelling a command that's only hazardous due to ignored range checks
  await page.locator('[data-test="select-send"]').click()
  await expect(page.getByRole('dialog')).toContainText(
    'Warning: Command INST COLLECT is considered Hazardous because range checks are ignored. Send?',
  )
  await page.getByRole('dialog').getByRole('button', { name: 'Cancel' }).click()
  await expect(page.locator('main')).toContainText('Hazardous command not sent')
  await expect(page.locator('[data-test=sender-history]')).not.toContainText(
    'INST COLLECT',
  )

  // Send it so it's in the history
  await sendHazardousCmd(page)
  await expect(page.locator('main')).toContainText(
    'cmd_no_range_check("INST COLLECT with TYPE \'NORMAL\', DURATION 1, OPCODE 171, TEMP 0") sent',
  )

  // Resending from history still requires confirmation and names the command.
  // Select a different command first so the history entry replaces it.
  await utils.selectTargetPacketItem('INST', 'CLEAR')
  await expect(page.locator('main')).toContainText(
    'Clears counters on the INST instrument',
  )
  await loadFromHistory(page, 'INST COLLECT', 'INST COLLECT')
  await page.locator('[data-test="select-send"]').click()
  await expect(page.getByRole('dialog')).toContainText(
    'Warning: Command INST COLLECT is considered Hazardous because range checks are ignored. Send?',
  )
  await expect(page.getByRole('dialog')).toContainText(
    'Description: Starts a collect on the INST target',
  )
  await expect(
    page.getByRole('dialog').locator('[data-test=hazardous-description]'),
  ).toHaveCount(0)
  await page.getByRole('dialog').getByRole('button', { name: 'Send' }).click()
  await expect(page.locator('main')).toContainText(
    'cmd_no_range_check("INST COLLECT with TYPE \'NORMAL\', DURATION 1, OPCODE 171, TEMP 0") sent',
  )
})

test('confirms commands when disabling parameter conversions', async ({
  page,
  utils,
}) => {
  await page.locator('[data-test="clear-history"]').click()
  await utils.selectTargetPacketItem('INST', 'COLLECT')
  await selectValue(page, 'TYPE', 'NORMAL')
  await toggleMode(page, 'Disable Parameter')

  await sendHazardousCmd(
    page,
    'Warning: Command INST COLLECT is considered Hazardous because parameter conversions are disabled. Send?',
  )
  await expect(page.locator('main')).toContainText('cmd_raw("INST COLLECT')
})

//
// Test VARIABLE_ARRAYS command with variable_bit_size arrays
//
for (const target of ['INST', 'INST2']) {
  test(`sends ${target} VARIABLE_ARRAYS command and verifies in packet viewer`, async ({
    page,
    utils,
  }) => {
    await page.locator('[data-test="clear-history"]').click()
    await utils.selectTargetPacketItem(target, 'VARIABLE_ARRAYS')

    // Verify the LENGTH fields are disabled (shown but not editable)
    // Use exact text match with colon suffix to avoid partial matches
    const array1LengthRow = page.locator('tr:has(td:text-is("ARRAY1_LENGTH"))')
    const array2LengthRow = page.locator('tr:has(td:text-is("ARRAY2_LENGTH"))')

    // selectTargetPacketItem only confirms the packet dropdown updated, not that
    // the parameter table re-rendered for the new packet. On a slow runner the
    // LENGTH rows may not exist yet, so wait for them before asserting state
    // (otherwise toBeDisabled fails with "element(s) not found").
    await expect(array1LengthRow).toBeVisible({ timeout: 15000 })
    await expect(array2LengthRow).toBeVisible({ timeout: 15000 })

    // Check that the LENGTH input fields are disabled
    await expect(
      array1LengthRow.locator('[data-test=cmd-param-value] input'),
    ).toBeDisabled()
    await expect(
      array2LengthRow.locator('[data-test=cmd-param-value] input'),
    ).toBeDisabled()

    // Set the array values
    await setValue(page, 'ARRAY1', '[1, 2, 3]')
    await setValue(page, 'ARRAY2', '[4, 5]')

    // Send the command
    await page.locator('[data-test="select-send"]').click()
    await expect(page.locator('main')).toContainText(
      `cmd("${target} VARIABLE_ARRAYS with ARRAY1_LENGTH 0, ARRAY1 [ 1, 2, 3 ], ARRAY2_LENGTH 0, ARRAY2 [ 4, 5 ]") sent`,
    )

    // Open Packet Viewer to verify the telemetry
    await page.locator('[data-test="nav-drawer-toggle"]').click()
    await page.locator('text=Packet Viewer').click()
    await expect(page.locator('.v-app-bar')).toContainText('Packet Viewer')
    await expect(page.locator('.v-table')).toContainText('PACKET_TIMESECONDS *')

    // Navigate to the VARIABLE_ARRAYS telemetry packet
    await utils.selectTargetPacketItem(target, 'VARIABLE_ARRAYS')

    // Wait for the packet to be received and verify the values
    // Use polling since telemetry updates asynchronously
    await expect
      .poll(
        async () => {
          return await page.inputValue(
            'tr:has(td div:text-is("ARRAY1_LENGTH")) input',
          )
        },
        { timeout: 10000 },
      )
      .toBe('3')

    await expect
      .poll(
        async () => {
          return await page.inputValue(
            'tr:has(td div:text-is("ARRAY2_LENGTH")) input',
          )
        },
        { timeout: 10000 },
      )
      .toBe('2')

    await expect
      .poll(
        async () => {
          return await page.inputValue('tr:has(td div:text-is("ARRAY1")) input')
        },
        { timeout: 10000 },
      )
      .toMatch(/\[\s*1,\s*2,\s*3\s*\]/)

    await expect
      .poll(
        async () => {
          return await page.inputValue('tr:has(td div:text-is("ARRAY2")) input')
        },
        { timeout: 10000 },
      )
      .toMatch(/\[\s*4,\s*5\s*\]/)
  })
}

test('sends manually entered state values', async ({ page, utils }) => {
  await page.locator('[data-test="clear-history"]').click()
  await utils.selectTargetPacketItem('INST', 'COLLECT')
  await expect(page.locator('main')).toContainText(
    'Starts a collect on the INST target',
  )

  // Enable Ignore Range Checks to unlock manual entry
  await toggleMode(page, 'Ignore Range Checks')

  // Select MANUALLY_ENTERED from the TYPE state dropdown
  let row = page.locator('tr:has(td:text-is("TYPE"))')
  await row.locator('[data-test=cmd-param-select]').click({ force: true })
  await page.getByRole('option', { name: 'MANUALLY_ENTERED' }).click()
  // Manual entry is hazardous so it's highlighted in yellow
  await expect(row.locator('.v-autocomplete__selection-text')).toHaveCSS(
    'color',
    'rgb(255, 220, 0)',
  )

  // Enter a raw numeric value in the manual entry text field
  await expect(
    row.locator('[data-test=cmd-param-value] input').first(),
  ).toBeEditable()
  await row.locator('[data-test=cmd-param-value] input').first().fill('0')
  await row.locator('[data-test=cmd-param-value] input').first().press('Enter')

  // Ignoring range checks makes every command hazardous
  await sendHazardousCmd(
    page,
    'Warning: Command INST COLLECT is considered Hazardous because range checks are ignored. Send?',
  )
  await checkSent(
    page,
    'cmd_no_range_check("INST COLLECT with TYPE 0, DURATION 1, OPCODE 171, TEMP 0")',
  )

  // Disable Ignore Range Checks and verify MANUALLY_ENTERED option is gone
  await toggleMode(page, 'Ignore Range Checks')

  // The TYPE dropdown should no longer have MANUALLY_ENTERED
  await row.locator('[data-test=cmd-param-select]').click({ force: true })
  await expect(
    page.getByRole('option', { name: 'MANUALLY_ENTERED' }),
  ).not.toBeVisible()
  // Close the dropdown by pressing Escape
  await page.keyboard.press('Escape')
})

// The navigation and the tool are separate Vue apps, and Vue numbers useId()
// per app. Duplicate ids point a field's aria-labelledby at the other app's
// label, so the field gets the wrong accessible name.
test('navigation ids do not collide with the tool', async ({ page }) => {
  await expect(commandLine(page)).toBeVisible()
  // Opening a navigation menu renders it with a generated id
  await page.locator('[data-test="user-menu"]').click()
  const menu = page.locator('.v-menu.v-overlay--active')
  await expect(menu).toBeVisible()
  await expect(menu).toHaveAttribute('id', /^v-menu-nav-/)

  // Only the ids Vue generates (e.g. input-v-23, v-menu-nav-5)
  const duplicates = await page.evaluate(() => {
    const ids = [...document.querySelectorAll('[id]')]
      .map((el) => el.id)
      .filter((id) => /(^|-)(v|nav)-\d/.test(id))
    return [...new Set(ids.filter((id, i) => ids.indexOf(id) !== i))]
  })
  expect(duplicates).toEqual([])
  await page.keyboard.press('Escape')
})
