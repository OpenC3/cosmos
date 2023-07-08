/*
# Copyright 2023 OpenC3, Inc.
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
*/

// @ts-check
import { test, expect } from './fixture'

test.use({
  toolPath: '/tools/autonomic',
  toolName: 'Autonomic',
})

test('test trigger groups', async ({ page, utils }) => {
  await expect(
    page.locator('[data-test="trigger-group"]').locator('..')
  ).toContainText('DEFAULT')
  await page.locator('[data-test="delete-group"]').click()
  await expect(
    page.getByText('DEFAULT trigger group can not be deleted.')
  ).toBeVisible()
  await page.locator('[data-test="add-group"]').click()
  await expect(page.locator('.v-dialog')).toBeVisible()
  await expect(page.getByText('Group name can not be blank.')).toBeVisible()
  await page.locator('[data-test="group-input-name"]').fill('DEFAULT')
  await expect(
    page.getByText('Group name must be unique. Duplicate name found: DEFAULT.')
  ).toBeVisible()
  await page.locator('[data-test="group-input-name"]').fill('TEST_THIS')
  await expect(
    page.getByText('Group name can not contain an underscore.')
  ).toBeVisible()
  await page.locator('[data-test="group-input-name"]').fill('TEST')
  await page.locator('[data-test="group-create-submit-btn"]').click()
  await expect(page.locator('[data-test="log-messages"]')).toContainText(
    'Trigger group TEST was created'
  )
  await expect(
    page.locator('[data-test="trigger-group"]').locator('..')
  ).toContainText('TEST')
})

// This whole thing basically must be run top to bottom starting here
// There a lot of dependencies on previous tests

test('create item value trigger', async ({ page, utils }) => {
  // Create a trigger that will never activate
  await page.locator('[data-test="new-trigger"]').click()
  await page.locator('[data-test="trigger-operand-left-type"]').click()
  await page.getByText('Telemetry Item').click()
  await utils.selectTargetPacketItem('INST', 'HEALTH_STATUS', 'TEMP1')
  await page.locator('[data-test="trigger-create-step-two-btn"]').click()
  await page.locator('[data-test="trigger-create-select-operator"]').click()
  await page.getByRole('option', { name: '>', exact: true }).click()
  await page.locator('[data-test="trigger-create-step-three-btn"]').click()
  await page.locator('[data-test="trigger-operand-right-type"]').click()
  await page.getByRole('option', { name: 'Value' }).click()
  await page.locator('[data-test="trigger-operand-right-float"]').fill('100')
  await page.locator('[data-test="trigger-operand-right-float"]').press('Enter')
  expect(await page.inputValue('[data-test="trigger-create-eval"]')).toMatch(
    'INST HEALTH_STATUS TEMP1 (CONVERTED) > 100'
  )
  await page.locator('[data-test="trigger-create-submit-btn"]').click()
  await expect(page.locator('[data-test="log-messages"]')).toContainText(
    'DEFAULT:TRIG1 (TEMP1 > 100) was created'
  )

  await expect(
    page.locator('[data-test="triggers-table"] >> tr >> nth=1')
  ).toContainText('TRIG1')
  await expect(
    page.locator('[data-test="triggers-table"] >> tr >> nth=1')
  ).toContainText('TEMP1 > 100')
  await expect(
    page.locator(
      '[data-test="triggers-table"] >> tr >> nth=1 >> td >> nth=2 >> i'
    )
  ).not.toHaveClass(/mdi-bell-ring/)
})

test('create command reaction', async ({ page, utils }) => {
  await page.getByRole('tab', { name: 'Reactions' }).click()
  await expect(page).toHaveURL(
    'http://localhost:2900/tools/autonomic/reactions'
  )
  await expect(page.locator('[data-test="new-reaction"]')).toBeEnabled()
  await page.locator('[data-test="new-reaction"]').click()
  await page.getByText('Level Trigger').click() // Default is 'Edge Trigger'
  await page.locator('[data-test="reaction-select-triggers"]').click()
  await page.getByText('DEFAULT: TRIG1').click()
  await page.locator('[data-test="reaction-create-step-two-btn"]').click()
  await utils.sleep(500)
  // await page.getByText('Script').nth(1).click();
  await page.locator('label:has-text("Command")').click()
  // await page.getByText('Notify Only').click();
  await page.locator('[data-test="reaction-action-command"]').fill('INST ABORT')
  await page.locator('[data-test="reaction-notification"]').click()
  await page.getByRole('option', { name: 'serious' }).click()
  await page
    .locator('[data-test="reaction-notify-text"]')
    .fill('INST ABORT was sent')
  await page.locator('[data-test="reaction-create-step-three-btn"]').click()
  await utils.sleep(500)
  await page.locator('[data-test="reaction-snooze-input"]').fill('10')
  await page.locator('[data-test="reaction-create-submit-btn"]').click()
  await expect(
    page.locator('[data-test="reactions-table"] >> tr >> nth=1')
  ).toContainText('REACT1')
  await expect(page.locator('[data-test="log-messages"]')).toContainText(
    'REACT1 was created'
  )
})

