/*
# Copyright 2026 OpenC3, Inc.
# All Rights Reserved.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
# See LICENSE.md for more details.
*/

// @ts-check
import { test, expect } from './fixture'
import { STORAGE_STATE } from './../playwright.config'

// Run inside Script Runner so we can emit log messages from a script. The
// Notifications toolbar (which shows the toast) is present in every tool.
test.use({
  toolPath: '/tools/scriptrunner',
  toolName: 'Script Runner',
})

// Emit a single log message from a running script.
async function runLog(page, ruby) {
  await page.locator('[data-test=script-runner-file]').click()
  await page.locator('text=New File').click()
  await page.waitForTimeout(1000)
  await page.locator('textarea').fill(ruby)
  await page.locator('[data-test=start-button]').click()
}

// Set the QUIET state on both demo sim targets so they stop generating their
// own out-of-limits telemetry (which would raise unrelated limit alerts and
// pollute the toasts these tests assert on). Runs in its own authenticated
// context since before/afterAll have no test-scoped page.
async function setQuiet(browser, baseURL, state) {
  const context = await browser.newContext({ storageState: STORAGE_STATE })
  const page = await context.newPage()
  await page.goto(`${baseURL}/tools/scriptrunner`, {
    waitUntil: 'domcontentloaded',
  })
  await expect(page.locator('.v-app-bar')).toContainText('Script Runner', {
    timeout: 20000,
  })
  await runLog(
    page,
    `cmd("INST QUIET with STATE ${state}")\ncmd("INST2 QUIET with STATE ${state}")`,
  )
  await setSetting(page, 'show-alerts', true)
  if (state === 'TRUE') {
    await setSetting(page, 'show-red-limit-alerts', true)
  } else {
    await setSetting(page, 'show-red-limit-alerts', false)
  }

  // Give the two commands time to be sent before tearing down the context.
  await page.waitForTimeout(3000)
  await context.close()
}

test.beforeAll(async ({ browser, baseURL }) => {
  await setQuiet(browser, baseURL, 'TRUE')
})

test.afterAll(async ({ browser, baseURL }) => {
  await setQuiet(browser, baseURL, 'FALSE')
})

// Open Notification settings and set a switch to the desired state (only
// clicking if it isn't already there), then close the dialog.
async function setSetting(page, dataTest, enable) {
  await page.locator('[data-test=notifications]').click()
  await page.locator('[data-test=notification-settings]').click()
  const input = page.locator(`[data-test=${dataTest}] input`)
  if ((await input.isChecked()) !== enable) {
    // Click the toggle control itself, not the full-width switch row.
    await page
      .locator(`[data-test=${dataTest}] .v-selection-control__input`)
      .click()
  }
  await expect(input).toBeChecked({ checked: enable })
  await page.locator('button:has-text("Close")').click()
  // Close the notifications menu so its overlay stops intercepting clicks.
  await page.keyboard.press('Escape')
}

test('plain notifications only appear in the menu, not as a toast', async ({
  page,
  utils,
}) => {
  const notifyText = 'Playwright notification only test'
  await runLog(
    page,
    `OpenC3::Logger.warn("${notifyText}", type: OpenC3::Logger::NOTIFICATION)`,
  )

  // No toast for a plain notification.
  await page.waitForTimeout(3000)
  await expect(
    page.locator('[data-test=toast]', { hasText: notifyText }),
  ).toHaveCount(0)

  // It does show up in the notifications menu.
  await page.locator('[data-test=notifications]').click()
  await expect(page.locator('[data-test=notification-list]')).toContainText(
    notifyText,
  )
})

test('red limit alerts are gated by the red limit toggle', async ({
  page,
  utils,
}) => {
  // Fresh defaults: master "Show alerts" on, "Show red limit alerts" off.
  const redText = 'Playwright RED limit test'
  const emitRed =
    `OpenC3::Logger.error("${redText}", ` +
    `type: OpenC3::Logger::ALERT, other: { limits_state: 'RED_LOW' })`
  const redToast = page.locator('[data-test=toast]', { hasText: redText })

  // With the red limit toggle off, a red limit alert must NOT toast.
  await setSetting(page, 'show-red-limit-alerts', false)
  await runLog(page, emitRed)
  await page.waitForTimeout(3000)
  await expect(redToast).toHaveCount(0)

  // Enable red limit alerts, then the same alert appears as a must-ack toast.
  await setSetting(page, 'show-red-limit-alerts', true)
  await runLog(page, emitRed)
  await expect(redToast).toBeVisible({ timeout: 20000 })
  await redToast.getByRole('button', { name: 'Acknowledge' }).click()
  await expect(redToast).toBeHidden()
})

