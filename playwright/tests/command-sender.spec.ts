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
# All changes Copyright 2023, OpenC3, Inc.
# All Rights Reserved
*/

// @ts-check
import { test, expect } from './fixture'

test.use({
  toolPath: '/tools/cmdsender',
  toolName: 'Command Sender',
})

// Helper function to select a parameter dropdown
async function selectValue(page, param, value) {
  let row = page.locator(`tr:has-text("${param}")`)
  await row.getByRole('button').click()
  await page.getByRole('option', { name: value }).click()
}

// Helper function to set parameter value
async function setValue(page, param, value) {
  await page
    .locator(`tr:has-text("${param}") [data-test=cmd-param-value]`)
    .first()
    .fill(value)
  // Trigger the update handler that sets the drop down by pressing Enter
  await page
    .locator(`tr:has-text("${param}") [data-test=cmd-param-value]`)
    .first()
    .press('Enter')
  await checkValue(page, param, value)
}

// Helper function to check parameter value
async function checkValue(page, param, value) {
  expect(
    await page.inputValue(
      `tr:has-text("${param}") [data-test=cmd-param-value]`,
    ),
  ).toMatch(value)
}

// Helper function to check command history
async function checkHistory(page, value) {
  await page
    .locator('[data-test=sender-history] div')
    .filter({ hasText: value })
}

//
// Test the basic functionality of the application
//
test('selects a target and packet', async ({ page, utils }) => {
  await utils.selectTargetPacketItem('INST', 'ABORT')
  await page.locator('[data-test="select-send"]').click()
  await expect(page.locator('main')).toContainText('cmd("INST ABORT") sent')
  // Test the autocomplete by typing in a command
  await page.locator('[data-test=select-packet] input[type="text"]').fill('COL')
  await page.locator('span:has-text("COL")').click()
  await expect(page.locator('main')).toContainText('Starts a collect')
})

