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
    page.getByRole('cell', { name: 'No data available' }),
  ).toBeVisible()

  await page.getByText('config').click()
  await expect(page).toHaveURL(/.*\/tools\/bucketexplorer\/config%2F/)
  await page.getByRole('cell', { name: 'DEFAULT' }).click()
  await expect(page.locator('[data-test="file-path"]')).toContainText(
    '/ DEFAULT /',
  )
  await expect(page).toHaveURL(/.*\/tools\/bucketexplorer\/config%2FDEFAULT%2F/)
  await page.getByRole('cell', { name: 'targets', exact: true }).click()
  await expect(page.locator('[data-test="file-path"]')).toContainText(
    '/ DEFAULT / targets /',
  )
  await expect(page).toHaveURL(
    /.*\/tools\/bucketexplorer\/config%2FDEFAULT%2Ftargets%2F/,
  )
  await page.getByRole('cell', { name: 'INST', exact: true }).click()
  await expect(page.locator('[data-test="file-path"]')).toContainText(
    '/ DEFAULT / targets / INST /',
  )
  await expect(page).toHaveURL(
    /.*\/tools\/bucketexplorer\/config%2FDEFAULT%2Ftargets%2FINST%2F/,
  )
  await expect(page.locator('tbody > tr')).toHaveCount(9)

  // Clicking a file should do nothing
  await page.getByRole('cell', { name: 'target.txt' }).click()
  await expect(page).toHaveURL(
    /.*\/tools\/bucketexplorer\/config%2FDEFAULT%2Ftargets%2FINST%2F/,
  )
  await expect(page.locator('tbody > tr')).toHaveCount(9)
  // Download the file
  await utils.download(
    page,
    'tbody > tr:has-text("target.txt") [data-test="download-file"]',
    function (contents) {
      expect(contents).toContain('LANGUAGE')
      expect(contents).toContain('IGNORE_PARAMETER')
      expect(contents).toContain('IGNORE_ITEM')
    },
  )

  await page.locator('[data-test="be-nav-back"]').click()
  await expect(page.locator('[data-test="file-path"]')).toContainText(
    '/ DEFAULT / targets /',
  )
  await expect(page).toHaveURL(
    /.*\/tools\/bucketexplorer\/config%2FDEFAULT%2Ftargets%2F/,
  )
  await page.locator('[data-test="be-nav-back"]').click()
  await expect(page.locator('[data-test="file-path"]')).toContainText(
    '/ DEFAULT /',
  )
  await expect(page).toHaveURL(/.*\/tools\/bucketexplorer\/config%2FDEFAULT%2F/)
  await page.locator('[data-test="be-nav-back"]').click()
  await expect(page.locator('[data-test="file-path"]')).toHaveText('/')
  await expect(page).toHaveURL(/.*\/tools\/bucketexplorer\/config%2F/)
  // Back again just to show that doesn't break things
  await page.locator('[data-test="be-nav-back"]').click()
  await expect(page.locator('[data-test="file-path"]')).toHaveText('/')
  await expect(page).toHaveURL(/.*\/tools\/bucketexplorer\/config%2F/)
})

test('navigate gems volume', async ({ page, utils }) => {
  await page.getByText('gems').click()
  // Note the URL is prefixed with %2F, i.e. '/'
  await expect(page).toHaveURL(/.*\/tools\/bucketexplorer\/%2Fgems%2F/)
  await page.getByRole('cell', { name: 'cosmoscache' }).click()
  await expect(page.locator('[data-test="file-path"]')).toContainText(
    '/ cosmoscache /',
  )
  await expect(page).toHaveURL(
    /.*\/tools\/bucketexplorer\/%2Fgems%2Fcosmoscache%2F/,
  )

  await page.locator('[data-test="search-input"] input').fill('bucket')
  await expect(page.locator('tbody > tr')).toHaveCount(1)
  // Download the file
  await utils.download(page, 'tbody > tr [data-test="download-file"] >> nth=0')

  // Reload and ensure we get to the same place
  await page.reload()
  await expect(page.locator('[data-test="file-path"]')).toContainText(
    '/ cosmoscache /',
  )
  await expect(page).toHaveURL(
    /.*\/tools\/bucketexplorer\/%2Fgems%2Fcosmoscache%2F/,
  )
  await page.locator('[data-test="search-input"] input').fill('bucket')
  await expect(page.locator('tbody > tr')).toHaveCount(1)
})