test('yellow limit changes never toast, only show in the menu', async ({
  page,
  utils,
}) => {
  const yellowText = 'Playwright YELLOW limit test'
  const emitYellow =
    `OpenC3::Logger.warn("${yellowText}", ` +
    `type: OpenC3::Logger::NOTIFICATION, other: { limits_state: 'YELLOW_LOW' })`
  const yellowToast = page.locator('[data-test=toast]', { hasText: yellowText })

  // Yellow limit changes are notifications, never toasts.
  await runLog(page, emitYellow)
  await page.waitForTimeout(3000)
  await expect(yellowToast).toHaveCount(0)

  // They do appear in the notifications menu.
  await page.locator('[data-test=notifications]').click()
  await expect(page.locator('[data-test=notification-list]')).toContainText(
    yellowText,
  )
})

test('disabling a limit toggle dismisses its existing toasts', async ({
  page,
  utils,
}) => {
  const redText = 'Playwright RED dismiss-on-disable test'
  const emitRed =
    `OpenC3::Logger.error("${redText}", ` +
    `type: OpenC3::Logger::ALERT, other: { limits_state: 'RED_HIGH' })`
  const redToast = page.locator('[data-test=toast]', { hasText: redText })

  // Enable red limit alerts and raise one.
  await setSetting(page, 'show-red-limit-alerts', true)
  await runLog(page, emitRed)
  await expect(redToast).toBeVisible({ timeout: 20000 })

  // Turning the red limit toggle back off clears the displayed alert.
  await setSetting(page, 'show-red-limit-alerts', false)
  await expect(redToast).toBeHidden()

  // Dismissing the toast via the toggle must NOT acknowledge the alert - it
  // remains un-acked in the menu (its Ack button is still shown).
  await page.locator('[data-test=notifications]').click()
  await expect(
    menuRow(page, redText).locator('[data-test=ack-notification]'),
  ).toBeVisible()
})

// A menu row (v-list-item) for the alert carrying the given text.
function menuRow(page, text) {
  return page.locator('[data-test=notification-list] .v-list-item', {
    hasText: text,
  })
}

test('acking a toast marks the same alert read in the menu (event round trip)', async ({
  page,
  utils,
}) => {
  const alertText = 'Playwright toast round-trip test'
  await runLog(
    page,
    `OpenC3::Logger.error("${alertText}", type: OpenC3::Logger::ALERT)`,
  )
  const toast = page.locator('[data-test=toast]', { hasText: alertText })
  await expect(toast).toBeVisible({ timeout: 20000 })

  // The alert is unread in the menu (opening then closing the menu must not
  // mark an alert read - only an explicit ack does).
  await page.locator('[data-test=notifications]').click()
  await expect(
    menuRow(page, alertText).locator('[data-test=ack-notification]'),
  ).toBeVisible()
  await page.keyboard.press('Escape')

  // Acknowledge from the toast; the openc3-ack-alert event marks the menu row
  // read even though the toast lives in a separate app instance.
  await toast.getByRole('button', { name: 'Acknowledge' }).click()
  await expect(toast).toBeHidden()

  await page.locator('[data-test=notifications]').click()
  await expect(
    menuRow(page, alertText).locator('[data-test=ack-notification]'),
  ).toHaveCount(0)
})

test('acknowledging an alert from its dialog marks it read and clears its toast', async ({
  page,
  utils,
}) => {
  const alertText = 'Playwright dialog ack test'
  await runLog(
    page,
    `OpenC3::Logger.error("${alertText}", type: OpenC3::Logger::ALERT)`,
  )
  const toast = page.locator('[data-test=toast]', { hasText: alertText })
  await expect(toast).toBeVisible({ timeout: 20000 })

  // Open the menu, then open the alert's dialog by clicking its title.
  await page.locator('[data-test=notifications]').click()
  await menuRow(page, alertText).getByText(alertText).click()
  const dialogAck = page.locator('[data-test=ack-notification-dialog]')
  await expect(dialogAck).toBeVisible()

  // Acknowledging from the dialog closes it, marks the alert read, and clears
  // the toast.
  await dialogAck.click()
  await expect(dialogAck).toHaveCount(0)
  await expect(toast).toBeHidden()
  await expect(
    menuRow(page, alertText).locator('[data-test=ack-notification]'),
  ).toHaveCount(0)
})

test('acknowledging an alert from the menu marks it read and clears its toast', async ({
  page,
  utils,
}) => {
  const alertText = 'Playwright menu ack test'
  await runLog(
    page,
    `OpenC3::Logger.error("${alertText}", type: OpenC3::Logger::ALERT)`,
  )
  const toast = page.locator('[data-test=toast]', { hasText: alertText })
  await expect(toast).toBeVisible({ timeout: 20000 })

  // Open the menu; an unread alert row exposes an Ack button.
  await page.locator('[data-test=notifications]').click()
  const row = menuRow(page, alertText)
  const ack = row.locator('[data-test=ack-notification]')
  await expect(ack).toBeVisible()

  // Acking from the menu removes the row's Ack button (now read) and also
  // dismisses the matching toast.
  await ack.click()
  await expect(ack).toHaveCount(0)
  await expect(toast).toBeHidden()
})

