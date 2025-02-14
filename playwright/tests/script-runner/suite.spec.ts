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

async function saveAs(page, filename: string) {
  await page.locator('[data-test=script-runner-file]').click()
  await page.locator('text=Save As...').click()
  await page
    .locator('[data-test=file-open-save-filename] input')
    .fill(`INST/procedures/${filename}`)
  await page.locator('[data-test=file-open-save-submit-btn]').click()

  // Handle Overwrite
  await page.waitForTimeout(1000) // hard wait for 1000ms
  // If we see overwrite, handle it
  if (await page.$('text=Are you sure you want to overwrite')) {
    await page.locator('text=Are you sure you want to overwrite').click()
    await page.locator('button:has-text("Overwrite")').click()
  }

  await expect(page.locator('[data-test=start-suite]')).toBeVisible()
  expect(await page.locator('#sr-controls')).toContainText(
    `INST/procedures/${filename}`,
  )
}

async function deleteFile(page) {
  await page.locator('[data-test=script-runner-file]').click()
  await page.locator('text=Delete File').click()
  await page.locator('button:has-text("Delete")').click()
}

// Run by clicking on the passed startLocator and then wait for the results dialog
// Call the checker function to verify the textarea has the desired results
// and finally click OK to close the dialog
async function runAndCheckResults(
  page,
  utils,
  startLocator,
  validator,
  download = false,
) {
  await page.locator(startLocator).click()
  // Wait for the results ... allow for additional time
  await expect(page.locator('.v-dialog')).toContainText('Script Results', {
    timeout: 30000,
  })
  // Allow the caller to validate the results
  validator(await page.inputValue('.v-dialog >> textarea'))

  // Downloading the report is additional processing so we make it optional
  if (download) {
    await utils.download(
      page,
      'button:has-text("Download")',
      function (contents: string) {
        expect(contents).toContain('Script Report')
        validator(contents)
      },
    )
  }
  await page.locator('button:has-text("Ok")').click()
  await expect(page.locator('.v-dialog')).not.toBeVisible()

  // Verify we're ready to run again
  await expect(page.locator('[data-test=start-suite]')).toBeEnabled()
  await expect(page.locator('[data-test=start-group]')).toBeEnabled()
  await expect(page.locator('[data-test=start-script]')).toBeEnabled()
}

async function suiteTemplate(page, utils, type) {
  await page.locator('[data-test=script-runner-file]').click()
  await page.getByText('New Suite').hover()
  await page.getByText(type).click()
  await utils.sleep(1000)
  // Verify the drop downs are populated
  await expect(page.getByText('Suite:TestSuiteSuite:')).toBeEnabled()
  await expect(page.getByText('Group:PowerGroup:')).toBeEnabled()
  await expect(page.getByText('Script:power_onScript:')).toBeEnabled()
  // Verify Suite Start buttons are enabled
  await expect(page.locator('[data-test=start-suite]')).toBeEnabled()
  await expect(page.locator('[data-test=start-group]')).toBeEnabled()
  await expect(page.locator('[data-test=start-script]')).toBeEnabled()
}

test('generates a ruby suite template', async ({ page, utils }) => {
  await suiteTemplate(page, utils, 'Ruby')
  await expect(
    page
    .locator('pre')
    .filter({ hasText: "require 'openc3/script/suite.rb'" })
    .first()
  ).toBeVisible()
})

test('generates a python suite template', async ({ page, utils }) => {
  await suiteTemplate(page, utils, 'Python')
  await expect(page
    .locator('pre')
    .filter({ hasText: 'from openc3.script.suite import Suite, Group' })
    .first()
  ).toBeVisible()
})

