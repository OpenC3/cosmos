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
import { test, expect } from './../fixture'

test.use({
  toolPath: '/tools/scriptrunner',
  toolName: 'Script Runner',
})

test('keeps a debug command history', async ({ page, utils }) => {
  await page.locator('textarea').fill(`
  x = 12345
  wait
  puts "x:#{x}"
  puts "one"
  puts "two"
  `)
  await page.locator('[data-test=start-button]').click()
  await expect(page.locator('[data-test=state] input')).toHaveValue(
    /waiting \d+s/,
    {
      timeout: 20000,
    },
  )
  await page.locator('[data-test=script-runner-script]').click()
  await page.locator('text=Toggle Debug').click()
  await expect(page.locator('[data-test=debug-text]')).toBeVisible()
  await page.locator('[data-test=debug-text]').locator('input').fill('x')
  await page.keyboard.press('Enter')
  await expect(page.locator('[data-test=output-messages]')).toContainText(
    '12345',
  )
  await page
    .locator('[data-test=debug-text]')
    .locator('input')
    .fill('puts "abc123!"')
  await page.keyboard.press('Enter')
  await expect(page.locator('[data-test=output-messages]')).toContainText(
    'abc123!',
  )
  await page
    .locator('[data-test=debug-text]')
    .locator('input')
    .fill('x = 67890')
  await page.keyboard.press('Enter')
  // Test the history
  await page.locator('[data-test=debug-text]').click()
  await page.keyboard.press('ArrowUp')
  expect(await page.inputValue('[data-test=debug-text] input')).toMatch(
    'x = 67890',
  )
  await page.keyboard.press('ArrowUp')
  expect(await page.inputValue('[data-test=debug-text] input')).toMatch(
    'puts "abc123!"',
  )
  await page.keyboard.press('ArrowUp')
  expect(await page.inputValue('[data-test=debug-text] input')).toMatch('x')
  await page.keyboard.press('ArrowUp') // history wraps
  expect(await page.inputValue('[data-test=debug-text] input')).toMatch(
    'x = 67890',
  )
  await page.keyboard.press('ArrowDown')
  expect(await page.inputValue('[data-test=debug-text] input')).toMatch('x')
  await page.keyboard.press('ArrowDown')
  expect(await page.inputValue('[data-test=debug-text] input')).toMatch(
    'puts "abc123!"',
  )
  await page.keyboard.press('ArrowDown')
  expect(await page.inputValue('[data-test=debug-text] input')).toMatch(
    'x = 67890',
  )
  await page.keyboard.press('ArrowDown') // history wraps
  expect(await page.inputValue('[data-test=debug-text] input')).toMatch('x')
  await page.keyboard.press('Escape') // clear the debug
  expect(await page.inputValue('[data-test=debug-text] input')).toMatch('')
  // Step
  await page.locator('[data-test=step-button]').click()
  await expect(page.locator('[data-test=state] input')).toHaveValue(
    /paused \d+s/,
  )
  await page.locator('[data-test=step-button]').click()
  await expect(page.locator('[data-test=state] input')).toHaveValue(
    /paused \d+s/,
  )
  // Go
  await page.locator('[data-test=go-button]').click()
  await expect(page.locator('[data-test=state] input')).toHaveValue('stopped')
  // Verify we were able to change the 'x' variable
  await expect(page.locator('[data-test=output-messages]')).toContainText(
    'x:67890',
  )

  await page.locator('[data-test=script-runner-script]').click()
  await page.locator('text=Toggle Debug').click()
  await expect(page.locator('[data-test=debug-text]')).not.toBeVisible()
})

test('retries failed checks', async ({ page, utils }) => {
  await page.locator('textarea').fill('check_expression("1 == 2")')
  await page.locator('[data-test=start-button]').click()
  await expect(page.locator('[data-test=state] input')).toHaveValue('error', {
    timeout: 20000,
  })
  // Check for the initial check message
  await expect(page.locator('[data-test=output-messages]')).toContainText(
    '1 == 2 is FALSE',
  )
  await page.locator('[data-test=pause-retry-button]').click() // Retry
  // Now we should have two error messages
  await expect(
    page.locator('[data-test=output-messages] td:has-text("1 == 2 is FALSE")'),
  ).toHaveCount(2)
  await expect(page.locator('[data-test=state] input')).toHaveValue('error')
  await page.locator('[data-test=go-button]').click()
  await expect(page.locator('[data-test=state] input')).toHaveValue('stopped')
})