test('manually run a reaction', async ({ page, utils }) => {
  await page.getByRole('tab', { name: 'Reactions' }).click()
  await expect(page).toHaveURL(
    'http://localhost:2900/tools/autonomic/reactions'
  )
  await expect(page.locator('[data-test="new-reaction"]')).toBeEnabled()
  // Clear the notification
  await page.getByRole('button', { name: 'Badge' }).click()
  await page.locator('[data-test="clear-notifications"]').click()
  // Click the drop down ... weird name generated by codegen
  await page.getByRole('button', { name: '󰅀' }).click()
  await expect(page.getByText('Actions:')).toBeVisible()
  await page.locator('[data-test="execute-actions"]').click()
  await expect(page.getByText('Executed Reaction')).toBeVisible()
  await page.getByRole('button', { name: 'Dismiss' }).click()
  await expect(page.locator('[data-test="log-messages"]')).toContainText(
    'REACT1 was executed'
  )
  await expect(page.locator('[data-test="log-messages"]')).toContainText(
    'REACT1 ran command: INST ABORT'
  )
  await expect(page.locator('[data-test="log-messages"]')).toContainText(
    'REACT1 ran notify (serious): INST ABORT was sent'
  )
  // Check the notification
  await page.getByRole('button', { name: 'Badge' }).click()
  await expect(page.locator('[data-test="notification-list"]')).toContainText(
    'REACT1 run'
  )
  await expect(page.locator('[data-test="notification-list"]')).toContainText(
    'INST ABORT was sent'
  )
})

test('edit a reaction', async ({ page, utils }) => {
  await page.getByRole('tab', { name: 'Reactions' }).click()
  await expect(page).toHaveURL(
    'http://localhost:2900/tools/autonomic/reactions'
  )
  await page.locator('[data-test="item-edit"]').nth(0).click()
  await expect(page.locator('[data-test="level-trigger"]')).toHaveAttribute(
    'aria-checked',
    'true'
  )
  await expect(page.locator('span:has-text("TRIG1")')).toBeVisible()
  await page.locator('[data-test="reaction-create-step-two-btn"]').click()
  await utils.sleep(500)
  await page
    .locator('[data-test="reaction-action-option-script"]')
    .locator('..') // Can only click on the parent
    .click()
  await page.getByLabel('Select a script').click()
  await page.locator('[data-test="select-script"]').fill('stash')
  await utils.sleep(100)
  await page.getByText('INST/procedures/stash.rb', { exact: true }).click()
  await page.locator('[data-test="reaction-notification"]').click()
  await page.getByRole('option', { name: 'caution' }).click()
  await page
    .locator('[data-test="reaction-notify-text"]')
    .fill('stash script run')
  await page.locator('[data-test="reaction-create-step-three-btn"]').click()
  await page.locator('[data-test="reaction-create-submit-btn"]').click()
  await expect(page.locator('[data-test="log-messages"]')).toContainText(
    'REACT1 was updated'
  )
})

test('edit a trigger', async ({ page, utils }) => {
  await page.locator('[data-test="events-clear"]').click()
  await page.locator('[data-test="confirm-dialog-clear"]').click()

  // Edit and make a trigger that is always active
  await page.locator('[data-test="item-edit"]').nth(0).click()
  await page.locator('[data-test="trigger-create-step-two-btn"]').click()
  await page.getByRole('button', { name: 'Operator >' }).click()
  await page.getByRole('option', { name: '<=' }).click()
  await page.locator('[data-test="trigger-create-step-three-btn"]').click()
  expect(await page.inputValue('[data-test="trigger-create-eval"]')).toMatch(
    'INST HEALTH_STATUS TEMP1 (CONVERTED) <= 100'
  )
  await page.locator('[data-test="trigger-create-submit-btn"]').click()
  await expect(page.locator('[data-test="log-messages"]')).toContainText(
    'DEFAULT:TRIG1 (TEMP1 <= 100) was updated'
  )

  await expect(
    page.locator('[data-test="triggers-table"] >> tr >> nth=1')
  ).toContainText('TRIG1')
  await expect(
    page.locator('[data-test="triggers-table"] >> tr >> nth=1')
  ).toContainText('TEMP1 <= 100')
  await utils.sleep(1000)
  await expect(
    page.locator(
      '[data-test="triggers-table"] >> tr >> nth=1 >> td >> nth=2 >> i'
    )
  ).toHaveClass(/mdi-bell-ring/)
  await expect(page.locator('[data-test="log-messages"]')).toContainText(
    'DEFAULT:TRIG1 (TEMP1 <= 100) is true'
  )
  await expect(page.locator('[data-test="log-messages"]')).toContainText(
    'REACT1 ran script: INST/procedures/stash.rb'
  )
  await expect(page.locator('[data-test="log-messages"]')).toContainText(
    'REACT1 ran notify (caution): stash script run'
  )
})

