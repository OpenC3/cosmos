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

import type { Page } from '@playwright/test'
import { Utilities } from '../../utilities'
import { test, expect } from './../fixture'

test.use({
  toolPath: '/tools/scriptrunner',
  toolName: 'Script Runner',
})

async function openFile(page: Page, utils: Utilities, filename: string) {
  await page.locator('[data-test=script-runner-file]').click()
  await page.locator('text=Open File').click()
  await utils.sleep(500) // Allow background data to fetch
  await expect(
    page.locator('.v-dialog').getByText('INST2', { exact: true }),
  ).toBeVisible()
  await page.locator('[data-test=file-open-save-search] input').fill(filename)
  await page.locator(`text=${filename}`).click()
  await page.locator('[data-test=file-open-save-submit-btn]').click()
  await expect(page.locator('.v-dialog')).not.toBeVisible()

  // Check for potential "<User> is editing this script"
  // This can happen if we had to do a retry on this test
  const someone = page.getByText('is editing this script')
  if (await someone.isVisible()) {
    await page.locator('[data-test="unlock-button"]').click()
    await page.locator('[data-test="confirm-dialog-force unlock"]').click()
  }
}

async function runScript(
  page: Page,
  utils: Utilities,
  filename: string,
  callback = async (): Promise<any> => {},
) {
  await openFile(page, utils, filename)
  await page.locator('[data-test=start-button]').click()
  await callback()
  await expect(page.locator('[data-test=state] input')).toHaveValue(
    'completed',
    {
      timeout: 60000,
    },
  )
}

test('opens a target file', async ({ page, utils }) => {
  await page.locator('textarea')
    .fill(`put_target_file("INST/test.txt", "file contents")
file = get_target_file("INST/test.txt")
puts file.read
file.delete
delete_target_file("INST/test.txt")
file = get_target_file("INST/test.txt")
puts file.read # Causes error because file is nil
file = get_target_file("INST/screens/web.txt")
web = file.read
web += 'LABEL "TEST"'
put_target_file("INST/screens/web.txt", web)
file = get_target_file("INST/screens/web.txt")
if file.read.include?("TEST")
  puts "Edited web"
end
file = get_target_file("INST/screens/web.txt", original: true)
if !file.read.include?("TEST")
  puts "Original web"
end
delete_target_file("INST/screens/web.txt") # Cleanup modified`)

  await page.locator('[data-test=start-button]').click()
  await expect(page.locator('[data-test=state] input')).toHaveValue('error', {
    timeout: 30000,
  })
  await expect(page.locator('[data-test=output-messages]')).toContainText(
    'Writing DEFAULT/targets_modified/INST/test.txt',
  )
  await expect(page.locator('[data-test=output-messages]')).toContainText(
    'Reading DEFAULT/targets_modified/INST/test.txt',
  )
  await expect(page.locator('[data-test=output-messages]')).toContainText(
    'file contents',
  )
  await expect(page.locator('[data-test=output-messages]')).toContainText(
    'Deleting DEFAULT/targets_modified/INST/test.txt',
  )
  // Restart after the error
  await page.locator('[data-test=go-button]').click()
  await expect(page.locator('[data-test=output-messages]')).toContainText(
    'Reading DEFAULT/targets_modified/INST/screens/web.txt',
  )
  await expect(page.locator('[data-test=output-messages]')).toContainText(
    'Edited web',
  )
  await expect(page.locator('[data-test=output-messages]')).toContainText(
    'Reading DEFAULT/targets/INST/screens/web.txt',
  )
  await expect(page.locator('[data-test=output-messages]')).toContainText(
    'Original web',
  )
  await expect(page.locator('[data-test=state] input')).toHaveValue('completed')
})

