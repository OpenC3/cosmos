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
import { test, expect } from './fixture'
import { format, sub } from 'date-fns'

test.use({
  toolPath: '/tools/tlmgrapher',
  toolName: 'Telemetry Grapher',
})

test('add item start, pause, resume and stop', async ({ page, utils }) => {
  await utils.selectTargetPacketItem('INST', 'HEALTH_STATUS', 'TEMP1')
  await page.locator('button:has-text("Add Item")').click()
  await expect(page.locator('#chart0')).toContainText('TEMP1')
  await utils.sleep(3000) // Wait for graphing to occur
  // Add another item while it is already graphing
  await utils.selectTargetPacketItem('INST', 'HEALTH_STATUS', 'TEMP2')
  await page.locator('button:has-text("Add Item")').click()
  await expect(page.locator('#chart0')).toContainText('TEMP2')
  // Use the graph buttons first
  await page.locator('[data-test=pause-graph]').click()
  await utils.sleep(1000) // Wait for graphing to pause
  await page.locator('[data-test=start-graph]').click()
  await utils.sleep(1000) // Wait for graphing to resume
  // Use the graph menu now
  await page.locator('[data-test=telemetry-grapher-graph]').click()
  await page.locator('text=Pause').click()
  await utils.sleep(1000) // Wait for graphing to pause
  await page.locator('[data-test=telemetry-grapher-graph]').click()
  await page.locator('text=Start').click()
  await utils.sleep(1000) // Wait for graphing to resume
  await page.locator('[data-test=telemetry-grapher-graph]').click()
  await page.locator('text=Stop').click()
  await utils.sleep(1000) // Wait for graphing to stop
})

test('adds multiple graphs', async ({ page, utils }) => {
  await utils.selectTargetPacketItem('INST', 'HEALTH_STATUS', 'TEMP1')
  await page.locator('button:has-text("Add Item")').click()
  await expect(page.locator('#chart0')).toContainText('TEMP1')
  await utils.sleep(1000) // Wait for graphing to occur
  await page.locator('[data-test=telemetry-grapher-graph]').click()
  await page.locator('text=Add Graph').click()
  await utils.selectTargetPacketItem('INST', 'HEALTH_STATUS', 'TEMP2')
  await page.locator('button:has-text("Add Item")').click()
  await expect(page.locator('#chart1')).toContainText('TEMP2')
  await expect(page.locator('#chart1')).not.toContainText('TEMP1')
  await expect(page.locator('#chart0')).not.toContainText('TEMP2')
  // Close the charts
  await page.locator('[data-test=close-graph-icon]').first().click()
  await expect(page.locator('#chart0')).not.toBeVisible()
  await expect(page.locator('#chart1')).toBeVisible()
  await page.locator('[data-test=close-graph-icon]').click()
  await expect(page.locator('#chart1')).not.toBeVisible()
})

test('minimizes a graph', async ({ page, utils }) => {
  await utils.sleep(500) // Ensure chart is stable
  // Get ElementHandle to the chart
  const chart = page.locator('#chart0')
  if (chart) {
    await chart.waitFor({ state: 'visible' })
  } else {
    throw new Error('Chart element not found')
  }
  const origBox = await chart.boundingBox()
  if (origBox === null) {
    throw new Error('Unable to get chart bounding box')
  }

  // Minimize / maximized the graph
  await page.locator('[data-test=minimize-screen-icon]').click()
  await expect(page.locator('#chart0')).not.toBeVisible()
  await page.locator('[data-test=maximize-screen-icon]').click()
  await expect(page.locator('#chart0')).toBeVisible()
  await chart.waitFor({ state: 'visible' })
  const maximizeBox = await chart.boundingBox()
  if (maximizeBox === null) {
    throw new Error('Unable to get chart bounding box')
  }
  expect(maximizeBox.width).toEqual(origBox.width)
  expect(maximizeBox.height).toEqual(origBox.height)
})

test('shrinks and expands a graph width', async ({ page, utils }) => {
  await utils.sleep(500) // Ensure chart is stable
  // Get ElementHandle to the chart
  const chart = page.locator('#chart0')
  if (chart) {
    await chart.waitFor({ state: 'visible' })
  } else {
    throw new Error('Chart element not found')
  }
  const origBox = await chart.boundingBox()
  if (origBox === null) {
    throw new Error('Unable to get chart bounding box')
  }

  await page.locator('[data-test=collapse-width]').click()
  await chart.waitFor({ state: 'visible' })
  const halfWidthBox = await chart.boundingBox()
  if (halfWidthBox === null) {
    throw new Error('Unable to get chart bounding box')
  }

  // Check that we're now half with only 1 digit of precision
  expect(origBox.width / halfWidthBox.width).toBeCloseTo(2, 1)
  expect(halfWidthBox.height).toEqual(origBox.height)
  await page.locator('[data-test=expand-width]').click()
  await chart.waitFor({ state: 'visible' })
  const collapseWidthBox = await chart.boundingBox()
  if (collapseWidthBox === null) {
    throw new Error('Unable to get chart bounding box')
  }
  expect(origBox.width).toEqual(collapseWidthBox.width)
  expect(collapseWidthBox.height).toEqual(origBox.height)
})

