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
import { format, add, sub } from 'date-fns'

test.use({
  toolPath: '/tools/calendar',
  toolName: 'Calendar',
})

async function formatTime(date) {
  return format(date, 'HH:mm:ss')
}

async function formatDate(date) {
  return format(date, 'yyyy-MM-dd')
}

test('file menu', async ({ page, utils }) => {
  await page.locator('[data-test="calendar-file"]').click()
  await page.getByText('Global Environment').click()
  await page.locator('.v-dialog').press('Escape')
  await page.locator('[data-test="calendar-file"]').click()
  await page.getByText('Refresh Display').click()
  await page.locator('[data-test="calendar-file"]').click()
  await page.getByText('Show Table Display').click()
  await page.locator('[data-test="close-event-list"]').click()
  await page.locator('[data-test="calendar-file"]').click()
  await page.getByText('Toggle UTC Display').click()
  await page.locator('[data-test="calendar-file"]').click()
  await utils.sleep(100)
  await utils.download(
    page,
    '[data-test=calendar-file-download-event-list]',
    function (contents) {
      expect(contents).toContain('') // % is empty
    },
  )
})

test('test top bar', async ({ page, utils }) => {
  // test the day calendar view
  await page.locator('[data-test=change-type]').click()
  await page.locator('[data-test=type-day]').click()
  await page.locator('[data-test=prev]').click()
  await page.locator('[data-test=next]').click()
  // test the four day calendar view
  await page.locator('[data-test=change-type]').click()
  await page.locator('[data-test=type-four-day]').click()
  await page.locator('[data-test=prev]').click()
  await page.locator('[data-test=next]').click()
  // test the week calendar view
  await page.locator('[data-test=change-type]').click()
  await page.locator('[data-test=type-week]').click()
  await page.locator('[data-test=prev]').click()
  await page.locator('[data-test=next]').click()
  // test the today button
  await page.locator('[data-test=today]').click()
  // test the mini calendar
  await page.locator('[data-test=mini-prev]').click()
  await page.locator('[data-test=mini-next]').click()
})

test('test create note', async ({ page, utils }) => {
  //
  const stopDateTime = add(new Date(), { minutes: 30 })
  const stopDate = await formatDate(stopDateTime)
  const stopTime = await formatTime(stopDateTime)
  // Click create dropdown
  await page.locator('[data-test=create-event]').click()
  await page.locator('[data-test=note]').click()
  // Fill
  await page.locator('[data-test=note-stop-date]').fill(stopDate)
  await page.locator('[data-test=note-stop-time]').fill(stopTime)
  // step two
  await page.locator('[data-test=create-note-step-two-btn]').click()
  await page
    .locator('[data-test=create-note-description]')
    .fill('Cancel this test')
  await page.locator('[data-test=create-note-cancel-btn]').click()
  // Click create dropdown
  await page.locator('[data-test=create-event]').click()
  await page.locator('[data-test=note]').click()
  // Fill
  await page.locator('[data-test=note-stop-date]').fill(stopDate)
  await page.locator('[data-test=note-stop-time]').fill(stopTime)
  // step two
  await page.locator('[data-test=create-note-step-two-btn]').click()
  await page.locator('[data-test=create-note-description]').click()
  await page.locator('[data-test=create-note-description]').fill('Another test')
  await page.locator('[data-test=create-note-submit-btn]').click()
})

test('test create metadata', async ({ page, utils }) => {
  //
  const startDateTime = sub(new Date(), { minutes: 30 })
  const startDate = await formatDate(startDateTime)
  const startTime = await formatTime(startDateTime)
  // Click create dropdown
  await page.locator('[data-test=create-event]').click()
  await page.locator('[data-test=metadata]').click()
  // Fill
  await page.locator('[data-test=metadata-start-date]').fill(startDate)
  await page.locator('[data-test=metadata-start-time]').fill(startTime)
  // step two
  await page.locator('[data-test=create-metadata-step-two-btn]').click()
  await page.locator('[data-test=new-metadata-icon]').click()
  await page.locator('[data-test=key-0]').fill('version')
  await page.locator('[data-test=value-0]').fill('0')
  await page.locator('[data-test=new-metadata-icon]').click()
  await page.locator('[data-test=key-1]').fill('remove')
  await page.locator('[data-test=value-1]').fill('this')
  await page.locator('[data-test=delete-metadata-icon-1]').click()
  await page.locator('[data-test=create-metadata-cancel-btn]').click()
  // Click create dropdown
  await page.locator('[data-test=create-event]').click()
  await page.locator('[data-test=metadata]').click()
  // Fill
  await page.locator('[data-test=metadata-start-date]').fill(startDate)
  await page.locator('[data-test=metadata-start-time]').fill(startTime)
  // step two
  await page.locator('[data-test=create-metadata-step-two-btn]').click()
  await page.locator('[data-test=new-metadata-icon]').click()
  await page.locator('[data-test=key-0]').fill('version')
  await page.locator('[data-test=value-0]').fill('1')
  await page.locator('[data-test=create-metadata-submit-btn]').click()
})