test('runs a script', async ({ page, utils }) => {
  await page
    .locator('textarea')
    .fill(`script_run("INST/procedures/disconnect.rb")`)
  await page.locator('[data-test=start-button]').click()
  await expect(page.locator('[data-test=state] input')).toHaveValue(
    'Connecting...',
    {
      timeout: 5000,
    },
  )
  await expect(page.locator('[data-test=state] input')).toHaveValue(
    'completed',
    {
      timeout: 20000,
    },
  )

  await page.locator('[data-test="script-runner-script"]').click()
  await page.getByText('Execution Status').click()
  await utils.sleep(1000)
  await page.getByText('Running Scripts').click()
  await expect(
    page.locator('[data-test="running-scripts"] thead').getByText('Connect'),
  ).toBeVisible()
  await page
    .locator(
      '[data-test="running-scripts"] tr:has-text("INST/procedures/disconnect.rb")',
    )
    .first()
    .getByRole('button', { name: 'Connect' })
    .click()

  await expect(page.locator('[data-test=state] input')).toHaveValue('error', {
    timeout: 20000,
  })
  await page.locator('[data-test="stop-button"]').click()
  await expect(page.locator('[data-test=state] input')).toHaveValue('stopped')
})

test('test ruby calendar apis', async ({ page, utils }) => {
  await runScript(page, utils, 'calendar.rb', async function () {
    await expect(page.locator('[data-test=state] input')).toHaveValue('error', {
      timeout: 20000,
    })
    await page.locator('[data-test=go-button]').click()
  })
})

test('test python calendar apis', async ({ page, utils }) => {
  await runScript(page, utils, 'calendar.py', async function () {
    await expect(page.locator('[data-test=state] input')).toHaveValue('error', {
      timeout: 20000,
    })
    await page.locator('[data-test=go-button]').click()
  })
})

test('test ruby stash apis', async ({ page, utils }) => {
  await runScript(page, utils, 'stash.rb')
})

test('test python stash apis', async ({ page, utils }) => {
  await runScript(page, utils, 'stash.py')
})

async function testMetadataApis(
  page: Page,
  utils: Utilities,
  filename: string,
) {
  // Clear other test data
  await page.goto('/tools/admin/redis')
  await page
    .getByLabel('Redis command')
    .fill('zremrangebyscore DEFAULT__METADATA -inf +inf')
  await page.getByLabel('Redis command').press('Enter')
  await page.goto('/tools/scriptrunner')

  await openFile(page, utils, filename)
  await page.locator('[data-test=script-runner-script]').click()
  await page.locator('[data-test="script-runner-script-metadata"]').click()
  await utils.sleep(500)
  await expect(page.locator('[data-test="new-event"]')).toBeVisible()
  // Delete any existing metadata so we start fresh
  while (true) {
    if (await page.$('[data-test=delete-event]')) {
      await page.locator('[data-test=delete-event] >> nth=0').click()
      await page.locator('[data-test=confirm-dialog-delete]').click()
      await utils.sleep(300)
    } else {
      break
    }
  }
  await page.locator('[data-test="close-event-list"]').click()

  await page.locator('[data-test=start-button]').click()
  await expect(page.locator('[data-test="new-event"]')).toBeVisible({
    timeout: 20000,
  })
  await page.locator('[data-test="new-event"]').click()
  await page.getByRole('button', { name: 'Next', exact: true }).click()
  await page.locator('[data-test="new-metadata-icon"]').click()
  await page
    .locator('[data-test="key-0"]')
    .locator('input')
    .fill('inputkey_' + filename)
  await page
    .locator('[data-test="value-0"]')
    .locator('input')
    .fill('inputvalue')
  await page.getByRole('button', { name: 'Ok' }).click()
  await page.locator('[data-test="close-event-list"]').click()

  await expect(page.locator('[data-test=state] input')).toHaveValue(
    'completed',
    {
      timeout: 20000,
    },
  )
}

test('test ruby metadata apis', async ({ page, utils }) => {
  await testMetadataApis(page, utils, 'metadata.rb')
  await expect(page.locator('[data-test=output-messages]')).toContainText(
    '"setkey" => 1',
  )
  await expect(page.locator('[data-test=output-messages]')).toContainText(
    '"setkey" => 2',
  )
  await expect(page.locator('[data-test=output-messages]')).toContainText(
    '"updatekey" => 3',
  )
  await expect(page.locator('[data-test=output-messages]')).toContainText(
    '"inputkey_metadata.rb" => "inputvalue"',
  )
})

