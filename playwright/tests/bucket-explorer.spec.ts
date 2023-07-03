/*
# Copyright 2023 OpenC3, Inc.
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
*/

// @ts-check
import { test, expect } from './fixture'

test.use({
  toolPath: '/tools/bucketexplorer',
  toolName: 'Bucket Explorer',
})

//
// Test the basic functionality of the application
//
test('navigate config bucket', async ({ page, utils }) => {
  // Initially empty
  await expect(
    page.getByRole('cell', { name: 'No data available' })
  ).toBeVisible()

  await page.getByText('config').click()
  await expect(page).toHaveURL(/.*\/tools\/bucketexplorer\/config%2F/)
  await page.getByRole('cell', { name: 'DEFAULT' }).click()
  await expect(page.locator('[data-test="file-path"]')).toHaveText('/DEFAULT/')
  await expect(page).toHaveURL(/.*\/tools\/bucketexplorer\/config%2FDEFAULT%2F/)
  await page.getByRole('cell', { name: 'targets', exact: true }).click()
  await expect(page.locator('[data-test="file-path"]')).toHaveText(
    '/DEFAULT/targets/'
  )
  await expect(page).toHaveURL(
    /.*\/tools\/bucketexplorer\/config%2FDEFAULT%2Ftargets%2F/
  )
  await page.getByRole('cell', { name: 'INST', exact: true }).click()
  await expect(page.locator('[data-test="file-path"]')).toHaveText(
    '/DEFAULT/targets/INST/'
  )
  await expect(page).toHaveURL(
    /.*\/tools\/bucketexplorer\/config%2FDEFAULT%2Ftargets%2FINST%2F/
  )
  await expect(page.locator('tbody > tr')).toHaveCount(9)

  // Clicking a file should do nothing
  await page.getByRole('cell', { name: 'target.txt' }).click()
  await expect(page).toHaveURL(
    /.*\/tools\/bucketexplorer\/config%2FDEFAULT%2Ftargets%2FINST%2F/
  )
  await expect(page.locator('tbody > tr')).toHaveCount(9)
  // Download the file
  await utils.download(
    page,
    'tbody > tr:has-text("target.txt") [data-test="download-file"]',
    function (contents) {
      expect(contents).toContain('REQUIRE')
      expect(contents).toContain('IGNORE_PARAMETER')
      expect(contents).toContain('IGNORE_ITEM')
    }
  )

  // codegen created this weird named button for back
  await page.getByRole('button', { name: '󰧙' }).nth(1).click()
  await expect(page.locator('[data-test="file-path"]')).toHaveText(
    '/DEFAULT/targets/'
  )
  await expect(page).toHaveURL(
    /.*\/tools\/bucketexplorer\/config%2FDEFAULT%2Ftargets%2F/
  )
  await page.getByRole('button', { name: '󰧙' }).nth(1).click()
  await expect(page.locator('[data-test="file-path"]')).toHaveText('/DEFAULT/')
  await expect(page).toHaveURL(/.*\/tools\/bucketexplorer\/config%2FDEFAULT%2F/)
  await page.getByRole('button', { name: '󰧙' }).nth(1).click()
  await expect(page.locator('[data-test="file-path"]')).toHaveText('/')
  await expect(page).toHaveURL(/.*\/tools\/bucketexplorer\/config%2F/)
  // Back again just to show that doesn't break things
  await page.getByRole('button', { name: '󰧙' }).nth(1).click()
  await expect(page.locator('[data-test="file-path"]')).toHaveText('/')
  await expect(page).toHaveURL(/.*\/tools\/bucketexplorer\/config%2F/)
})

test('navigate logs and tools bucket', async ({ page, utils }) => {
  await page.getByText('logs').click()
  await expect(page).toHaveURL(/.*\/tools\/bucketexplorer\/logs%2F/)
  await page.getByRole('cell', { name: 'DEFAULT' }).click()
  await expect(page.locator('[data-test="file-path"]')).toHaveText('/DEFAULT/')
  await expect(page).toHaveURL(/.*\/tools\/bucketexplorer\/logs%2FDEFAULT%2F/)
  await expect(page.locator('tbody > tr').first()).toHaveText(/\w+_logs/)
  // Reload and ensure we get to the same place
  await page.reload()
  await expect(page.locator('[data-test="file-path"]')).toHaveText('/DEFAULT/')
  await expect(page).toHaveURL(/.*\/tools\/bucketexplorer\/logs%2FDEFAULT%2F/)
  await expect(page.locator('tbody > tr').first()).toHaveText(/\w+_logs/)

  await page.getByText('tools').click()
  await expect(page).toHaveURL(/.*\/tools\/bucketexplorer\/tools%2F/)
  await expect(page.locator('tbody > tr')).toHaveCount(17)
})

