/*
# Copyright 2024 OpenC3, Inc.
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
import {
  format,
  sub,
  parse,
  addSeconds,
  addMinutes,
  subMinutes,
  isWithinInterval,
} from 'date-fns'

test.beforeEach(async ({ page }) => {
  // Ensure local time
  await page.goto('/tools/admin/settings')
  await expect(page.locator('.v-app-bar')).toContainText('Administrator')
  await page.locator('[data-test=time-zone]').click()
  await page.getByRole('option', { name: 'local' }).click()
  await page.locator('[data-test="save-time-zone"]').click()
})
test.afterAll(async ({ browser }) => {
  let page = await browser.newPage()
  // Ensure local time
  await page.goto('/tools/admin/settings')
  await expect(page.locator('.v-app-bar')).toContainText('Administrator')
  await page.locator('[data-test=time-zone]').click()
  await page.getByRole('option', { name: 'local' }).click()
  await page.locator('[data-test="save-time-zone"]').click()
})

test.describe('CmdTlmServer', () => {
  test.use({
    toolPath: '/tools/cmdtlmserver',
    toolName: 'CmdTlmServer',
  })
  test('displays in local or UTC time', async ({ page, utils }) => {
    // Allow the table to populate
    await expect(page.locator('[data-test=log-messages]')).toContainText('INFO')
    // First row is the header: Index, Name, Value so grab second (1)
    const now = new Date()
    let dateString =
      (
        await page
          .locator('[data-test="log-messages"]')
          .locator('tr')
          .nth(1)
          .locator('td')
          .nth(0)
          .textContent()
      )?.trim() || ''
    let date = parse(dateString, 'yyyy-MM-dd HH:mm:ss.SSS', now)
    expect(
      isWithinInterval(date, {
        start: subMinutes(now, 5),
        end: addMinutes(now, 5),
      }),
    ).toBeTruthy()

    // Switch to UTC
    await page.goto('/tools/admin/settings')
    await expect(page.locator('.v-app-bar')).toContainText('Administrator')
    await page.locator('[data-test=time-zone]').click()
    await page.getByRole('option', { name: 'UTC' }).click()
    await page.locator('[data-test="save-time-zone"]').click()

    await page.goto('/tools/cmdtlmserver')
    await expect(page.locator('.v-app-bar')).toContainText('CmdTlmServer')
    // Allow the table to populate
    await expect(page.locator('[data-test=log-messages]')).toContainText('INFO')
    // First row is the header: Index, Name, Value so grab second (1)
    dateString =
      (
        await page
          .locator('[data-test="log-messages"]')
          .locator('tr')
          .nth(1)
          .locator('td')
          .nth(0)
          .textContent()
      )?.trim() || ''
    // The date is now in UTC but we parse it like it is local time
    date = parse(dateString, 'yyyy-MM-dd HH:mm:ss.SSS', now)
    // so subtrack off the timezone offset to get it back to local time
    date = subMinutes(date, now.getTimezoneOffset())

    expect(
      isWithinInterval(date, {
        start: subMinutes(now, 5),
        end: addMinutes(now, 5),
      }),
    ).toBeTruthy()
  })
})

test.describe('data extractor', () => {
  test.use({
    toolPath: '/tools/dataextractor',
    toolName: 'Data Extractor',
  })

  test('works with UTC date / times', async ({ page, utils }) => {
    let now = new Date()
    // Verify the local date / time
    let startDateString =
      (await page.inputValue('[data-test=start-date] input'))?.trim() || ''
    let startDate = parse(startDateString, 'yyyy-MM-dd', now)
    let startTimeString =
      (await page.inputValue('[data-test=start-time] input'))?.trim() || ''
    let startTime = parse(startTimeString, 'HH:mm:ss', startDate)
    expect(
      isWithinInterval(startTime, {
        // Start time is automatically 1hr in the past
        start: subMinutes(now, 62),
        end: subMinutes(now, 58),
      }),
    ).toBeTruthy()
    let endDateString =
      (await page.inputValue('[data-test=end-date] input'))?.trim() || ''
    let endDate = parse(endDateString, 'yyyy-MM-dd', now)
    let endTimeString =
      (await page.inputValue('[data-test=end-time] input'))?.trim() || ''
    let endTime = parse(endTimeString, 'HH:mm:ss', endDate)
    expect(
      isWithinInterval(endTime, {
        // end time is now
        start: subMinutes(now, 2),
        end: addMinutes(now, 2),
      }),
    ).toBeTruthy()

    // Switch to UTC
    await page.goto('/tools/admin/settings')
    await expect(page.locator('.v-app-bar')).toContainText('Administrator')
    await page.locator('[data-test=time-zone]').click()
    await page.getByRole('option', { name: 'UTC' }).click()
    await page.locator('[data-test="save-time-zone"]').click()

    await page.goto('/tools/dataextractor')
    await expect(page.locator('.v-app-bar')).toContainText('Data Extractor', {
      timeout: 20000,
    })
    await page.locator('rux-icon-apps').getByRole('img').click()
    await expect(page.locator('#openc3-nav-drawer')).not.toBeInViewport()

    now = new Date()
    // add the timezone offset to get it to UTC
    now = addMinutes(now, now.getTimezoneOffset())
    startDateString =
      (await page.inputValue('[data-test=start-date] input'))?.trim() || ''
    startDate = parse(startDateString, 'yyyy-MM-dd', now)
    startTimeString =
      (await page.inputValue('[data-test=start-time] input'))?.trim() || ''
    startTime = parse(startTimeString, 'HH:mm:ss', startDate)
    expect(
      isWithinInterval(startTime, {
        // Start time is automatically 1hr in the past
        start: subMinutes(now, 62),
        end: subMinutes(now, 58),
      }),
    ).toBeTruthy()
    endDateString =
      (await page.inputValue('[data-test=end-date] input'))?.trim() || ''
    endDate = parse(endDateString, 'yyyy-MM-dd', now)
    endTimeString =
      (await page.inputValue('[data-test=end-time] input'))?.trim() || ''
    endTime = parse(endTimeString, 'HH:mm:ss', endDate)
    expect(
      isWithinInterval(endTime, {
        // end time is now
        start: subMinutes(now, 2),
        end: addMinutes(now, 2),
      }),
    ).toBeTruthy()

    const start = sub(startTime, { minutes: 2 })
    await page
      .locator('[data-test=start-time] input')
      .fill(format(start, 'HH:mm:ss'))
    await utils.addTargetPacketItem('INST', 'MECH')

    await utils.download(page, 'text=Process', function (contents) {
      let lines = contents.split('\n')
      expect(lines[0]).toContain('SLRPNL1')
      expect(lines[0]).toContain('SLRPNL2')
      expect(lines[0]).toContain('SLRPNL3')
      expect(lines[0]).toContain('SLRPNL4')
      expect(lines[0]).toContain('SLRPNL5')
      expect(lines[0]).toContain(',') // csv
      expect(lines.length).toBeGreaterThan(60) // 2 min at 60Hz is 120 samples
    })
  })
})

test.describe('Data Viewer UTC', () => {
  test.use({
    toolPath: '/tools/dataviewer',
    toolName: 'Data Viewer',
  })

  test('works with UTC date / times', async ({ page, utils }) => {
    let now = new Date()
    // Verify the local date / time
    let startTimeString =
      (await page.inputValue('[data-test=start-time] input'))?.trim() || ''
    let startTime = parse(startTimeString, 'HH:mm:ss', now)
    expect(
      isWithinInterval(startTime, {
        start: subMinutes(now, 1),
        end: addMinutes(now, 1),
      }),
    ).toBeTruthy()

    // Switch to UTC
    await page.goto('/tools/admin/settings')
    await expect(page.locator('.v-app-bar')).toContainText('Administrator')
    await page.locator('[data-test=time-zone]').click()
    await page.getByRole('option', { name: 'UTC' }).click()
    await page.locator('[data-test="save-time-zone"]').click()

    await page.goto('/tools/dataviewer')
    await expect(page.locator('.v-app-bar')).toContainText('Data Viewer', {
      timeout: 20000,
    })
    await page.locator('rux-icon-apps').getByRole('img').click()
    await expect(page.locator('#openc3-nav-drawer')).not.toBeInViewport()

    now = new Date()
    // The date is now in UTC but we parse it like it is local time
    let startDateString =
      (await page.inputValue('[data-test=start-date] input'))?.trim() || ''
    startTimeString =
      (await page.inputValue('[data-test=start-time] input'))?.trim() || ''
    startTime = parse(
      startDateString + ' ' + startTimeString,
      'yyyy-MM-dd HH:mm:ss',
      now,
    )
    // so subtrack off the timezone offset to get it back to local time
    let localStartTime = subMinutes(startTime, now.getTimezoneOffset())
    expect(
      isWithinInterval(localStartTime, {
        start: subMinutes(now, 1),
        end: addMinutes(now, 1),
      }),
    ).toBeTruthy()

    await page.locator('[data-test=new-tab]').click()
    await utils.selectTargetPacketItem('INST', 'ADCS')
    await page.locator('[data-test=select-send]').click() // add the packet to the list
    await page.locator('[data-test=add-component]').click()
    await page.locator('[data-test=start-button]').click()
    localStartTime = addSeconds(localStartTime, 5)
    // Poll since inputValue is immediate
    await expect
      .poll(async () => {
        return await page
          .locator('[data-test=history-component-text-area]')
          .getByLabel('')
          .inputValue()
      })
      .toContain(
        // Original string is like '2024-08-26T21:23:41.319Z'
        // So we split on ':' to just get the year and hour
        localStartTime.toISOString().split(':').slice(0, 1).join(':'),
      )
  })
})

test.describe('Packet Viewer UTC', () => {
  test.use({
    toolPath: '/tools/packetviewer',
    toolName: 'Packet Viewer',
  })

  test('displays local time and UTC time', async ({ page, utils }) => {
    await utils.selectTargetPacketItem('INST', 'HEALTH_STATUS')
    await expect(page.locator('tbody')).toContainText('PACKET_TIMEFORMATTED')
    await expect(page.locator('tbody')).toContainText('RECEIVED_TIMEFORMATTED')

    let now = new Date()
    let dateTimeString = await page
      .getByRole('cell', { name: 'PACKET_TIMEFORMATTED *' })
      .locator('..')
      .locator('input')
      .inputValue()
    let dateTime = parse(dateTimeString, 'yyyy-MM-dd HH:mm:ss.SSS', now)
    expect(
      isWithinInterval(dateTime, {
        start: subMinutes(now, 1),
        end: addMinutes(now, 1),
      }),
    ).toBeTruthy()
    dateTimeString = await page
      .getByRole('cell', { name: 'RECEIVED_TIMEFORMATTED *' })
      .locator('..')
      .locator('input')
      .inputValue()
    dateTime = parse(dateTimeString, 'yyyy-MM-dd HH:mm:ss.SSS', now)
    expect(
      isWithinInterval(dateTime, {
        start: subMinutes(now, 1),
        end: addMinutes(now, 1),
      }),
    ).toBeTruthy()

    // Switch to UTC
    await page.goto('/tools/admin/settings')
    await expect(page.locator('.v-app-bar')).toContainText('Administrator')
    await page.locator('[data-test=time-zone]').click()
    await page.getByRole('option', { name: 'UTC' }).click()
    await page.locator('[data-test="save-time-zone"]').click()

    await page.goto('/tools/packetviewer/INST/HEALTH_STATUS')
    await expect(page.locator('.v-app-bar')).toContainText('Packet Viewer')
    await expect(page.locator('tbody')).toContainText('PACKET_TIMEFORMATTED')
    await expect(page.locator('tbody')).toContainText('RECEIVED_TIMEFORMATTED')

    await utils.selectTargetPacketItem('INST', 'HEALTH_STATUS')
    now = new Date()
    dateTimeString = await page
      .getByRole('cell', { name: 'PACKET_TIMEFORMATTED *' })
      .locator('..')
      .locator('input')
      .inputValue()
    dateTime = parse(dateTimeString, 'yyyy-MM-dd HH:mm:ss.SSS', now)
    // dateTime is now in UTC so subtract off the timezone offset to get it back to local time
    dateTime = subMinutes(dateTime, now.getTimezoneOffset())
    expect(
      isWithinInterval(dateTime, {
        start: subMinutes(now, 1),
        end: addMinutes(now, 1),
      }),
    ).toBeTruthy()
    dateTimeString = await page
      .getByRole('cell', { name: 'RECEIVED_TIMEFORMATTED *' })
      .locator('..')
      .locator('input')
      .inputValue()
    dateTime = parse(dateTimeString, 'yyyy-MM-dd HH:mm:ss.SSS', now)
    // dateTime is now in UTC so subtrack off the timezone offset to get it back to local time
    dateTime = subMinutes(dateTime, now.getTimezoneOffset())
    expect(
      isWithinInterval(dateTime, {
        start: subMinutes(now, 1),
        end: addMinutes(now, 1),
      }),
    ).toBeTruthy()
  })
})

test.describe('Telemetry Grapher UTC', () => {
  test.use({
    toolPath: '/tools/tlmgrapher',
    toolName: 'Telemetry Grapher',
  })

  test('works with UTC time', async ({ page, utils }) => {
    await page.locator('[data-test="telemetry-grapher-file"]').click()
    await page
      .locator('[data-test="telemetry-grapher-file-reset-configuration"]')
      .click()
    await expect(page.getByText('Add a graph')).toBeVisible()
    await page.locator('[data-test=telemetry-grapher-graph]').click()
    await page.locator('text=Add Graph').click()
    await utils.selectTargetPacketItem('INST', 'HEALTH_STATUS', 'TEMP1')
    await page.locator('button:has-text("Add Item")').click()
    await page.locator('.v-expansion-panel-header').click()
    await utils.sleep(3000) // Wait for graphing to occur
    // We can't check the canvas legend because its a canvas
    await page.locator('#chart0 canvas').click({
      position: { x: 200, y: 100 },
      force: true,
    })
    let now = new Date()
    let dateTimeString =
      (
        await page.locator('.u-legend').locator('td').nth(0).textContent()
      )?.trim() || ''
    let dateTime = parse(dateTimeString, 'yyyy-MM-dd HH:mm:ss.SSS', now)
    expect(
      isWithinInterval(dateTime, {
        start: subMinutes(now, 1),
        end: addMinutes(now, 1),
      }),
    ).toBeTruthy()
    let value = parseFloat(
      (await page.locator('.u-legend').locator('td').nth(1).textContent()) ||
        '',
    )
    expect(value).toBeGreaterThanOrEqual(-100)
    expect(value).toBeLessThanOrEqual(100)

    // Switch to UTC
    await page.goto('/tools/admin/settings')
    await expect(page.locator('.v-app-bar')).toContainText('Administrator')
    await page.locator('[data-test=time-zone]').click()
    await page.getByRole('option', { name: 'UTC' }).click()
    await page.locator('[data-test="save-time-zone"]').click()

    await page.goto('/tools/tlmgrapher')
    await expect(page.locator('.v-app-bar')).toContainText('Telemetry Grapher')
    // This is the expansion panel button
    await page.locator('#innerapp button').first().click()
    await utils.sleep(3000) // Wait for graphing to occur
    await page.locator('#chart0 canvas').click({
      position: { x: 200, y: 100 },
      force: true,
    })
    now = new Date()
    dateTimeString =
      (
        await page.locator('.u-legend').locator('td').nth(0).textContent()
      )?.trim() || ''
    dateTime = parse(dateTimeString, 'yyyy-MM-dd HH:mm:ss.SSS', now)
    // dateTime is now in UTC so subtrack off the timezone offset to get it back to local time
    dateTime = subMinutes(dateTime, now.getTimezoneOffset())
    expect(
      isWithinInterval(dateTime, {
        start: subMinutes(now, 1),
        end: addMinutes(now, 1),
      }),
    ).toBeTruthy()
    value = parseFloat(
      (await page.locator('.u-legend').locator('td').nth(1).textContent()) ||
        '',
    )
    expect(value).toBeGreaterThanOrEqual(-100)
    expect(value).toBeLessThanOrEqual(100)

    // Verify we can stream in data using UTC time
    await page.locator('[data-test=edit-graph-icon]').click()
    await expect(page.locator('.v-dialog')).toContainText('Edit Graph')
    const start = sub(new Date(), { minutes: 2 })
    await page.getByLabel('Start Date').fill(format(start, 'yyyy-MM-dd'))
    await page.getByLabel('Start Time').fill(format(start, 'HH:mm:ss'))
  })
})
