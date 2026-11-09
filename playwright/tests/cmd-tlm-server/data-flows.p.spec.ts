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

import { test, expect } from './../fixture'

test.use({
  toolPath: '/tools/cmdtlmserver/interfaces',
  toolName: 'CmdTlmServer',
})

// utils is requested because that fixture navigates to the tool
test.beforeEach(async ({ page, utils }) => {
  await page.getByRole('tab', { name: 'Data Flows' }).click()
  await expect(page).toHaveURL(/\/tools\/cmdtlmserver\/data-flows/)
})

test('views the metrics for target processing', async ({ page }) => {
  // The health indicator on the INST2 Processing node opens its metrics
  await page
    .getByRole('button', { name: /^INST2: .*View processing metrics/ })
    .click()
  const dialog = page.locator('[data-test=target-processing-details]')
  await expect(dialog).toContainText('Target Processing: INST2')
  const metrics = dialog.locator('[data-test=flow-metrics]')
  await expect(metrics).toContainText('Processing metrics')
  // Metrics are published every 5 seconds so allow time for the first report
  const decom = metrics.locator('tr', { hasText: 'DEFAULT__DECOM__INST2' })
  await expect(decom.filter({ hasText: 'Packets decommutated' })).toBeVisible({
    timeout: 15000,
  })
  await expect(
    decom.filter({ hasText: 'Decommutation queue delay' }),
  ).toBeVisible()
  // Services are matched on the complete target name so INST isn't included
  await expect(metrics.getByRole('cell', { name: /__INST$/ })).toHaveCount(0)

  await dialog.locator('[data-test=close]').click()
  await expect(dialog).not.toBeVisible()
})

test('views the metrics for an interface', async ({ page }) => {
  // The health indicator on the INST2_INT Interface node opens its details
  await page
    .getByRole('button', { name: /^INST2_INT: .*View processing metrics/ })
    .click()
  const dialog = page.locator('.v-dialog', {
    hasText: 'Interface Properties: INST2_INT',
  })
  await expect(dialog).toBeVisible()
  const metrics = dialog.locator('[data-test=flow-metrics]')
  await expect(metrics).toContainText('Processing metrics')
  const service = metrics.locator('tr', {
    hasText: 'DEFAULT__INTERFACE__INST2_INT',
  })
  await expect(
    service.filter({ hasText: 'Telemetry packets received' }),
  ).toBeVisible({ timeout: 15000 })
  await expect(service.filter({ hasText: 'Buffered input' })).toBeVisible()

  await dialog.locator('[data-test=close]').click()
  await expect(dialog).not.toBeVisible()
})

// An interface that is registered but whose microservice isn't running makes
// interface_details wait for a cmd ack timeout (30s) before failing. That must
// not delay the other interfaces or pile up a request per refresh.
test('renders healthy interfaces while another interface never responds', async ({
  page,
  utils,
}) => {
  const DEAD = 'DEAD_INT'
  let deadDetailsRequests = 0
  // Intercept the JSON-RPC API calls to simulate an interface whose
  // microservice isn't running: add a fake interface name to the
  // get_interface_names result and never answer its interface_details request.
  // Everything else passes through to the real API. This avoids having to
  // register a broken interface in the demo plugin.
  await page.route('**/openc3-api/api*', async (route) => {
    const body = route.request().postDataJSON()
    if (body?.method === 'get_interface_names') {
      const response = await route.fetch()
      const json = await response.json()
      json.result = [...json.result, DEAD]
      await route.fulfill({ response, json })
    } else if (
      body?.method === 'interface_details' &&
      body.params?.[0] === DEAD
    ) {
      // Never answer, like an interface with no running microservice
      deadDetailsRequests++
    } else {
      await route.continue()
    }
  })

  // The healthy interfaces render without waiting for the dead one
  await expect(
    page.getByRole('button', { name: /^INST_INT: .*View processing metrics/ }),
  ).toBeVisible({ timeout: 5000 })
  await expect(
    page.getByRole('button', {
      name: /^INST2_INT: .*View processing metrics/,
    }),
  ).toBeVisible({ timeout: 5000 })
  // The unresponsive interface has no details so it isn't drawn
  await expect(page.getByText(DEAD)).toHaveCount(0)

  // The tab refreshes every second. Let several refreshes pass, then make sure
  // the unanswered request wasn't repeated while it was still outstanding.
  await utils.sleep(3500)
  expect(deadDetailsRequests).toBe(1)
})
