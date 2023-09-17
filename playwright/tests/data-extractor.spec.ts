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
import { test, expect } from './fixture'
import { format, add, sub } from 'date-fns'

test.use({
  toolPath: '/tools/dataextractor',
  toolName: 'Data Extractor',
})

test('loads and saves the configuration', async ({ page, utils }) => {
  await utils.addTargetPacketItem('INST', 'HEALTH_STATUS', 'TEMP1')
  await utils.addTargetPacketItem('INST', 'HEALTH_STATUS', 'TEMP2')

  let config = 'spec' + Math.floor(Math.random() * 10000)
  await page.locator('[data-test=cosmos-data-extractor-file]').click()
  await page.locator('text=Save Configuration').click()
  await page.locator('[data-test=name-input-save-config-dialog]').fill(config)
  await page.locator('button:has-text("Ok")').click()
  // Clear the success toast
  await page.locator('button:has-text("Dismiss")').click()

  await expect(page.locator('tbody > tr')).toHaveCount(2)
  await page.locator('[data-test=delete-all]').click()
  await expect(
    page.getByRole('cell', { name: 'No data available' }),
  ).toBeVisible()

  await page.locator('[data-test=cosmos-data-extractor-file]').click()
  await page.locator('text=Open Configuration').click()
  await page.locator(`td:has-text("${config}")`).click()
  await page.locator('button:has-text("Ok")').click()
  // Clear the success toast
  await page.locator('button:has-text("Dismiss")').click()
  await expect(page.locator('tbody > tr')).toHaveCount(2)

  // Delete this test configuation
  await page.locator('[data-test=cosmos-data-extractor-file]').click()
  await page.locator('text=Open Configuration').click()
  await page.locator(`tr:has-text("${config}") [data-test=item-delete]`).click()
  await page.locator('button:has-text("Delete")').click()
  await page.locator('[data-test=open-config-cancel-btn]').click()
})

test('validates dates and times', async ({ page, utils }) => {
  // Date validation
  const d = new Date()
  await expect(page.locator('text=Required')).not.toBeVisible()
  // await page.locator("[data-test=start-date]").click();
  // await page.keyboard.press('Delete')
  await page.locator('[data-test=start-date]').fill('')
  await expect(page.locator('text=Required')).toBeVisible()
  // Note: Firefox doesn't implement min/max the same way as Chrome
  // Chromium limits you to just putting in the day since it has a min/max value
  // Firefox doesn't apppear to limit at all so you need to enter entire date
  // End result is that in Chromium the date gets entered as the 2 digit year
  // e.g. "22", which is fine because even if you go big it will round down.
  await page.locator('[data-test=start-date]').type(format(d, 'MM'))
  await page.locator('[data-test=start-date]').type(format(d, 'dd'))
  await page.locator('[data-test=start-date]').type(format(d, 'yyyy'))
  await expect(page.locator('text=Required')).not.toBeVisible()
  // Time validation
  await page.locator('[data-test=start-time]').fill('')
  await expect(page.locator('text=Required')).toBeVisible()
  await page.locator('[data-test=start-time]').fill('12:15:15')
  await expect(page.locator('text=Required')).not.toBeVisible()
})

test("won't start with 0 items", async ({ page, utils }) => {
  await expect(page.locator('text=Process')).toBeDisabled()
})

test('warns with duplicate item', async ({ page, utils }) => {
  await utils.addTargetPacketItem('INST', 'HEALTH_STATUS', 'TEMP2')
  await page.locator('[data-test=select-send]').click() // Send again
  await expect(
    page.locator('text=This item has already been added'),
  ).toBeVisible()
})

test('warns with no time delta', async ({ page, utils }) => {
  await utils.addTargetPacketItem('INST', 'HEALTH_STATUS', 'TEMP2')
  await page.locator('text=Process').click()
  await expect(
    page.locator('text=Start date/time is equal to end date/time'),
  ).toBeVisible()
})

test('warns with no data', async ({ page, utils }) => {
  const start = sub(new Date(), { seconds: 10 })
  await page.locator('[data-test=start-time]').fill(format(start, 'HH:mm:ss'))
  await page.locator('label:has-text("Command")').click()
  await utils.sleep(500) // Allow the command to switch
  await utils.addTargetPacketItem('EXAMPLE', 'START', 'RECEIVED_TIMEFORMATTED')
  await page.locator('text=Process').click()
  await expect(page.locator('text=No data found')).toBeVisible()
})

