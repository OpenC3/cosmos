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
  toolName: 'Dashboards (Beta)',
})

test.beforeEach(({ page }) => {
  // Throw exceptions on any pageerror events
  page.on('pageerror', (exception) => {
    throw exception
  })
})

// Every test takes `utils`: that fixture is what opens the tool and logs in

// Dashboard names are saved uppercase; keep them unique across parallel runs
function uniqueName(prefix: string) {
  return `${prefix}_${Date.now().toString(36)}${Math.floor(Math.random() * 1000)}`.toUpperCase()
}

async function openDashboard(page, key: string) {
  await page.goto(`/tools/dashboards/${key}`)
  await expect(page.locator('[data-test="dashboard-title"]')).toBeVisible()
  await expect(page.locator('[data-test="dashboard-opening"]')).toHaveCount(0)
}

async function fileMenu(page, item: string) {
  await page.getByRole('button', { name: 'File' }).click()
  await page.getByText(item, { exact: true }).click()
}

// Creates INST/<name> from the File menu; it opens in edit mode
async function createDashboard(page, name: string) {
  await fileMenu(page, 'New Dashboard')
  await page.locator('[data-test="dashboard-dialog-target"]').click()
  await page.getByRole('option', { name: 'INST', exact: true }).click()
  await page.locator('[data-test="dashboard-dialog-name"] input').fill(name)
  await page.locator('[data-test="dashboard-dialog-submit"]').click()
  await expect(page.locator('[data-test="dashboard-save"]')).toBeVisible()
  await expect(page).toHaveURL(new RegExp(`/tools/dashboards/INST/${name}$`))
}

// Replaces the dashboard with `lines` in the Code dialog (applied as typed)
async function setCode(page, lines: string[]) {
  await page.locator('[data-test="dashboard-code-btn"]').click()
  await page.locator('[data-test="dashboard-code"] textarea').fill(lines.join('\n'))
  // Edits apply shortly after typing stops
  await page.waitForTimeout(800)
  await page.locator('[data-test="code-dialog"]').getByLabel('Close').click()
}

async function save(page) {
  await page.locator('[data-test="dashboard-save"]').click()
  await expect(page.locator('[data-test="dashboard-status"]')).toHaveText(
    'Saved',
  )
}

// Deletes the open dashboard and checks the navigator no longer lists it
async function deleteDashboard(page, name: string) {
  await fileMenu(page, 'Delete Dashboard')
  await page.getByRole('button', { name: 'Delete', exact: true }).click()
  await expect(page.locator('[data-test="dashboard-title"]')).toHaveCount(0)
  await page.locator('[data-test="dashboard-choose"]').click()
  await page.locator('[data-test="navigator-search"] input').fill(name)
  await expect(page.locator('[data-test="navigator-item"]')).toHaveCount(0)
  await page.keyboard.press('Escape')
}

test('shows the demo dashboard with live values and health', async ({ page, utils }) => {
  await openDashboard(page, 'INST/OVERVIEW')
  await expect(page.locator('[data-test="dashboards-beta-banner"]')).toBeVisible()
  await expect(page.locator('[data-test="dashboard-health"]')).toBeVisible()
  const titles = page.locator('[data-test="panel-title"]')
  for (const title of ['Temperatures', 'Health', 'Limits', 'Collect', 'ADCS']) {
    await expect(titles.filter({ hasText: title }).first()).toBeVisible()
  }
  // Values update from the poller
  const value = page.locator('[data-test="values-value"]').first()
  await expect(value).not.toHaveText('--')
  const first = await value.textContent()
  await expect(value).not.toHaveText(first as string, { timeout: 10000 })
  // Graph legends show the latest streamed value
  await expect(
    page.locator('[data-test="graph-legend-value"]').first(),
  ).not.toHaveText('--')
  await expect(page.locator('[data-test="graph-plot"] canvas').first()).toBeVisible()
})

