/*
# Copyright 2022 Ball Aerospace & Technologies Corp.
# All Rights Reserved.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
# See LICENSE.md for more details.
#
# Modified by OpenC3, Inc.
# All changes Copyright 2026, OpenC3, Inc.
# All Rights Reserved
*/

import { test, expect } from './fixture'

// Take the demo sim targets out of QUIET mode. The demo boots quiet
// (INST/lib/sim_inst.rb @quiet = true, INST2/lib/sim_inst.py self.quiet = True),
// and QUIET suppresses every limits violation: temps cycle inside in-limits
// bands, GROUND1STATUS/GROUND2STATUS are pinned CONNECTED, PARAMS VALUE2/VALUE4
// write 0 (GREEN) and the NaN/Infinity injection into TEMP2 is disabled. Specs
// that assert on red/yellow limits (limits-monitor, data-extractor's NaN checks,
// the enterprise autonomic TEMP1 == RED_HIGH and GROUND2STATUS != CONNECTED
// triggers) need it off.
//
// This lives here rather than in global.setup.ts because the setup project is a
// dependency of every other project, so it ran *before* this spec's CONNECTED
// checks -- the cmd was sent while the interfaces were still coming up and the
// API answered 500. QUIET is sim-microservice global state, so setting it once
// per run is enough.
async function resetQuiet(page) {
  for (const target of ['INST', 'INST2']) {
    const status = await page.evaluate(async (target) => {
      const response = await fetch('/openc3-api/api', {
        method: 'POST',
        headers: {
          Authorization: localStorage.openc3Token,
          'Content-Type': 'application/json-rpc',
          manual: 'true',
        },
        body: JSON.stringify({
          jsonrpc: '2.0',
          method: 'cmd',
          params: `${target} QUIET with STATE FALSE`,
          id: 1,
          keyword_params: { scope: 'DEFAULT' },
        }),
      })
      return response.status
    }, target)
    expect(status).toBe(200)
  }
}

test('waits for the services to deploy and connect', async ({
  page,
  utils,
}) => {
  test.setTimeout(5 * 60 * 1000) // 5 minutes
  await page.goto('/tools/cmdtlmserver')
  await expect(page.locator('.v-app-bar')).toContainText('CmdTlmServer')
  // Check the 3rd column (nth starts at 0) on the row containing INST_INT says CONNECTED
  await expect(
    page
      .locator('[data-test="interfaces-table"]')
      .locator('tr:has-text("INST_INT") td >> nth=2'),
  ).toContainText('CONNECTED', {
    timeout: 120000,
  })
  await expect(
    page
      .locator('[data-test="interfaces-table"]')
      .locator('tr:has-text("INST2_INT") td >> nth=2'),
  ).toContainText('CONNECTED', {
    timeout: 60000,
  })

  // Both interfaces are connected, so the sim will accept commands now.
  await resetQuiet(page)
})
