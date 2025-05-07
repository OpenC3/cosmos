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
import { format } from 'date-fns'

test.use({
  toolPath: '/tools/scriptrunner',
  toolName: 'Script Runner',
})

test('show started scripts', async ({ page, utils }) => {
  // Have to fill on an editable area like the textarea
  await page.locator('textarea').fill(`
  puts "now we wait"
  wait
  puts "now we're done"
  `)
  // NOTE: We can't check that there are no running scripts because
  // the tests run in parallel and there actually could be running scripts

  // Start the script
  await page.locator('[data-test=start-button]').click()
  await expect(page.locator('[data-test=state] input')).toHaveValue(
    /waiting \d+s/,
    {
      timeout: 20000,
    },
  )
  // Get the name of the running script
  let filename = await page.locator('[data-test=filename] input').inputValue()

  await page.locator('[data-test=script-runner-script]').click()
  await page.getByText('Execution Status').click()
  await utils.sleep(1000)
  // Each section has a Refresh button so click the first one
  await page.getByRole('button', { name: 'Refresh' }).first().click()
  await expect(page.locator('[data-test=running-scripts]')).toContainText(
    format(new Date(), 'yyyy_MM_dd'),
  )

  // Get out of the Running Scripts sheet
  await page.keyboard.press('Escape')
  await page.locator('[data-test=go-button]').click()
  await expect(page.locator('[data-test=state] input')).toHaveValue('stopped')
  await page.locator('[data-test=script-runner-script]').click()
  await page.getByText('Execution Status').click()
  await utils.sleep(1000)
  await page.locator('button:has-text("Refresh")').first().click()
  await expect(page.locator('[data-test=running-scripts]')).not.toContainText(
    filename,
  )
  await page.getByText('Completed Scripts').click()
  await expect(page.locator('[data-test=completed-scripts]')).toContainText(
    filename,
  )
})

test('sets environment variables', async ({ page, utils }) => {
  await page.locator('textarea').fill(`puts ENV.inspect`)
  await page.locator('[data-test=script-runner-script]').click()
  await page.locator('text=Global Environment').click()
  await page.locator('[data-test=env-key] input').fill('KEY')
  await page.locator('[data-test=env-value] input').fill('VALUE')
  await page.locator('[data-test=add-env]').click()
  await page.locator('[data-test=env-key] input').fill('USER')
  await page.locator('[data-test=env-value] input').fill('RYAN')
  await page.locator('[data-test=add-env]').click()
  await page.locator('.v-dialog').press('Escape')

  await page.locator('[data-test="env-button"]').click()
  await page.locator('[data-test="new-metadata-icon"]').click()
  await page.locator('[data-test="key-0"] input').fill('USER')
  await page.locator('[data-test="value-0"] input').fill('JASON')
  await page.locator('[data-test="environment-dialog-save"]').click()

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
    '"KEY"=>"VALUE"',
  )
  await expect(page.locator('[data-test=output-messages]')).toContainText(
    '"USER"=>"JASON"', // JASON not RYAN because it was overridden locally
  )
  await page.locator('[data-test=clear-log]').click()
  await page.locator('button:has-text("Clear")').click()

  // Clear the local override
  await page.locator('[data-test="env-button"]').click()
  await page.locator('[data-test="remove-env-icon-0"]').click()
  await page.locator('[data-test="environment-dialog-save"]').click()

  // Re-run and verify the global is output
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
    '"KEY"=>"VALUE"',
  )
  await expect(page.locator('[data-test=output-messages]')).toContainText(
    '"USER"=>"RYAN"',
  )

  // Clear the globals
  await page.locator('[data-test=script-runner-script]').click()
  await page.locator('text=Global Environment').click()
  await page
    .getByRole('row', { name: 'KEY VALUE' })
    .locator('[data-test="item-delete"]')
    .click()
  await page.locator('[data-test="confirm-dialog-delete"]').click()
  await page
    .getByRole('row', { name: 'USER RYAN' })
    .locator('[data-test="item-delete"]')
    .click()
  await page.locator('[data-test="confirm-dialog-delete"]').click()
})

