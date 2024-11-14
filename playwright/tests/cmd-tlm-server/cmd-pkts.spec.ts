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
import { test, expect } from './../fixture'

test.use({
  toolPath: '/tools/cmdtlmserver/cmd-packets',
  toolName: 'CmdTlmServer',
})

test('displays the list of command', async ({ page, utils }) => {
  // When we ask for just text there are no spaces
  await expect(
    page.locator('[data-test=cmd-packets-table]').locator('text=INSTABORT'),
  ).toBeVisible()
  await expect(
    page.locator('[data-test=cmd-packets-table]').locator('text=INSTCLEAR'),
  ).toBeVisible()
  await expect(
    page.locator('[data-test=cmd-packets-table]').locator('text=INSTCOLLECT'),
  ).toBeVisible()
  await expect(
    page.locator('[data-test=cmd-packets-table]').locator('text=EXAMPLESTART'),
  ).toBeVisible()
})

test('displays the command count', async ({ page, utils }) => {
  await expect
    .poll(() =>
      page.locator('[data-test=cmd-packets-table] >> tbody > tr').count(),
    )
    .toBeGreaterThan(3)
  await utils.sleep(1500) // Allow API to fetch counts
  await page
    .locator(
      'div.v-card-title:has-text("Command Packets") >> input[type="text"]',
    )
    .fill('abort')
  await expect
    .poll(() =>
      page.locator('[data-test=cmd-packets-table] >> tbody > tr').count(),
    )
    .toEqual(2)
  const count = parseInt(
    await page
      .locator('[data-test=cmd-packets-table] >> tr td >> nth=2')
      .textContent(),
  )
  // Send an ABORT command
  await page.goto('/tools/cmdsender/INST/ABORT', {
    waitUntil: 'domcontentloaded',
  })
  await expect(page.locator('.v-app-bar')).toContainText('Command Sender')
  await page.locator('[data-test=select-send]').click()
  await expect(page.locator('main')).toContainText('cmd("INST ABORT") sent')
  await page
    .locator('[data-test="sender-history"] div')
    .filter({ hasText: 'cmd("INST ABORT")' })

  await page.goto('/tools/cmdtlmserver/cmd-packets', {
    waitUntil: 'domcontentloaded',
  })
  await expect(page.locator('.v-app-bar')).toContainText('CmdTlmServer')
  await expect
    .poll(() =>
      page.locator('[data-test=cmd-packets-table] >> tbody > tr').count(),
    )
    .toBeGreaterThan(3)
  await utils.sleep(1500) // Allow API to fetch counts
  await page
    .locator(
      'div.v-card-title:has-text("Command Packets") >> input[type="text"]',
    )
    .fill('abort')
  await expect
    .poll(() =>
      page.locator('[data-test=cmd-packets-table] >> tbody > tr').count(),
    )
    .toEqual(2)
  await expect
    .poll(async () =>
      parseInt(
        await page
          .locator('[data-test=cmd-packets-table] >> tr td >> nth=2')
          .textContent(),
      ),
    )
    .toEqual(count + 1)
})

test('displays a raw command', async ({ page, utils }) => {
  await expect(page.locator('text=INSTABORT')).toBeVisible()
  await page
    .getByRole('row', { name: 'INST ABORT' })
    .getByRole('button', { name: 'View Raw' })
    .click()
  await expect(page.locator('.raw-dialog')).toContainText(
    'Raw Command Packet: INST ABORT',
  )
  await expect(page.locator('.raw-dialog')).toContainText('Received Time:')
  await expect(page.locator('.raw-dialog')).toContainText('Count:')
  expect(await page.inputValue('.raw-dialog textarea')).toMatch('Address')
  expect(await page.inputValue('.raw-dialog textarea')).toMatch('00000000:')

  await utils.download(page, '[data-test=download]', function (contents) {
    expect(contents).toMatch('Raw Command Packet: INST ABORT')
    expect(contents).toMatch('Received Time:')
    expect(contents).toMatch('Count:')
    expect(contents).toMatch('Address')
    expect(contents).toMatch('00000000:')
  })
  await page.locator('[data-test=close]').click()
  await expect(page.locator('.raw-dialog')).not.toBeVisible()
})

test('links to command sender', async ({ page, utils }) => {
  await expect(page.locator('text=INSTCOLLECT')).toBeVisible()
  const [newPage] = await Promise.all([
    page.context().waitForEvent('page'),
    await page.locator('text=INSTCOLLECT >> td >> nth=4').click(),
  ])
  await expect(newPage.locator('.v-app-bar')).toContainText('Command Sender', {
    timeout: 30000,
  })
  await expect(newPage.locator('id=openc3-tool')).toContainText(
    'Starts a collect on the INST target',
  )
})
