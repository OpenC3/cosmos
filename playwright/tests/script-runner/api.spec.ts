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
# All changes Copyright 2025, OpenC3, Inc.
# All Rights Reserved
*/

// @ts-check
import { test, expect } from './../fixture'

test.use({
  toolPath: '/tools/scriptrunner',
  toolName: 'Script Runner',
})

async function openFile(page, utils, filename) {
  await page.locator('[data-test=script-runner-file]').click()
  await page.locator('text=Open File').click()
  await expect(
    page.locator('.v-dialog').getByText('INST2', { exact: true }),
  ).toBeVisible()
  await page.locator('[data-test=file-open-save-search]').type(filename)
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

async function runScript(page, utils, filename, callback = async () => {}) {
  await openFile(page, utils, filename)
  await page.locator('[data-test=start-button]').click()
  await callback()
  await expect(page.locator('[data-test=state] input')).toHaveValue('stopped', {
    timeout: 20000,
  })
}

test('opens a target file', async ({ page, utils }) => {
  await page.locator('textarea').fill(`
  put_target_file("INST/test.txt", "file contents")
  file = get_target_file("INST/test.txt")
  puts file.read
  file.delete
  delete_target_file("INST/test.txt")
  get_target_file("INST/test.txt") # Causes error

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
  delete_target_file("INST/screens/web.txt") # Cleanup modified
  `)

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
  await expect(page.locator('[data-test=state] input')).toHaveValue('stopped')
})

test('runs a script', async ({ page, utils }) => {
  await page.locator('textarea').fill(`
  script_run("INST/procedures/disconnect.rb")
  `)
  await page.locator('[data-test=start-button]').click()
  await expect(page.locator('[data-test=state] input')).toHaveValue(
    'Connecting...',
    {
      timeout: 5000,
    },
  )
  await expect(page.locator('[data-test=state] input')).toHaveValue('stopped', {
    timeout: 20000,
  })

  await page.locator('[data-test="script-runner-script"]').click()
  await page.getByText('Execution Status').click()
  await page.getByRole('button', { name: 'Connect' }).first().click()

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

// Note: For local testing you can clear metadata
// Go to the Admin / Redis tab and enter the following:
//   Persistent: zremrangebyscore DEFAULT__METADATA -inf +inf
async function testMetadataApis(page, utils, filename) {
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
  await page.locator('[data-test="key-0"]').locator('input').fill('inputkey')
  await page
    .locator('[data-test="value-0"]')
    .locator('input')
    .fill('inputvalue')
  await page.getByRole('button', { name: 'Ok' }).click()
  await page.locator('[data-test="close-event-list"]').click()

  await expect(page.locator('[data-test=state] input')).toHaveValue('stopped', {
    timeout: 20000,
  })
}

test('test ruby metadata apis', async ({ page, utils }) => {
  await testMetadataApis(page, utils, 'metadata.rb')
  await expect(page.locator('[data-test=output-messages]')).toContainText(
    '"setkey"=>1',
  )
  await expect(page.locator('[data-test=output-messages]')).toContainText(
    '"setkey"=>2',
  )
  await expect(page.locator('[data-test=output-messages]')).toContainText(
    '"updatekey"=>3',
  )
  await expect(page.locator('[data-test=output-messages]')).toContainText(
    '"inputkey"=>"inputvalue"',
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
    "'inputkey': 'inputvalue'",
  )
})

async function testScreenApis(page, utils, filename, target) {
  await runScript(page, utils, filename, async function () {
    // script displays INST ADCS
    await expect(
      page.getByText(`${target} ADCS`, { exact: true }),
    ).toBeVisible()
    // script displays INST HS
    await expect(page.getByText(`${target} HS`, { exact: true })).toBeVisible()
    // script calls clear_screen("INST", "ADCS")
    await expect(
      page.getByText(`${target} ADCS`, { exact: true }),
    ).not.toBeVisible()
    // script displays INST IMAGE
    await expect(
      page.getByText(`${target} IMAGE`, { exact: true }),
    ).toBeVisible()
    // script calls clear_all_screens()
    await expect(
      page.getByText(`${target} HS`, { exact: true }),
    ).not.toBeVisible()
    await expect(
      page.getByText(`${target} IMAGE`, { exact: true }),
    ).not.toBeVisible()
    // script creates local screen "TEST"
    await expect(page.getByText('LOCAL TEST', { exact: true })).toBeVisible()
    // script calls clear_all_screens()
    await expect(
      page.getByText('LOCAL TEST', { exact: true }),
    ).not.toBeVisible()
    // script creates local screen "INST TEST"
    await expect(
      page.getByText(`${target} TEST`, { exact: true }),
    ).toBeVisible()
    // script calls clear_all_screens()
    await expect(
      page.getByText(`${target} TEST`, { exact: true }),
    ).not.toBeVisible()
    // script deletes INST TEST and tries to display it which results in error
    await expect(page.locator('[data-test=state] input')).toHaveValue('error')
    await page.locator('[data-test=go-button]').click()
  })
}

test('test ruby screen apis', async ({ page, utils }) => {
  await testScreenApis(page, utils, 'screens.rb', 'INST')
})

test('test python screen apis', async ({ page, utils }) => {
  await testScreenApis(page, utils, 'screens.py', 'INST2')
})

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
  await expect(page.locator('[data-test=state] input')).toHaveValue('stopped', {
    timeout: 20000,
  })
})
