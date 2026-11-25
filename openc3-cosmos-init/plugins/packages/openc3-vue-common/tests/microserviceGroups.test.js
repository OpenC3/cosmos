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

import assert from 'node:assert/strict'
import { test } from 'node:test'
import {
  microserviceGroupKey,
  microserviceRows,
} from '../src/tools/admin/tabs/microserviceGroups.js'

// What the rows show: indented names and group headers
function outline(rows) {
  return rows.map((row) =>
    row.type === 'group'
      ? `[${row.scope} ${row.name} (${row.count})${row.collapsed ? ' +' : ''}]`
      : `${'  '.repeat(row.depth)}${row.key}${row.collapsed ? ' +' : ''}`,
  )
}

const multi = 'DEFAULT__MULTIGROUP__DEMO'
const pymulti = 'DEFAULT__PYMULTIGROUP__DEMO'
const microservices = [
  { name: 'DEFAULT__CLEANUP__INST2', parent: multi },
  { name: 'DEFAULT__COMMANDLOG__INST', parent: 'DEFAULT__MULTI__INST' },
  { name: 'DEFAULT__DECOM__INST', parent: 'DEFAULT__MULTI__INST' },
  { name: 'DEFAULT__DECOM__INST2', parent: pymulti },
  { name: 'DEFAULT__INTERFACE__INST_INT' },
  { name: multi },
  { name: 'DEFAULT__MULTI__INST' },
  { name: 'DEFAULT__PACKETLOG__INST2', parent: multi },
  { name: pymulti },
  { name: 'DEFAULT__TSDB__INST', parent: pymulti },
  { name: 'DEFAULT__TSDB__INST2', parent: pymulti },
]

test('identifies microservice group microservices', () => {
  assert.equal(microserviceGroupKey(multi), 'DEFAULT__DEMO')
  assert.equal(
    microserviceGroupKey('DEFAULT__PYMULTIGROUP__A__B'),
    'DEFAULT__A__B',
  )
  assert.equal(microserviceGroupKey('DEFAULT__MULTI__DEMO'), null)
  assert.equal(microserviceGroupKey('DEFAULT__DECOMGROUP__DEMO'), null)
  assert.equal(microserviceGroupKey('DEFAULT__TRIGGER_GROUP__DEFAULT'), null)
  assert.equal(microserviceGroupKey('DEFAULT__MULTIGROUP'), null)
})

test('nests children under their parent and groups under a header', () => {
  assert.deepEqual(outline(microserviceRows(microservices)), [
    'DEFAULT__INTERFACE__INST_INT',
    '[DEFAULT DEMO (7)]',
    '  DEFAULT__MULTIGROUP__DEMO',
    '    DEFAULT__CLEANUP__INST2',
    '    DEFAULT__PACKETLOG__INST2',
    '  DEFAULT__PYMULTIGROUP__DEMO',
    '    DEFAULT__DECOM__INST2',
    '    DEFAULT__TSDB__INST',
    '    DEFAULT__TSDB__INST2',
    'DEFAULT__MULTI__INST',
    '  DEFAULT__COMMANDLOG__INST',
    '  DEFAULT__DECOM__INST',
  ])
  const row = microserviceRows(microservices).find(
    (row) => row.key === 'DEFAULT__MULTI__INST',
  )
  assert.equal(row.childCount, 2)
})

test('collapses parents and groups', () => {
  assert.deepEqual(
    outline(microserviceRows(microservices, new Set([pymulti]))).slice(1, 5),
    [
      '[DEFAULT DEMO (7)]',
      '  DEFAULT__MULTIGROUP__DEMO',
      '    DEFAULT__CLEANUP__INST2',
      '    DEFAULT__PACKETLOG__INST2',
    ],
  )
  assert.equal(
    microserviceRows(microservices, new Set([pymulti])).find(
      (row) => row.key === pymulti,
    ).collapsed,
    true,
  )
  const rows = microserviceRows(
    microservices,
    new Set(['DEFAULT__MULTI__INST', 'DEFAULT__DEMO']),
  )
  assert.deepEqual(outline(rows), [
    'DEFAULT__INTERFACE__INST_INT',
    '[DEFAULT DEMO (7) +]',
    'DEFAULT__MULTI__INST +',
  ])
  // Collapsing a microservice without children does nothing
  assert.deepEqual(
    outline(
      microserviceRows(
        microservices,
        new Set(['DEFAULT__INTERFACE__INST_INT']),
      ),
    ),
    outline(microserviceRows(microservices)),
  )
})

test('shows children at the top level when their parent is filtered out', () => {
  const filtered = microservices.filter((ms) => ms.name !== multi)
  const lines = outline(microserviceRows(filtered))
  assert.ok(lines.includes('DEFAULT__CLEANUP__INST2'))
  assert.ok(lines.includes('DEFAULT__PACKETLOG__INST2'))
  assert.ok(lines.includes('[DEFAULT DEMO (4)]'))
})

test('does not lose microservices in a parent cycle', () => {
  const rows = microserviceRows([
    { name: 'DEFAULT__MULTI__A', parent: 'DEFAULT__MULTI__B' },
    { name: 'DEFAULT__MULTI__B', parent: 'DEFAULT__MULTI__A' },
  ])
  assert.deepEqual(outline(rows), ['DEFAULT__MULTI__A', 'DEFAULT__MULTI__B'])
})
