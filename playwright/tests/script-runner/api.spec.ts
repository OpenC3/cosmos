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
  toolPath: '/tools/scriptrunner',
  toolName: 'Script Runner',
})

async function openFile(page, utils, filename) {
  let half = Math.floor(filename.length / 2)
  let part1 = filename.substring(0, half)
  let part2 = filename.substring(half, filename.length)
  await page.locator('[data-test=script-runner-file]').click()
  await page.locator('text=Open File').click()
  await expect(page.locator('.v-dialog >> text=INST2')).toBeVisible()
  await utils.sleep(200)
  await page.locator('[data-test=file-open-save-search]').type(part1)
  await utils.sleep(200)
  await page.locator('[data-test=file-open-save-search]').type(part2)
  await utils.sleep(200)
  await page.locator(`text=${filename}`).click()
  await page.locator('[data-test=file-open-save-submit-btn]').click()
  await expect(page.locator('.v-dialog')).not.toBeVisible()
  await utils.sleep(500)

  // Check for potential "<User> is editing this script"
  // This can happen if we had to do a retry on this test
  const someone = page.getByText('is editing this script')
  if (await someone.isVisible()) {
    await page.locator('[data-test="unlock-button"]').click()
    await page.locator('[data-test="confirm-dialog-force unlock"]').click()
  }
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
  await expect(page.locator('[data-test=state]')).toHaveValue('error', {
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
  await expect(page.locator('[data-test=state]')).toHaveValue('stopped')
})

test('runs a script', async ({ page, utils }) => {
  await page.locator('textarea').fill(`
  script_run("INST/procedures/disconnect.rb")
  `)
  await page.locator('[data-test=start-button]').click()
  await expect(page.locator('[data-test=state]')).toHaveValue('Connecting...', {
    timeout: 5000,
  })
  await expect(page.locator('[data-test=state]')).toHaveValue('stopped', {
    timeout: 20000,
  })

  await page.locator('[data-test="script-runner-script"]').click()
  await page.getByText('Execution Status').click()
  await page.getByRole('cell', { name: 'Connect' }).nth(0).click()

  await expect(page.locator('[data-test=state]')).toHaveValue('error')
  await page.locator('[data-test="stop-button"]').click()
  await expect(page.locator('[data-test=state]')).toHaveValue('stopped')
})

async function testCalendarApis(page, utils, filename) {
  await openFile(page, utils, filename)
  await page.locator('[data-test=start-button]').click()
  await expect(page.locator('[data-test=state]')).toHaveValue('Connecting...', {
    timeout: 5000,
  })
  await expect(page.locator('[data-test=state]')).toHaveValue('error', {
    timeout: 20000,
  })
  await page.locator('[data-test=go-button]').click()
  await expect(page.locator('[data-test=state]')).toHaveValue('stopped', {
    timeout: 20000,
  })
}

test('test ruby calendar apis', async ({ page, utils }) => {
  await testCalendarApis(page, utils, 'calendar.rb')
})

test('test python calendar apis', async ({ page, utils }) => {
  await testCalendarApis(page, utils, 'calendar.py')
})

async function testStashApis(page, utils, filename) {
  await openFile(page, utils, filename)
  await page.locator('[data-test=start-button]').click()
  await expect(page.locator('[data-test=state]')).toHaveValue('Connecting...', {
    timeout: 5000,
  })
  await expect(page.locator('[data-test=state]')).toHaveValue('stopped', {
    timeout: 20000,
  })
}

test('test ruby stash apis', async ({ page, utils }) => {
  await testStashApis(page, utils, 'stash.rb')
})

test('test python stash apis', async ({ page, utils }) => {
  await testStashApis(page, utils, 'stash.py')
})

// Note: For local testing you can clear metadata
// Go to the Admin / Redis tab and enter the following:
//   Persistent: zremrangebyscore DEFAULT__METADATA -inf +inf
async function testMetadataApis(page, utils, filename) {
  await openFile(page, utils, filename)
  await page.locator('[data-test=script-runner-script]').click()
  await page.locator('[data-test="script-runner-script-metadata"]').click()
  await utils.sleep(500)
  await expect(page.getByText('Metadata Search')).toBeVisible()
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
  await expect(page.getByText('Metadata Search')).toBeVisible({
    timeout: 20000,
  })
  await page.locator('[data-test="new-event"]').click()
  await page.locator('[data-test="metadata-step-two-btn"]').click()
  await page.locator('[data-test="new-metadata-icon"]').click()
  await page.locator('[data-test="key-0"]').fill('inputkey')
  await page.locator('[data-test="value-0"]').fill('inputvalue')
  await page.locator('[data-test="metadata-submit-btn"]').click()
  await page.locator('[data-test="close-event-list"]').click()

  await expect(page.locator('[data-test=state]')).toHaveValue('stopped', {
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
    "{'setkey': 1}",
  )
  await expect(page.locator('[data-test=output-messages]')).toContainText(
    "{'setkey': 2}",
  )
  await expect(page.locator('[data-test=output-messages]')).toContainText(
    "{'updatekey': 3}",
  )
  await expect(page.locator('[data-test=output-messages]')).toContainText(
    "{'inputkey': 'inputvalue'}",
  )
})
