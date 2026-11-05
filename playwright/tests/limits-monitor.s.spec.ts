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

// Serial because the limits_resync procedures stall a decom microservice for
// 30s and flood the limits event stream, which breaks tests running alongside.

import type { Page } from '@playwright/test'
import { test, expect } from './fixture'

test.use({
  toolPath: '/tools/limitsmonitor',
  toolName: 'Limits Monitor',
})

async function openCmdTlmServer(page: Page) {
  const server = await page.context().newPage()
  await server.goto('/tools/cmdtlmserver')
  await expect(server.locator('[data-test=log-messages]')).toContainText('INFO')
  // Clear older messages so only messages from this run can match
  await server.locator('[data-test=clear-log]').click()
  return server
}

async function runProcedure(page: Page, filename: string) {
  const scriptRunner = await page.context().newPage()
  await scriptRunner.goto('/tools/scriptrunner')
  await scriptRunner.locator('[data-test=script-runner-file]').click()
  await scriptRunner.locator('text=Open File').click()
  await expect(
    scriptRunner.locator('.v-dialog').getByText('INST2', { exact: true }),
  ).toBeVisible()
  await scriptRunner
    .locator('[data-test=file-open-save-search] input')
    .fill(filename)
  await scriptRunner.locator(`text=${filename}`).click()
  await scriptRunner.locator('[data-test=file-open-save-submit-btn]').click()
  await expect(scriptRunner.locator('.v-dialog')).not.toBeVisible()
  // Check for potential "<User> is editing this script" from a retry
  const someone = scriptRunner.getByText('is editing this script')
  if (await someone.isVisible()) {
    await scriptRunner.locator('[data-test="unlock-button"]').click()
    await scriptRunner
      .locator('[data-test="confirm-dialog-force unlock"]')
      .click()
  }
  await scriptRunner.locator('[data-test=start-button]').click()
  return scriptRunner
}

for (const { language, filename, target, group } of [
  {
    language: 'Ruby',
    filename: 'limits_resync.rb',
    target: 'INST',
    group: 'INST_TEMP2',
  },
  {
    language: 'Python',
    filename: 'limits_resync.py',
    target: 'INST2',
    group: 'INST2_TEMP2',
  },
]) {
  test(`${language} decom resyncs limits after limits events are trimmed`, async ({
    page,
    utils, // Requesting utils is what opens Limits Monitor on page
  }) => {
    // The procedure stalls decom for 30s, floods the stream and then verifies
    test.setTimeout(5 * 60 * 1000)
    const microservice = `DEFAULT__DECOM__${target}`
    const server = await openCmdTlmServer(page)
    const scriptRunner = await runProcedure(page, filename)

    await expect(scriptRunner.locator('[data-test=state] input')).toHaveValue(
      'completed',
      { timeout: 3 * 60 * 1000 },
    )
    const output = scriptRunner.locator('[data-test=output-messages]')
    // Proves the flood trimmed the group event before decom could read it
    await expect(output).toContainText('trimmed from the limits event stream')
    await expect(output).toContainText(
      `PASS: ${target} decom microservice resynced and stopped checking limits on TEMP2`,
    )

    // Decom fell behind while stalled, then detected the trimmed events and resynced.
    // Decom reports catching up a few seconds after the procedure completes.
    const logMessages = server.locator('[data-test=log-messages]')
    const timeout = 30000
    await expect(logMessages).toContainText(
      `${microservice} is falling behind processing`,
      { timeout },
    )
    await expect(logMessages).toContainText(
      `${microservice}: Limits events were trimmed before they could be read, resyncing limits`,
      { timeout },
    )
    await expect(logMessages).toContainText(
      `${microservice} has caught up processing`,
      { timeout },
    )

    // The procedure re-enables the group when it finishes
    await expect(page.locator('[data-test=limits-events]')).toContainText(
      `Enabling Limits Group: ${group}`,
    )
  })
}
