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
# All changes Copyright 2022, OpenC3, Inc.
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
  await expect(page.locator('[data-test=state]')).toHaveValue('waiting', {
    timeout: 20000,
  })
  // Traverse up to get the name of the running script
  const filename = await page
    .locator('[data-test=filename]')
    .locator('xpath=../div')
    .textContent()

  await page.locator('[data-test=cosmos-script-runner-script]').click()
  await page.locator('text="Execution Status"').click()
  await utils.sleep(1000)
  // Each section has a Refresh button so click the first one
  await page.locator('button:has-text("Refresh")').first().click()
  await expect(page.locator('[data-test=running-scripts]')).toContainText(
    format(new Date(), 'yyyy_MM_dd'),
  )

  // Get out of the Running Scripts sheet
  await page
    .locator('#openc3-menu >> text=Script Runner')
    .click({ force: true })
  await page.locator('[data-test=go-button]').click()
  await expect(page.locator('[data-test=state]')).toHaveValue('stopped')
  await page.locator('[data-test=cosmos-script-runner-script]').click()
  await page.locator('text="Execution Status"').click()
  await utils.sleep(1000)
  await page.locator('button:has-text("Refresh")').first().click()
  await expect(page.locator('[data-test=running-scripts]')).not.toContainText(
    filename,
  )
  await page.locator('button:has-text("Refresh")').nth(1).click()
  await expect(page.locator('[data-test=completed-scripts]')).toContainText(
    filename,
  )
})

