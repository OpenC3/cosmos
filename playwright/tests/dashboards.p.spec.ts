/*
# Copyright 2026 OpenC3, Inc.
# All Rights Reserved.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
# See LICENSE.md for more details.
#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.
*/

import { test, expect } from './fixture'

test.use({
  toolPath: '/tools/dashboards',
  toolName: 'Dashboards',
})

test.beforeEach(({ page }) => {
  // Throw exceptions on any pageerror events
  page.on('pageerror', (exception) => {
    throw exception
  })
})

function uniqueName(prefix: string) {
  return `${prefix}_${Date.now().toString(36).toUpperCase()}${Math.floor(Math.random() * 1000)}`
}

async function selectDashboard(page, key: string) {
  await page.locator('[data-test="dashboard-select"]').click()
  await page.getByRole('option', { name: key, exact: true }).click()
  await expect(page.locator('[data-test="dashboard-title"]')).toBeVisible()
}

async function createDashboard(page, name: string) {
  await page.locator('[data-test="dashboard-new"]').click()
  await page.locator('[data-test="new-dashboard-target"]').click()
  await page.getByRole('option', { name: 'INST', exact: true }).click()
  await page.locator('[data-test="new-dashboard-name"] input').fill(name)
  await page.locator('[data-test="new-dashboard-create"]').click()
  await expect(page.getByText('Saved dashboard')).toBeVisible()
  await page
    .getByRole('button', { name: 'Dismiss' })
    .click({ timeout: 5000 })
    .catch(() => {})
  // New dashboards open in edit mode
  await expect(page.locator('[data-test="dashboard-done"]')).toBeVisible()
}

async function applyCode(page, text: string) {
  await page.locator('[data-test="dashboard-code-btn"]').click()
  await page.locator('[data-test="dashboard-code"] textarea').fill(text)
  await page.locator('[data-test="dashboard-code-apply"]').click()
}

async function deleteDashboard(page, key: string) {
  await page.locator('[data-test="dashboards-file"]').click()
  await page.locator('text=Delete Dashboard').click()
  await page.locator('button:has-text("Delete")').click()
  await expect(page.getByText('Deleted dashboard')).toBeVisible()
  await page.locator('[data-test="dashboard-select"]').click()
  await expect(
    page.getByRole('option', { name: key, exact: true }),
  ).not.toBeVisible()
  await page.keyboard.press('Escape')
}

test('displays the demo dashboard with live values', async ({ page }) => {
  await selectDashboard(page, 'INST/OVERVIEW')
  const titles = page.locator('[data-test="panel-title"]')
  for (const title of [
    'Temperature 1',
    'Temperatures',
    'Health',
    'Limits',
    'Collect',
    'ADCS',
  ]) {
    await expect(titles.filter({ hasText: title })).toHaveCount(1)
  }
  // Multi-target panels label items with their target
  await expect(
    page.locator('[data-test="values-row"]').filter({ hasText: 'INST2 TEMP1' }),
  ).toBeVisible()
  // Values update from the poller
  const value = page.locator('[data-test="values-value"]').first()
  await expect(value).not.toHaveText('--')
  const first = await value.textContent()
  await expect(value).not.toHaveText(first as string, { timeout: 10000 })
  // Graph legend shows the latest streamed value
  await expect(
    page.locator('[data-test="graph-legend-value"]').first(),
  ).not.toHaveText('--')
})

test('builds a multi-target panel and saves it', async ({ page, utils }) => {
  const name = uniqueName('PW_PANEL')
  await createDashboard(page, name)

  await page.locator('[data-test="panel-add"]').click()
  await page.locator('[data-test="panel-type-VALUES"]').click()
  await utils.addTargetPacketItem('INST', 'HEALTH_STATUS', 'TEMP1')
  await utils.addTargetPacketItem('INST2', 'HEALTH_STATUS', 'TEMP1')
  await expect(page.locator('[data-test="config-items"]')).toContainText(
    'INST2 HEALTH_STATUS TEMP1',
  )
  await page.locator('[data-test="panel-title-input"] input').fill('Both temps')
  await page.locator('[data-test="panel-save"]').click()

  const rows = page.locator('[data-test="values-row"]')
  await expect(rows).toHaveCount(2)
  await expect(rows.nth(0)).toContainText('INST TEMP1')
  await expect(rows.nth(1)).toContainText('INST2 TEMP1')
  await expect(page.locator('[data-test="dashboard-unsaved"]')).toBeVisible()

  await page.locator('[data-test="dashboard-done"]').click()
  await expect(
    page.locator('[data-test="dashboard-unsaved"]'),
  ).not.toBeVisible()

  // Reload and the dashboard comes back from the server
  await page.reload()
  await expect(page.locator('[data-test="panel-title"]')).toContainText(
    'Both temps',
  )
  await expect(page.locator('[data-test="values-row"]')).toHaveCount(2)

  await deleteDashboard(page, `INST/${name}`)
})