test('show overrides', async ({ page, utils }) => {
  await page.locator('textarea').fill(`
  set_tlm("INST HEALTH_STATUS COLLECTS = 5")
  override_tlm("INST HEALTH_STATUS COLLECTS = 10")
  override_tlm("INST", "HEALTH_STATUS", "DURATION", "10", type: :CONVERTED)
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
  // Run twice to view the overrides in the output messages
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
    'The following overrides were present',
  )
  await expect(page.locator('[data-test=output-messages]')).toContainText(
    'INST HEALTH_STATUS COLLECTS = 10, type: :RAW',
  )
  await expect(page.locator('[data-test=output-messages]')).toContainText(
    'INST HEALTH_STATUS COLLECTS = 10, type: :CONVERTED',
  )
  await expect(page.locator('[data-test=output-messages]')).toContainText(
    'INST HEALTH_STATUS COLLECTS = 10, type: :FORMATTED',
  )
  await expect(page.locator('[data-test=output-messages]')).toContainText(
    'INST HEALTH_STATUS COLLECTS = 10, type: :WITH_UNITS',
  )
  await expect(page.locator('[data-test=output-messages]')).toContainText(
    'INST HEALTH_STATUS DURATION = 10, type: :CONVERTED',
  )

  await page.locator('[data-test=script-runner-script]').click()
  await page.locator('[data-test="script-runner-script-overrides"]').click()
  await expect(page.locator('.v-dialog >> tbody > tr')).toHaveCount(5)
  await expect(page.locator('.v-dialog >> tbody')).toContainText(
    'INSTHEALTH_STATUSCOLLECTSRAW10',
  )
  await expect(page.locator('.v-dialog >> tbody')).toContainText(
    'INSTHEALTH_STATUSCOLLECTSCONVERTED10',
  )
  await expect(page.locator('.v-dialog >> tbody')).toContainText(
    'INSTHEALTH_STATUSCOLLECTSFORMATTED10',
  )
  await expect(page.locator('.v-dialog >> tbody')).toContainText(
    'INSTHEALTH_STATUSCOLLECTSWITH_UNITS10',
  )
  await expect(page.locator('.v-dialog >> tbody')).toContainText(
    'INSTHEALTH_STATUSDURATIONCONVERTED10',
  )
  await page
    .locator('.v-dialog >> tbody > tr')
    .nth(0)
    .getByRole('button')
    .click()
  await expect(page.locator('.v-dialog >> tbody > tr')).toHaveCount(4)
  // Clear all overrides
  await page.locator('[data-test="overrides-dialog-clear-all"]').click()
  await expect(
    page.getByRole('cell', { name: 'No data available' }),
  ).toBeVisible()
  await page.locator('[data-test=overrides-dialog-ok]').click()
  await expect(page.locator('.v-dialog')).not.toBeVisible()
})

test('syntax check', async ({ page, utils }) => {
  await page.locator('textarea').fill('puts "TEST"')
  await page.locator('[data-test=script-runner-script]').click()
  await page.locator('text=Syntax Check').click()
  await expect(page.locator('.v-dialog')).toContainText('Syntax OK')
  await page.locator('.v-dialog >> button').click()

  await page.locator('textarea').fill(`
  puts "MORE"
  if true
  puts "TRUE"
  `)
  await page.locator('[data-test=script-runner-script]').click()
  await page.locator('text=Syntax Check').click()
  await expect(page.locator('.v-dialog')).toContainText('syntax error')
  await page.locator('.v-dialog >> button').click()
})

test('mnemonic check', async ({ page, utils }) => {
  await page.locator('textarea').fill(`
  cmd("INST ABORT")
  `)
  await page.locator('[data-test=script-runner-script]').click()
  await page.locator('text=Mnemonic Check').click()
  await expect(page.locator('.v-dialog')).toContainText(
    'Everything looks good!',
  )
  await page.locator('button:has-text("Ok")').click()

  await page.locator('textarea').fill(`
  cmd("BLAH ABORT")
  cmd("INST ABORT with ANGER")
  `)
  await page.locator('[data-test=script-runner-script]').click()
  await page.locator('text=Mnemonic Check').click()
  await expect(page.locator('.v-dialog')).toContainText(
    'Target "BLAH" does not exist',
  )
  await expect(page.locator('.v-dialog')).toContainText(
    'Command "INST ABORT" param "ANGER" does not exist',
  )
  await page.locator('button:has-text("Ok")').click()
})

test('view instrumented script', async ({ page, utils }) => {
  await page.locator('textarea').fill('puts "HI"')
  await page.locator('[data-test=script-runner-script]').click()
  await page.locator('text=Instrumented Script').click()
  await expect(page.locator('.v-dialog')).toContainText('binding')
  await page.locator('button:has-text("Ok")').click()
})

// Remaining menu items tested in other cosmos-script-runner tests
