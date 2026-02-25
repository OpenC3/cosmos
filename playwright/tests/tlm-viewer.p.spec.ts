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
import { test, expect } from './fixture'
import { format, sub } from 'date-fns'

test.use({
  toolPath: '/tools/tlmviewer',
  toolName: 'Telemetry Viewer',
})

test.beforeEach(async ({ page, utils }) => {
  // Throw exceptions on any pageerror events
  page.on('pageerror', (exception) => {
    throw exception
  })
})

async function showScreen(
  page,
  utils,
  target,
  screen,
  callback = async () => {},
) {
  await page.locator('[data-test="select-target"]').click()
  await page.getByRole('option', { name: target, exact: true }).click()
  await page.locator('[data-test="select-screen"]').click()
  await page.getByRole('option', { name: screen, exact: true }).click()
  // Navigating to a screen displays it automatically unless already selected
  // In that case we need to click the Show button
  try {
    await expect(
      page.locator(`.v-toolbar:has-text("${target} ${screen}")`),
    ).toBeVisible({ timeout: 3000 })
  } catch {
    await page.locator('[data-test="show-screen"]').click()
    await expect(
      page.locator(`.v-toolbar:has-text("${target} ${screen}")`),
    ).toBeVisible()
  }
  await callback()
  await page.locator('[data-test=close-screen-icon]').click()
  await expect(
    page.locator(`.v-toolbar:has-text("${target} ${screen}")`),
  ).not.toBeVisible()
}

async function deleteScreen(page, utils, target, screen) {
  await expect(
    page.locator(`.v-toolbar:has-text("${target} ${screen}")`),
  ).toBeVisible()
  await page.locator('[data-test=edit-screen-icon]').click()
  await page.locator('[data-test=delete-screen-icon]').click()
  await page.locator('button:has-text("Delete")').click()
  await page.locator('[data-test="select-screen"]').click()
  await expect(
    page.locator(`.v-list-item__title:text-is("${screen}")`),
  ).not.toBeVisible()
}

test('changes targets', async ({ page, utils }) => {
  await page.locator('[data-test="select-target"]').click()
  await page.getByRole('option', { name: 'SYSTEM', exact: true }).click()
  await expect(page.locator('[data-test="select-screen"]')).toContainText(
    'STATUS',
  )
})

test('displays INST ADCS', async ({ page, utils }) => {
  await showScreen(page, utils, 'INST', 'ADCS')
})

test('displays INST ARRAY', async ({ page, utils }) => {
  await showScreen(page, utils, 'INST', 'ARRAY')
})

test('displays INST BLOCK', async ({ page, utils }) => {
  await showScreen(page, utils, 'INST', 'BLOCK')
})

test('displays INST COMMANDING', async ({ page, utils }) => {
  await showScreen(page, utils, 'INST', 'COMMANDING', async function () {
    // This is the expansion panel button
    await page.locator('#innerapp button').first().click()

    await page.getByRole('combobox').filter({ hasText: 'NORMAL' }).click()
    await page.getByRole('option', { name: 'NORMAL' }).click()
    await page.getByRole('button', { name: 'Start Collect' }).click()
    // Send clear command which is hazardous
    await page.getByRole('button', { name: 'Send' }).click()
    await expect(
      page.getByText('Warning: Command is Hazardous. Send?'),
    ).toBeVisible()
    await page.getByRole('dialog').getByRole('button', { name: 'Send' }).click()

    await page.getByRole('combobox').filter({ hasText: 'collect.rb' }).click()
    await page.getByText('checks.rb').click()
    const page1Promise = page.waitForEvent('popup')
    await page.getByRole('button', { name: 'Run Script' }).click()
    const page1 = await page1Promise
    await expect(page1.locator('[data-test=state] input')).toHaveValue(
      'error',
      {
        timeout: 30000,
      },
    )
    await page1.locator('[data-test="stop-button"]').click()
    await page1.close()
  })
})

test('displays INST GRAPHS', async ({ page, utils }) => {
  await showScreen(page, utils, 'INST', 'GRAPHS')
})

test('displays INST GROUND', async ({ page, utils }) => {
  await showScreen(page, utils, 'INST', 'GROUND')
})

test('displays INST HS', async ({ page, utils }) => {
  await showScreen(page, utils, 'INST', 'HS', async function () {
    await expect(page.locator('text=Health and Status')).toBeVisible()
    await page.locator('[data-test=minimize-screen-icon]').click()
    await expect(page.locator('text=Health and Status')).not.toBeVisible()
    await page.locator('[data-test=maximize-screen-icon]').click()
    await expect(page.locator('text=Health and Status')).toBeVisible()
  })
})

test('displays INST IMAGE', async ({ page, utils }) => {
  await showScreen(page, utils, 'INST', 'IMAGE')
})

test('displays INST LATEST', async ({ page, utils }) => {
  await showScreen(page, utils, 'INST', 'LATEST')
})

