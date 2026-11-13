/*
# Copyright 2026 OpenC3, Inc.
# All Rights Reserved.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
# See LICENSE.md for more details.
*/

import { test, expect } from './../fixture'

test.use({
  toolPath: '/tools/admin/tsdb',
  toolName: 'Administrator',
  storageState: 'adminStorageState.json',
})

test('shows the Metrics and Queries sub-tabs', async ({ page, utils }) => {
  await expect(page.locator('[data-test=tsdb-metrics-tab]')).toBeVisible()
  await expect(page.locator('[data-test=tsdb-queries-tab]')).toBeVisible()
  await page.locator('[data-test=tsdb-queries-tab]').click()
  await expect(page.locator('[data-test=tsdb-queries-tab]')).toHaveAttribute(
    'aria-selected',
    'true',
  )
  await page.locator('[data-test=tsdb-metrics-tab]').click()
  await expect(page.locator('[data-test=tsdb-metrics-tab]')).toHaveAttribute(
    'aria-selected',
    'true',
  )
})