test('enable & disable a reaction', async ({ page, utils }) => {
  await page.getByRole('tab', { name: 'Reactions' }).click()
  await expect(page).toHaveURL(
    'http://localhost:2900/tools/autonomic/reactions'
  )
  await page.locator('[data-test="reaction-disable"]').click()
  await expect(page.locator('[data-test="log-messages"]')).toContainText(
    'REACT1 was disabled'
  )
  await page.locator('[data-test="events-clear"]').click()
  await page.locator('[data-test="confirm-dialog-clear"]').click()
  await utils.sleep(5000)
  await expect(page.locator('[data-test="log-messages"]')).not.toContainText(
    'REACT1'
  )
  await page.locator('[data-test="reaction-enable"]').click()
  await expect(page.locator('[data-test="log-messages"]')).toContainText(
    'REACT1 was enabled'
  )
  await expect(page.locator('[data-test="log-messages"]')).toContainText(
    'REACT1 ran script: INST/procedures/stash.rb'
  )
})

test('enable & disable a trigger', async ({ page, utils }) => {
  await page.locator('[data-test="trigger-disable"]').nth(0).click()
  await expect(page.locator('[data-test="log-messages"]')).toContainText(
    'DEFAULT:TRIG1 (TEMP1 <= 100) was disabled'
  )
  // Disabling the trigger sets the state to false
  await expect(
    page.locator(
      '[data-test="triggers-table"] >> tr >> nth=1 >> td >> nth=2 >> i'
    )
  ).not.toHaveClass(/mdi-bell-ring/)
  await page.locator('[data-test="events-clear"]').click()
  await page.locator('[data-test="confirm-dialog-clear"]').click()
  await utils.sleep(5000)
  await page.locator('[data-test="trigger-enable"]').click()
  await expect(
    page.locator(
      '[data-test="triggers-table"] >> tr >> nth=1 >> td >> nth=2 >> i'
    )
  ).toHaveClass(/mdi-bell-ring/)
  await expect(page.locator('[data-test="log-messages"]')).toContainText(
    'DEFAULT:TRIG1 (TEMP1 <= 100) was enabled'
  )
  await expect(page.locator('[data-test="log-messages"]')).toContainText(
    'DEFAULT:TRIG1 (TEMP1 <= 100) is true'
  )
  await expect(page.locator('[data-test="log-messages"]')).toContainText(
    'REACT1 ran script: INST/procedures/stash.rb'
  )
  await expect(page.locator('[data-test="log-messages"]')).toContainText(
    'REACT1 ran notify (caution): stash script run'
  )
})

test('create item state trigger', async ({ page, utils }) => {
  await page.locator('[data-test="new-trigger"]').click()
  await page.locator('[data-test="trigger-operand-left-type"]').click()
  await page.getByText('Telemetry Item').click()
  await utils.selectTargetPacketItem('INST', 'HEALTH_STATUS', 'TEMP1')
  await page.locator('[data-test="trigger-create-step-two-btn"]').click()
  await page.locator('[data-test="trigger-create-select-operator"]').click()
  await page.getByRole('option', { name: '==' }).click()
  await page.locator('[data-test="trigger-create-step-three-btn"]').click()
  await page.locator('[data-test="trigger-operand-right-type"]').click()
  await page.getByRole('option', { name: 'Limits State' }).click()
  await page.locator('[data-test="trigger-operand-right-limit"]').click()
  await page.getByRole('option', { name: 'RED_HIGH (Limit)' }).click()
  expect(await page.inputValue('[data-test="trigger-create-eval"]')).toMatch(
    'INST HEALTH_STATUS TEMP1 (CONVERTED) == RED_HIGH'
  )
  await page.locator('[data-test="trigger-create-submit-btn"]').click()
  await expect(page.locator('[data-test="log-messages"]')).toContainText(
    'DEFAULT:TRIG2 (TEMP1 == RED_HIGH) was created'
  )

  await expect(
    page.locator('[data-test="triggers-table"] >> tr >> nth=2')
  ).toContainText('TRIG2')
  await expect(
    page.locator('[data-test="triggers-table"] >> tr >> nth=2')
  ).toContainText('TEMP1 == RED_HIGH')
  await expect(page.locator('[data-test="log-messages"]')).toContainText(
    'DEFAULT:TRIG2 (TEMP1 == RED_HIGH) is true',
    { timeout: 120000 } // Takes 1:15 to full cyle but worst case is about 1:10 for outside RED_HIGH
  )

  // Edit it to ensure the fields are populated correctly and we can change
  await page.locator('[data-test="item-edit"]').nth(1).click()
  await page.locator('[data-test="trigger-create-step-two-btn"]').click()
  await page.locator('[data-test="trigger-create-step-three-btn"]').click()
  await page.locator('[data-test="trigger-operand-right-limit"]').click()
  await page.getByRole('option', { name: 'RED_LOW (Limit)' }).click()
  expect(await page.inputValue('[data-test="trigger-create-eval"]')).toMatch(
    'INST HEALTH_STATUS TEMP1 (CONVERTED) == RED_LOW'
  )
  await page.locator('[data-test="trigger-create-submit-btn"]').click()
  await expect(page.locator('[data-test="log-messages"]')).toContainText(
    'DEFAULT:TRIG2 (TEMP1 == RED_LOW) was updated'
  )
  await expect(
    page.locator('[data-test="triggers-table"] >> tr >> nth=2')
  ).toContainText('TEMP1 == RED_LOW')
})