test('displays INST LAUNCHER', async ({ page, utils }) => {
  await page.locator('[data-test="select-target"]').click()
  await page.getByRole('option', { name: 'INST', exact: true }).click()
  await page.locator('[data-test="select-screen"]').click()
  await page.getByRole('option', { name: 'LAUNCHER', exact: true }).click()
  await expect(
    page.locator('.v-toolbar:has-text("INST LAUNCHER")'),
  ).toBeVisible()
  await page.getByRole('button', { name: 'HS', exact: true }).click()
  await expect(page.locator('.v-toolbar:has-text("INST HS")')).toBeVisible()
  await page.getByRole('button', { name: 'CMD', exact: true }).click()
  await expect(
    page.locator('.v-toolbar:has-text("INST COMMANDING")'),
  ).toBeVisible()
  await page.getByRole('button', { name: 'GROUND', exact: true }).click()
  await expect(page.locator('.v-toolbar:has-text("INST GROUND")')).toBeVisible()
  await page.getByRole('button', { name: 'Close HS & CMD' }).click()
  await expect(page.locator('.v-toolbar:has-text("INST HS")')).not.toBeVisible()
  await expect(
    page.locator('.v-toolbar:has-text("INST COMMANDING")'),
  ).not.toBeVisible()
  await expect(page.locator('.v-toolbar:has-text("INST GROUND")')).toBeVisible()
  await page.getByRole('button', { name: 'Close All' }).click()
  await expect(
    page.locator('.v-toolbar:has-text("INST GROUND")'),
  ).not.toBeVisible()
  await expect(
    page.locator('.v-toolbar:has-text("INST LAUNCHER")'),
  ).not.toBeVisible()
})

test('displays INST LIMITS', async ({ page, utils }) => {
  await showScreen(page, utils, 'INST', 'LIMITS')
})

test('displays INST OTHER', async ({ page, utils }) => {
  await showScreen(page, utils, 'INST', 'OTHER')
})

test('displays INST PARAMS', async ({ page, utils }) => {
  await showScreen(page, utils, 'INST', 'PARAMS')
})

test('displays INST ROLLUP', async ({ page, utils }) => {
  await showScreen(page, utils, 'INST', 'ROLLUP')
})

test('displays INST SIMPLE', async ({ page, utils }) => {
  const text = 'TEST' + Math.floor(Math.random() * 10000)
  await showScreen(page, utils, 'INST', 'SIMPLE', async function () {
    await expect(page.locator(`text=${text}`)).not.toBeVisible()
    await page.locator('[data-test=edit-screen-icon]').click()
    await page.locator('textarea').fill(`SCREEN AUTO AUTO 0.5
LABEL ${text}
BIG INST HEALTH_STATUS TEMP2`)
    await page.locator('[data-test="edit-screen-save"]').click()
    await expect(page.locator(`text=${text}`)).toBeVisible()
    await page.locator('[data-test=edit-screen-icon]').click()
    await expect(
      page.locator(`.v-toolbar:has-text("Edit Screen")`),
    ).toBeVisible()
    await utils.download(
      page,
      '[data-test=download-screen-icon]',
      function (contents) {
        expect(contents).toContain(`LABEL ${text}`)
        expect(contents).toContain('BIG INST HEALTH_STATUS TEMP2')
      },
    )
    await page.locator('button:has-text("Cancel")').click()
    await expect(
      page.locator(`.v-toolbar:has-text("Edit Screen")`),
    ).not.toBeVisible()
  })
})

test('displays INST TABS', async ({ page, utils }) => {
  await showScreen(page, utils, 'INST', 'TABS')
})

test('displays INST WEB', async ({ page, utils }) => {
  await showScreen(page, utils, 'INST', 'WEB')
})

test('creates new blank screen', async ({ page, utils }) => {
  await page.locator('[data-test="new-screen"]').click()
  await expect(page.locator(`.v-toolbar:has-text("New Screen")`)).toBeVisible()
  await page.locator('[data-test="new-screen-target"]').click()
  await page.getByRole('option', { name: 'INST2' }).click()
  await expect(
    page.locator('[data-test="new-screen-target"]'),
  ).toContainText('INST2')
  // Check trying to create an existing screen
  await page
    .locator('[data-test="new-screen-name"] input')
    .pressSequentially('adcs')
  await expect(page.locator('.v-dialog')).toContainText(
    'Screen ADCS already exists!',
  )
  // Create the screen name as upcase because OpenC3 upcases the name
  const screen = 'SCREEN' + Math.floor(Math.random() * 10000)
  await page.locator('[data-test="new-screen-name"] input').fill(screen)
  await page.getByRole('button', { name: 'Save' }).click()
  await expect(
    page.locator(`.v-toolbar:has-text("INST2 ${screen}")`),
  ).toBeVisible()
  await deleteScreen(page, utils, 'INST2', screen)
})

test('creates new screen based on packet', async ({ page, utils }) => {
  await page.locator('[data-test="new-screen"]').click()
  await expect(page.locator(`.v-toolbar:has-text("New Screen")`)).toBeVisible()
  await page.locator('[data-test="new-screen-packet"]').click()
  await page.getByRole('option', { name: 'HEALTH_STATUS' }).click()
  expect(await page.inputValue('[data-test=new-screen-name] input')).toMatch(
    'health_status',
  )
  await page.getByRole('button', { name: 'Save' }).click()
  await expect(
    page.locator(`.v-toolbar:has-text("INST HEALTH_STATUS")`),
  ).toBeVisible()
  await deleteScreen(page, utils, 'INST', 'HEALTH_STATUS')
})

