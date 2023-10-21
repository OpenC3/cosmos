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
  toolPath: '/tools/cmdtlmserver/targets',
  toolName: 'CmdTlmServer',
})

test('displays the list of targets', async ({ page, utils }) => {
  await expect(page.locator('[data-test=targets-table]')).toContainText('INST')
  await expect(page.locator('[data-test=targets-table]')).toContainText('INST2')
  await expect(page.locator('[data-test=targets-table]')).toContainText(
    'EXAMPLE',
  )
  await expect(page.locator('[data-test=targets-table]')).toContainText(
    'TEMPLATED',
  )
})

test('displays the interfaces', async ({ page, utils }) => {
  await expect(page.locator('[data-test=targets-table]')).toContainText(
    'INST_INT',
  )
  await expect(page.locator('[data-test=targets-table]')).toContainText(
    'INST2_INT',
  )
  await expect(page.locator('[data-test=targets-table]')).toContainText(
    'EXAMPLE_INT',
  )
  await expect(page.locator('[data-test=targets-table]')).toContainText(
    'TEMPLATED_INT',
  )
})