test('edits the definition as code', async ({ page }) => {
  const name = uniqueName('PW_CODE')
  await createDashboard(page, name)

  // Errors are reported with line numbers and nothing is applied
  await page.locator('[data-test="dashboard-code-btn"]').click()
  await page
    .locator('[data-test="dashboard-code"] textarea')
    .fill('DASHBOARD "Bad"\nPANEL NOPE 0 0 3 3\nEND\n')
  await page.locator('[data-test="dashboard-code-apply"]').click()
  await expect(
    page.locator('[data-test="dashboard-code-error"]'),
  ).toContainText('Line 2')
  await page.locator('button:has-text("Cancel")').click()

  await applyCode(
    page,
    [
      'DASHBOARD "Code Test"',
      'PANEL STAT 0 0 3 3',
      '  ITEM INST HEALTH_STATUS TEMP2',
      'END',
      'PANEL STATE 3 0 3 3',
      '  ITEM INST2 HEALTH_STATUS GROUND1STATUS',
      'END',
      'PANEL LIMITS 6 0 6 5 "All limits"',
      'END',
      'PANEL GRAPH 0 3 6 6',
      '  ITEM INST HEALTH_STATUS TEMP1',
      '  ITEM INST2 HEALTH_STATUS TEMP1',
      '  SETTING DURATION 60',
      'END',
    ].join('\n'),
  )
  await expect(page.locator('[data-test="dashboard-title"]')).toHaveText(
    'Code Test',
  )
  await expect(page.locator('[data-test="stat-value"]')).not.toHaveText('--')
  await expect(page.locator('[data-test="state-value"]')).not.toHaveText('--')
  await expect(
    page.locator('[data-test="panel-title"]').filter({ hasText: 'All limits' }),
  ).toBeVisible()
  await expect(page.locator('[data-test="graph-plot"] canvas')).toBeVisible()

  await page.locator('[data-test="dashboard-save"]').click()
  await expect(page.getByText('Saved dashboard')).toBeVisible()
  await deleteDashboard(page, `INST/${name}`)
})

test('sends commands with hold and click confirmation', async ({ page }) => {
  const name = uniqueName('PW_CMD')
  await createDashboard(page, name)
  await applyCode(
    page,
    [
      'DASHBOARD "Commands"',
      'PANEL COMMAND 0 0 4 6 "Hold abort"',
      '  COMMAND INST ABORT',
      'END',
      'PANEL COMMAND 4 0 4 6 "Click clear"',
      '  COMMAND INST CLEAR',
      '  SETTING CONFIRM CLICK',
      'END',
    ].join('\n'),
  )
  const panels = page.locator('[data-test="dashboard-panel"]')
  const hold = panels.filter({ hasText: 'Hold abort' })
  const click = panels.filter({ hasText: 'Click clear' })

  // Releasing early doesn't send
  const holdButton = hold.locator('[data-test="command-send"]')
  await expect(holdButton).toBeEnabled()
  await holdButton.hover()
  await page.mouse.down()
  await page.waitForTimeout(200)
  await page.mouse.up()
  await expect(hold.locator('[data-test="command-status"]')).toContainText(
    'not sent',
  )

  // Holding sends
  await holdButton.hover()
  await page.mouse.down()
  await page.waitForTimeout(1200)
  await page.mouse.up()
  await expect(hold.locator('[data-test="command-status"]')).toContainText(
    'Sent INST ABORT',
  )

  // CLEAR is hazardous so clicking asks first, cancel doesn't send
  await expect(click.locator('[data-test="command-hazardous"]')).toBeVisible()
  await click.locator('[data-test="command-send"]').click()
  await page.locator('button:has-text("Cancel")').click()
  await expect(click.locator('[data-test="command-status"]')).toContainText(
    'not sent',
  )

  await deleteDashboard(page, `INST/${name}`)
})