test('finds and opens dashboards from the navigator', async ({ page, utils }) => {
  await openDashboard(page, 'INST/OVERVIEW')

  // Ctrl+K opens it on the dashboard that's open
  await page.keyboard.press('Control+k')
  const navigator = page.locator('[data-test="dashboard-navigator"]')
  await expect(navigator).toBeVisible()
  await expect(
    navigator.locator('[data-test="navigator-item"].highlighted'),
  ).toContainText('INST Overview')

  // Folders list each target's dashboards
  await navigator.locator('[data-test="navigator-folder-INST2"]').click()
  await expect(navigator.locator('[data-test="navigator-pane"]')).toContainText(
    'INST2/dashboards/',
  )
  await expect(
    navigator.locator('[data-test="navigator-item"]').filter({
      hasText: 'INST2 Overview',
    }),
  ).toBeVisible()

  // Search covers every folder, and Enter opens the highlighted result
  const search = navigator.locator('[data-test="navigator-search"] input')
  await search.fill('Map and Orbit')
  await expect(navigator.locator('[data-test="navigator-item"]')).toHaveCount(2)
  await search.press('Enter')
  await expect(navigator).not.toBeVisible()
  await expect(page.locator('[data-test="dashboard-title"]')).toContainText(
    'Map and Orbit',
  )
  await expect(page).toHaveURL(/\/tools\/dashboards\/INST2?\/MAPANDORBIT$/)
})

test('changes the time range and enters playback', async ({ page, utils }) => {
  await openDashboard(page, 'INST/OVERVIEW')

  await page.locator('[data-test="time-range"]').click()
  await page.locator('[data-test="time-range-300"]').click()
  await expect(page.locator('[data-test="time-range"]')).toContainText(
    'Last 5 minutes',
  )

  // A custom range from the same menu
  await page.locator('[data-test="time-range"]').click()
  await page.locator('[data-test="time-range-amount"] input').fill('10')
  await page.locator('[data-test="time-range-apply"]').click()
  await expect(page.locator('[data-test="time-range"]')).toContainText(
    'Last 10 minutes',
  )

  // Playback shows its controls; clicking again goes back to live
  await page.locator('[data-test="dashboard-playback"]').click()
  await expect(page.locator('[data-test="playback-bar"]')).toBeVisible()
  await page.locator('[data-test="dashboard-playback"]').click()
  await expect(page.locator('[data-test="playback-bar"]')).toHaveCount(0)
})

test('builds a multi-target panel and saves it', async ({ page, utils }) => {
  const name = uniqueName('PW_PANEL')
  await createDashboard(page, name)

  await page.locator('[data-test="panel-add"]').click()
  const dialog = page.locator('[data-test="panel-dialog"]')
  await dialog.locator('[data-test="panel-type"]').click()
  await page.locator('[data-test="panel-type-VALUES"]').click()
  await utils.addTargetPacketItem('INST', 'HEALTH_STATUS', 'TEMP1')
  await utils.addTargetPacketItem('INST2', 'HEALTH_STATUS', 'TEMP1')
  await expect(dialog.locator('[data-test="config-items"]')).toContainText(
    'INST2 HEALTH_STATUS TEMP1',
  )
  await dialog.locator('[data-test="panel-title-input"] input').fill('Both temps')
  await dialog.locator('[data-test="panel-save"]').click()

  const rows = page.locator('[data-test="values-row"]')
  await expect(rows).toHaveCount(2)
  await expect(rows.nth(0)).toContainText('INST TEMP1')
  await expect(rows.nth(1)).toContainText('INST2 TEMP1')
  await expect(page.locator('[data-test="dashboard-status"]')).toHaveText(
    'Unsaved changes',
  )

  // Undo removes the panel, redo brings it back
  await page.locator('[data-test="editor-undo"]').click()
  await expect(rows).toHaveCount(0)
  await page.locator('[data-test="editor-redo"]').click()
  await expect(rows).toHaveCount(2)

  await save(page)

  // Reload and the dashboard comes back from the server
  await page.reload()
  await expect(
    page.locator('[data-test="panel-title"]').filter({ hasText: 'Both temps' }),
  ).toBeVisible()
  await expect(page.locator('[data-test="values-row"]')).toHaveCount(2)

  await deleteDashboard(page, name)
})

