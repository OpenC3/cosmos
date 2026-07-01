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

test('alerts show a toast that must be acknowledged to dismiss', async ({
  page,
  utils,
}) => {
  const alertText = 'Playwright alert ack test'
  // Logger.error defaults the scope to ENV['OPENC3_SCOPE'], so it publishes to
  // the scope log stream the Notifications toolbar subscribes to, with ALERT.
  await runLog(
    page,
    `OpenC3::Logger.error("${alertText}", type: OpenC3::Logger::ALERT)`,
  )

  // The alert appears as a toast whose only action is Acknowledge (alerts have
  // no auto-hide timeout, unlike notification toasts which auto-dismiss).
  const toast = page.locator('[data-test=toast]', { hasText: alertText })
  await expect(toast).toBeVisible({ timeout: 20000 })
  const ackButton = toast.getByRole('button', { name: 'Acknowledge' })
  await expect(ackButton).toBeVisible()

  // Wait past the 5s notification auto-hide window to prove the alert persists.
  await page.waitForTimeout(6000)
  await expect(toast).toBeVisible()

  // Acknowledging dismisses the toast.
  await ackButton.click()
  await expect(toast).toBeHidden()
})

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
})
