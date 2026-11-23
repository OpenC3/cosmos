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

test('finds text on page', async ({ page, utils }) => {
  // Have to fill on an editable area like the textarea
  let string = `openc3 is a command and control system
openc3 can send commands and execute scripts
openc3 is everything I thought it could be`
  await page.locator('textarea').fill(string)
  await page.locator('[data-test=script-runner-edit]').click()
  await page.locator('[data-test=script-runner-edit-find] >> text=Find').click()
  await page.locator('[placeholder="Search for"]').fill('openc3')
  await expect(page.locator('text=1 of 3')).toBeVisible()
  await page.locator('textarea').press('Escape')

  await page.locator('[data-test=script-runner-edit]').click()
  await page
    .locator('[data-test=script-runner-edit-replace] >> text=Replace')
    .click()
  await page.locator('[placeholder="Search for"]').fill('openc3')
  await page.locator('[placeholder="Replace with"]').fill('OpenC3')
  await page.locator('text=All').nth(1).click() // Replace All
  await page.locator('textarea').press('Escape')
  if (process.platform === 'darwin') {
    await page.locator('textarea').press('Meta+F') // Ctrl-S save
  } else {
    await page.locator('textarea').press('Control+F') // Ctrl-S save
  }
  await page.locator('[placeholder="Search for"]').fill('openc3')
  await expect(page.locator('text=1 of 3')).toBeVisible()
  await page.locator('text=Aa').click()
  await expect(page.locator('text=0 of 0')).toBeVisible()
})

test('inserts and edits commands', async ({ page, utils }) => {
  // await page.locator('textarea').click({ button: 'right' })
  await page.locator('.ace_content').click({
    button: 'right',
  })
  await page.getByText('Insert Command').click()
  await utils.selectTargetPacketItem('INST', 'ABORT')
  await page.getByRole('button', { name: 'Insert Command' }).click()

  await page.locator('.ace_content').click({
    button: 'right',
  })
  await page.getByText('Insert Command').click()
  await utils.selectTargetPacketItem('INST', 'COLLECT')
  await page
    .locator('[data-test="cmd-param-select"]')
    .getByRole('combobox')
    .first()
    .click()
  await page.getByRole('option', { name: 'NORMAL' }).click()
  await page.getByRole('button', { name: 'Insert Command' }).click()

  await expect(page.locator('.ace_content')).toContainText(
    'cmd("INST ABORT")\n',
  )
  await expect(page.locator('.ace_content')).toContainText(
    'cmd("INST COLLECT with TYPE \'NORMAL\', DURATION 1, OPCODE 0xAB, TEMP 0")\n',
  )
})

test('edits the parameters of an inserted command', async ({ page, utils }) => {
  // Insert a command with parameters, including a quoted state
  await page.locator('.ace_content').click({ button: 'right' })
  await page.getByText('Insert Command').click()
  await utils.selectTargetPacketItem('INST', 'COLLECT')
  await page
    .locator('[data-test="cmd-param-select"]')
    .getByRole('combobox')
    .first()
    .click()
  await page.getByRole('option', { name: 'SPECIAL' }).click()
  await page
    .locator('tr:has(td:text-is("DURATION")) [data-test=cmd-param-value] input')
    .fill('3')
  await page.getByRole('button', { name: 'Insert Command' }).click()
  await expect(page.locator('.ace_content')).toContainText(
    `cmd("INST COLLECT with TYPE 'SPECIAL', DURATION 3, OPCODE 0xAB, TEMP 0")`,
  )

  // Edit Command loads the line's values back into the dialog, the quoted
  // state included. The menu acts on the cursor's line, which a right click
  // doesn't move, so put the cursor on the command first.
  // (Ace re-renders its lines, so click the content at the first line.)
  const firstLine = { x: 100, y: 8 }
  await page.locator('.ace_content').click({ position: firstLine })
  await page
    .locator('.ace_content')
    .click({ button: 'right', position: firstLine })
  await page.getByText('Edit Command').click()
  await expect(page.locator('[data-test="select-packet"]')).toContainText(
    'COLLECT',
  )
  await expect(
    page.locator('tr:has(td:text-is("TYPE")) [data-test=cmd-param-select]'),
  ).toContainText('SPECIAL')
  await expect(
    page.locator(
      'tr:has(td:text-is("DURATION")) [data-test=cmd-param-value] input',
    ),
  ).toHaveValue('3')

  // Changing a value replaces the line rather than adding another
  await page
    .locator('tr:has(td:text-is("DURATION")) [data-test=cmd-param-value] input')
    .fill('7')
  await page.getByRole('button', { name: 'Insert Command' }).click()
  await expect(page.locator('.ace_content')).toContainText(
    `cmd("INST COLLECT with TYPE 'SPECIAL', DURATION 7, OPCODE 0xAB, TEMP 0")`,
  )
  await expect(page.locator('.ace_content')).not.toContainText('DURATION 3')
})

test('keeps quoted strings with spaces when editing a command', async ({
  page,
  utils,
}) => {
  await page
    .locator('textarea')
    .fill(
      `cmd("INST ASCIICMD with STRING 'NOOP', BINARY 0xDEADBEEF, ASCII 'hello world'")`,
    )
  await page.locator('.ace_content').click({ button: 'right' })
  await page.getByText('Edit Command').click()
  await expect(
    page.locator(
      'tr:has(td:text-is("ASCII")) [data-test=cmd-param-value] input',
    ),
  ).toHaveValue(`'hello world'`)
  await page.getByRole('button', { name: 'Insert Command' }).click()
  // The value was already quoted, so it isn't quoted again ('' hello world '')
  await expect(page.locator('.ace_content')).toContainText(
    `ASCII 'hello world'")`,
  )
  await expect(page.locator('.ace_content')).not.toContainText(`''hello`)
})

test('preserves a trailing comment when editing a command', async ({
  page,
  utils,
}) => {
  // Editing an existing command rebuilds the whole line, so the indentation and
  // any trailing comment have to be carried across to the replacement
  await page.locator('textarea').fill('cmd("INST ABORT")  # keep this comment')
  await page.locator('.ace_content').click({ button: 'right' })
  await page.getByText('Edit Command').click()
  // The dialog loads the existing command before it can be rebuilt
  await expect(page.locator('[data-test="select-target"]')).toContainText(
    'INST',
  )
  await expect(page.locator('[data-test="select-packet"]')).toContainText(
    'ABORT',
  )
  await page.getByRole('button', { name: 'Insert Command' }).click()
  await expect(page.locator('.ace_content')).toContainText(
    'cmd("INST ABORT")  # keep this comment',
  )

  // Changing the command keeps the comment attached to the rebuilt line
  await page.locator('.ace_content').click({ button: 'right' })
  await page.getByText('Edit Command').click()
  await utils.selectTargetPacketItem('INST', 'CLEAR')
  await page.getByRole('button', { name: 'Insert Command' }).click()
  await expect(page.locator('.ace_content')).toContainText(
    'cmd("INST CLEAR")  # keep this comment',
  )
})

test('edits a command on a line with no trailing comment', async ({
  page,
  utils,
}) => {
  await page.locator('textarea').fill('cmd("INST ABORT")')
  await page.locator('.ace_content').click({ button: 'right' })
  await page.getByText('Edit Command').click()
  await utils.selectTargetPacketItem('INST', 'CLEAR')
  await page.getByRole('button', { name: 'Insert Command' }).click()
  await expect(page.locator('.ace_content')).toContainText('cmd("INST CLEAR")')
  // No comment existed, so none is invented
  await expect(page.locator('.ace_content')).not.toContainText('#')
})