test('edits the dashboard as code', async ({ page, utils }) => {
  const name = uniqueName('PW_CODE')
  await createDashboard(page, name)

  // Problems are reported with their line numbers
  await page.locator('[data-test="dashboard-code-btn"]').click()
  await page
    .locator('[data-test="dashboard-code"] textarea')
    .fill('DASHBOARD "Bad"\nPANEL STAT 0 0 3 3\n  BOGUS\nEND\n')
  await expect(
    page.locator('[data-test="dashboard-code-error"]').first(),
  ).toContainText('Line 3')
  await page.locator('[data-test="code-dialog"]').getByLabel('Close').click()

  await setCode(page, [
    'DASHBOARD "Code Test"',
    '  COLUMNS 24',
    'PANEL STAT 0 0 6 3',
    '  ITEM INST HEALTH_STATUS TEMP2',
    'END',
    'PANEL STATE 6 0 6 3',
    '  ITEM INST2 HEALTH_STATUS GROUND1STATUS',
    'END',
    'PANEL GAUGE 12 0 6 4',
    '  ITEM INST HEALTH_STATUS TEMP3',
    'END',
    'PANEL LIMITS 18 0 6 5 "All limits"',
    '  TARGET INST',
    'END',
    'PANEL GRAPH 0 5 12 6',
    '  ITEM INST HEALTH_STATUS TEMP1',
    '  ITEM INST2 HEALTH_STATUS TEMP1',
    'END',
  ])
  await expect(page.locator('[data-test="dashboard-title-input"] input')).toHaveValue(
    'Code Test',
  )
  await expect(page.locator('[data-test="stat-value"]')).not.toHaveText('--')
  await expect(page.locator('[data-test="state-value"]')).not.toHaveText('--')
  await expect(page.locator('[data-test="gauge-value"]')).not.toHaveText('--')
  await expect(
    page.locator('[data-test="panel-title"]').filter({ hasText: 'All limits' }),
  ).toBeVisible()
  await expect(page.locator('[data-test="graph-plot"] canvas')).toBeVisible()

  await save(page)
  await deleteDashboard(page, name)
})

test('sends commands with hold and click confirmation', async ({ page, utils }) => {
  const name = uniqueName('PW_CMD')
  await createDashboard(page, name)
  await setCode(page, [
    'DASHBOARD "Commands"',
    'PANEL COMMAND 0 0 4 6 "Hold abort"',
    '  COMMAND INST ABORT',
    'END',
    'PANEL COMMAND 4 0 4 6 "Click clear"',
    '  COMMAND INST CLEAR',
    '  SETTING CONFIRM CLICK',
    'END',
  ])
  // Commands only send outside the editor
  await save(page)
  await page.locator('[data-test="dashboard-done"]').click()
  await expect(page.locator('[data-test="dashboard-edit"]')).toBeVisible()

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

  // CLEAR is hazardous so clicking asks first, and cancel doesn't send
  await expect(click.locator('[data-test="command-hazardous"]')).toBeVisible()
  await click.locator('[data-test="command-send"]').click()
  await page.getByRole('button', { name: 'Cancel', exact: true }).click()
  await expect(click.locator('[data-test="command-status"]')).toContainText(
    'not sent',
  )

  await deleteDashboard(page, name)
})

test('keeps a missing plugin panel as written', async ({ page, utils }) => {
  const name = uniqueName('PW_PLUGIN')
  await createDashboard(page, name)
  // Written as a plugin's dashboard would be: the editor won't apply a
  // panel type that isn't installed, but a saved file can have one
  const text = [
    'DASHBOARD "Plugin panel"',
    'PANEL NOT_INSTALLED 0 0 4 4 "From a plugin"',
    '  ITEM INST HEALTH_STATUS TEMP1',
    '  SETTING ANYTHING 1',
    'END',
  ].join('\n')
  await page.evaluate(
    async ({ name, text }) => {
      const response = await fetch('/openc3-api/dashboard', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          Authorization: localStorage.openc3Token,
        },
        body: JSON.stringify({
          scope: 'DEFAULT',
          target: 'INST',
          dashboard: name,
          text,
        }),
      })
      if (!response.ok) throw new Error(`Save failed: ${response.status}`)
    },
    { name, text },
  )
  await page.reload()

  const panel = page
    .locator('[data-test="dashboard-panel"]')
    .filter({ hasText: 'From a plugin' })
  await expect(panel).toContainText('NOT_INSTALLED plugin not installed')
  await expect(page.locator('[data-test="dashboard-errors"]')).toContainText(
    "Panel type 'NOT_INSTALLED' isn't installed",
  )

  // Kept as written, so installing the plugin later brings it back
  await page.locator('[data-test="dashboard-code-btn"]').click()
  const code = page.locator('[data-test="dashboard-code"] textarea')
  await expect(code).toHaveValue(/PANEL NOT_INSTALLED 0 0 4 4 "From a plugin"/)
  await expect(code).toHaveValue(/SETTING ANYTHING 1/)
  await page.locator('[data-test="code-dialog"]').getByLabel('Close').click()

  await deleteDashboard(page, name)
})