test('sets environment variables', async ({ page, utils }) => {
  await page.locator('textarea').fill(`puts ENV.inspect`)
  await page.locator('[data-test=cosmos-script-runner-script]').click()
  await page.locator('text=Global Environment').click()
  await page.locator('[data-test=env-key]').fill('KEY')
  await page.locator('[data-test=env-value]').fill('VALUE')
  await page.locator('[data-test=add-env]').click()
  await page.locator('[data-test=env-key]').fill('USER')
  await page.locator('[data-test=env-value]').fill('RYAN')
  await page.locator('[data-test=add-env]').click()
  await page.locator('.v-dialog').press('Escape')

  await page.locator('[data-test="env-button"]').click()
  await page.locator('[data-test="new-metadata-icon"]').click()
  await page.locator('[data-test="key-0"]').fill('USER')
  await page.locator('[data-test="value-0"]').fill('JASON')
  await page.locator('[data-test="environment-dialog-save"]').click()

  await page.locator('[data-test=start-button]').click()
  await expect(page.locator('[data-test=state]')).toHaveValue('Connecting...', {
    timeout: 5000,
  })
  await expect(page.locator('[data-test=state]')).toHaveValue('stopped', {
    timeout: 20000,
  })
  await expect(page.locator('[data-test=output-messages]')).toContainText(
    '"KEY"=>"VALUE"',
  )
  await expect(page.locator('[data-test=output-messages]')).toContainText(
    '"USER"=>"JASON"', // JASON not RYAN because it was overriden locally
  )
  await page.locator('[data-test=clear-log]').click()
  await page.locator('button:has-text("Clear")').click()

  // Clear the local override
  await page.locator('[data-test="env-button"]').click()
  await page.locator('[data-test="remove-env-icon-0"]').click()
  await page.locator('[data-test="environment-dialog-save"]').click()

  // Re-run and verify the global is output
  await page.locator('[data-test=start-button]').click()
  await expect(page.locator('[data-test=state]')).toHaveValue('Connecting...', {
    timeout: 5000,
  })
  await expect(page.locator('[data-test=state]')).toHaveValue('stopped', {
    timeout: 20000,
  })
  await expect(page.locator('[data-test=output-messages]')).toContainText(
    '"KEY"=>"VALUE"',
  )
  await expect(page.locator('[data-test=output-messages]')).toContainText(
    '"USER"=>"RYAN"',
  )

  // Clear the globals
  await page.locator('[data-test=cosmos-script-runner-script]').click()
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

test('sets and gets stash', async ({ page, utils }) => {
  await page.locator('[data-test=cosmos-script-runner-file]').click()
  await page.locator('text=Open File').click()
  await utils.sleep(1000)
  await page.locator('[data-test=file-open-save-search]').type('st')
  await utils.sleep(500)
  await page.locator('[data-test=file-open-save-search]').type('ash')
  await page.locator('text=stash >> nth=0').click() // nth=0 because INST, INST2
  await page.locator('[data-test=file-open-save-submit-btn]').click()
  await page.locator('[data-test=start-button]').click()
  await expect(page.locator('[data-test=state]')).toHaveValue('Connecting...', {
    timeout: 5000,
  })
  await expect(page.locator('[data-test=state]')).toHaveValue('stopped', {
    timeout: 20000,
  })
})

// Note: For local testing you can clear metadata
// Go to the Admin / Redis tab and enter the following:
//   Persistent: zremrangebyscore DEFAULT__METADATA -inf +inf
test('sets metadata', async ({ page, utils }) => {
  await page.locator('[data-test=cosmos-script-runner-file]').click()
  await page.locator('text=Open File').click()
  await utils.sleep(1000)
  await page.locator('[data-test=file-open-save-search]').type('meta')
  await utils.sleep(500)
  await page.locator('[data-test=file-open-save-search]').type('data')
  await page.locator('text=metadata >> nth=0').click() // nth=0 because INST, INST2
  await page.locator('[data-test=file-open-save-submit-btn]').click()
  await expect(page.locator('.v-dialog')).not.toBeVisible()
  await utils.sleep(500)

  // Check for potential "Someone else is editing this script"
  // This can happen if we had to do a retry on this test
  const someone = page.getByText(
    'Someone else is editing this script. Editor is in read-only mode',
  )
  if (await someone.isVisible()) {
    await page.locator('[data-test="unlock-button"]').click()
    await page.locator('[data-test="confirm-dialog-force unlock"]').click()
  }

  await page.locator('[data-test=cosmos-script-runner-script]').click()
  await page
    .locator('[data-test="cosmos-script-runner-script-metadata"]')
    .click()
  await expect(page.locator('.v-dialog')).toBeVisible()
  // Delete any existing metadata so we start fresh
  while (true) {
    if (await page.$('[data-test=delete-event]')) {
      await page.locator('[data-test=delete-event] >> nth=0').click()
      await page.locator('[data-test=confirm-dialog-delete]').click()
      await utils.sleep(300)
    } else {
      break
    }
  }
  await page.locator('[data-test="new-event"]').click()
  await page.locator('[data-test="create-metadata-step-two-btn"]').click()
  await page.locator('[data-test="new-metadata-icon"]').click()
  await page.locator('[data-test="key-0"]').fill('metakey')
  await page.locator('[data-test="value-0"]').fill('metaval')
  await page.locator('[data-test="create-metadata-submit-btn"]').click()
  await page.locator('[data-test="close-event-list"]').click()

  await page.locator('[data-test=start-button]').click()
  await expect(page.locator('.v-dialog')).toBeVisible({
    timeout: 20000,
  })
  await page.locator('[data-test="new-event"]').click()
  await page.locator('[data-test="create-metadata-step-two-btn"]').click()
  await page.locator('[data-test="new-metadata-icon"]').click()
  await page.locator('[data-test="key-0"]').fill('inputkey')
  await page.locator('[data-test="value-0"]').fill('inputvalue')
  await page.locator('[data-test="create-metadata-submit-btn"]').click()
  await page.locator('[data-test="close-event-list"]').click()

  await expect(page.locator('[data-test=state]')).toHaveValue('stopped', {
    timeout: 20000,
  })
  await expect(page.locator('[data-test=output-messages]')).toContainText(
    '"setkey"=>1',
  )
  await expect(page.locator('[data-test=output-messages]')).toContainText(
    '"setkey"=>2',
  )
  await expect(page.locator('[data-test=output-messages]')).toContainText(
    '"updatekey"=>3',
  )
  await expect(page.locator('[data-test=output-messages]')).toContainText(
    '"inputkey"=>"inputvalue"',
  )
})

test('show overrides', async ({ page, utils }) => {
  await page.locator('textarea').fill(`
  set_tlm("INST HEALTH_STATUS COLLECTS = 5")
  override_tlm("INST HEALTH_STATUS COLLECTS = 10")
  override_tlm("INST", "HEALTH_STATUS", "DURATION", "10", type: :CONVERTED)
  `)
  await page.locator('[data-test=start-button]').click()
  await expect(page.locator('[data-test=state]')).toHaveValue('Connecting...', {
    timeout: 5000,
  })
  await expect(page.locator('[data-test=state]')).toHaveValue('stopped', {
    timeout: 20000,
  })
  // Run twice to view the overrides in the output messages
  await page.locator('[data-test=start-button]').click()
  await expect(page.locator('[data-test=state]')).toHaveValue('Connecting...', {
    timeout: 5000,
  })
  await expect(page.locator('[data-test=state]')).toHaveValue('stopped', {
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

  await page.locator('[data-test=cosmos-script-runner-script]').click()
  await page
    .locator('[data-test="cosmos-script-runner-script-overrides"]')
    .click()
  await expect(page.locator('.v-dialog >> tbody > tr')).toHaveCount(5)
  await expect(page.locator('.v-dialog >> tbody > tr').nth(0)).toContainText(
    'INSTHEALTH_STATUSCOLLECTSRAW10',
  )
  await expect(page.locator('.v-dialog >> tbody > tr').nth(1)).toContainText(
    'INSTHEALTH_STATUSCOLLECTSCONVERTED10',
  )
  await expect(page.locator('.v-dialog >> tbody > tr').nth(2)).toContainText(
    'INSTHEALTH_STATUSCOLLECTSFORMATTED10',
  )
  await expect(page.locator('.v-dialog >> tbody > tr').nth(3)).toContainText(
    'INSTHEALTH_STATUSCOLLECTSWITH_UNITS10',
  )
  await expect(page.locator('.v-dialog >> tbody > tr').nth(4)).toContainText(
    'INSTHEALTH_STATUSDURATIONCONVERTED10',
  )
  // Click the delete button on the first item
  await page.locator('.v-dialog >> tbody > tr >> nth=0 >> button').click()
  await expect(page.locator('.v-dialog >> tbody > tr')).toHaveCount(4)
  // Clear all overrides
  await page.locator('[data-test=overrides-dialog-clear-all]').click()
  await expect(
    page.getByRole('cell', { name: 'No data available' }),
  ).toBeVisible()
  await page.locator('[data-test=overrides-dialog-ok]').click()
  await expect(page.locator('.v-dialog')).not.toBeVisible()
})

test('syntax check', async ({ page, utils }) => {
  await page.locator('textarea').fill('puts "TEST"')
  await page.locator('[data-test=cosmos-script-runner-script]').click()
  await page.locator('text=Syntax Check').click()
  await expect(page.locator('.v-dialog')).toContainText('Syntax OK')
  await page.locator('.v-dialog >> button').click()

  await page.locator('textarea').fill(`
  puts "MORE"
  if true
  puts "TRUE"
  `)
  await page.locator('[data-test=cosmos-script-runner-script]').click()
  await page.locator('text=Syntax Check').click()
  await expect(page.locator('.v-dialog')).toContainText('syntax error')
  await page.locator('.v-dialog >> button').click()
})

test('mnemonic check', async ({ page, utils }) => {
  await page.locator('textarea').fill(`
  cmd("INST ABORT")
  `)
  await page.locator('[data-test=cosmos-script-runner-script]').click()
  await page.locator('text=Mnemonic Check').click()
  await expect(page.locator('.v-dialog')).toContainText(
    'Everything looks good!',
  )
  await page.locator('button:has-text("Ok")').click()

  await page.locator('textarea').fill(`
  cmd("BLAH ABORT")
  cmd("INST ABORT with ANGER")
  `)
  await page.locator('[data-test=cosmos-script-runner-script]').click()
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
  await page.locator('[data-test=cosmos-script-runner-script]').click()
  await page.locator('text=Instrumented Script').click()
  await expect(page.locator('.v-dialog')).toContainText('binding')
  await page.locator('button:has-text("Ok")').click()
})

// Remaining menu items tested in other cosmos-script-runner tests