test('navigate gems volume', async ({ page, utils }) => {
  await page.getByText('gems').click()
  // Note the URL is prefixed with %2F, i.e. '/'
  await expect(page).toHaveURL(/.*\/tools\/bucketexplorer\/%2Fgems%2F/)
  await page.getByRole('cell', { name: 'cache' }).click()
  await expect(page.locator('[data-test="file-path"]')).toHaveText('/cache/')
  await expect(page).toHaveURL(/.*\/tools\/bucketexplorer\/%2Fgems%2Fcache%2F/)

  await page.locator('internal:label=Search').fill('bucket')
  await expect(page.locator('tbody > tr')).toHaveCount(1)
  // Download the file
  await utils.download(page, 'tbody > tr [data-test="download-file"]')

  // Reload and ensure we get to the same place
  await page.reload()
  await expect(page.locator('[data-test="file-path"]')).toHaveText('/cache/')
  await expect(page).toHaveURL(/.*\/tools\/bucketexplorer\/%2Fgems%2Fcache%2F/)
  await page.locator('internal:label=Search').fill('bucket')
  await expect(page.locator('tbody > tr')).toHaveCount(1)
})

test('direct URLs', async ({ page, utils }) => {
  // Verify using slashes rather than %2F works
  await page.goto('/tools/bucketexplorer/config/DEFAULT/targets/')
  await utils.sleep(300) // Ensure the page is rendered before getting the count
  // Can't match exact because Enterprise has the PW_TEST target
  await expect.poll(() => page.locator('tr').count()).toBeGreaterThan(4)

  // Basic makes it a bucket
  await page.goto('/tools/bucketexplorer/blah')
  await expect(
    page.getByText('Unknown bucket / volume OPENC3_BLAH_BUCKET')
  ).toBeVisible()
  await page.getByRole('button', { name: 'Dismiss' }).click()
  // Prepending %2F makes it a volume
  await page.goto('/tools/bucketexplorer/%2FBAD')
  await expect(
    page.getByText('Unknown bucket / volume OPENC3_BAD_VOLUME')
  ).toBeVisible()
  await page.getByRole('button', { name: 'Dismiss' }).click()
})

// Create a new screen so we have modifications to browse
test('creates new screen', async ({ page, utils }) => {
  await page.goto('/tools/tlmviewer')
  await expect(page.locator('.v-app-bar')).toContainText('Telemetry Viewer')
  await page.locator('.v-app-bar__nav-icon').click()
  await page.locator('[data-test=new-screen]').click()
  await expect(
    page.locator(`.v-system-bar:has-text("New Screen")`)
  ).toBeVisible()
  await page.locator('[data-test=new-screen-name]').fill('NEW_SCREEN')
  await page.locator('button:has-text("Ok")').click()
  await expect(
    page.locator(`.v-system-bar:has-text("NEW_SCREEN")`)
  ).toBeVisible()
})

test('upload and delete', async ({ page, utils }) => {
  await page.getByText('config').click()
  await expect(page).toHaveURL(/.*\/tools\/bucketexplorer\/config%2F/)
  await expect(page.locator('[data-test="file-path"]')).toHaveText('/')
  await page.getByRole('cell', { name: 'DEFAULT' }).click()
  await expect(page.locator('[data-test="file-path"]')).toHaveText('/DEFAULT/')
  await page.getByRole('cell', { name: 'targets_modified' }).click()
  await expect(page.locator('[data-test="file-path"]')).toHaveText(
    '/DEFAULT/targets_modified/'
  )
  await utils.sleep(300) // Ensure the table is rendered before getting the count
  let count = await page.locator('tbody > tr').count()

  // Note that Promise.all prevents a race condition
  // between clicking and waiting for the file chooser.
  const [fileChooser] = await Promise.all([
    // It is important to call waitForEvent before click to set up waiting.
    page.waitForEvent('filechooser'),
    // Opens the file chooser.
    await page.getByRole('button', { name: 'prepend icon' }).click(),
  ])
  await fileChooser.setFiles('package.json')
  await expect(page.locator('tbody > tr')).toHaveCount(count + 1)
  await expect(page.getByRole('cell', { name: 'package.json' })).toBeVisible()
  await page
    .locator('tr:has-text("package.json") [data-test="delete-file"]')
    .click()
  await page.locator('[data-test="confirm-dialog-delete"]').click()
  await expect(page.locator('tbody > tr')).toHaveCount(count)
})