test('displays the call stack', async ({ page, utils }) => {
  // Call Stack is disabled unless a script is running
  await page.locator('[data-test=script-runner-script]').click()
  // NOTE: This doesn't work in playwright 1.21.0 due to unexpected value "false"
  // await expect(page.locator('text=Call Stack')).toBeDisabled()
  // See: https://github.com/microsoft/playwright/issues/13583
  // See: https://github.com/vuetifyjs/vuetify/issues/14968
  // await expect(
  //   page.locator('[data-test=script-runner-script-call-stack]')
  // ).toBeDisabled()
  await expect(
    page.locator('[data-test=script-runner-script-call-stack]'),
  ).toHaveClass(/v-list-item--disabled/)

  await page.locator('textarea').fill(`
  def one
    two()
  end
  def two
    wait
  end
  one()
  `)
  await page.locator('[data-test=start-button]').click()
  await expect(page.locator('[data-test=state] input')).toHaveValue(
    /waiting \d+s/,
    {
      timeout: 20000,
    },
  )
  await page.locator('[data-test=pause-retry-button]').click()
  await expect(page.locator('[data-test=state] input')).toHaveValue(
    /paused \d+s/,
  )

  await page.locator('[data-test=script-runner-script]').click()
  await page.locator('text=Call Stack').click()
  await expect(page.locator('.v-dialog')).toContainText('Call Stack')
  await page.locator('button:has-text("Ok")').click()
  await page.locator('[data-test=stop-button]').click()
  await expect(page.locator('[data-test=state] input')).toHaveValue('stopped')

  await page.locator('[data-test=script-runner-script]').click()
  await expect(
    page.locator('[data-test=script-runner-script-call-stack]'),
  ).toHaveClass(/v-list-item--disabled/)
})

test('displays disconnect icon', async ({ page, utils }) => {
  // Initialize the values so we know what we're comparing against
  await page.locator('textarea').fill(`
  cmd("INST SETPARAMS with VALUE1 0, VALUE2 1, VALUE3 2, VALUE4 1, VALUE5 0")
  `)
  await page.locator('[data-test=start-button]').click()
  await expect(page.locator('[data-test=state] input')).toHaveValue('stopped', {
    timeout: 20000,
  })

  await page.locator('[data-test=script-runner-script]').click()
  await page.locator('text=Toggle Disconnect').click()

  // In Disconnect mode all commands go nowhere, all checks pass,
  // and all waits are immediate (no waiting)
  // Only read-only methods are allowed and tlm methods can take
  // a disconnect kwarg to set a return value
  await page.locator('textarea').fill(`
  cmd("INST SETPARAMS with VALUE1 0")
  set_tlm("INST PARAMS VALUE2 = 0")
  wait_check_expression("1 == 2", 5)
  wait
  wait_check("INST PARAMS VALUE1 == 'BAD'", 5)
  wait_check("INST PARAMS VALUE2 == 'BAD'", 5)
  val = tlm("INST HEALTH_STATUS COLLECTS", disconnect: 100)
  puts "disconnect:#{val}"
  `)

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
  await expect(page.locator('[data-test=output-messages]')).toContainText(
    "CHECK: INST PARAMS VALUE1 == 'BAD' failed",
  )
  await expect(page.locator('[data-test=output-messages]')).toContainText(
    "CHECK: INST PARAMS VALUE2 == 'BAD' success",
  )
  await expect(page.locator('[data-test=output-messages]')).toContainText(
    'disconnect:100',
  )

  await page.locator('[data-test=script-runner-script]').click()
  await page.locator('text=Toggle Disconnect').click()
})

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
  await expect(page.locator('[data-test=state] input')).toHaveValue('stopped', {
    timeout: 20000,
  })
  await expect(page.locator('[data-test=start-button]')).toBeVisible()

  // Disable the breakpoint
  await page.locator('.ace_gutter-cell').nth(2).click({ force: true })
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
})

test('remembers breakpoints and clears all', async ({ page, utils }) => {
  await page.locator('[data-test=script-runner-file]').click()
  await page.locator('text=Open File').click()
  await utils.sleep(1000)
  await page.locator('[data-test=file-open-save-search]').type('checks')
  await page.locator('text=checks >> nth=0').click() // nth=0 because INST, INST2
  await page.locator('[data-test=file-open-save-submit-btn]').click()
  expect(await page.locator('#sr-controls')).toContainText(
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
  expect(await page.locator('#sr-controls')).toContainText(
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