test('Acknowledge All acks every alert and clears their toasts', async ({
  page,
  utils,
}) => {
  const textA = 'Playwright ack-all A'
  const textB = 'Playwright ack-all B'
  await runLog(
    page,
    `OpenC3::Logger.error("${textA}", type: OpenC3::Logger::ALERT)\n` +
      `OpenC3::Logger.error("${textB}", type: OpenC3::Logger::ALERT)`,
  )
  const toastA = page.locator('[data-test=toast]', { hasText: textA })
  const toastB = page.locator('[data-test=toast]', { hasText: textB })
  await expect(toastA).toBeVisible({ timeout: 20000 })
  await expect(toastB).toBeVisible()

  // Acknowledge All acks both alerts and dismisses both toasts.
  await page.locator('[data-test=notifications]').click()
  await page.locator('[data-test=ack-all-notifications]').click()
  await expect(toastA).toBeHidden()
  await expect(toastB).toBeHidden()
  await expect(
    page.locator('[data-test=notification-list] [data-test=ack-notification]'),
  ).toHaveCount(0)
})

test('Clear Read removes read notifications but keeps un-acked alerts', async ({
  page,
  utils,
}) => {
  const notifyText = 'Playwright clear notification'
  const alertText = 'Playwright clear alert'
  await runLog(
    page,
    `OpenC3::Logger.warn("${notifyText}", type: OpenC3::Logger::NOTIFICATION)\n` +
      `OpenC3::Logger.error("${alertText}", type: OpenC3::Logger::ALERT)`,
  )
  // Wait for the alert toast so we know both messages arrived.
  await expect(
    page.locator('[data-test=toast]', { hasText: alertText }),
  ).toBeVisible({ timeout: 20000 })

  await page.locator('[data-test=notifications]').click()
  const list = page.locator('[data-test=notification-list]')
  await expect(list).toContainText(notifyText)
  await expect(list).toContainText(alertText)

  // Clear Read marks non-alerts read and removes them, leaving the un-acked
  // alert.
  await page.locator('[data-test=clear-notifications]').click()
  await expect(list).not.toContainText(notifyText)
  await expect(list).toContainText(alertText)
})

test('un-acked alerts survive a page reload (must-ack persists)', async ({
  page,
  utils,
}) => {
  const alertText = 'Playwright reload persist test'
  await runLog(
    page,
    `OpenC3::Logger.error("${alertText}", type: OpenC3::Logger::ALERT)`,
  )
  const toast = page.locator('[data-test=toast]', { hasText: alertText })
  await expect(toast).toBeVisible({ timeout: 20000 })

  // Open and close the menu without acking. This must not advance the stream
  // offset past the un-acked alert, otherwise the reload below would drop it.
  await page.locator('[data-test=notifications]').click()
  await page.keyboard.press('Escape')

  // After reload the un-acked alert is re-fetched and toasts again.
  await page.reload()
  await expect(toast).toBeVisible({ timeout: 20000 })
  await toast.getByRole('button', { name: 'Acknowledge' }).click()
  await expect(toast).toBeHidden()
})

test('acked alerts stay acked across a reload (no re-toast)', async ({
  page,
  utils,
}) => {
  const alertText = 'Playwright reload acked test'
  await runLog(
    page,
    `OpenC3::Logger.error("${alertText}", type: OpenC3::Logger::ALERT)`,
  )
  const toast = page.locator('[data-test=toast]', { hasText: alertText })
  await expect(toast).toBeVisible({ timeout: 20000 })

  // Acknowledge, then reload. The acked msg_id is persisted, so the alert must
  // not re-toast and must not reappear as unread in the menu.
  await toast.getByRole('button', { name: 'Acknowledge' }).click()
  await expect(toast).toBeHidden()

  await page.reload()
  await page.waitForTimeout(6000)
  await expect(toast).toHaveCount(0)
  await page.locator('[data-test=notifications]').click()
  await expect(
    menuRow(page, alertText).locator('[data-test=ack-notification]'),
  ).toHaveCount(0)
})

test('turning off Show alerts dismisses existing toasts and suppresses new ones', async ({
  page,
  utils,
}) => {
  const firstText = 'Playwright master toggle existing'
  await runLog(
    page,
    `OpenC3::Logger.error("${firstText}", type: OpenC3::Logger::ALERT)`,
  )
  const firstToast = page.locator('[data-test=toast]', { hasText: firstText })
  await expect(firstToast).toBeVisible({ timeout: 20000 })

  // Turning the master "Show alerts" toggle off dismisses all current toasts.
  await setSetting(page, 'show-alerts', false)
  await expect(firstToast).toBeHidden()

  // With the master toggle off, a new alert does not toast (still logged to
  // the menu).
  const secondText = 'Playwright master toggle new'
  await runLog(
    page,
    `OpenC3::Logger.error("${secondText}", type: OpenC3::Logger::ALERT)`,
  )
  await page.waitForTimeout(3000)
  await expect(
    page.locator('[data-test=toast]', { hasText: secondText }),
  ).toHaveCount(0)
})