test('direct URLs', async ({ page, utils }) => {
  await utils.sleep(500) // Wait for the app to be ready
  // Verify using slashes rather than %2F works
  await page.goto('/tools/bucketexplorer/config%2FDEFAULT%2Ftargets%2F')
  await expect(page.locator('.v-app-bar')).toContainText('Bucket Explorer')
  // Can't match exact because Enterprise has the PW_TEST target
  await expect.poll(() => page.locator('tr').count()).toBeGreaterThan(4)

  // Basic makes it a bucket
  await page.goto('/tools/bucketexplorer/blah')
  await expect(page.locator('.v-app-bar')).toContainText('Bucket Explorer')
  await expect(
    page.getByText('Unknown bucket / volume OPENC3_BLAH_BUCKET'),
  ).toBeVisible()
  // Prepending %2F makes it a volume
  await page.goto('/tools/bucketexplorer/%2FBAD')
  await expect(page.locator('.v-app-bar')).toContainText('Bucket Explorer')
  await expect(
    page.getByText('Unknown bucket / volume OPENC3_BAD_VOLUME'),
  ).toBeVisible()
})

test('view file', async ({ page, utils }) => {
  await page.getByText('config').click()
  await page.getByRole('cell', { name: 'DEFAULT' }).click()
  await page.getByRole('cell', { name: 'targets', exact: true }).click()
  await page.getByRole('cell', { name: 'INST', exact: true }).click()
  await page.getByRole('cell', { name: 'procedures' }).click()
  await page.locator('[data-test="search-input"] input').fill('calendar')
  await page.locator('[data-test="view-file"]').first().click()
  await expect(page.locator('pre')).toContainText('create_timeline')
  await page.getByRole('button', { name: 'Ok' }).click()
  await page.locator('[data-test="search-input"] input').fill('')
  await page.getByText('INST', { exact: true }).click()
  await utils.sleep(500) // Allow the page to render
  await page.locator('[data-test="search-input"] input').fill('target.txt')
  await page.locator('[data-test="view-file"]').first().click()
  await expect(page.locator('pre')).toContainText('LANGUAGE ruby')
  await page.getByRole('button', { name: 'Ok' }).click()
})

test('upload and delete', async ({ page, utils }) => {
  // Create a file so we have something in __TEMP__
  await page.goto('/tools/scriptrunner')
  await expect(page.locator('.v-app-bar')).toContainText('Script Runner')
  await page.locator('[data-test=script-runner-file]').click()
  await page.locator('text=New File').click()
  await expect(page.locator('textarea')).toHaveText('')
  await page.locator('textarea').fill(`print('hello world')`)
  await page.locator('[data-test=script-runner-file]').click()
  await page.locator('[data-test=start-button]').click()
  await expect(page.locator('[data-test=state] input')).toHaveValue(
    'completed',
    {
      timeout: 30000,
    },
  )

  await page.goto('/tools/bucketexplorer')
  await page.getByText('config').click()
  await expect(page).toHaveURL(/.*\/tools\/bucketexplorer\/config%2F/)
  await expect(page.locator('[data-test="file-path"]')).toHaveText('/')
  await page.getByRole('cell', { name: 'DEFAULT' }).click()
  await expect(page.locator('[data-test="file-path"]')).toHaveText(
    '/ DEFAULT /',
  )
  await page.getByRole('cell', { name: 'targets_modified' }).click()
  await expect(page.locator('[data-test="file-path"]')).toHaveText(
    '/ DEFAULT / targets_modified /',
  )
  await page.getByRole('cell', { name: '__TEMP__' }).click()
  await expect(page.locator('[data-test="file-path"]')).toHaveText(
    '/ DEFAULT / targets_modified / __TEMP__ /',
  )

  // Note that Promise.all prevents a race condition
  // between clicking and waiting for the file chooser.
  await expect(page.getByLabel('prepended action')).toBeVisible()
  const [fileChooser] = await Promise.all([
    // It is important to call waitForEvent before click to set up waiting.
    page.waitForEvent('filechooser'),
    // Opens the file chooser.
    await page.getByLabel('prepended action').click(),
  ])
  await fileChooser.setFiles('package.json')
  await page.locator('[data-test="upload-file-submit-btn"]').click()

  await expect(page.getByRole('cell', { name: 'package.json' })).toBeVisible()
  await page
    .locator('tr:has-text("package.json") [data-test="delete-file"]')
    .click()
  await page.locator('[data-test="confirm-dialog-delete"]').click()
})

