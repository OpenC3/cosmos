/* Copyright 2026 OpenC3, Inc. All Rights Reserved. See LICENSE.md. */

import assert from 'node:assert/strict'
import { test } from 'node:test'

globalThis.window = { openc3Scope: 'OTHER' }
const { applySharedResources } =
  await import('../src/tools/CmdTlmServer/sharedResources.js')

function resource(owner, state = 'ACTIVE', to = null) {
  return {
    name: 'CHAMBER',
    owner,
    state,
    to,
    members: {
      DEFAULT: [{ type: 'INTERFACE', name: 'DEFAULT__INTERFACE__INT' }],
      OTHER: [
        { type: 'INTERFACE', name: 'OTHER__INTERFACE__INT' },
        { type: 'INTERFACE', name: 'OTHER__INTERFACE__NEVER_RAN' },
        { type: 'ROUTER', name: 'OTHER__ROUTER__ROUTE' },
        { type: 'TARGET', name: 'INST' },
      ],
    },
  }
}

function row(name, connected = 'DISCONNECTED') {
  return { name, connected, connect: 'Connect', connectedClass: 'x' }
}

test('leaves rows alone when the shared resource is active in this scope', () => {
  const rows = applySharedResources(
    [row('INT'), row('PLAIN')],
    [resource('OTHER')],
    'INTERFACE',
  )
  assert.equal(rows.length, 3)
  assert.equal(rows[0].dormant, undefined)
  assert.equal(rows[0].connect, 'Connect')
  assert.equal(rows[0].sharedResource, 'CHAMBER')
  assert.equal(rows[1].sharedResource, undefined)
})

test('marks dormant members and adds rows for members without status', () => {
  const rows = applySharedResources(
    [row('INT'), row('PLAIN')],
    [resource('DEFAULT')],
    'INTERFACE',
  )
  const names = rows.map((r) => r.name)
  assert.deepEqual(names, ['INT', 'PLAIN', 'NEVER_RAN'])
  for (const r of [rows[0], rows[2]]) {
    assert.equal(r.dormant, true)
    assert.equal(r.switching, false)
    assert.equal(r.connect, 'Activate')
    assert.equal(r.connected, 'SHARED: Active in DEFAULT')
  }
  assert.equal(rows[2].tx_bytes, 0)
  assert.equal(rows[1].dormant, undefined)
})

test('describes a switch in progress and only uses the requested type', () => {
  const rows = applySharedResources(
    [],
    [resource('DEFAULT', 'RELEASING', 'OTHER')],
    'ROUTER',
  )
  assert.deepEqual(
    rows.map((r) => r.name),
    ['ROUTE'],
  )
  assert.equal(rows[0].switching, true)
  assert.equal(rows[0].connected, 'SHARED: Switching DEFAULT to OTHER')
})

test('handles no shared resources', () => {
  const rows = applySharedResources([row('INT')], [], 'INTERFACE')
  assert.equal(rows.length, 1)
  assert.equal(rows[0].dormant, undefined)
})