test('loads Suite controls when opening a suite', async ({ page, utils }) => {
  // Open the file
  await page.locator('[data-test=script-runner-file]').click()
  await page.locator('text=Open File').click()
  await utils.sleep(1000)
  await page.locator('[data-test=file-open-save-search] input').fill('my_script_')
  await utils.sleep(500)
  await page.locator('[data-test=file-open-save-search] input').fill('suite')
  await page.locator('text=script_suite >> nth=0').click() // nth=0 because INST, INST2
  await page.locator('[data-test=file-open-save-submit-btn]').click()
  await expect(page.locator('#sr-controls')).toContainText(
    `INST/procedures/my_script_suite.rb`,
  )
  // Verify defaults in the Suite options
  await expect(page.locator('[data-test=pause-on-error] input')).toBeChecked()
  await expect(page.locator('[data-test=manual] input')).toBeChecked()
  await expect(
    page.locator('[data-test=continue-after-error] input'),
  ).toBeChecked()
  await expect(page.locator('[data-test=loop] input')).not.toBeChecked()
  await expect(
    page.locator('[data-test=abort-after-error] input'),
  ).not.toBeChecked()
  await expect(
    page.locator('[data-test=break-loop-on-error] input'),
  ).toBeDisabled()
  // Verify the drop downs are populated
  await expect(page.getByText('Suite:MySuiteSuite:')).toBeEnabled()
  await expect(page.getByText('Group:ExampleGroupGroup:')).toBeEnabled()
  await expect(page.getByText('Script:2Script:')).toBeEnabled()
  // // Verify Suite Start buttons are enabled
  await expect(page.locator('[data-test=start-suite]')).toBeEnabled()
  await expect(page.locator('[data-test=start-group]')).toBeEnabled()
  await expect(page.locator('[data-test=start-script]')).toBeEnabled()
  // Verify Script Start button is disabled
  await expect(page.locator('[data-test=start-button]')).toBeDisabled()

  // Verify Suite controls go away when loading a normal script
  await page.locator('[data-test=script-runner-file]').click()
  await page.locator('text=Open File').click()
  await utils.sleep(1000)
  await page.locator('[data-test=file-open-save-search] input').fill('dis')
  await utils.sleep(500)
  await page.locator('[data-test=file-open-save-search] input').fill('connect')
  await page.locator('text=disconnect >> nth=0').click() // nth=0 because INST, INST2
  await page.locator('[data-test=file-open-save-submit-btn]').click()
  await expect(page.locator('#sr-controls')).toContainText(
    `INST/procedures/disconnect.rb`,
  )
  await expect(page.locator('[data-test=start-suite]')).not.toBeVisible()
  await expect(page.locator('[data-test=start-group]')).not.toBeVisible()
  await expect(page.locator('[data-test=start-script]')).not.toBeVisible()
  await expect(page.locator('[data-test=setup-suite]')).not.toBeVisible()
  await expect(page.locator('[data-test=setup-group]')).not.toBeVisible()
  await expect(page.locator('[data-test=teardown-suite]')).not.toBeVisible()
  await expect(page.locator('[data-test=teardown-group]')).not.toBeVisible()
})

test('disables all suite buttons when running', async ({ page, utils }) => {
  await page.locator('textarea').fill(`
  require "openc3/script/suite.rb"
  class TestGroup < OpenC3::Group
    def test_test; wait; end
  end
  class TestSuite < OpenC3::Suite
    def initialize
      super()
      add_group("TestGroup")
    end
  end
  `)
  await saveAs(page, 'test_suite_buttons.rb')

  await page.locator('[data-test=start-script]').click()
  await expect(page.locator('[data-test=state] input')).toHaveValue(
    /waiting \d+s/,
    {
      timeout: 20000,
    },
  )
  // After script starts the Script Start/Go and all Suite buttons should be disabled
  await expect(page.locator('[data-test=start-suite]')).toBeDisabled()
  await expect(page.locator('[data-test=start-group]')).toBeDisabled()
  await expect(page.locator('[data-test=start-script]')).toBeDisabled()
  await expect(page.locator('[data-test=setup-suite]')).toBeDisabled()
  await expect(page.locator('[data-test=setup-group]')).toBeDisabled()
  await expect(page.locator('[data-test=teardown-suite]')).toBeDisabled()
  await expect(page.locator('[data-test=teardown-group]')).toBeDisabled()

  await page.locator('[data-test=go-button]').click()
  // Wait for the results
  await expect(page.locator('.v-dialog')).toContainText('Script Results')
  await page.locator('button:has-text("Ok")').click()
  await deleteFile(page)
})

