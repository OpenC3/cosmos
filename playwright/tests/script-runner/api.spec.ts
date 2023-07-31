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
# All changes Copyright 2022, OpenC3, Inc.
# All Rights Reserved
*/

// @ts-check
import { test, expect } from './../fixture'

test.use({
  toolPath: '/tools/scriptrunner',
  toolName: 'Script Runner',
})

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
    'Writing DEFAULT/targets_modified/INST/test.txt'
  )
  await expect(page.locator('[data-test=output-messages]')).toContainText(
    'Reading DEFAULT/targets_modified/INST/test.txt'
  )
  await expect(page.locator('[data-test=output-messages]')).toContainText(
    'file contents'
  )
  await expect(page.locator('[data-test=output-messages]')).toContainText(
    'Deleting DEFAULT/targets_modified/INST/test.txt'
  )
  // Restart after the error
  await page.locator('[data-test=go-button]').click()
  await expect(page.locator('[data-test=output-messages]')).toContainText(
    'Reading DEFAULT/targets_modified/INST/screens/web.txt'
  )
  await expect(page.locator('[data-test=output-messages]')).toContainText(
    'Edited web'
  )
  await expect(page.locator('[data-test=output-messages]')).toContainText(
    'Reading DEFAULT/targets/INST/screens/web.txt'
  )
  await expect(page.locator('[data-test=output-messages]')).toContainText(
    'Original web'
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

  await page.locator('[data-test="cosmos-script-runner-script"]').click()
  await page.getByText('Execution Status').click()
  await page.getByRole('cell', { name: 'Connect' }).nth(0).click()

  await expect(page.locator('[data-test=state]')).toHaveValue('error')
  await page.locator('[data-test="stop-button"]').click()
  await expect(page.locator('[data-test=state]')).toHaveValue('stopped')
})