test('shrinks and expands a graph height', async ({ page, utils }) => {
  await utils.sleep(500) // Ensure chart is stable
  // Get ElementHandle to the chart
  const chart = page.locator('#chart0')
  if (chart) {
    await chart.waitFor({ state: 'visible' })
  } else {
    throw new Error('Chart element not found')
  }

  const origBox = await chart.boundingBox()
  if (origBox === null) {
    throw new Error('Unable to get chart bounding box')
  }
  await page.locator('[data-test=collapse-height]').click()
  await chart.waitFor({ state: 'visible' })
  const collapseHeightBox = await chart.boundingBox()
  if (collapseHeightBox === null) {
    throw new Error('Unable to get chart bounding box')
  }

  // Check that we're less than original ... it's not half
  expect(collapseHeightBox.height).toBeLessThan(origBox.height)
  expect(collapseHeightBox.width).toEqual(origBox.width)
  await page.locator('[data-test=expand-height]').click()
  await chart.waitFor({ state: 'visible' })
  const expandHeightBox = await chart.boundingBox()
  if (expandHeightBox === null) {
    throw new Error('Unable to get chart bounding box')
  }
  expect(expandHeightBox.width).toEqual(origBox.width)
  expect(Math.abs(origBox.height - expandHeightBox.height)).toBeLessThanOrEqual(
    1.1,
  )
})

test('shrinks and expands both width and height', async ({ page, utils }) => {
  await utils.sleep(500) // Ensure chart is stable
  // Get ElementHandle to the chart
  const chart = page.locator('#chart0')
  if (chart) {
    await chart.waitFor({ state: 'visible' })
  } else {
    throw new Error('Chart element not found')
  }

  await page.locator('[data-test=collapse-all]').click()
  await chart.waitFor({ state: 'visible' })
  const minBox = await chart.boundingBox()
  if (minBox === null) {
    throw new Error('Unable to get chart bounding box')
  }
  await page.locator('[data-test=expand-all]').click()
  await chart.waitFor({ state: 'visible' })
  const maxBox = await chart.boundingBox()
  if (maxBox === null) {
    throw new Error('Unable to get chart bounding box')
  }

  // Check that width is double with only 1 digit of precision
  expect(maxBox.width / minBox.width).toBeCloseTo(2, 1)
  // Height is simply larger
  expect(maxBox.height).toBeGreaterThan(minBox.height)
  await page.locator('[data-test=collapse-all]').click()
  await chart.waitFor({ state: 'visible' })
  const minBox2 = await chart.boundingBox()
  if (minBox2 === null) {
    throw new Error('Unable to get chart bounding box')
  }
  expect(minBox.width).toEqual(minBox2.width)
  expect(Math.abs(minBox.height - minBox2.height)).toBeLessThanOrEqual(1.1)
})

test('edits a graph', async ({ page, utils }) => {
  await utils.selectTargetPacketItem('INST', 'HEALTH_STATUS', 'TEMP1')
  await page.locator('button:has-text("Add Item")').click()
  await expect(page.locator('#chart0')).toContainText('TEMP1')
  await utils.sleep(3000) // Wait for graphing to occur

  await page.locator('[data-test=edit-graph-icon]').click()
  await expect(page.locator('.v-dialog')).toContainText('Edit Graph')
  await page.getByLabel('Title').fill('Test Graph Title')

  const start = sub(new Date(), { minutes: 2 })
  await page.getByLabel('Start Date').fill(format(start, 'yyyy-MM-dd'))
  await page.getByLabel('Start Time').fill(format(start, 'HH:mm:ss'))

  await page.getByRole('tab', { name: 'Scale / Lines' }).click()
  await page.getByLabel('Min Y Axis (Optional)').fill('-50')
  await page.getByLabel('Max Y Axis (Optional)').fill('50')
  await page.getByRole('button', { name: 'New Line' }).click()
  await page.getByLabel('Y Value').fill('20')
  await page.getByText('white').click()
  await page.getByRole('option', { name: 'darkorange' }).click()

  await page.getByRole('tab', { name: 'Items' }).click()
  await expect(page.locator('[data-test=edit-graph-items]')).toContainText(
    'TEMP1',
  )

  await page.getByRole('button', { name: 'Ok' }).click()

  // Validate our settings, have to use gridItem0 because chart0 doesn't include title
  await expect(page.locator('#gridItem0')).toContainText('Test Graph Title')
  await utils.sleep(5000) // Allow data to flow
})

test.only('custom x-axis item with RECEIVED_COUNT', async ({ page, utils }) => {
  await utils.selectTargetPacketItem('INST', 'ADCS', 'POSX')
  await page.locator('button:has-text("Add Item")').click()
  await expect(page.locator('#chart0')).toContainText('POSX')
  await expect(page.locator('#chart0')).toContainText('Time')

  await page.locator('[data-test=edit-graph-icon]').click()
  await expect(page.locator('.v-dialog')).toContainText('Edit Graph')
  await page.getByRole('tab', { name: 'Scale / Lines' }).click()
  await page.getByLabel('Custom X axis item').check()
  await page.locator('.v-dialog [data-test=select-item] i').click()
  await page.locator('.v-dialog').getByLabel('Select Item').fill('RECEIVED_COUNT')
  await page.getByRole('option', { name: 'RECEIVED_COUNT' }).click()
  await page.getByRole('button', { name: 'Set' }).click()
  await page.getByRole('button', { name: 'Ok' }).click()
  await expect(page.locator('#chart0')).toContainText('RECEIVED_COUNT')
})
