/*
# Copyright 2026 OpenC3, Inc.
# All Rights Reserved.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
# See LICENSE.md for more details.
#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.
*/

import { test, expect } from './../fixture'

test.use({
  toolPath: '/tools/scriptrunner',
  toolName: 'Script Runner',
})

// These specs depend on the PW_TEST plugin shipping a pyproject.toml (see
// playwright/fixtures/pw-test-pyproject.toml), which makes PluginModel build a
// per-plugin venv containing cowsay. With no plugin venv on disk the
// plugin_python_venvs endpoint returns an empty list and the selector never
// renders, so a missing fixture shows up as "selector not visible" below.

// cowsay is in the plugin venv only, never the openc3 base venv, so which
// interpreter environment ran the script is visible in the output.
const IMPORT_COWSAY = `import cowsay
print(cowsay.get_output_string('cow', 'venv ok'))`

// Spawning a fresh Python interpreter and resolving the venv takes noticeably
// longer than a Ruby script start, especially under CI load.
const RUN_TIMEOUT = 30000

// Open the venv dropdown and return the option labels it offers.
async function venvOptions(page): Promise<string[]> {
  await page.locator('[data-test=python-venv-select]').click()
  const options = page.locator('.v-list-item-title')
  await expect(options.first()).toBeVisible()
  const labels = await options.allTextContents()
  await page.keyboard.press('Escape')
  return labels.map((label: string) => label.trim())
}

async function selectVenv(page, name: string) {
  await page.locator('[data-test=python-venv-select]').click()
  await page.locator('.v-list-item-title', { hasText: name }).first().click()
}

test('offers the plugin venv alongside the system venv', async ({ page }) => {
  // detectLanguage() sees the import and treats the untitled buffer as Python,
  // which is what makes showPythonVenv true.
  await page.locator('textarea').fill(IMPORT_COWSAY)
  await expect(page.locator('[data-test=python-venv-select]')).toBeVisible()

  const labels = await venvOptions(page)
  expect(labels).toContain('system')
  // Everything else in the list comes from /gems/plugin_venvs, so at least one
  // non-system entry proves the fixture plugin's venv was built and listed.
  expect(labels.filter((label) => label !== 'system').length).toBeGreaterThan(0)
})

test('runs a script against the selected plugin venv', async ({ page }) => {
  await page.locator('textarea').fill(IMPORT_COWSAY)
  await expect(page.locator('[data-test=python-venv-select]')).toBeVisible()

  const pluginVenv = (await venvOptions(page)).find(
    (label) => label !== 'system',
  )
  expect(pluginVenv).toBeTruthy()
  await selectVenv(page, pluginVenv as string)

  await page.locator('[data-test=start-button]').click()
  await expect(page.locator('[data-test=output-messages]')).toContainText(
    'venv ok',
    { timeout: RUN_TIMEOUT },
  )
})

test('cannot import a plugin package under the system venv', async ({
  page,
}) => {
  await page.locator('textarea').fill(IMPORT_COWSAY)
  await expect(page.locator('[data-test=python-venv-select]')).toBeVisible()

  // 'system' is the default, but select it explicitly so the test states its
  // premise rather than relying on the component's initial value.
  await selectVenv(page, 'system')

  await page.locator('[data-test=start-button]').click()
  // The base venv has no cowsay, so the import is what fails - this is the
  // negative half that proves the previous test used the plugin venv and not
  // simply a package that happened to be available everywhere.
  await expect(page.locator('[data-test=output-messages]')).toContainText(
    'ModuleNotFoundError',
    { timeout: RUN_TIMEOUT },
  )
})