test('cancels a process', async ({ page, utils }) => {
  const start = sub(new Date(), { minutes: 2 })
  await page.locator('[data-test=start-time]').fill(format(start, 'HH:mm:ss'))
  let endTime = add(start, { hours: 1 })
  await page.locator('[data-test=end-time]').fill(format(endTime, 'HH:mm:ss'))
  // Set the end-date in case the day wrapped by adding a hour
  await page.locator('[data-test=end-date]').fill(format(endTime, 'yyyy-MM-dd'))
  await utils.addTargetPacketItem('INST', 'ADCS', 'CCSDSVER')
  await page.locator('text=Process').click()
  await expect(
    page.locator('text=End date/time is greater than current date/time'),
  ).toBeVisible()
  await utils.sleep(5000)
  await utils.download(page, 'text=Cancel')
  // Ensure the Cancel button goes back to Process
  await expect(page.locator('text=Process')).toBeVisible()
})

test('adds an entire target', async ({ page, utils }) => {
  await utils.addTargetPacketItem('INST')
  await expect(page.getByText('1-20 of 133')).toBeVisible()
})

test('adds an entire packet', async ({ page, utils }) => {
  await utils.addTargetPacketItem('INST', 'HEALTH_STATUS')
  await expect(page.getByText('1-20 of 35')).toBeVisible()
})

test('add, edits, deletes items', async ({ page, utils }) => {
  const start = sub(new Date(), { minutes: 1 })
  await page.locator('[data-test=start-time]').fill(format(start, 'HH:mm:ss'))
  await utils.addTargetPacketItem('INST', 'ADCS', 'CCSDSVER')
  await utils.addTargetPacketItem('INST', 'ADCS', 'CCSDSTYPE')
  await utils.addTargetPacketItem('INST', 'ADCS', 'CCSDSSHF')
  await expect(page.locator('tbody > tr')).toHaveCount(3)
  // Delete CCSDSVER by clicking Delete icon
  let row = await page.locator('tr:has-text("CCSDSVER")')
  await row.locator('td >> button').nth(1).click()
  await expect(page.locator('tbody > tr')).toHaveCount(2)
  // Delete CCSDSTYPE
  row = await page.locator('tr:has-text("CCSDSTYPE")')
  await row.locator('td >> button').nth(1).click()
  await expect(page.locator('tbody > tr')).toHaveCount(1)
  // Edit CCSDSSHF
  row = await page.locator('tr:has-text("CCSDSSHF")')
  await expect(row.locator('td:has-text("CONVERTED")')).toBeVisible()
  await row.locator('td >> button').nth(0).click()
  await page.locator('text=Value Type').click()
  await page.locator('text=RAW').click()
  await page.locator('button:has-text("CLOSE")').click()
  await expect(row.locator('td:has-text("RAW")')).toBeVisible()

  await utils.download(page, 'text=Process', function (contents) {
    const lines = contents.split('\n')
    expect(lines[0]).toContain('CCSDSSHF (RAW)')
    expect(lines[1]).not.toContain('FALSE')
    expect(lines[1]).toContain('0')
  })
})

test('edit all items', async ({ page, utils }) => {
  const start = sub(new Date(), { minutes: 1 })
  await page.locator('[data-test=start-time]').fill(format(start, 'HH:mm:ss'))
  await utils.addTargetPacketItem('INST', 'ADCS')
  await expect(page.getByText('1-20 of 36')).toBeVisible()
  expect(await page.locator('tr:has-text("CONVERTED")')).toHaveCount(20)
  await page.locator('[data-test=editAll]').click()
  await page.locator('text=Value Type').click()
  await page.locator('text=RAW').click()
  await page.locator('button:has-text("Ok")').click()
  await expect(page.locator('tr:has-text("CONVERTED")')).not.toBeVisible()
  expect(await page.locator('tr:has-text("RAW")')).toHaveCount(20)
})