test('test python metadata apis', async ({ page, utils }) => {
  await testMetadataApis(page, utils, 'metadata.py')
  await expect(page.locator('[data-test=output-messages]')).toContainText(
    "'setkey': 1",
  )
  await expect(page.locator('[data-test=output-messages]')).toContainText(
    "'setkey': 2",
  )
  await expect(page.locator('[data-test=output-messages]')).toContainText(
    "'updatekey': 3",
  )
  await expect(page.locator('[data-test=output-messages]')).toContainText(
    "'inputkey_metadata.py': 'inputvalue'",
  )
})

// The screen APIs were originally exercised by a single long script that
// chained ~10 transient-state assertions. Each screen was only visible for a
// 2s window, so under load a lagged render could miss a window and fail the
// whole test; a retry then re-ran every step (and re-triggered the file lock
// contention in openFile). These are split into focused tests, each running a
// small inline script so a failure is isolated, retries are cheap, and there
// is no "<user> is editing this script" lock to work around.

type ScriptLanguage = 'ruby' | 'python'

// A leading marker line forces Script Runner's language auto-detection for an
// unsaved inline script (see detectLanguage in ScriptRunner.vue): `puts ` marks
// Ruby, an `(f"` f-string marks Python.
function languageMarker(language: ScriptLanguage): string {
  return language === 'ruby' ? 'puts "start"' : 'print(f"start")'
}

function screenDefinition(language: ScriptLanguage, target: string): string {
  const body = `
SCREEN AUTO AUTO 1.0

VERTICALBOX "Test Screen"
  LABELVALUE ${target} HEALTH_STATUS TEMP1
END
`
  return language === 'ruby' ? `'${body}'` : `"""${body}"""`
}

async function startInlineScript(page: Page, script: string) {
  await page.locator('textarea').fill(script)
  await page.locator('[data-test=start-button]').click()
}

async function expectCompleted(page: Page) {
  await expect(page.locator('[data-test=state] input')).toHaveValue(
    'completed',
    { timeout: 30000 },
  )
}

// Generous timeout so a slow first render (fetch definition + telemetry
// subscribe over the WebSocket) doesn't miss a screen's visibility window.
const SCREEN_TIMEOUT = 15000

async function testDisplayAndClearScreen(
  page: Page,
  language: ScriptLanguage,
  target: string,
) {
  await startInlineScript(
    page,
    `${languageMarker(language)}
display_screen("${target}", "ADCS")
wait(3)
display_screen("${target}", "HS", 400, 0)
wait(3)
clear_screen("${target}", "ADCS")
wait(3)
clear_all_screens()`,
  )
  const timeout = SCREEN_TIMEOUT
  await expect(page.getByText(`${target} ADCS`, { exact: true })).toBeVisible({
    timeout,
  })
  await expect(page.getByText(`${target} HS`, { exact: true })).toBeVisible({
    timeout,
  })
  // clear_screen removes only ADCS; HS stays up
  await expect(
    page.getByText(`${target} ADCS`, { exact: true }),
  ).not.toBeVisible({ timeout })
  await expect(page.getByText(`${target} HS`, { exact: true })).toBeVisible({
    timeout,
  })
  // clear_all_screens removes HS
  await expect(page.getByText(`${target} HS`, { exact: true })).not.toBeVisible(
    { timeout },
  )
  await expectCompleted(page)
}

async function testClearAllScreens(
  page: Page,
  language: ScriptLanguage,
  target: string,
) {
  await startInlineScript(
    page,
    `${languageMarker(language)}
display_screen("${target}", "IMAGE")
wait(3)
display_screen("${target}", "HS", 400, 0)
wait(3)
clear_all_screens()`,
  )
  const timeout = SCREEN_TIMEOUT
  await expect(page.getByText(`${target} IMAGE`, { exact: true })).toBeVisible({
    timeout,
  })
  await expect(page.getByText(`${target} HS`, { exact: true })).toBeVisible({
    timeout,
  })
  await expect(
    page.getByText(`${target} IMAGE`, { exact: true }),
  ).not.toBeVisible({ timeout })
  await expect(page.getByText(`${target} HS`, { exact: true })).not.toBeVisible(
    { timeout },
  )
  await expectCompleted(page)
}