test('test create timeline', async ({ page, utils }) => {
  await page.locator('[data-test="create-event"]').click()
  await page.locator('[data-test="create-timeline"]').click()
  await page.locator('[data-test="input-timeline-name"]').fill('Alpha')
  await page.locator('[data-test="create-timeline-cancel-btn"]').click()
  await page.locator('[data-test="create-event"]').click()
  await page.locator('[data-test="create-timeline"]').click()
  await page.locator('[data-test="input-timeline-name"]').fill('Alpha')
  await page.locator('[data-test="create-timeline-submit-btn"]').click()
})

test('test create activity', async ({ page, utils }) => {
  const startDateTime = add(new Date(), { minutes: 90 })
  const startDate = await formatDate(startDateTime)
  const startTime = await formatTime(startDateTime)
  const stopDateTime = add(new Date(), { minutes: 95 })
  const stopDate = await formatDate(stopDateTime)
  const stopTime = await formatTime(stopDateTime)
  // click create dropdown
  await page.locator('[data-test=create-event]').click()
  await page.locator('[data-test=activity]').click()
  // v-select timeline
  await page.getByRole('button', { name: /Timeline/ }).click()
  await page.locator('[data-test=activity-select-timeline-Alpha]').click()
  // Fill
  await page.locator('[data-test=activity-start-date]').fill(startDate)
  await page.locator('[data-test=activity-start-time]').fill(startTime)
  await page.locator('[data-test=activity-stop-date]').fill(stopDate)
  await page.locator('[data-test=activity-stop-time]').fill(stopTime)
  // step two
  await page.locator('[data-test=create-activity-step-two-btn]').click()
  // select reserve
  await page.getByRole('button', { name: /Activity Type/ }).click()
  await page.locator('[data-test=activity-select-type-RESERVE]').click()
  // select script
  await page.getByRole('button', { name: /Activity Type/ }).click()
  await page.locator('[data-test=activity-select-type-SCRIPT]').click()
  // input command
  await page.getByRole('button', { name: /Activity Type/ }).click()
  await page.locator('[data-test=activity-select-type-COMMAND]').click()
  await page.locator('[data-test=activity-cmd]').fill('FOO CLEAR')
  await page.locator('[data-test=create-activity-cancel-btn]').click()

  // click create dropdown
  await page.locator('[data-test=create-event]').click()
  await page.locator('[data-test=activity]').click()
  // v-select timeline
  await page.getByRole('button', { name: /Timeline/ }).click()
  await page.locator('[data-test=activity-select-timeline-Alpha]').click()
  // Fill
  await page.locator('[data-test=activity-start-date]').fill(startDate)
  await page.locator('[data-test=activity-start-time]').fill(startTime)
  await page.locator('[data-test=activity-stop-date]').fill(stopDate)
  await page.locator('[data-test=activity-stop-time]').fill(stopTime)
  // step two
  await page.locator('[data-test=create-activity-step-two-btn]').click()
  // input command
  await page.getByRole('button', { name: /Activity Type/ }).click()
  await page.locator('[data-test=activity-select-type-COMMAND]').click()
  await page.locator('[data-test=activity-cmd]').fill('INST CLEAR')
  await page.locator('[data-test=create-activity-submit-btn]').click()
})

test('test timeline select and activity delete', async ({ page, utils }) => {
  await page.locator('strong').filter({ hasText: 'Metadata' }).click()
  await page.locator('[data-test="delete-metadata"]').click()
  await page.locator('[data-test="confirm-dialog-delete"]').click()
  await page.getByRole('button', { name: 'Dismiss' }).click()
  await expect(page.locator('strong:has-text("Metadata")')).not.toBeVisible()
  // Delete the activity
  await page.getByText('Alpha command').click()
  await page.locator('[data-test=delete-activity]').click()
  await page.locator('[data-test="confirm-dialog-delete"]').click()
  await page.getByRole('button', { name: 'Dismiss' }).click()
  await expect(page.getByText('Alpha command')).not.toBeVisible()
  // Delete the note (use nth=0 in case it spans a day)
  await page.locator('text=Another test >> nth=0').click()
  await page.locator('[data-test=delete-note]').click()
  await page.locator('[data-test="confirm-dialog-delete"]').click()
  await page.getByRole('button', { name: 'Dismiss' }).click()
  await expect(page.locator('text=Another test')).not.toBeVisible()
})

test('test delete timeline', async ({ page, utils }) => {
  await page.locator('[data-test=Alpha-options]').click()
  await page.locator('[data-test=Alpha-delete]').click()
  await page.locator('[data-test=confirm-dialog-cancel]').click()

  await page.locator('[data-test=Alpha-options]').click()
  await page.locator('[data-test=Alpha-delete]').click()
  await page.locator('[data-test=confirm-dialog-delete]').click()
})