test('create item change trigger', async ({ page, utils }) => {
  await page.locator('[data-test="new-trigger"]').click()
  await page.locator('[data-test="trigger-operand-left-type"]').click()
  await page.getByText('Telemetry Item').click()
  await utils.selectTargetPacketItem('INST', 'HEALTH_STATUS', 'CCSDSVER')
  await page.locator('[data-test="trigger-create-step-two-btn"]').click()
  await page.locator('[data-test="trigger-create-select-operator"]').click()
  await page.getByRole('option', { name: 'DOES NOT CHANGE' }).click()
  await page.locator('[data-test="trigger-create-step-three-btn"]').click()
  expect(await page.inputValue('[data-test="trigger-create-eval"]')).toMatch(
    'INST HEALTH_STATUS CCSDSVER (CONVERTED) DOES NOT CHANGE'
  )
  await page.locator('[data-test="trigger-create-submit-btn"]').click()
  await expect(page.locator('[data-test="log-messages"]')).toContainText(
    'DEFAULT:TRIG3 (CCSDSVER DOES NOT CHANGE) was created'
  )

  await expect(
    page.locator('[data-test="triggers-table"] >> tr >> nth=3')
  ).toContainText('TRIG3')
  await expect(
    page.locator('[data-test="triggers-table"] >> tr >> nth=3')
  ).toContainText('CCSDSVER DOES NOT CHANGE')
  await expect(page.locator('[data-test="log-messages"]')).toContainText(
    'DEFAULT:TRIG3 (CCSDSVER DOES NOT CHANGE) is true'
  )

  // Edit it to ensure the fields are populated correctly and we can change
  await page.locator('[data-test="item-edit"]').nth(2).click()
  await page.locator('[data-test="trigger-create-step-two-btn"]').click()
  await page.locator('[data-test="trigger-create-select-operator"]').click()
  await page.getByRole('option', { name: 'CHANGES' }).click()
  await page.locator('[data-test="trigger-create-step-three-btn"]').click()
  expect(await page.inputValue('[data-test="trigger-create-eval"]')).toMatch(
    'INST HEALTH_STATUS CCSDSVER (CONVERTED) CHANGES'
  )
  await page.locator('[data-test="trigger-create-submit-btn"]').click()
  await expect(page.locator('[data-test="log-messages"]')).toContainText(
    'DEFAULT:TRIG3 (CCSDSVER CHANGES) was updated'
  )
  await expect(
    page.locator('[data-test="triggers-table"] >> tr >> nth=3')
  ).toContainText('CCSDSVER CHANGES')
})