async function testLocalScreen(
  page: Page,
  language: ScriptLanguage,
  target: string,
) {
  await startInlineScript(
    page,
    `${languageMarker(language)}
local_screen("TEST", ${screenDefinition(language, target)})
wait(3)
clear_all_screens()`,
  )
  const timeout = SCREEN_TIMEOUT
  await expect(page.getByText('LOCAL TEST', { exact: true })).toBeVisible({
    timeout,
  })
  await expect(page.getByText('LOCAL TEST', { exact: true })).not.toBeVisible({
    timeout,
  })
  await expectCompleted(page)
}

async function testCreateAndDeleteScreen(
  page: Page,
  language: ScriptLanguage,
  target: string,
) {
  await startInlineScript(
    page,
    `${languageMarker(language)}
create_screen("${target}", "TEST", ${screenDefinition(language, target)})
display_screen("${target}", "TEST")
wait(3)
clear_all_screens()
delete_screen("${target}", "TEST")
display_screen("${target}", "TEST") # Expected to fail because the screen was deleted`,
  )
  const timeout = SCREEN_TIMEOUT
  await expect(page.getByText(`${target} TEST`, { exact: true })).toBeVisible({
    timeout,
  })
  await expect(
    page.getByText(`${target} TEST`, { exact: true }),
  ).not.toBeVisible({ timeout })
  // Displaying the deleted screen raises an error
  await expect(page.locator('[data-test=state] input')).toHaveValue('error', {
    timeout,
  })
  await page.locator('[data-test=go-button]').click()
  await expectCompleted(page)
}

for (const { language, target } of [
  { language: 'ruby' as const, target: 'INST' },
  { language: 'python' as const, target: 'INST2' },
]) {
  // The `utils` fixture performs the goto to the Script Runner tool, so it must
  // be destructured (even when otherwise unused) for the page to navigate.
  test(`test ${language} display and clear screen`, async ({ page, utils }) => {
    await testDisplayAndClearScreen(page, language, target)
  })

  test(`test ${language} clear all screens`, async ({ page, utils }) => {
    await testClearAllScreens(page, language, target)
  })

  test(`test ${language} local screen`, async ({ page, utils }) => {
    await testLocalScreen(page, language, target)
  })

  test(`test ${language} create and delete screen`, async ({ page, utils }) => {
    await testCreateAndDeleteScreen(page, language, target)
  })
}

test('test ruby script apis', async ({ page, utils }) => {
  await runScript(page, utils, 'scripting.rb', async function () {
    await expect(page.locator('[data-test=state] input')).toHaveValue(
      /paused \d+s/,
    )
    await page.locator('[data-test=step-button]').click()
    await utils.sleep(500)
    await page.locator('[data-test=step-button]').click()
    await utils.sleep(500)
    await page.locator('[data-test=step-button]').click()
    await utils.sleep(500)
    await page.locator('[data-test=step-button]').click()
  })
})

test('test python script apis', async ({ page, utils }) => {
  await runScript(page, utils, 'scripting.py', async function () {
    await expect(page.locator('[data-test=state] input')).toHaveValue(
      /paused \d+s/,
    )
    await page.locator('[data-test=step-button]').click()
    await utils.sleep(500)
    await page.locator('[data-test=step-button]').click()
    await utils.sleep(500)
    await page.locator('[data-test=step-button]').click()
    await utils.sleep(500)
    await page.locator('[data-test=step-button]').click()
  })
})

test('test python numpy import', async ({ page, utils }) => {
  await openFile(page, utils, 'numpy.py')
  await page.locator('[data-test=start-button]').click()
  await expect(page.locator('[data-test=state] input')).toHaveValue(
    'Connecting...',
    {
      timeout: 5000,
    },
  )
  await expect(page.locator('[data-test=state] input')).toHaveValue(
    'completed',
    {
      timeout: 20000,
    },
  )
})