test('processes commands', async ({ page, utils }) => {
  // Preload an ABORT command
  await page.goto('/tools/cmdsender/INST/ABORT')
  await page.locator('[data-test=select-send]').click()
  await page.locator('text=cmd("INST ABORT") sent')
  await utils.sleep(1000)
  await page
    .locator('[data-test="sender-history"] div')
    .filter({ hasText: 'cmd("INST ABORT")' })

  const start = sub(new Date(), { minutes: 1 })
  await page.goto('/tools/dataextractor')
  await page.locator('.v-app-bar__nav-icon').click()
  await page.locator('[data-test=start-time]').fill(format(start, 'HH:mm:ss'))
  await page.locator('label:has-text("Command")').click()
  await utils.sleep(500) // Allow the command to switch
  await utils.addTargetPacketItem('INST', 'ABORT', 'RECEIVED_TIMEFORMATTED')
  await utils.download(page, 'text=Process', function (contents) {
    const lines = contents.split('\n')
    expect(lines[1]).toContain('INST')
    expect(lines[1]).toContain('ABORT')
  })
})

test('creates CSV output', async ({ page, utils }) => {
  const start = sub(new Date(), { minutes: 2 })
  await page.locator('[data-test=cosmos-data-extractor-file]').click()
  await page.locator('text=Comma Delimited').click()
  await page.locator('[data-test=start-time]').fill(format(start, 'HH:mm:ss'))
  await utils.addTargetPacketItem('INST', 'HEALTH_STATUS', 'TEMP1')
  await utils.addTargetPacketItem('INST', 'HEALTH_STATUS', 'TEMP2')

  await utils.download(page, 'text=Process', function (contents) {
    expect(contents).toContain('NaN')
    expect(contents).toContain('Infinity')
    expect(contents).toContain('-Infinity')
    var lines = contents.split('\n')
    expect(lines[0]).toContain('TEMP1')
    expect(lines[0]).toContain('TEMP2')
    expect(lines[0]).toContain(',') // csv
    expect(lines.length).toBeGreaterThan(60) // 2 min at 60Hz is 120 samples
  })
})

test('creates tab delimited output', async ({ page, utils }) => {
  const start = sub(new Date(), { minutes: 2 })
  await page.locator('[data-test=cosmos-data-extractor-file]').click()
  await page.locator('text=Tab Delimited').click()
  await page.locator('[data-test=start-time]').fill(format(start, 'HH:mm:ss'))
  await utils.addTargetPacketItem('INST', 'HEALTH_STATUS', 'TEMP1')
  await utils.addTargetPacketItem('INST', 'HEALTH_STATUS', 'TEMP2')

  await utils.download(page, 'text=Process', function (contents) {
    var lines = contents.split('\n')
    expect(lines[0]).toContain('TEMP1')
    expect(lines[0]).toContain('TEMP2')
    expect(lines[0]).toContain('\t') // tab delimited
    expect(lines.length).toBeGreaterThan(60) // 2 min at 60Hz is 120 samples
  })
})

test('outputs full column names', async ({ page, utils }) => {
  let start = sub(new Date(), { minutes: 1 })
  await page.locator('[data-test=cosmos-data-extractor-mode]').click()
  await page.locator('text=Full Column Names').click()
  await page.locator('[data-test=start-time]').fill(format(start, 'HH:mm:ss'))
  await utils.addTargetPacketItem('INST', 'HEALTH_STATUS', 'TEMP1')
  await utils.addTargetPacketItem('INST', 'HEALTH_STATUS', 'TEMP2')

  await utils.download(page, 'text=Process', function (contents) {
    var lines = contents.split('\n')
    expect(lines[0]).toContain('INST HEALTH_STATUS TEMP1')
    expect(lines[0]).toContain('INST HEALTH_STATUS TEMP2')
  })
  await utils.sleep(1000)

  // Switch back and verify
  await page.locator('[data-test=cosmos-data-extractor-mode]').click()
  await page.locator('text=Normal Columns').click()
  // Create a new end time so we get a new filename
  start = sub(new Date(), { minutes: 2 })
  await page.locator('[data-test=start-time]').fill(format(start, 'HH:mm:ss'))
  await utils.download(page, 'text=Process', function (contents) {
    expect(contents).toContain('TARGET,PACKET,TEMP1,TEMP2')
  })
})