test('create item string trigger', async ({ page, utils }) => {
  await page.locator('[data-test="new-trigger"]').click()
  await page.locator('[data-test="trigger-operand-left-type"]').click()
  await page.getByText('Telemetry Item').click()
  await page.getByLabel('Select Target').click()
  await page.getByRole('option', { name: 'INST', exact: true }).click()
  await page.getByLabel('Select Packet').click()
  await page.getByRole('option', { name: 'HEALTH_STATUS' }).click()
  await page.getByLabel('Select Item').fill('gr')
  await utils.sleep(100)
  await page.getByRole('option', { name: 'GROUND2STATUS' }).click()
  await page.locator('[data-test="trigger-create-step-two-btn"]').click()
  await page.locator('[data-test="trigger-create-select-operator"]').click()
  await page.getByRole('option', { name: '!=' }).click()
  await page.locator('[data-test="trigger-create-step-three-btn"]').click()
  await page.locator('[data-test="trigger-operand-right-type"]').click()
  await page.getByRole('option', { name: 'String' }).click()
  await page
    .locator('[data-test="trigger-operand-right-string"]')
    .fill('CONNECTED')
  await page
    .locator('[data-test="trigger-operand-right-string"]')
    .press('Enter')
  expect(await page.inputValue('[data-test="trigger-create-eval"]')).toMatch(
    'INST HEALTH_STATUS GROUND2STATUS (CONVERTED) != CONNECTED'
  )
  await page.locator('[data-test="trigger-create-submit-btn"]').click()
  await expect(page.locator('[data-test="log-messages"]')).toContainText(
    'DEFAULT:TRIG4 (GROUND2STATUS != CONNECTED) was created'
  )

  await expect(
    page.locator('[data-test="triggers-table"] >> tr >> nth=4')
  ).toContainText('TRIG4')
  await expect(
    page.locator('[data-test="triggers-table"] >> tr >> nth=4')
  ).toContainText('GROUND2STATUS != CONNECTED')
  await expect(page.locator('[data-test="log-messages"]')).toContainText(
    'DEFAULT:TRIG4 (GROUND2STATUS != CONNECTED) is true',
    { timeout: 15000 } // 5s cycle
  )

  // Edit it to ensure the fields are populated correctly and we can change
  await page.locator('[data-test="item-edit"]').nth(3).click()
  await page.locator('[data-test="trigger-create-step-two-btn"]').click()
  await page.locator('[data-test="trigger-create-step-three-btn"]').click()
  await page
    .locator('[data-test="trigger-operand-right-string"]')
    .fill('UNAVAILABLE')
  await page
    .locator('[data-test="trigger-operand-right-string"]')
    .press('Enter')
  expect(await page.inputValue('[data-test="trigger-create-eval"]')).toMatch(
    'INST HEALTH_STATUS GROUND2STATUS (CONVERTED) != UNAVAILABLE'
  )
  await page.locator('[data-test="trigger-create-submit-btn"]').click()
  await expect(page.locator('[data-test="log-messages"]')).toContainText(
    'DEFAULT:TRIG4 (GROUND2STATUS != UNAVAILABLE) was updated'
  )
  await expect(
    page.locator('[data-test="triggers-table"] >> tr >> nth=4')
  ).toContainText('GROUND2STATUS != UNAVAILABLE')
})

test('create item regex trigger', async ({ page, utils }) => {
  // Put this in the TEST group
  await page.getByRole('button', { name: 'Group DEFAULT' }).click()
  await page.getByRole('option', { name: 'TEST' }).click()

  await page.locator('[data-test="new-trigger"]').click()
  await page.locator('[data-test="trigger-operand-left-type"]').click()
  await page.getByText('Telemetry Item').click()
  await utils.selectTargetPacketItem('INST', 'HEALTH_STATUS', 'ASCIICMD')
  await page.locator('[data-test="trigger-create-step-two-btn"]').click()
  await page.locator('[data-test="trigger-create-select-operator"]').click()
  await page.getByRole('option', { name: '==' }).click()
  await page.locator('[data-test="trigger-create-step-three-btn"]').click()
  await page.locator('[data-test="trigger-operand-right-type"]').click()
  await page.getByRole('option', { name: 'Regular Expression' }).click()
  await page
    .locator('[data-test="trigger-operand-right-regex"]')
    .fill('\\d\\d.*')
  await page.locator('[data-test="trigger-operand-right-regex"]').press('Enter')
  expect(await page.inputValue('[data-test="trigger-create-eval"]')).toMatch(
    'INST HEALTH_STATUS ASCIICMD (CONVERTED) == \\d\\d.*'
  )
  await page.locator('[data-test="trigger-create-submit-btn"]').click()
  await expect(page.locator('[data-test="log-messages"]')).toContainText(
    'TEST:TRIG1 (ASCIICMD == \\d\\d.*) was created'
  )

  await expect(
    page.locator('[data-test="triggers-table"] >> tr >> nth=1')
  ).toContainText('TRIG1')
  await expect(
    page.locator('[data-test="triggers-table"] >> tr >> nth=1')
  ).toContainText('ASCIICMD == \\d\\d.*')

  await page.goto('/tools/cmdsender/INST/ASCIICMD')
  await page
    .locator(`tr:has-text("STRING") [data-test=cmd-param-value]`)
    .first()
    .fill('12TEST')
  await page.locator('[data-test=select-send]').click()
  await page.locator('text=cmd("INST ASCIICMD") sent')

  await page.goto('/tools/autonomic')
  await expect(page.locator('[data-test="log-messages"]')).toContainText(
    'TEST:TRIG1 (ASCIICMD == \\d\\d.*) is true'
  )

  await page.goto('/tools/cmdsender/INST/ASCIICMD')
  await page
    .locator(`tr:has-text("STRING") [data-test=cmd-param-value]`)
    .first()
    .fill('TEST')
  await page.locator('[data-test=select-send]').click()
  await page.locator('text=cmd("INST ASCIICMD") sent')

  await page.goto('/tools/autonomic')
  await expect(page.locator('[data-test="log-messages"]')).toContainText(
    'TEST:TRIG1 (ASCIICMD == \\d\\d.*) is false'
  )

  // Edit it to ensure the fields are populated correctly and we can change
  await page.locator('[data-test="item-edit"]').nth(0).click()
  await page.locator('[data-test="trigger-create-step-two-btn"]').click()
  await page.locator('[data-test="trigger-create-step-three-btn"]').click()
  await page.locator('[data-test="trigger-operand-right-regex"]').fill('*')
  await page.locator('[data-test="trigger-operand-right-regex"]').press('Enter')
  expect(await page.inputValue('[data-test="trigger-create-eval"]')).toMatch(
    'INST HEALTH_STATUS ASCIICMD (CONVERTED) == *'
  )
  await page.locator('[data-test="trigger-create-submit-btn"]').click()
  await expect(page.locator('[data-test="log-messages"]')).toContainText(
    'TEST:TRIG1 (ASCIICMD == *) was updated'
  )
  await expect(page.locator('[data-test="log-messages"]')).toContainText(
    'TEST:TRIG1 (ASCIICMD == *) was disabled'
  )
  await expect(
    page.locator('[data-test="triggers-table"] >> tr >> nth=1')
  ).toContainText('ASCIICMD == *')
})