test('opens SCREEN documentation from context menu', async ({
  page,
  utils,
}) => {
  await showScreen(page, utils, 'INST', 'ADCS', async function () {
    await page.locator('[data-test=edit-screen-icon]').click()
    await expect(
      page.locator(`.v-toolbar:has-text("Edit Screen")`),
    ).toBeVisible()
    await page
      .locator('pre div')
      .filter({ hasText: 'SCREEN' })
      .nth(0)
      .click({ button: 'right', position: { x: 10, y: 10 } })
    const page1Promise = page.waitForEvent('popup')
    await page.getByText('SCREEN documentation').click()
    const page1 = await page1Promise
    await expect(page1.locator('h1').nth(0)).toContainText('Screens')
    await page1.close()
    await page.locator('button:has-text("Cancel")').click()
  })
})

test('plays back to a screen', async ({ page, utils }) => {
  await showScreen(page, utils, 'INST', 'ADCS', async function () {
    // Helper to parse timestamp string to epoch seconds
    const parseTime = (timeStr: string): number => {
      // Format: "2026-01-26 15:16:13.116"
      return Math.floor(new Date(timeStr).getTime() / 1000)
    }

    // Define the locator for the PACKET_TIMEFORMATTED value
    const packetTimeInput = page
      .locator('[data-test="label"]:has-text("PACKET_TIMEFORMATTED")')
      .locator('..')
      .locator('[data-test="value"] input')

    // Wait for it to have a valid timestamp value before entering playback mode
    await expect(packetTimeInput).toHaveValue(
      /\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}/,
    )

    await page.locator('[data-test="telemetry-viewer-file"]').click()
    await page.getByRole('checkbox', { name: 'Playback Mode' }).check()
    await page.keyboard.press('Escape') // Close the file menu

    // Open and close the time dialog
    await page
      .locator('[data-test="playback-time"]')
      .getByRole('button')
      .click()
    await utils.sleep(500)
    await page.keyboard.press('Escape')

    const start = sub(new Date(), { minutes: 2 })
    await page
      .locator('[data-test=playback-date] input')
      .fill(format(start, 'yyyy-MM-dd'))
    await page
      .locator('[data-test=playback-time] input')
      .fill(format(start, 'HH:mm:ss'))

    // Click play, wait for time to increment, then pause
    await page.getByRole('button', { name: 'Play / Pause' }).click()
    await utils.sleep(1100)
    // Get time after starting playback
    let previousTime = parseTime(await packetTimeInput.inputValue())
    await expect
      .poll(async () => parseTime(await packetTimeInput.inputValue()))
      .toBeGreaterThan(previousTime)
    await page.getByRole('button', { name: 'Play / Pause' }).click()
    await utils.sleep(500)

    // Verify step forward increments by 1s
    previousTime = parseTime(await packetTimeInput.inputValue())
    await page.locator('[data-test="playback-step-forward"]').click()
    await expect
      .poll(async () => parseTime(await packetTimeInput.inputValue()))
      .toBe(previousTime + 1)

    // Verify step backward decrements by 1s
    previousTime = parseTime(await packetTimeInput.inputValue())
    await page.locator('[data-test="playback-step-backward"]').click()
    await expect
      .poll(async () => parseTime(await packetTimeInput.inputValue()))
      .toBe(previousTime - 1)

    // Verify skip forward increments by 15s
    previousTime = parseTime(await packetTimeInput.inputValue())
    await page.locator('[data-test="playback-skip-forward"]').click()
    await expect
      .poll(async () => parseTime(await packetTimeInput.inputValue()))
      .toBe(previousTime + 10)

    // Verify skip backward decrements by 15s
    previousTime = parseTime(await packetTimeInput.inputValue())
    await page.locator('[data-test="playback-skip-backward"]').click()
    await expect
      .poll(async () => parseTime(await packetTimeInput.inputValue()))
      .toBe(previousTime - 10)

    // Change step value to 2 and verify step forward increments by 2s
    await page.getByRole('spinbutton', { name: 'Step (Speed)' }).fill('2')
    previousTime = parseTime(await packetTimeInput.inputValue())
    await page.locator('[data-test="playback-step-forward"]').click()
    await expect
      .poll(async () => parseTime(await packetTimeInput.inputValue()))
      .toBe(previousTime + 2)

    // Change skip value to 15 and verify skip forward increments by 15s
    await page.getByRole('spinbutton', { name: 'Skip' }).fill('15')
    previousTime = parseTime(await packetTimeInput.inputValue())
    await page.locator('[data-test="playback-skip-forward"]').click()
    await expect
      .poll(async () => parseTime(await packetTimeInput.inputValue()))
      .toBe(previousTime + 15)
  })
})
