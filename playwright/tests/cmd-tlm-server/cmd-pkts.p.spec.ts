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
  // It is important in this test that we send a command that is not being sent
  // by other tests to ensure the count increments by one. Thus NOT ABORT or COLLECT
  // as those are being sent by background tasks.
  await expect
    .poll(() =>
      page.locator('[data-test=cmd-packets-table] >> tbody > tr').count(),
    )
    .toBeGreaterThan(3)
  await page
    .locator(
      'div.v-card-title:has-text("Command Packets") >> input[type="text"]',
    )
    .fill('fltcmd')
  await expect
    .poll(() =>
      page.locator('[data-test=cmd-packets-table] >> tbody > tr').count(),
    )
    .toEqual(2)
  await utils.sleep(2000) // Allow API to fetch counts
  const countStr = await page
    .locator('[data-test=cmd-packets-table] >> tr td >> nth=2')
    .textContent()
  if (countStr === null) {
    throw new Error('Unable to get packet count')
  }
  const count = parseInt(countStr)
  // Send a FLTCMD command
  await page.goto('/tools/cmdsender/INST/FLTCMD/', {
    waitUntil: 'domcontentloaded',
  })
  await expect(page.locator('.v-app-bar')).toContainText('Command Sender')
  await utils.selectTargetPacketItem('INST', 'FLTCMD')
  await page.locator('[data-test=select-send]').click()
  await expect(page.locator('main')).toContainText(
    'cmd("INST FLTCMD with FLOAT32 0, FLOAT64 0") sent',
  )

  await page.goto('/tools/cmdtlmserver/cmd-packets', {
    waitUntil: 'domcontentloaded',
  })
  await expect(page.locator('.v-app-bar')).toContainText('CmdTlmServer')
  await expect
    .poll(() =>
      page.locator('[data-test=cmd-packets-table] >> tbody > tr').count(),
    )
    .toBeGreaterThan(3)
  await utils.sleep(2000) // Allow API to fetch counts
  await page
    .locator(
      'div.v-card-title:has-text("Command Packets") >> input[type="text"]',
    )
    .fill('fltcmd')
  await expect
    .poll(() =>
      page.locator('[data-test=cmd-packets-table] >> tbody > tr').count(),
    )
    .toEqual(2)
  await expect
    .poll(
      async () =>
        await page
          .locator('[data-test=cmd-packets-table] >> tr td >> nth=2')
          .textContent(),
    )
    .toEqual(`${count + 1}`)
})

test('displays a raw command', async ({ page, utils }) => {
  // Preload an ABORT command
  await page.goto('/tools/cmdsender/INST/ABORT/')
  await expect(page.locator('.v-app-bar')).toContainText('Command Sender')
  await utils.selectTargetPacketItem('INST', 'ABORT')
  await page.locator('[data-test=select-send]').click()
  await expect(page.locator('text=cmd("INST ABORT") sent')).toBeVisible()

  await page.goto('/tools/cmdtlmserver/cmd-packets')
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