test('create item dependent trigger', async ({ page, utils }) => {
  await page.locator('[data-test="new-trigger"]').click()
  await page.locator('[data-test="trigger-operand-left-type"]').click()
  await page.getByText('Existing Trigger').click()
  await page.locator('[data-test="trigger-operand-left-trigger"]').click()
  await page.getByRole('option', { name: 'TRIG1 (TEMP1 <= 100)' }).click()
  await page.locator('[data-test="trigger-create-step-two-btn"]').click()
  await page.locator('[data-test="trigger-create-select-operator"]').click()
  await page.getByRole('option', { name: 'AND' }).click()
  await page.locator('[data-test="trigger-create-step-three-btn"]').click()
  await page.locator('[data-test="trigger-operand-right-trigger"]').click()
  await page
    .getByRole('option', { name: 'TRIG4 (GROUND2STATUS != UNAVAILABLE)' })
    .click()
  expect(await page.inputValue('[data-test="trigger-create-eval"]')).toMatch(
    'TRIG1 (TEMP1 <= 100) AND TRIG4 (GROUND2STATUS != UNAVAILABLE)'
  )
  await page.locator('[data-test="trigger-create-submit-btn"]').click()
  await expect(page.locator('[data-test="log-messages"]')).toContainText(
    'DEFAULT:TRIG5 (TRIG1 AND TRIG4) was created'
  )

  await expect(
    page.locator('[data-test="triggers-table"] >> tr >> nth=5')
  ).toContainText('TRIG5')
  await expect(
    page.locator('[data-test="triggers-table"] >> tr >> nth=5')
  ).toContainText('(TEMP1 <= 100) AND (GROUND2STATUS != UNAVAILABLE)')

  await expect(page.locator('[data-test="log-messages"]')).toContainText(
    'DEFAULT:TRIG5 (TRIG1 AND TRIG4) is true',
    { timeout: 15000 } // 5s cycle
  )

  // Edit it to ensure the fields are populated correctly and we can change
  await page.locator('[data-test="item-edit"]').nth(4).click()
  await page.locator('[data-test="trigger-create-step-two-btn"]').click()
  await page.locator('[data-test="trigger-create-select-operator"]').click()
  await page.getByRole('option', { name: 'OR' }).click()
  await page.locator('[data-test="trigger-create-step-three-btn"]').click()
  expect(await page.inputValue('[data-test="trigger-create-eval"]')).toMatch(
    'TRIG1 (TEMP1 <= 100) OR TRIG4 (GROUND2STATUS != UNAVAILABLE)'
  )
  await page.locator('[data-test="trigger-create-submit-btn"]').click()
  await expect(page.locator('[data-test="log-messages"]')).toContainText(
    'DEFAULT:TRIG5 (TRIG1 OR TRIG4) was updated'
  )
  await expect(
    page.locator('[data-test="triggers-table"] >> tr >> nth=5')
  ).toContainText('(TEMP1 <= 100) OR (GROUND2STATUS != UNAVAILABLE)')
})