test('fills values', async ({ page, utils }) => {
  const start = sub(new Date(), { minutes: 1 })
  await page.locator('[data-test=cosmos-data-extractor-mode]').click()
  await page.locator('text=Fill Down').click()
  await page.locator('[data-test=start-time]').fill(format(start, 'HH:mm:ss'))
  await page.locator('[data-test=cosmos-data-extractor-mode]').click()
  await page.locator('text=Full Column Names').click()
  // Deliberately test with two different packets
  await utils.addTargetPacketItem('INST', 'ADCS', 'CCSDSSEQCNT')
  await utils.addTargetPacketItem('INST', 'HEALTH_STATUS', 'CCSDSSEQCNT')

  await utils.download(page, 'text=Process', function (contents) {
    var lines = contents.split('\n')
    expect(lines[0]).toContain('CCSDSSEQCNT')
    var [header1, header2, header3, header4] = lines[0].split(',')
    var adcsFirst = false
    if (header3 === 'INST ADCS CCSDSSEQCNT') {
      adcsFirst = true
    }
    var firstHS = -2
    for (let i = 1; i < lines.length; i++) {
      if (firstHS > 0) {
        if (adcsFirst) {
          var [tgt1, pkt1, adcs1, hs1] = lines[firstHS].split(',')
          var [tgt2, pkt2, adcs2, hs2] = lines[i].split(',')
          expect(tgt1).toEqual(tgt2) // Both INST
          expect(pkt1).toEqual('HEALTH_STATUS')
          expect(pkt2).toEqual('ADCS')
          expect(parseInt(adcs1) + 1).toEqual(parseInt(adcs2)) // ADCS goes up by one each time
          expect(parseInt(hs1)).toBeGreaterThan(1) // Double check for a value
          expect(hs1).toEqual(hs2) // HEALTH_STATUS should be the same
        } else {
          var [tgt1, pkt1, hs1, adcs1] = lines[firstHS].split(',')
          var [tgt2, pkt2, hs2, adcs2] = lines[i].split(',')
          expect(tgt1).toEqual(tgt2) // Both INST
          expect(pkt1).toEqual('HEALTH_STATUS')
          expect(pkt2).toEqual('ADCS')
          expect(parseInt(adcs1) + 1).toEqual(parseInt(adcs2)) // ADCS goes up by one each time
          expect(parseInt(hs1)).toBeGreaterThan(1) // Double check for a value
          expect(hs1).toEqual(hs2) // HEALTH_STATUS should be the same
        }
        break
      } else if (lines[i].includes('HEALTH_STATUS')) {
        // Look for the second line containing HEALTH_STATUS
        // console.log("Found first HEALTH_STATUS on line " + i);
        if (firstHS === -2) {
          firstHS = -1
        } else {
          firstHS = i
        }
      }
    }
  })
})

test('adds Matlab headers', async ({ page, utils }) => {
  const start = sub(new Date(), { minutes: 1 })
  await page.locator('[data-test=cosmos-data-extractor-mode]').click()
  await page.locator('text=Matlab Header').click()
  await page.locator('[data-test=start-time]').fill(format(start, 'HH:mm:ss'))
  await utils.addTargetPacketItem('INST', 'ADCS', 'Q1')
  await utils.addTargetPacketItem('INST', 'ADCS', 'Q2')

  await utils.download(page, 'text=Process', function (contents) {
    expect(contents).toContain('% TIME,TARGET,PACKET,Q1,Q2') // % is matlab
  })
})

test('outputs unique values only', async ({ page, utils }) => {
  const start = sub(new Date(), { minutes: 1 })
  await page.locator('[data-test=cosmos-data-extractor-mode]').click()
  await page.locator('text=Unique Only').click()
  await page.locator('[data-test=start-time]').fill(format(start, 'HH:mm:ss'))
  await utils.addTargetPacketItem('INST', 'HEALTH_STATUS', 'CCSDSVER')

  await utils.download(page, 'text=Process', function (contents) {
    var lines = contents.split('\n')
    expect(lines[0]).toContain('CCSDSVER')
    expect(lines.length).toEqual(2) // header and a single value
  })
})
