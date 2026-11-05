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

// Global setup waits for the demo plugin, which declares numpy in its
// pyproject.toml. PW_TEST is installed and removed by the admin plugin tests,
// so it cannot serve as a fixture for this independently scheduled spec.
// Both environments have numpy; its source path proves which copy was loaded.
const IMPORT_NUMPY = `import numpy
print('numpy source: ' + numpy.__file__)`
const DEMO_VENV = /__openc3-cosmos-demo-.*_gem__/

// Spawning a fresh Python interpreter and resolving the venv takes noticeably
// longer than a Ruby script start, especially under CI load.
const RUN_TIMEOUT = 30000

// Open the venv dropdown and return the option labels it offers.
// Read only titles: each option also has a subtitle containing its venv path.
// Scope titles to options to exclude the navigation drawer's list item titles.
async function venvOptions(page): Promise<string[]> {
  await page.locator('[data-test=python-venv-select]').click()
  const options = page.getByRole('option')
  await expect(options.first()).toBeVisible()
  const labels = await options.locator('.v-list-item-title').allTextContents()
  await page.keyboard.press('Escape')
  await expect(options).toHaveCount(0)
  return labels.map((label: string) => label.trim())
}

async function selectVenv(page, name: string) {
  await page.locator('[data-test=python-venv-select]').click()
  await page.getByRole('option').getByText(name, { exact: true }).click()
}

test('offers the plugin venv alongside the system venv', async ({
  page,
  utils,
}) => {
  // detectLanguage() sees the import and treats the untitled buffer as Python,
  // which is what makes showPythonVenv true.
  await page.locator('textarea').fill(IMPORT_NUMPY)
  await expect(page.locator('[data-test=python-venv-select]')).toBeVisible()

  const labels = await venvOptions(page)
  expect(labels).toContain('system')
  expect(labels.some((label) => DEMO_VENV.test(label))).toBe(true)
})

test('runs a script against the selected plugin venv', async ({
  page,
  utils,
}) => {
  await page.locator('textarea').fill(IMPORT_NUMPY)
  await expect(page.locator('[data-test=python-venv-select]')).toBeVisible()

  const pluginVenv = (await venvOptions(page)).find((label) =>
    DEMO_VENV.test(label),
  )
  expect(pluginVenv).toBeTruthy()
  await selectVenv(page, pluginVenv as string)

  await page.locator('[data-test=start-button]').click()
  await expect(page.locator('[data-test=output-messages]')).toContainText(
    `numpy source: /gems/plugin_venvs/${pluginVenv}/.venv/`,
    { timeout: RUN_TIMEOUT },
  )
})

test('loads the system package under the system venv', async ({
  page,
  utils,
}) => {
  await page.locator('textarea').fill(IMPORT_NUMPY)
  await expect(page.locator('[data-test=python-venv-select]')).toBeVisible()

  // 'system' is the default, but select it explicitly so the test states its
  // premise rather than relying on the component's initial value.
  await selectVenv(page, 'system')

  await page.locator('[data-test=start-button]').click()
  // Selecting system must load the base copy, not the demo plugin's copy.
  await expect(page.locator('[data-test=output-messages]')).toContainText(
    'numpy source: /openc3/python/.venv/',
    { timeout: RUN_TIMEOUT },
  )
})