test('navigate logs and tools bucket', async ({ page, utils }) => {
  test.setTimeout(3 * 60 * 1000) // 3 minutes
  // Keep clicking alternatively on tools and then logs to force a refresh
  // This allows the DEFAULT folder to appear in time
  await expect(async () => {
    await page.getByText('tools', { exact: true }).click()
    await page.getByText('logs', { exact: true }).click()
    await expect(page.getByRole('cell', { name: 'DEFAULT' })).toBeVisible()
  }).toPass()
  await expect(page).toHaveURL(/.*\/tools\/bucketexplorer\/logs%2F/)

  await page.getByRole('cell', { name: 'DEFAULT' }).click()
  await expect(page.locator('[data-test="file-path"]')).toHaveText(
    '/ DEFAULT /',
  )
  await expect(page).toHaveURL(/.*\/tools\/bucketexplorer\/logs%2FDEFAULT%2F/)
  await expect(page.locator('tbody > tr').first()).toHaveText(/\w+_logs/)
  // Reload and ensure we get to the same place
  await page.reload()
  await expect(page.locator('[data-test="file-path"]')).toHaveText(
    '/ DEFAULT /',
  )
  await expect(page).toHaveURL(/.*\/tools\/bucketexplorer\/logs%2FDEFAULT%2F/)
  // Ensure the log files have the correct dates
  let date = new Date().toISOString().split('T')[0].replace(/-/g, '')
  await page.getByRole('cell', { name: 'raw_logs' }).click()
  await page.getByRole('cell', { name: 'tlm' }).click()
  await page.getByRole('cell', { name: 'INST', exact: true }).click()
  // Verify no bad dates
  await expect(page.getByText('1970')).not.toBeVisible()
  await page.getByRole('cell', { name: date }).click()
  // Don't check for date because 2 files could be present
  await expect(
    page.getByText('DEFAULT__INST__ALL__rt__raw').first(),
  ).toBeVisible()

  await page.getByText('tools').click()
  await expect(page).toHaveURL(/.*\/tools\/bucketexplorer\/tools%2F/)
  if (process.env.ENTERPRISE === '1') {
    await expect(page.locator('tbody > tr')).toHaveCount(23)
  } else {
    await expect(page.locator('tbody > tr')).toHaveCount(17)
  }
})

test('auto refreshes to update files', async ({
  page,
  utils,
  toolPath,
  context,
}) => {
  // Create a file so we have something in __TEMP__
  await page.goto('/tools/scriptrunner')
  await expect(page.locator('.v-app-bar')).toContainText('Script Runner')
  await page.locator('[data-test=script-runner-file]').click()
  await page.locator('text=New File').click()
  await expect(page.locator('textarea')).toHaveText('')
  await page.locator('textarea').fill(`print('hello world')`)
  await page.locator('[data-test=start-button]').click()
  await expect(page.locator('[data-test=state] input')).toHaveValue(
    'completed',
    {
      timeout: 30000,
    },
  )

  // Open another tab and navigate to the __TEMP__ dir
  const pageTwo = await context.newPage()
  pageTwo.goto(toolPath)
  await pageTwo.getByText('config').click()
  await pageTwo.getByRole('cell', { name: 'DEFAULT' }).click()
  await pageTwo.getByRole('cell', { name: 'targets_modified' }).click()
  await pageTwo.getByRole('cell', { name: '__TEMP__' }).click()

  // Set the refresh interval on the second tab to be really slow
  await pageTwo.locator('[data-test=bucket-explorer-file]').click()
  await pageTwo.locator('[data-test=bucket-explorer-file-options]').click()
  await pageTwo
    .locator('.v-dialog [data-test=refresh-interval] input')
    .fill('1000')
  await pageTwo.getByRole('button', { name: 'Save' }).click()

  // Upload a file from the first tab
  await page.goto(
    '/tools/bucketexplorer/config%2FDEFAULT%2Ftargets_modified%2F__TEMP__%2F',
  )
  await expect(page.locator('.v-app-bar')).toContainText('Bucket Explorer')
  await expect(page.getByLabel('prepended action')).toBeVisible()
  const [fileChooser] = await Promise.all([
    page.waitForEvent('filechooser'),
    await page.getByLabel('prepended action').click(),
  ])
  await fileChooser.setFiles('package.json')
  await page
    .locator('[data-test="upload-file-path"] input')
    .fill(`DEFAULT/targets_modified/__TEMP__/refresh_package.json`)
  await page.locator('[data-test="upload-file-submit-btn"]').click()

  // The second tab shouldn't have refreshed yet, so the file shouldn't be there
  await page.locator('tbody> tr').first().waitFor()
  await expect(
    pageTwo.getByRole('cell', { name: 'refresh_package.json' }),
  ).not.toBeVisible({ timeout: 10000 })

  // Set the refresh interval on the second tab to 1s
  await pageTwo.locator('[data-test=bucket-explorer-file]').click()
  await pageTwo.locator('[data-test=bucket-explorer-file-options]').click()
  await pageTwo
    .locator('.v-dialog [data-test=refresh-interval] input')
    .fill('1')
  await pageTwo.getByRole('button', { name: 'Save' }).click()

  // Second tab should auto refresh in 1s and then the file should be there
  await page.locator('tbody> tr').first().waitFor()
  await expect(
    pageTwo.getByRole('cell', { name: 'refresh_package.json' }),
  ).toBeVisible()

  // Cleanup
  await page
    .locator('tr:has-text("refresh_package.json") [data-test="delete-file"]')
    .click()
  await page.locator('[data-test="confirm-dialog-delete"]').click()
})