test('starts a suite', async ({ page, utils }) => {
  await page.locator('textarea').fill(`
  require "openc3/script/suite.rb"
  class TestGroup < OpenC3::Group
    def test_test; puts "test"; end
  end
  class TestSuite < OpenC3::Suite
    def setup; OpenC3::Group.puts("setup"); end
    def teardown; OpenC3::Group.puts("teardown"); end
    def initialize
      super()
      add_group("TestGroup")
    end
  end
  `)
  await saveAs(page, 'test_suite1.rb')

  // Verify the suite startup, teardown buttons are enabled
  await expect(page.locator('[data-test=setup-suite]')).toBeEnabled()
  await expect(page.locator('[data-test=teardown-suite]')).toBeEnabled()
  await runAndCheckResults(
    page,
    utils,
    '[data-test=setup-suite]',
    function (textarea: string) {
      expect(textarea).toMatch('setup:PASS')
      expect(textarea).toMatch('Total Tests: 1')
      expect(textarea).toMatch('Pass: 1')
    },
  )

  // Run suite teardown
  await runAndCheckResults(
    page,
    utils,
    '[data-test=teardown-suite]',
    function (textarea: string) {
      expect(textarea).toMatch('teardown:PASS')
      expect(textarea).toMatch('Total Tests: 1')
      expect(textarea).toMatch('Pass: 1')
    },
  )

  // Run suite
  await runAndCheckResults(
    page,
    utils,
    '[data-test=start-suite]',
    function (textarea: string) {
      expect(textarea).toMatch('setup:PASS')
      expect(textarea).toMatch('teardown:PASS')
      expect(textarea).toMatch('Total Tests: 3')
      expect(textarea).toMatch('Pass: 3')
    },
    true,
  )

  // Rewrite the script but remove setup and teardown
  await page.locator('.ace_content').click()
  if (process.platform === 'darwin') {
    await page.keyboard.press('Meta+A')
  } else {
    await page.keyboard.press('Control+A')
  }
  await utils.sleep(1000)
  await page.keyboard.press('Backspace')
  await utils.sleep(1000)
  await page.locator('textarea').fill(`
  require "openc3/script/suite.rb"
  class TestGroup < OpenC3::Group
    def test_test; puts "test"; end
  end
  class TestSuite < OpenC3::Suite
    def initialize
      super()
      add_group("TestGroup")
    end
  end
  `)
  await utils.sleep(1000)
  // Verify filename is marked as edited
  await expect(page.locator('#sr-controls')).toContainText('*')
  // Save the new values which should refresh the controls
  if (process.platform === 'darwin') {
    await page.keyboard.press('Meta+S')
  } else {
    await page.keyboard.press('Control+S')
  }
  await utils.sleep(1000)

  // Verify the suite startup, teardown buttons are disabled
  await expect(page.locator('[data-test=setup-suite]')).toBeDisabled()
  await expect(page.locator('[data-test=teardown-suite]')).toBeDisabled()

  await deleteFile(page)
})