test('displays INST COLLECT using the route', async ({ page, utils }) => {
  await page.goto('/tools/cmdsender/INST/COLLECT')
  await utils.inputValue(page, '[data-test=select-target] input', 'INST')
  await utils.inputValue(page, '[data-test=select-packet] input', 'COLLECT')
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

test('supports manually entered state values', async ({ page, utils }) => {
  await utils.selectTargetPacketItem('INST', 'COLLECT')
  await setValue(page, 'TYPE', '3')
  // Typing in the state value should automatically switch the state
  await expect(page.locator('tr:has-text("TYPE")')).toContainText(
    'MANUALLY ENTERED',
  )

  // Manually typing in an existing state value should change the state drop down
  await setValue(page, 'TYPE', '0x0')
  await expect(page.locator('tr:has-text("TYPE")')).toContainText('NORMAL')
  await setValue(page, 'TYPE', '1')
  await expect(page.locator('tr:has-text("TYPE")')).toContainText('SPECIAL')
  // Switch back to MANUALLY ENTERED
  await selectValue(page, 'TYPE', 'MANUALLY ENTERED')
  await setValue(page, 'TYPE', '3')
  await page.locator('[data-test="select-send"]').click()
  await expect(page.locator('main')).toContainText(
    'cmd("INST COLLECT with TYPE 3, DURATION 1, OPCODE 171, TEMP 0") sent',
  )
  await checkHistory(
    page,
    'cmd("INST COLLECT with TYPE 3, DURATION 1, OPCODE 171, TEMP 0")',
  )
})

test('warns for hazardous commands', async ({ page, utils }) => {
  await utils.selectTargetPacketItem('INST', 'CLEAR')
  await expect(page.locator('main')).toContainText('Clears counters')
  await page.locator('[data-test="select-send"]').click()
  await page.getByRole('button', { name: 'Cancel' }).click()
  await expect(page.locator('main')).toContainText('Hazardous command not sent')
  await page.locator('[data-test="select-send"]').click()
  await page.getByRole('dialog').getByRole('button', { name: 'Send' }).click()
  await expect(page.locator('main')).toContainText('cmd("INST CLEAR") sent')
  await checkHistory(page, 'cmd("INST CLEAR")')

  // Disable range checks to confirm history output
  await page.locator('[data-test=command-sender-mode]').click()
  await page.locator('text=Ignore Range Checks').click()

  await page.locator('[data-test="select-send"]').click()
  await page.getByRole('dialog').getByRole('button', { name: 'Send' }).click()
  await expect(page.locator('main')).toContainText(
    'cmd_no_range_check("INST CLEAR") sent',
  )
  await checkHistory(page, 'cmd_no_range_check("INST CLEAR")')

  // Disable parameter conversions to confirm history output
  await page.locator('[data-test=command-sender-mode]').click()
  await page.locator('text=Disable Parameter').click()

  await page.locator('[data-test="select-send"]').click()
  await page.getByRole('dialog').getByRole('button', { name: 'Send' }).click()
  await expect(page.locator('main')).toContainText(
    'cmd_raw_no_range_check("INST CLEAR") sent',
  )
  await checkHistory(page, 'cmd_raw_no_range_check("INST CLEAR")')

  // Enable range checks to confirm history output
  await page.locator('[data-test=command-sender-mode]').click()
  await page.locator('text=Ignore Range Checks').click()

  await page.locator('[data-test="select-send"]').click()
  await page.getByRole('dialog').getByRole('button', { name: 'Send' }).click()
  await expect(page.locator('main')).toContainText('cmd_raw("INST CLEAR") sent')
  await checkHistory(page, 'cmd_raw("INST CLEAR")')
})

test('warns for required parameters', async ({ page, utils }) => {
  await utils.selectTargetPacketItem('INST', 'COLLECT')
  await page.locator('[data-test="select-send"]').click()
  // Break apart the checks so we have output flexibily in the future
  await expect(page.locator('.v-dialog')).toContainText('Error sending')
  await expect(page.locator('.v-dialog')).toContainText('INST COLLECT TYPE')
  await expect(page.locator('.v-dialog')).toContainText('not in valid range')
  await page.locator('button:has-text("Ok")').click()
})

test('warns for hazardous parameters', async ({ page, utils }) => {
  await utils.selectTargetPacketItem('INST', 'COLLECT')
  await selectValue(page, 'TYPE', 'SPECIAL')
  await page.locator('[data-test="select-send"]').click()
  await page.getByRole('button', { name: 'Cancel' }).click()
  await expect(page.locator('main')).toContainText('Hazardous command not sent')
  await page.locator('[data-test="select-send"]').click()
  await page.getByRole('dialog').getByRole('button', { name: 'Send' }).click()
  // Ensure the state is used, e.g. 'SPECIAL' and not the value
  await expect(page.locator('main')).toContainText(
    'cmd("INST COLLECT with TYPE \'SPECIAL\', DURATION 1, OPCODE 171, TEMP 0") sent',
  )
  await checkHistory(
    page,
    'cmd("INST COLLECT with TYPE \'SPECIAL\', DURATION 1, OPCODE 171, TEMP 0")',
  )
})

test('handles float values and scientific notation', async ({
  page,
  utils,
}) => {
  await utils.selectTargetPacketItem('INST', 'FLTCMD')
  await setValue(page, 'FLOAT32', '123.456')
  await setValue(page, 'FLOAT64', '12e3')
  await page.locator('[data-test="select-send"]').click()
  await expect(page.locator('main')).toContainText(
    'cmd("INST FLTCMD with FLOAT32 123.456, FLOAT64 12000") sent',
  )
  await checkHistory(
    page,
    'cmd("INST FLTCMD with FLOAT32 123.456, FLOAT64 12000")',
  )
})

test('handles NaN and Infinite values', async ({ page, utils }) => {
  await utils.selectTargetPacketItem('INST', 'FLTCMD')
  await setValue(page, 'FLOAT32', 'NAN')
  await setValue(page, 'FLOAT64', 'nan')
  await page.locator('[data-test="select-send"]').click()
  // Dialog should pop up with error
  await expect(page.locator('.v-dialog')).toContainText('not in valid range')
  await page.locator('button:has-text("Ok")').click()
  // Disable range checks
  await page.locator('[data-test=command-sender-mode]').click()
  await page.locator('text=Ignore Range Checks').click()
  await page.locator('[data-test="select-send"]').click()

  await expect(page.locator('main')).toContainText(
    'cmd_no_range_check("INST FLTCMD with FLOAT32 NaN, FLOAT64 NaN") sent',
  )
  await checkHistory(
    page,
    'cmd_no_range_check("INST FLTCMD with FLOAT32 NaN, FLOAT64 NaN")',
  )

  await setValue(page, 'FLOAT32', 'INFINITY')
  await setValue(page, 'FLOAT64', '-infinity')
  await page.locator('[data-test="select-send"]').click()
  await expect(page.locator('main')).toContainText(
    'cmd_no_range_check("INST FLTCMD with FLOAT32 Infinity, FLOAT64 -Infinity") sent',
  )
  await checkHistory(
    page,
    'cmd_no_range_check("INST FLTCMD with FLOAT32 Infinity, FLOAT64 -Infinity")',
  )
})

test('handles array values', async ({ page, utils }) => {
  await utils.selectTargetPacketItem('INST', 'ARYCMD')
  await setValue(page, 'ARRAY', '10')
  await page.locator('[data-test="select-send"]').click()
  await expect(page.locator('.v-dialog')).toContainText('must be an Array')
  await page.locator('button:has-text("Ok")').click()
  await setValue(page, 'ARRAY', '[1,2,3,4]')
  await page.locator('[data-test="select-send"]').click()
  await expect(page.locator('main')).toContainText(
    'cmd("INST ARYCMD with ARRAY [ 1, 2, 3, 4 ], CRC 0") sent',
  )
  await checkHistory(
    page,
    'cmd("INST ARYCMD with ARRAY [ 1, 2, 3, 4 ], CRC 0")',
  )
})

test('handles string values', async ({ page, utils }) => {
  await utils.selectTargetPacketItem('INST', 'ASCIICMD')
  await expect(page.locator('main')).toContainText('ASCII command')
  // The default text 'NOOP' should be selected
  let row = page.locator(`tr:has-text("STRING")`)
  await expect(row.getByRole('button')).toContainText('NOOP')
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
  // Enter a custom string
  await setValue(page, 'STRING', 'MY VAL')
  // Enter a custom binary value
  await setValue(page, 'BINARY', '0xBA5EBA11')
  // Typing in the state value should automatically switch the state
  await expect(page.locator('tr:has-text("STRING")').first()).toContainText(
    'MANUALLY ENTERED',
  )
  await page.locator('[data-test="select-send"]').click()
  await expect(page.locator('main')).toContainText(
    "cmd(\"INST ASCIICMD with STRING 'MY VAL', BINARY 0xBA5EBA11, ASCII '0xDEADBEEF'\")",
  )
  // Manually typing in an existing state value should change the state drop down
  await setValue(page, 'STRING', 'FIRE LASER')
  await expect(
    page.locator('div[role=button]:has-text("FIRE LASER")'),
  ).toBeVisible()
})

test('gets details with right click', async ({ page, utils }) => {
  await utils.selectTargetPacketItem('INST', 'COLLECT')
  await page.locator('text=Collect type').click({ button: 'right' })
  await page.locator('text=Details').click()
  await expect(page.locator('.v-dialog')).toContainText('INST COLLECT TYPE')
  await page.locator('.v-dialog').press('Escape')
  await expect(page.locator('.v-dialog')).not.toBeVisible()
})

test('executes commands from history', async ({ page, utils }) => {
  await utils.selectTargetPacketItem('INST', 'CLEAR')
  await page.locator('[data-test="select-send"]').click()
  await page.getByRole('dialog').getByRole('button', { name: 'Send' }).click()
  await expect(page.locator('main')).toContainText('cmd("INST CLEAR") sent')
  await checkHistory(page, 'cmd("INST CLEAR")')
  // Re-execute the command from the history
  await page.locator('[data-test=sender-history]').click()
  await page.locator('[data-test=sender-history]').press('ArrowUp')
  await page.locator('[data-test=sender-history]').press('Enter')
  await page.getByRole('dialog').getByRole('button', { name: 'Send' }).click()
  // Now history says it was sent twice (2)
  await expect(page.locator('main')).toContainText(
    'cmd("INST CLEAR") sent. (2)',
  )
  await page.locator('[data-test=sender-history]').click()
  await page.locator('[data-test=sender-history]').press('ArrowUp')
  await page.locator('[data-test=sender-history]').press('Enter')
  await page.getByRole('dialog').getByRole('button', { name: 'Send' }).click()
  // Now history says it was sent three times (3)
  await expect(page.locator('main')).toContainText(
    'cmd("INST CLEAR") sent. (3)',
  )

  // Send a different command: INST SETPARAMS
  await utils.selectTargetPacketItem('INST', 'SETPARAMS')
  await page.locator('[data-test="select-send"]').click()
  await expect(page.locator('main')).toContainText(
    'cmd("INST SETPARAMS with VALUE1 1, VALUE2 1, VALUE3 1, VALUE4 1, VALUE5 1") sent.',
  )
  // History should now contain both commands
  await checkHistory(page, 'cmd("INST CLEAR")')
  await checkHistory(
    page,
    'cmd("INST SETPARAMS with VALUE1 1, VALUE2 1, VALUE3 1, VALUE4 1, VALUE5 1")',
  )
  // Re-execute command
  await page.locator('[data-test=sender-history]').click()
  await page.locator('[data-test=sender-history]').press('ArrowUp')
  await page.locator('[data-test=sender-history]').press('Enter')
  await expect(page.locator('main')).toContainText(
    'cmd("INST SETPARAMS with VALUE1 1, VALUE2 1, VALUE3 1, VALUE4 1, VALUE5 1") sent. (2)',
  )
  // Edit the existing SETPARAMS command and then send
  // This is somewhat fragile but not sure how else to edit
  await page.locator('[data-test=sender-history]').click()
  await page.locator('[data-test=sender-history]').press('ArrowUp')
  await page.locator('[data-test=sender-history]').press('End')
  await page.locator('[data-test=sender-history]').press('ArrowLeft')
  await page.locator('[data-test=sender-history]').press('ArrowLeft')
  await page.locator('[data-test=sender-history]').press('Backspace')
  await page.locator('[data-test=sender-history]').type('5')
  await page.locator('[data-test=sender-history]').press('Enter')
  await expect(page.locator('main')).toContainText(
    'cmd("INST SETPARAMS with VALUE1 1, VALUE2 1, VALUE3 1, VALUE4 1, VALUE5 5") sent.',
  )
  // History should now contain CLEAR and both SETPARAMS commands
  await checkHistory(page, 'cmd("INST CLEAR")')
  await checkHistory(
    page,
    'cmd("INST SETPARAMS with VALUE1 1, VALUE2 1, VALUE3 1, VALUE4 1, VALUE5 1")',
  )
  await checkHistory(
    page,
    'cmd("INST SETPARAMS with VALUE1 1, VALUE2 1, VALUE3 1, VALUE4 1, VALUE5 5")',
  )
})

test('send vs history', async ({ page, utils }) => {
  await utils.selectTargetPacketItem('INST', 'ABORT')
  await page.locator('[data-test="select-send"]').click()
  await expect(page.locator('main')).toContainText('cmd("INST ABORT") sent')
  await checkHistory(page, 'cmd("INST ABORT")')
  // Send a different command: INST SETPARAMS
  await utils.selectTargetPacketItem('INST', 'SETPARAMS')
  await page.locator('[data-test="select-send"]').click()
  await expect(page.locator('main')).toContainText(
    'cmd("INST SETPARAMS with VALUE1 1, VALUE2 1, VALUE3 1, VALUE4 1, VALUE5 1") sent.',
  )
  // Re-execute command
  await page.locator('[data-test=sender-history]').click()
  await page.locator('[data-test=sender-history]').press('ArrowDown')
  await page.locator('[data-test=sender-history]').press('Enter')
  await expect(page.locator('main')).toContainText('cmd("INST ABORT") sent')
  // Send command vs Send button
  await page.locator('[data-test="select-send"]').click()
  await expect(page.locator('main')).toContainText(
    'cmd("INST SETPARAMS with VALUE1 1, VALUE2 1, VALUE3 1, VALUE4 1, VALUE5 1") sent.',
  )
})

test('hazardous commands from history', async ({ page, utils }) => {
  await utils.selectTargetPacketItem('INST', 'CLEAR')
  await page.locator('[data-test="select-send"]').click()
  await page.getByRole('dialog').getByRole('button', { name: 'Send' }).click()
  await expect(page.locator('main')).toContainText('cmd("INST CLEAR") sent')
  await checkHistory(page, 'cmd("INST CLEAR")')
  // Send a different command: INST ASCIICMD
  await utils.selectTargetPacketItem('INST', 'ASCIICMD')
  await selectValue(page, 'STRING', 'ARM LASER')
  await checkValue(page, 'STRING', 'ARM LASER')
  await page.locator('[data-test="select-send"]').click()
  await page.getByRole('dialog').getByRole('button', { name: 'Send' }).click()
  await expect(page.locator('main')).toContainText(
    "cmd(\"INST ASCIICMD with STRING 'ARM LASER', BINARY 0xDEADBEEF, ASCII '0xDEADBEEF'\")",
  )
  // Re-execute commands from history
  await page.locator('[data-test=sender-history]').click()
  await page.locator('[data-test=sender-history]').press('ArrowDown')
  await page.locator('[data-test=sender-history]').press('Enter')
  await page.getByRole('dialog').getByRole('button', { name: 'Send' }).click()
  await expect(page.locator('main')).toContainText('cmd("INST CLEAR") sent')
  await page.locator('[data-test=sender-history]').click()
  await page.locator('[data-test=sender-history]').press('Enter')
  await page.getByRole('dialog').getByRole('button', { name: 'Send' }).click()
  await expect(page.locator('main')).toContainText(
    "cmd(\"INST ASCIICMD with STRING 'ARM LASER', BINARY 0xDEADBEEF, ASCII '0xDEADBEEF'\")",
  )
})

//
// Test the Mode menu
//
test('ignores normal range checks', async ({ page, utils }) => {
  await utils.selectTargetPacketItem('INST', 'COLLECT')
  await selectValue(page, 'TYPE', 'NORMAL') // Ensure TYPE is set since its required
  await setValue(page, 'TEMP', '100')
  await page.locator('[data-test="select-send"]').click()
  // Dialog should pop up with error
  await expect(page.locator('.v-dialog')).toContainText('not in valid range')
  await page.locator('button:has-text("Ok")').click()
  // Disable range checks
  await page.locator('[data-test=command-sender-mode]').click()
  await page.locator('text=Ignore Range Checks').click()
  await page.locator('[data-test="select-send"]').click()
  await expect(page.locator('main')).toContainText(
    'cmd_no_range_check("INST COLLECT with TYPE \'NORMAL\', DURATION 1, OPCODE 171, TEMP 100") sent',
  )
  await checkHistory(
    page,
    'cmd_no_range_check("INST COLLECT with TYPE \'NORMAL\', DURATION 1, OPCODE 171, TEMP 100")',
  )
})

test('ignores hazardous range checks', async ({ page, utils }) => {
  await utils.selectTargetPacketItem('INST', 'COLLECT')
  await selectValue(page, 'TYPE', 'SPECIAL') // Special is hazardous
  await setValue(page, 'TEMP', '100')
  await page.locator('[data-test="select-send"]').click()
  await page.getByRole('dialog').getByRole('button', { name: 'Send' }).click() // Hazardous confirm
  // Dialog should pop up with error
  await expect(page.locator('.v-dialog:has-text("Error")')).toContainText(
    'not in valid range',
  )
  await page.locator('button:has-text("Ok")').click()
  // Disable range checks
  await page.locator('[data-test=command-sender-mode]').click()
  await page.locator('text=Ignore Range Checks').click()
  await page.locator('[data-test="select-send"]').click()
  await page.getByRole('dialog').getByRole('button', { name: 'Send' }).click() // Hazardous confirm
  await expect(page.locator('main')).toContainText(
    'cmd_no_range_check("INST COLLECT with TYPE \'SPECIAL\', DURATION 1, OPCODE 171, TEMP 100") sent',
  )
  await checkHistory(
    page,
    'cmd_no_range_check("INST COLLECT with TYPE \'SPECIAL\', DURATION 1, OPCODE 171, TEMP 100")',
  )
})

test('displays state values in hex', async ({ page, utils }) => {
  await utils.selectTargetPacketItem('INST', 'COLLECT')
  await selectValue(page, 'TYPE', 'NORMAL') // Ensure TYPE is set since its required
  await checkValue(page, 'TYPE', '0')
  await page.locator('[data-test=command-sender-mode]').click()
  await page.locator('text=Display State').click()
  await checkValue(page, 'TYPE', '0x0')
})

test('shows ignored parameters', async ({ page, utils }) => {
  await utils.selectTargetPacketItem('INST', 'ABORT')
  // All the ABORT parameters are ignored so the table shouldn't appear
  await expect(page.locator('main')).not.toContainText('Parameters')
  await page.locator('[data-test=command-sender-mode]').click()
  await page.locator('text=Show Ignored').click()
  await expect(page.locator('main')).toContainText('Parameters') // Now the parameters table is shown
  await expect(page.locator('main')).toContainText('CCSDSVER') // CCSDSVER is one of the parameters
})

// In order to test parameter conversions we have to look at the raw buffer
// Thus we send the INST SET PARAMS command which has a parameter conversion,
// check the raw buffer, then send it with parameter conversions disabled,
// and re-check the raw buffer for a change.
test('disable parameter conversions', async ({ page, utils }) => {
  await utils.selectTargetPacketItem('INST', 'SETPARAMS')
  await page.locator('[data-test="select-send"]').click()
  await page.locator('rux-icon-apps path').click()

  await page.locator('text=Script Runner').click()
  await expect(page.locator('.v-app-bar')).toContainText('Script Runner')
  await page
    .locator('textarea')
    .fill('puts get_cmd_buffer("INST", "SETPARAMS")["buffer"].formatted')
  await page.locator('[data-test=start-button]').click()
  await expect(page.locator('[data-test=state]')).toHaveValue('Connecting...', {
    timeout: 5000,
  })
  await expect(page.locator('[data-test=state]')).toHaveValue('stopped', {
    timeout: 20000,
  })
  await expect(page.locator('[data-test=output-messages]')).toContainText(
    '00000010: 00 02',
  )

  await page.locator('text=Command Sender').click()
  await expect(page.locator('.v-app-bar')).toContainText('Command Sender')
  await page.locator('[data-test=command-sender-mode]').click()
  await page.locator('text=Disable Parameter').click()

  await utils.selectTargetPacketItem('INST', 'SETPARAMS')
  await page.locator('[data-test="select-send"]').click()
  await expect(page.locator('main')).toContainText(
    'cmd_raw("INST SETPARAMS with VALUE1 1, VALUE2 1, VALUE3 1, VALUE4 1, VALUE5 1") sent',
  )
  await checkHistory(
    page,
    'cmd_raw("INST SETPARAMS with VALUE1 1, VALUE2 1, VALUE3 1, VALUE4 1, VALUE5 1")',
  )
  // Disable range checks just to verify the command history 'cmd_raw_no_range_check'
  await page.locator('[data-test=command-sender-mode]').click()
  await page.locator('text=Ignore Range Checks').click()
  await page.locator('[data-test="select-send"]').click()
  await expect(page.locator('main')).toContainText(
    'cmd_raw_no_range_check("INST SETPARAMS with VALUE1 1, VALUE2 1, VALUE3 1, VALUE4 1, VALUE5 1") sent',
  )
  await checkHistory(
    page,
    'cmd_raw_no_range_check("INST SETPARAMS with VALUE1 1, VALUE2 1, VALUE3 1, VALUE4 1, VALUE5 1")',
  )

  await page.locator('text=Script Runner').click()
  await expect(page.locator('.v-app-bar')).toContainText('Script Runner')
  // Should load the previous script so we can just click start
  await page.locator('[data-test=start-button]').click()
  await expect(page.locator('[data-test=state]')).toHaveValue('Connecting...', {
    timeout: 5000,
  })
  await expect(page.locator('[data-test=state]')).toHaveValue('stopped', {
    timeout: 20000,
  })
  await expect(page.locator('[data-test=output-messages]')).toContainText(
    '00000010: 00 01',
  )
})