test('download triggers', async ({ page, utils }) => {
  await utils.download(
    page,
    '[data-test="trigger-download"]',
    function (contents) {
      expect(contents).toContain('TRIG1')
      expect(contents).toContain('TRIG2')
      expect(contents).toContain('TRIG3')
      expect(contents).toContain('TRIG4')
      expect(contents).toContain('TRIG5')
    }
  )
})

test('delete a trigger dependent trigger', async ({ page, utils }) => {
  await expect
    .poll(() => page.locator('[data-test="item-delete"]').count())
    .toBe(5)
  await page.locator('[data-test="item-delete"]').nth(3).click() // 4th item
  await page.locator('[data-test="confirm-dialog-delete"]').click()
  await expect(
    page.getByText(
      'Failed to delete DEFAULT:TRIG4 due to DEFAULT:TRIG4 has dependents: ["TRIG5"]'
    )
  ).toBeVisible()
})

test('create notification reaction', async ({ page, utils }) => {
  await page.getByRole('tab', { name: 'Reactions' }).click()
  await expect(page).toHaveURL(
    'http://localhost:2900/tools/autonomic/reactions'
  )
  await expect(page.locator('[data-test="new-reaction"]')).toBeEnabled()
  await page.locator('[data-test="new-reaction"]').click()
  await page.locator('[data-test="reaction-select-triggers"]').click()
  await page.getByText('DEFAULT: TRIG3').click()
  await page.locator('[data-test="reaction-select-triggers"]').click()
  await page.getByText('DEFAULT: TRIG4').click()
  await page.locator('[data-test="reaction-select-triggers"]').click()
  await page.getByText('DEFAULT: TRIG5').click()
  await page.locator('[data-test="reaction-create-remove-trigger-2"]').click()
  await page.locator('[data-test="reaction-create-step-two-btn"]').click()
  await utils.sleep(500)
  await page.getByText('Notify Only').click()
  await page.locator('[data-test="reaction-notification"]').click()
  await page.getByText('normal', { exact: true }).click()
  await page.locator('[data-test="reaction-notify-text"]').fill('Normal event')
  await page.locator('[data-test="reaction-create-step-three-btn"]').click()
  await utils.sleep(500)
  await page.locator('[data-test="reaction-snooze-input"]').fill('60')
  await page.locator('[data-test="reaction-create-submit-btn"]').click()
  await expect(
    page.locator('[data-test="reactions-table"] >> tr >> nth=2')
  ).toContainText('REACT2')
  await expect(page.locator('[data-test="log-messages"]')).toContainText(
    'REACT2 was created'
  )
})

test('download reactions', async ({ page, utils }) => {
  await page.getByRole('tab', { name: 'Reactions' }).click()
  await expect(page).toHaveURL(
    'http://localhost:2900/tools/autonomic/reactions'
  )
  await expect(page.locator('[data-test="new-reaction"]')).toBeEnabled()
  await utils.download(
    page,
    '[data-test="reaction-download"]',
    function (contents) {
      expect(contents).toContain('REACT1')
      expect(contents).toContain('REACT2')
    }
  )
})

test('delete a trigger', async ({ page, utils }) => {
  await expect
    .poll(() => page.locator('[data-test="item-delete"]').count())
    .toBe(5)
  await expect(
    page.locator('[data-test="triggers-table"] >> tr >> nth=5')
  ).toContainText('TRIG5')
  await page.locator('[data-test="item-delete"]').nth(4).click()
  await page.locator('[data-test="confirm-dialog-cancel"]').click()
  await expect(
    page.locator('[data-test="triggers-table"] >> tr >> nth=5')
  ).toContainText('TRIG5')

  await page.locator('[data-test="item-delete"]').nth(4).click()
  await page.locator('[data-test="confirm-dialog-delete"]').click()
  await expect(page.getByText('Deleted Trigger')).toBeVisible()

  await expect(page.locator('[data-test="triggers-table"]')).not.toContainText(
    'TRIG5'
  )
  await expect(page.locator('[data-test="log-messages"]')).toContainText(
    'DEFAULT:TRIG5 (TRIG1 OR TRIG4) was deleted'
  )
})

test('delete a reaction dependent trigger', async ({ page, utils }) => {
  await page.locator('[data-test="item-delete"]').nth(0).click()
  await page.locator('[data-test="confirm-dialog-delete"]').click()
  await expect(
    page.getByText(
      'Failed to delete DEFAULT:TRIG1 due to DEFAULT:TRIG1 has dependents: ["REACT1"]'
    )
  ).toBeVisible()
})