test('starts a group', async ({ page, utils }) => {
  await page.locator('textarea').fill(`
  require "openc3/script/suite.rb"
  class TestGroup1 < OpenC3::Group
    def setup; OpenC3::Group.puts("setup"); end
    def teardown; OpenC3::Group.puts("teardown"); end
    def test_test1; puts "test"; end
  end
  class TestGroup2 < OpenC3::Group
    def test_test2; puts "test"; end
  end
  class TestSuite < OpenC3::Suite
    def initialize
      super()
      add_group("TestGroup1")
      add_group("TestGroup2")
    end
  end
  `)
  await saveAs(page, 'test_suite2.rb')

  // Verify the group startup, teardown buttons are enabled
  await expect(page.locator('[data-test=setup-group]')).toBeEnabled()
  await expect(page.locator('[data-test=teardown-group]')).toBeEnabled()
  await runAndCheckResults(
    page,
    utils,
    '[data-test=setup-group]',
    function (textarea: string) {
      expect(textarea).toMatch('setup:PASS')
      expect(textarea).toMatch('Total Tests: 1')
      expect(textarea).toMatch('Pass: 1')
    },
  )

  // Run group teardown
  await runAndCheckResults(
    page,
    utils,
    '[data-test=teardown-group]',
    function (textarea: string) {
      expect(textarea).toMatch('teardown:PASS')
      expect(textarea).toMatch('Total Tests: 1')
      expect(textarea).toMatch('Pass: 1')
    },
  )

  // Run group
  await runAndCheckResults(
    page,
    utils,
    '[data-test=start-group]',
    function (textarea: string) {
      expect(textarea).toMatch('setup:PASS')
      expect(textarea).toMatch('teardown:PASS')
      expect(textarea).toMatch('Total Tests: 3')
      expect(textarea).toMatch('Pass: 3')
    },
  )

  // Rewrite the script but remove setup and teardown
  await page.locator('.ace_content').click()
  if (process.platform === 'darwin') {
    await page.keyboard.press('Meta+A')
  } else {
    await page.keyboard.press('Control+A')
  }
  await utils.sleep(1000)
  await page.keyboard.press('Backspace')
  await utils.sleep(1000)
  await page.locator('textarea').fill(`
  require "openc3/script/suite.rb"
  class TestGroup1 < OpenC3::Group
    def test_test1; puts "test"; end
  end
  class TestGroup2 < OpenC3::Group
    def test_test2; puts "test"; end
  end
  class TestSuite < OpenC3::Suite
    def initialize
      super()
      add_group("TestGroup1")
      add_group("TestGroup2")
    end
  end
  `)
  await utils.sleep(1000)
  // Verify filename is marked as edited
  await expect(page.locator('#sr-controls')).toContainText('*')
  // Save the new values which should refresh the controls
  if (process.platform === 'darwin') {
    await page.keyboard.press('Meta+S')
  } else {
    await page.keyboard.press('Control+S')
  }
  await utils.sleep(1000)

  // Verify the group startup, teardown buttons are disabled
  await expect(page.locator('[data-test=setup-group]')).toBeDisabled()
  await expect(page.locator('[data-test=teardown-group]')).toBeDisabled()

  await deleteFile(page)
})

test('starts a script', async ({ page, utils }) => {
  await page.locator('textarea').fill(`
  require "openc3/script/suite.rb"
  class TestGroup < OpenC3::Group
    def test_test1; puts "test1"; end
    def test_test2; puts "test2"; end
  end
  class TestSuite < OpenC3::Suite
    def initialize
      super()
      add_group("TestGroup")
    end
  end
  `)
  await saveAs(page, 'test_suite3.rb')
  // Run script
  await runAndCheckResults(
    page,
    utils,
    '[data-test=start-script]',
    function (textarea: string) {
      expect(textarea).toMatch('test1')
      expect(textarea).toMatch('Total Tests: 1')
      expect(textarea).toMatch('Pass: 1')
    },
  )
  await deleteFile(page)
})

test('handles manual mode', async ({ page, utils }) => {
  await page.locator('textarea').fill(`
  require "openc3/script/suite.rb"
  class TestGroup < OpenC3::Group
    def test_test1; OpenC3::Group.puts "manual1" if $manual; end
    def test_test2; OpenC3::Group.puts "manual2" unless $manual; end
  end
  class TestSuite < OpenC3::Suite
    def initialize
      super()
      add_group("TestGroup")
    end
  end
  `)
  await saveAs(page, 'test_suite4.rb')

  // Run group
  await runAndCheckResults(
    page,
    utils,
    '[data-test=start-group]',
    function (textarea: string) {
      expect(textarea).toMatch('Manual = true')
      expect(textarea).toMatch('manual1')
      expect(textarea).not.toMatch('manual2')
      expect(textarea).toMatch('Total Tests: 2')
      expect(textarea).toMatch('Pass: 2')
    },
  )
  await page.locator('label:has-text("Manual")').click() // uncheck Manual
  // Run group
  await runAndCheckResults(
    page,
    utils,
    '[data-test=start-group]',
    function (textarea: string) {
      expect(textarea).toMatch('Manual = false')
      expect(textarea).not.toMatch('manual1')
      expect(textarea).toMatch('manual2')
      expect(textarea).toMatch('Total Tests: 2')
      expect(textarea).toMatch('Pass: 2')
    },
  )
  await deleteFile(page)
})