test('delete a reaction', async ({ page, utils }) => {
  await page.getByRole('tab', { name: 'Reactions' }).click()
  await page.locator('[data-test="item-delete"]').nth(0).click()
  await page.locator('[data-test="confirm-dialog-cancel"]').click()
  await expect(page.locator('[data-test="reactions-table"]')).toContainText(
    'REACT1'
  )
  await page.locator('[data-test="item-delete"]').nth(0).click()
  await page.locator('[data-test="confirm-dialog-delete"]').click()
  await expect(page.getByText('Deleted Reaction')).toBeVisible()
  await page.getByRole('button', { name: 'Dismiss' }).click()
  await expect(page.locator('[data-test="log-messages"]')).toContainText(
    'REACT1 was deleted'
  )

  // Now try to delete the reaction dependent trigger
  await page.getByRole('tab', { name: 'Triggers' }).click()
  await page.locator('[data-test="item-delete"]').nth(0).click()
  await page.locator('[data-test="confirm-dialog-delete"]').click()
  await expect(page.getByText('Deleted Trigger')).toBeVisible()
  await page.getByRole('button', { name: 'Dismiss' }).click()

  await expect(page.locator('[data-test="triggers-table"]')).not.toContainText(
    'TRIG1'
  )
  await expect(page.locator('[data-test="log-messages"]')).toContainText(
    'DEFAULT:TRIG1 (TEMP1 <= 100) was deleted'
  )
})

test('delete trigger group', async ({ page, utils }) => {
  await page.getByRole('button', { name: 'Group DEFAULT' }).click()
  await page.getByRole('option', { name: 'TEST' }).click()

  await page.locator('[data-test="item-delete"]').nth(0).click()
  await page.locator('[data-test="confirm-dialog-delete"]').click()

  await page.locator('[data-test="delete-group"]').click()
  await page.locator('[data-test="group-delete-submit-btn"]').click()
  await page.locator('[data-test="confirm-dialog-delete"]').click()
  await expect(page.getByText('Deleted TriggerGroup')).toBeVisible()
  await expect(page.locator('[data-test="log-messages"]')).toContainText(
    'Trigger group TEST was deleted'
  )
})

test('event table', async ({ page, utils }) => {
  await page.locator('[data-test="pause"]').click() // pause
  await page.locator('[data-test="filter-type"]').click()
  await page.getByRole('option', { name: 'TRIGGER' }).click()
  await expect
    .poll(() => page.locator('[data-test="log-messages"] >> tr').count())
    .toBe(2) // Header plus No data available
  await page.locator('[data-test="pause"]').click() // resume
  await expect(page.locator('[data-test="log-messages"]')).toContainText(
    'TRIGGER'
  )
  await expect(page.locator('[data-test="log-messages"]')).not.toContainText(
    'REACTION'
  )
  await expect(page.locator('[data-test="log-messages"]')).not.toContainText(
    'GROUP'
  )
  const [download] = await Promise.all([
    page.waitForEvent('download'),
    page.locator('[data-test="events-download"]').click(),
  ])
  await page.locator('[data-test="filter-type"]').click()
  await page.getByRole('option', { name: 'REACTION' }).click()
  await expect(page.locator('[data-test="log-messages"]')).toContainText(
    'REACTION'
  )
  await expect(page.locator('[data-test="log-messages"]')).not.toContainText(
    'TRIGGER'
  )
  await expect(page.locator('[data-test="log-messages"]')).not.toContainText(
    'GROUP'
  )
  await page.locator('[data-test="filter-type"]').click()
  await page.getByRole('option', { name: 'GROUP' }).click()
  await expect(page.locator('[data-test="log-messages"]')).toContainText(
    'GROUP'
  )
  await expect(page.locator('[data-test="log-messages"]')).not.toContainText(
    'REACTION'
  )
  await expect(page.locator('[data-test="log-messages"]')).not.toContainText(
    'TRIGGER'
  )
  await page.locator('[data-test="filter-type"]').click()
  await page.getByRole('option', { name: 'ALL' }).click()
  await page.locator('[data-test="search-log-messages"]').fill('TRIG3')
  await expect
    .poll(() => page.locator('[data-test="log-messages"] >> tr').count())
    .toBeLessThan(10)
  await page.locator('[data-test="search-log-messages"]').fill('')
  await expect
    .poll(() => page.locator('[data-test="log-messages"] >> tr').count())
    .toBeGreaterThan(20)
  await page.locator('[data-test="events-clear"]').click()
  await page.locator('[data-test="confirm-dialog-cancel"]').click()
  await expect
    .poll(() => page.locator('[data-test="log-messages"] >> tr').count())
    .toBeGreaterThan(20)
  await page.locator('[data-test="events-clear"]').click()
  await page.locator('[data-test="confirm-dialog-clear"]').click()
  await expect
    .poll(() => page.locator('[data-test="log-messages"] >> tr').count())
    .toBeLessThan(10)
})
